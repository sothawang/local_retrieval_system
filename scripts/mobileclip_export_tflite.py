import os
import sys
import re
import argparse
import importlib.util
import importlib.metadata
import subprocess
import shutil
import torch
import torch.nn as nn
import torch.nn.functional as F
import numpy as np
import mobileclip
import onnx
import tensorflow as tf

# ============================================================================
# 【核心修复 1】：注入 Monkey Patch 以兼容新版 ONNX 结构
# ============================================================================
if not hasattr(onnx, 'mapping') and hasattr(onnx, '_mapping'):
    onnx.mapping = onnx._mapping
    print("-> ✅ 已动态修复 onnx.mapping 兼容性补丁")

# ============================================================================
# 【核心修复 3 增强版】：GELU -> Tanh 近似替换（避免 FlexErf）
# ============================================================================
def replace_gelu_with_tanh_approx(module: nn.Module) -> int:
    replaced = 0
    for name, child in module.named_children():
        if isinstance(child, nn.GELU) and child.approximate != 'tanh':
            setattr(module, name, nn.GELU(approximate='tanh'))
            replaced += 1
        else:
            replaced += replace_gelu_with_tanh_approx(child)
    return replaced

_original_functional_gelu = F.gelu
def _patched_functional_gelu(input, approximate='none'):
    return _original_functional_gelu(input, approximate='tanh')
F.gelu = _patched_functional_gelu

# ============================================================================
# 【核心修复 4 新增】：ArgMax dtype 净化（避免 Text Encoder 端 FlexArgMax / FlexGatherNd）
# ----------------------------------------------------------------------------
# MobileCLIP/OpenCLIP 风格的文本编码器通常通过如下方式取出 EOT token 的表示：
#     x = x[torch.arange(x.shape[0]), text.argmax(dim=-1)]
# 这里 text.argmax(dim=-1) 是在 int64 的 token id 张量上做 argmax，追踪到 ONNX
# 后容易生成一个类型不干净的 ArgMax 节点，进而在 onnx2tf 转换时被判定为无法
# 原生支持而退化为 FlexArgMax / FlexGatherNd。
#
# 做法：
#   1) 全局 monkey patch torch.argmax 与 torch.Tensor.argmax，在调用真正的
#      argmax 之前，如果输入是整型张量，显式 cast 为 torch.int32，确保追踪
#      到 ONNX 图中的 ArgMax 节点输入类型干净、规范。
#   2) 额外尝试对 mobileclip 包源码中形如 `.argmax(dim=-1)]` 的 EOT 索引写法
#      做源码级修补，把它替换成显式 int32 cast 后再 argmax 的形式，双重保险。
# ============================================================================
_original_torch_argmax = torch.argmax
_original_tensor_argmax = torch.Tensor.argmax

def _clean_argmax_input(input_tensor: torch.Tensor) -> torch.Tensor:
    # 只对整型张量做 int32 净化，浮点张量（例如 logits）保持原样，
    # 避免影响数值精度或改变模型行为。
    if isinstance(input_tensor, torch.Tensor) and not input_tensor.is_floating_point():
        if input_tensor.dtype != torch.int32:
            return input_tensor.to(torch.int32)
    return input_tensor

def _patched_torch_argmax(input, dim=None, keepdim=False):
    input = _clean_argmax_input(input)
    if dim is None:
        return _original_torch_argmax(input)
    return _original_torch_argmax(input, dim=dim, keepdim=keepdim)

def _patched_tensor_argmax(self, dim=None, keepdim=False):
    cleaned = _clean_argmax_input(self)
    if dim is None:
        return _original_tensor_argmax(cleaned)
    return _original_tensor_argmax(cleaned, dim=dim, keepdim=keepdim)

torch.argmax = _patched_torch_argmax
torch.Tensor.argmax = _patched_tensor_argmax


def patch_mobileclip_argmax_source():
    """
    在 mobileclip 包源码中查找形如 text.argmax(dim=-1) 的 EOT token 索引写法，
    尝试将其替换为显式 int32 cast 后再 argmax，从源头保证追踪到 ONNX 的算子
    类型干净。此修补是尽力而为（best-effort）：如果没有匹配到已知写法，
    上面的全局 monkey patch 仍会兜底生效。
    """
    try:
        spec = importlib.util.find_spec("mobileclip")
        if spec is None or spec.origin is None:
            print("-> ⚠️ 未找到 mobileclip 安装位置，跳过源码修补")
            return
        pkg_dir = os.path.dirname(spec.origin)

        # 匹配常见写法： xxx.argmax(dim=-1)  但排除已经被修补过的
        pattern = re.compile(r'(?<!to\(torch\.int32\)\.)([A-Za-z_][A-Za-z0-9_\.\[\]]*)\.argmax\(dim=-1\)')

        patched_files = 0
        for root, _, files in os.walk(pkg_dir):
            for fname in files:
                if not fname.endswith(".py"):
                    continue
                fpath = os.path.join(root, fname)
                try:
                    with open(fpath, "r", encoding="utf-8") as f:
                        content = f.read()
                except Exception:
                    continue

                if ".argmax(dim=-1)" not in content:
                    continue

                def _replace(match):
                    expr = match.group(1)
                    return f"{expr}.to(torch.int32).argmax(dim=-1)"

                new_content = pattern.sub(_replace, content)

                if new_content != content:
                    with open(fpath, "w", encoding="utf-8") as f:
                        f.write(new_content)
                    patched_files += 1
                    print(f"-> ✅ 已修补 EOT argmax 写法: {fpath}")

        if patched_files == 0:
            print("-> ℹ️ 未在 mobileclip 源码中找到需要修补的 argmax 写法（可能已由全局补丁覆盖）")
    except Exception as e:
        print(f"-> ⚠️ 修补 mobileclip 源码 argmax 时出现异常: {e}")


# ============================================================================
# 【核心修复 2 升级版】：自动修补 onnx2tf 源码（离线 + allow_pickle）
# ============================================================================
def patch_onnx2tf_source_code():
    try:
        spec = importlib.util.find_spec("onnx2tf")
        if spec is None or spec.origin is None:
            print("-> ⚠️ 未找到 onnx2tf 安装位置，跳过源码修补")
            return
        onnx2tf_dir = os.path.dirname(spec.origin)
        target_file = os.path.join(onnx2tf_dir, "utils", "common_functions.py")
        if not os.path.exists(target_file):
            print(f"-> ⚠️ 未找到目标文件: {target_file}，跳过源码修补")
            return
        with open(target_file, "r", encoding="utf-8") as f:
            content = f.read()
        modified = False
        old_pickle = "test_image_data: np.ndarray = np.load(f)"
        new_pickle = "test_image_data: np.ndarray = np.load(f, allow_pickle=True)"
        if old_pickle in content and new_pickle not in content:
            content = content.replace(old_pickle, new_pickle)
            print("-> ✅ 已成功注入 allow_pickle 兼容性补丁")
            modified = True
        offline_data_code = "\n    return np.random.rand(20, 128, 128, 3).astype(np.float32)"
        if "def download_test_image_data" in content and "return np.random.rand(20," not in content:
            content = content.replace(
                "def download_test_image_data() -> np.ndarray:",
                f"def download_test_image_data() -> np.ndarray:{offline_data_code}"
            )
            content = content.replace(
                "def download_test_image_data():",
                f"def download_test_image_data():{offline_data_code}"
            )
            print("-> ✅ 已成功注入离线数据流补丁")
            modified = True
        if modified:
            with open(target_file, "w", encoding="utf-8") as f:
                f.write(content)
    except Exception as e:
        print(f"-> ⚠️ 修补 onnx2tf 源码时出现异常: {e}")

# ============================================================================
# 【新增】安全文件搬运器 - 解决输出目录异常问题
# ============================================================================
def move_tflite_to_target(source_dir, target_dir, encoder_type):
    os.makedirs(target_dir, exist_ok=True)
    found = False
    search_dirs = [source_dir]
    if not os.path.exists(source_dir):
        cwd_items = [d for d in os.listdir('.') if os.path.isdir(d)]
        suspicious = [d for d in cwd_items if d not in (
            'saved_model_text', 'saved_model_image', 'checkpoints',
            '__pycache__', '.git', '.venv', 'venv'
        )]
        search_dirs.extend(suspicious)
    for search_path in search_dirs:
        if not os.path.exists(search_path):
            continue
        for root, _, files in os.walk(search_path):
            for file in files:
                if file.endswith('.tflite'):
                    src_file = os.path.join(root, file)
                    dst_file = os.path.join(target_dir, f"mobileclip_{encoder_type}.tflite")
                    print(f"   📦 正在移动模型: {src_file} -> {dst_file}")
                    shutil.move(src_file, dst_file)
                    found = True
    # 清理可能残留的错误文件夹 'b'
    if os.path.exists('b') and os.path.isdir('b'):
        try:
            shutil.rmtree('b')
            print("   🧹 已清理异常生成的 'b' 文件夹")
        except Exception:
            pass
    return found

# ============================================================================
# 【核心修复 5 新增】：调用 onnx2tf 时禁止 Flex 算子，并带版本兼容回退
# ----------------------------------------------------------------------------
# onnx2tf 不同版本对"禁止退化为 Flex/Select TF 算子"的参数支持情况不完全一致。
# 这里优先尝试用户要求的 --disable_flex_ops；如果当前安装的 onnx2tf 版本不
# 识别该参数（返回非零且提示 unrecognized arguments），则自动回退为不带该
# 参数的命令并给出明确警告，避免直接中断整个导出流程。
# ============================================================================
def run_onnx2tf(abs_onnx_path, abs_output_dir):
    base_cmd = ["onnx2tf", "-i", abs_onnx_path, "-o", abs_output_dir]
    cmd_with_flag = base_cmd + ["--disable_flex_ops"]

    print(f"   🚀 执行命令: {' '.join(cmd_with_flag)}")
    result = subprocess.run(cmd_with_flag, capture_output=True, text=True)

    if result.returncode == 0:
        if result.stdout:
            print(result.stdout)
        return

    combined_output = (result.stdout or "") + (result.stderr or "")
    unrecognized = "unrecognized arguments" in combined_output and "--disable_flex_ops" in combined_output

    if unrecognized:
        print("   ⚠️ 当前 onnx2tf 版本不支持 --disable_flex_ops 参数，回退为不带该参数重试...")
        print(f"   🚀 执行命令: {' '.join(base_cmd)}")
        result2 = subprocess.run(base_cmd, capture_output=True, text=True)
        if result2.returncode != 0:
            print(result2.stdout)
            print(result2.stderr)
            raise subprocess.CalledProcessError(result2.returncode, base_cmd)
        if result2.stdout:
            print(result2.stdout)
        return

    # 非"参数不识别"导致的失败：说明确实存在无法转换为 Builtin 的节点，
    # 直接把 onnx2tf 的报错原样打印出来，方便定位具体是哪个 ONNX 节点导致的。
    print(result.stdout)
    print(result.stderr)
    raise subprocess.CalledProcessError(result.returncode, cmd_with_flag)


# ============================================================================
# 通用导出流程
# ============================================================================
def export_encoder(encoder_type: str, checkpoint_path: str):
    print(f"\n{'=' * 60}")
    print(f"  开始导出 MobileCLIP-S0 {encoder_type.upper()} Encoder")
    print(f"{'=' * 60}")

    try:
        v = importlib.metadata.version("onnx2tf")
        print(f"ℹ️  onnx2tf 版本: {v}")
    except Exception:
        print("⚠️ 无法获取 onnx2tf 版本")

    # 文本编码器涉及 argmax 取 EOT token，提前尝试源码级修补
    if encoder_type == "text":
        print(f"0. 正在尝试修补 mobileclip 源码中的 EOT argmax 写法...")
        patch_mobileclip_argmax_source()

    print(f"1. 正在加载预训练模型 MobileCLIP-S0...")
    model, _, preprocess = mobileclip.create_model_and_transforms(
        'mobileclip_s0', pretrained=checkpoint_path
    )

    if encoder_type == "image":
        encoder = model.image_encoder
        dummy_input = torch.randn(1, 3, 224, 224)
        input_name = "input_image"
        output_name = "image_embeddings"
        onnx_filename = "mobileclip_image_encoder.onnx"
        tflite_output_dir = "saved_model_image"
    elif encoder_type == "text":
        encoder = model.text_encoder
        # token id 张量使用 int32，减少后续 argmax/gather 相关算子的类型分歧
        dummy_input = torch.randint(0, 49408, (1, 77), dtype=torch.int32)
        input_name = "input_ids"
        output_name = "text_embeddings"
        onnx_filename = "mobileclip_text_encoder.onnx"
        tflite_output_dir = "saved_model_text"
    else:
        raise ValueError(f"不支持的编码器类型: {encoder_type}")

    os.makedirs(tflite_output_dir, exist_ok=True)
    abs_onnx_path = os.path.abspath(onnx_filename)
    abs_output_dir = os.path.abspath(tflite_output_dir)

    encoder.eval()

    print(f"2. 正在替换 {encoder_type} encoder 中的精确 GELU 为 tanh 近似...")
    replaced_count = replace_gelu_with_tanh_approx(encoder)
    print(f"   -> 共替换 {replaced_count} 个 nn.GELU 模块")

    # ✅ 关键修复：opset_version 改为 17，避免 PyTorch 新版导出器降级失败
    print(f"3. 正在导出 ONNX ({onnx_filename}) [opset=17]...")
    torch.onnx.export(
        encoder, dummy_input, onnx_filename,
        export_params=True, opset_version=17,
        do_constant_folding=True,
        input_names=[input_name], output_names=[output_name],
    )
    print(f"   ✅ ONNX 导出成功")

    print(f"4. 正在校验 ONNX 图中是否残留不兼容算子...")
    onnx_model = onnx.load(onnx_filename)
    erf_nodes = [n.name or n.op_type for n in onnx_model.graph.node if n.op_type == "Erf"]
    if erf_nodes:
        print(f"   -> ⚠️ 仍有 {len(erf_nodes)} 个 Erf 节点")
    else:
        print(f"   -> ✅ 无 Erf 节点")

    if encoder_type == "text":
        risky_ops = ["Arange", "Trilu", "NonZero", "Where", "TopK"]
        risky_nodes = [n for n in onnx_model.graph.node if n.op_type in risky_ops]
        if risky_nodes:
            print(f"   -> ⚠️ Text Encoder 发现 {len(risky_nodes)} 个高风险算子")

        argmax_nodes = [n for n in onnx_model.graph.node if n.op_type == "ArgMax"]
        if argmax_nodes:
            for n in argmax_nodes:
                # 找到该 ArgMax 节点输入张量的声明类型（如果能在 value_info / input 中找到）
                input_name_ref = n.input[0] if n.input else None
                dtype_str = "未知"
                for vi in list(onnx_model.graph.value_info) + list(onnx_model.graph.input):
                    if vi.name == input_name_ref:
                        dtype_str = onnx.TensorProto.DataType.Name(vi.type.tensor_type.elem_type)
                        break
                print(f"   -> ℹ️ 发现 ArgMax 节点: {n.name or '(unnamed)'}, 输入类型: {dtype_str}")

    print(f"5. 正在使用 onnx2tf 转换为 TFLite（已启用 --disable_flex_ops）...")
    patch_onnx2tf_source_code()

    try:
        run_onnx2tf(abs_onnx_path, abs_output_dir)
    except subprocess.CalledProcessError as e:
        print(f"   ❌ ONNX 转 TFLite 失败 (返回码 {e.returncode})")
        sys.exit(1)
    finally:
        if os.path.exists(onnx_filename):
            os.remove(onnx_filename)

    print(f"6. 正在整理输出文件并校验 Flex/Custom 算子...")
    if not move_tflite_to_target(abs_output_dir, tflite_output_dir, encoder_type):
        print(f"   ❌ 未能找到任何 .tflite 文件！")
        sys.exit(1)

    tflite_path = os.path.join(tflite_output_dir, f"mobileclip_{encoder_type}.tflite")
    if not os.path.exists(tflite_path):
        print(f"   ❌ 预期文件不存在: {tflite_path}")
        sys.exit(1)

    with open(tflite_path, "rb") as f:
        model_content = f.read()

    interpreter = tf.lite.Interpreter(model_content=model_content)
    interpreter.allocate_tensors()
    ops = interpreter._get_ops_details()

    # ✅ 更严苛的校验：同时拦截 Flex* 与 CUSTOM 算子（例如某些 GatherNd/Select
    # 在个别 TF 版本下不带 Flex 前缀，而是直接以 CUSTOM 形式出现）
    non_builtin_ops = []
    for detail in ops:
        op_name = detail.get('op_name', '')
        if op_name.startswith('Flex') or op_name == 'CUSTOM':
            non_builtin_ops.append(detail)

    if non_builtin_ops:
        print(f"   ❌ 校验失败：模型中仍包含 {len(non_builtin_ops)} 个非原生（Flex/Custom）算子")
        for op in non_builtin_ops:
            print(f"      - Node {op['index']}: {op['op_name']}")
        print(f"   💡 提示：若为 Text Encoder，请重点检查 ArgMax / GatherNd 相关节点，")
        print(f"           确认 EOT token 索引逻辑已使用 int32 类型且未产生动态 Gather。")
        sys.exit(1)
    else:
        size_mb = len(model_content) / (1024 * 1024)
        print(f"   ✅ 校验通过！100% Builtin 算子 | {size_mb:.1f} MB")
        print(f"   📁 最终模型位置: {os.path.abspath(tflite_path)}")


# ============================================================================
# CLI 入口
# ============================================================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="MobileCLIP-S0 TFLite 导出工具")
    parser.add_argument(
        "--type", type=str, required=True, choices=["image", "text", "both"],
        help="要导出的编码器类型: image / text / both"
    )
    parser.add_argument(
        "--checkpoint", type=str, default="checkpoints/mobileclip_s0.pt",
        help="MobileCLIP 预训练权重路径"
    )
    args = parser.parse_args()

    if not os.path.exists(args.checkpoint):
        print(f"❌ 找不到权重文件: {args.checkpoint}")
        sys.exit(1)

    if args.type in ("image", "both"):
        export_encoder("image", args.checkpoint)
    if args.type in ("text", "both"):
        export_encoder("text", args.checkpoint)

    print("\n✅ 全部导出与校验任务顺利完成！")