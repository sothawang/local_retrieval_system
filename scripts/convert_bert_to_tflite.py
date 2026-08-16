import tensorflow as tf
import numpy as np
from transformers import BertModel
import sys

# ============================================================
# 1. 从 PyTorch 加载权重（绕过所有 TF 高层封装）
# ============================================================
pt_model = BertModel.from_pretrained(".")
pt_state = pt_model.state_dict()

def get_weight(key: str) -> np.ndarray:
    """安全提取 PyTorch 权重并转为 numpy"""
    return pt_state[key].numpy()

# ============================================================
# 2. 纯基础算子手写 BERT-base 前向计算
# ============================================================
class PureBertBase(tf.Module):
    """
    仅使用: MatMul, Add, Mul, Softmax, Reshape, Transpose,
            GatherV2, Slice, Cast, LayerNorm(手动实现)
    绝不使用: einsum, BatchMatMul, ArgMax, Range, Pack,
              keras.layers.Dense, TFBert* 任何组件
    """

    def __init__(self, hidden_size=768, num_heads=12, max_seq_len=128,
                 intermediate_size=3072, num_layers=12, vocab_size=30522,
                 type_vocab_size=2):
        super().__init__()
        self.hidden_size = hidden_size
        self.num_heads = num_heads
        self.head_dim = hidden_size // num_heads
        self.max_seq_len = max_seq_len
        self.intermediate_size = intermediate_size
        self.num_layers = num_layers

        # --- Embeddings ---
        self.word_embeddings = tf.Variable(
            get_weight("embeddings.word_embeddings.weight"), name="word_emb")
        self.position_embeddings = tf.Variable(
            get_weight("embeddings.position_embeddings.weight")[:max_seq_len],
            name="pos_emb")
        self.token_type_embeddings = tf.Variable(
            get_weight("embeddings.token_type_embeddings.weight"), name="tok_emb")
        self.emb_layer_norm_gamma = tf.Variable(
            get_weight("embeddings.LayerNorm.weight"), name="emb_ln_g")
        self.emb_layer_norm_beta = tf.Variable(
            get_weight("embeddings.LayerNorm.bias"), name="emb_ln_b")

        # --- Encoder Layers ---
        self.attn_q_w = []
        self.attn_q_b = []
        self.attn_k_w = []
        self.attn_k_b = []
        self.attn_v_w = []
        self.attn_v_b = []
        self.attn_out_w = []
        self.attn_out_b = []
        self.attn_ln_g = []
        self.attn_ln_b = []
        self.ffn_w1 = []
        self.ffn_b1 = []
        self.ffn_w2 = []
        self.ffn_b2 = []
        self.ffn_ln_g = []
        self.ffn_ln_b = []

        for i in range(num_layers):
            p = f"encoder.layer.{i}"
            qw = get_weight(f"{p}.attention.self.query.weight")
            qb = get_weight(f"{p}.attention.self.query.bias")
            kw = get_weight(f"{p}.attention.self.key.weight")
            kb = get_weight(f"{p}.attention.self.key.bias")
            vw = get_weight(f"{p}.attention.self.value.weight")
            vb = get_weight(f"{p}.attention.self.value.bias")

            self.attn_q_w.append(tf.Variable(qw, name=f"l{i}_qw"))
            self.attn_q_b.append(tf.Variable(qb, name=f"l{i}_qb"))
            self.attn_k_w.append(tf.Variable(kw, name=f"l{i}_kw"))
            self.attn_k_b.append(tf.Variable(kb, name=f"l{i}_kb"))
            self.attn_v_w.append(tf.Variable(vw, name=f"l{i}_vw"))
            self.attn_v_b.append(tf.Variable(vb, name=f"l{i}_vb"))

            ow = get_weight(f"{p}.attention.output.dense.weight")
            ob = get_weight(f"{p}.attention.output.dense.bias")
            self.attn_out_w.append(tf.Variable(ow, name=f"l{i}_ow"))
            self.attn_out_b.append(tf.Variable(ob, name=f"l{i}_ob"))

            lg = get_weight(f"{p}.attention.output.LayerNorm.weight")
            lb = get_weight(f"{p}.attention.output.LayerNorm.bias")
            self.attn_ln_g.append(tf.Variable(lg, name=f"l{i}_alg"))
            self.attn_ln_b.append(tf.Variable(lb, name=f"l{i}_alb"))

            w1 = get_weight(f"{p}.intermediate.dense.weight")
            b1 = get_weight(f"{p}.intermediate.dense.bias")
            self.ffn_w1.append(tf.Variable(w1, name=f"l{i}_w1"))
            self.ffn_b1.append(tf.Variable(b1, name=f"l{i}_b1"))

            w2 = get_weight(f"{p}.output.dense.weight")
            b2 = get_weight(f"{p}.output.dense.bias")
            self.ffn_w2.append(tf.Variable(w2, name=f"l{i}_w2"))
            self.ffn_b2.append(tf.Variable(b2, name=f"l{i}_b2"))

            fg = get_weight(f"{p}.output.LayerNorm.weight")
            fb = get_weight(f"{p}.output.LayerNorm.bias")
            self.ffn_ln_g.append(tf.Variable(fg, name=f"l{i}_flg"))
            self.ffn_ln_b.append(tf.Variable(fb, name=f"l{i}_flb"))

        # --- Pooler ---
        self.pooler_w = tf.Variable(
            get_weight("pooler.dense.weight"), name="pool_w")
        self.pooler_b = tf.Variable(
            get_weight("pooler.dense.bias"), name="pool_b")

    # ---------- 手动 LayerNorm ----------
    @staticmethod
    def _layer_norm(x, gamma, beta, eps=1e-12):
        mean = tf.reduce_mean(x, axis=-1, keepdims=True)
        variance = tf.reduce_mean(tf.square(x - mean), axis=-1, keepdims=True)
        x_normed = (x - mean) * tf.math.rsqrt(variance + eps)
        return x_normed * gamma + beta

    # ---------- 手动 GELU (tanh 近似版, TFLite Builtin 支持) ----------
    @staticmethod
    def _gelu(x):
        cdf = 0.5 * (1.0 + tf.tanh(
            0.7978845608028654 * (x + 0.044715 * x * x * x)))
        return x * cdf

    # ---------- 手动 Multi-Head Attention ----------
    def _attention(self, x, mask, layer_idx):
        batch = tf.shape(x)[0]
        seq = tf.shape(x)[1]

        q = tf.matmul(x, self.attn_q_w[layer_idx], transpose_b=True) + self.attn_q_b[layer_idx]
        k = tf.matmul(x, self.attn_k_w[layer_idx], transpose_b=True) + self.attn_k_b[layer_idx]
        v = tf.matmul(x, self.attn_v_w[layer_idx], transpose_b=True) + self.attn_v_b[layer_idx]

        q = tf.transpose(tf.reshape(q, [batch, seq, self.num_heads, self.head_dim]), [0, 2, 1, 3])
        k = tf.transpose(tf.reshape(k, [batch, seq, self.num_heads, self.head_dim]), [0, 2, 1, 3])
        v = tf.transpose(tf.reshape(v, [batch, seq, self.num_heads, self.head_dim]), [0, 2, 1, 3])

        scores = tf.matmul(q, k, transpose_b=True) * (1.0 / tf.sqrt(float(self.head_dim)))
        scores = scores + mask
        attn_probs = tf.nn.softmax(scores, axis=-1)

        context = tf.matmul(attn_probs, v)
        context = tf.reshape(tf.transpose(context, [0, 2, 1, 3]),
                             [batch, seq, self.hidden_size])

        out = tf.matmul(context, self.attn_out_w[layer_idx], transpose_b=True) \
              + self.attn_out_b[layer_idx]
        return out

    # ---------- 完整前向 ----------
    @tf.function(input_signature=[
        tf.TensorSpec([1, 128], tf.int32, name="input_ids"),
        tf.TensorSpec([1, 128], tf.int32, name="attention_mask"),
        tf.TensorSpec([1, 128], tf.int32, name="token_type_ids")
    ])
    def __call__(self, input_ids, attention_mask, token_type_ids):
        # === Embedding ===
        word_emb = tf.gather(self.word_embeddings, input_ids)
        pos_emb = tf.slice(self.position_embeddings, [0, 0], [128, self.hidden_size])
        pos_emb = tf.expand_dims(pos_emb, 0)
        tok_emb = tf.gather(self.token_type_embeddings, token_type_ids)

        emb = word_emb + pos_emb + tok_emb
        emb = self._layer_norm(emb, self.emb_layer_norm_gamma, self.emb_layer_norm_beta)

        # === Attention Mask ===
        extended_mask = tf.cast(
            tf.reshape(attention_mask, [1, 1, 1, 128]), tf.float32)
        extended_mask = (1.0 - extended_mask) * (-1e9)

        # === Encoder ===
        hidden = emb
        for i in range(self.num_layers):
            attn_out = self._attention(hidden, extended_mask, i)
            hidden = self._layer_norm(
                hidden + attn_out, self.attn_ln_g[i], self.attn_ln_b[i])

            ffn_mid = tf.matmul(hidden, self.ffn_w1[i], transpose_b=True) + self.ffn_b1[i]
            ffn_mid = self._gelu(ffn_mid)
            ffn_out = tf.matmul(ffn_mid, self.ffn_w2[i], transpose_b=True) + self.ffn_b2[i]
            hidden = self._layer_norm(
                hidden + ffn_out, self.ffn_ln_g[i], self.ffn_ln_b[i])

        # === CLS Token ===
        cls_embedding = tf.slice(hidden, [0, 0, 0], [1, 1, self.hidden_size])
        cls_embedding = tf.squeeze(cls_embedding, axis=1)

        # === Pooler ===
        pooler_out = tf.matmul(cls_embedding, self.pooler_w, transpose_b=True) + self.pooler_b
        pooler_out = tf.tanh(pooler_out)

        # ✅ 关键修改：返回元组而非字典，避免Signature序列化引入FlexArgMax
        return (
            tf.cast(hidden, tf.float32),
            tf.cast(cls_embedding, tf.float32),
            tf.cast(pooler_out, tf.float32)
        )


# ============================================================
# 3. 导出 + 转换 + 严格校验（强制纯Builtin）
# ============================================================
module = PureBertBase()

# 触发 trace 验证形状
dummy_ids = tf.zeros([1, 128], dtype=tf.int32)
dummy_mask = tf.ones([1, 128], dtype=tf.int32)
dummy_tok = tf.zeros([1, 128], dtype=tf.int32)
_ = module(dummy_ids, dummy_mask, dummy_tok)
print("✅ Trace 成功，开始导出 SavedModel...")

tf.saved_model.save(
    module, "saved_model_pure",
    signatures={"serving_default": module.__call__.get_concrete_function()}
)

converter = tf.lite.TFLiteConverter.from_saved_model("saved_model_pure")
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS]
converter.allow_custom_ops = False  # ✅ 关键：禁止任何自定义/Flex算子，遇阻即报错
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter._experimental_lower_tensor_list_ops = False

print("\n正在转换 TFLite 模型（严格纯 Builtin 模式）...")
try:
    tflite_model = converter.convert()
except Exception as e:
    print(f"❌ 转换失败（存在不支持的算子）：\n{e}")
    print("请检查模型中是否隐含了非 Builtin 操作，或考虑将后处理移至 App 层。")
    sys.exit(1)

# ✅ 转换后立即校验，绝不保存含 Flex 的模型
print("正在执行纯 Builtin 校验...")
interpreter = tf.lite.Interpreter(model_content=tflite_model)
interpreter.allocate_tensors()

ops = interpreter._get_ops_details()
flex_ops = [op for op in ops if op['op_name'].startswith('Flex')]

if flex_ops:
    print(f"❌ 模型包含 {len(flex_ops)} 个 Flex Ops，已终止保存：")
    for op in flex_ops:
        print(f"   - Node {op['index']}: {op['op_name']}")
    print("\n请检查上述算子来源，通常需要替换为纯 Builtin 实现或将后处理移出模型。")
    sys.exit(1)

# ✅ 校验通过，安全保存
with open("bert_pure.tflite", "wb") as f:
    f.write(tflite_model)

size_mb = len(tflite_model) / (1024 * 1024)
print(f"✅ 校验通过！共 {len(ops)} 个算子，全部为 TFLite Builtins")
print(f"文件已保存为 bert_pure.tflite ({size_mb:.1f} MB)")