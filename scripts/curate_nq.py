import pandas as pd

# 1. 读取下载好的原始 Parquet 文件
df = pd.read_parquet("curated_datasets/nq-train.parquet")

# 2. 查看原始列名（通常包含 question 和 answer 文本）
print("Original columns:", df.columns)

# 3. 随机或顺序抽取 500 条高质量问答对作为验证集
# 确保文本不为空
curated_df = df.dropna(subset=['query', 'answer']).head(500)

# 4. 仅保留系统评估核心需要的列
# 比如只需要问题文本作为检索输入，答案文本作为 ground truth（地面标准）
curated_df = curated_df[['query', 'answer']].rename(columns={'query': 'question'})

# 5. 保存为轻量且易于读取的格式（如 JSON 或 CSV）
curated_df.to_json("curated_datasets/Natural_Questions/nq_val_500.json", orient="records", indent=2, force_ascii=False)
print("成功生成精选验证集：nq_val_500.json")