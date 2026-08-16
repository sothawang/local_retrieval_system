import os
import json
import shutil
from pathlib import Path

# ==================== 路径配置 ====================
RAW_ANNOTATIONS_PATH = "./curated_datasets/coco_val2017_raw/annotations/captions_val2017.json"
# 更改为父级目录，使用 Path.rglob 进行深度递归搜索，防止多层文件夹嵌套
RAW_IMAGES_PARENT = "./curated_datasets/coco_val2017_raw"

CURATED_DIR = "./curated_datasets/coco_curated_500"
CURATED_IMAGES_DIR = os.path.join(CURATED_DIR, "images")
CURATED_JSON_PATH = os.path.join(CURATED_DIR, "image_caption_pairs.json")

SAMPLE_SIZE = 500

def curate_coco():
    print("=> 开始解析原始 COCO 2017 标签文件...")
    if not os.path.exists(RAW_ANNOTATIONS_PATH):
        print(f"[错误] 未找到原始标签文件: {RAW_ANNOTATIONS_PATH}")
        return

    with open(RAW_ANNOTATIONS_PATH, "r", encoding="utf-8") as f:
        raw_data = json.load(f)

    id_to_filename = {img["id"]: img["file_name"] for img in raw_data["images"]}

    curated_pairs = {}
    for ann in raw_data["annotations"]:
        img_id = ann["image_id"]
        caption = ann["caption"].strip().replace("\n", "")
        if img_id in id_to_filename:
            filename = id_to_filename[img_id]
            if filename not in curated_pairs:
                curated_pairs[filename] = caption

    print(f"=> 全量图文对提取完毕，共解析出 {len(curated_pairs)} 张图的独立描述。")

    # 建立一个本地原始目录结构下所有 .jpg 文件的扫描索引（解决前导零或深层嵌套问题）
    print("=> 正在扫描原始目录下的实际图片文件...")
    actual_images = {}
    for p in Path(RAW_IMAGES_PARENT).rglob("*.jpg"):
        # 建立 纯文件名 -> 绝对路径 的映射
        actual_images[p.name] = p
        # 同时支持去掉前导零的文件名匹配（双保险）
        actual_images[p.name.lstrip("0")] = p

    # 执行切片采样
    sampled_filenames = list(curated_pairs.keys())
    os.makedirs(CURATED_IMAGES_DIR, exist_ok=True)

    final_curated_data = {}
    success_count = 0

    print(f"=> 开始动态匹配并搬运 {SAMPLE_SIZE} 张图片...")
    for filename in sampled_filenames:
        if success_count >= SAMPLE_SIZE:
            break
            
        # 尝试标准匹配或去零匹配
        lookup_key = filename
        if lookup_key not in actual_images and filename.lstrip("0") in actual_images:
            lookup_key = filename.lstrip("0")

        if lookup_key in actual_images:
            src_path = actual_images[lookup_key]
            dst_path = os.path.join(CURATED_IMAGES_DIR, filename) # 导出时保持规范的 12 位标准名
            
            shutil.copy(src_path, dst_path)
            final_curated_data[filename] = curated_pairs[filename]
            success_count += 1

    # 导出清洗后的轻量标签
    with open(CURATED_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(final_curated_data, f, indent=4, ensure_ascii=False)

    print("\n[ OK ] COCO 数据集策展(Curate)清洗圆满成功！")
    print(f"   - 成功搬运并对齐图片: {success_count} 张 -> 存放于 {CURATED_IMAGES_DIR}")
    print(f"   - 成功生成扁平化轻量标签: 1 个 -> 存放于 {CURATED_JSON_PATH}")

if __name__ == "__main__":
    curate_coco()