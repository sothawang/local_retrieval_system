import os
import random
import shutil
from collections import defaultdict

# 1. 定义路径
RAW_DATA_DIR = r"E:\all.code\Offline_Accessible_Multimodal_Local_Content_Retrieval_System\curated_datasets\RVL-CDIP-raw"                 # 包含 images 文件夹和 val.txt 的原始大文件夹
VAL_TXT_PATH = os.path.join(RAW_DATA_DIR, "val.txt")

# 目标存放文件夹
TARGET_DIR = r"E:\all.code\Offline_Accessible_Multimodal_Local_Content_Retrieval_System\curated_datasets\RVL-CDIP"
TARGET_TXT_PATH = os.path.join(TARGET_DIR, "curated_val.txt")

os.makedirs(TARGET_DIR, exist_ok=True)

# 2. 读取 val.txt 并按类别归类
print("正在读取原始索引文件...")
category_buckets = defaultdict(list)

with open(VAL_TXT_PATH, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        rel_path, label = line.split()
        category_buckets[label].append(rel_path)

# 3. 开始对每个类别进行等量抽样，并保持原有的目录层级
SAMPLES_PER_CLASS = 50
curated_lines = []

print(f"开始抽样并保持目录层级结构...")
for label, rel_paths in category_buckets.items():
    sampled_paths = random.sample(rel_paths, min(SAMPLES_PER_CLASS, len(rel_paths)))
    
    for rel_path in sampled_paths:
        # 原始图片的绝对路径
        src_image_path = os.path.join(RAW_DATA_DIR, "images", rel_path)
        
        # 目标图片的绝对路径（保持 rel_path 的多层级结构）
        dest_image_path = os.path.join(TARGET_DIR, rel_path)
        
        # 动态创建该图片所需的多级父目录
        dest_image_dir = os.path.dirname(dest_image_path)
        os.makedirs(dest_image_dir, exist_ok=True)
        
        # 复制图片
        if os.path.exists(src_image_path):
            shutil.copy(src_image_path, dest_image_path)
            # 写入新的索引文件，保持原有路径格式
            curated_lines.append(f"{rel_path} {label}\n")
        else:
            print(f"警告：未找到图片 {src_image_path}")

# 4. 写入新的精简版索引文件
with open(TARGET_TXT_PATH, "w", encoding="utf-8") as f:
    f.writelines(curated_lines)

print(f"数据结构化整理完成！")
print(f"轻量多层级验证集已生成至: {TARGET_DIR}")