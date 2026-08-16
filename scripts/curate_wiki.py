import bz2
import xml.etree.ElementTree as ET
import os
import json
import random
import re

# 配置路径
compressed_file = "enwiki-2026-06-01-p10p1130124.xml.bz2"
base_path = r"E:\all.code\Offline_Accessible_Multimodal_Local_Content_Retrieval_System\curated_datasets\wikipedia"
train_dir = os.path.join(base_path, "train")
val_dir = os.path.join(base_path, "validation")

os.makedirs(train_dir, exist_ok=True)
os.makedirs(val_dir, exist_ok=True)

# 简单的正则：清洗掉Wikitext中常见的控制字符和链接标记
def clean_wikitext(text):
    if not text:
        return ""
    text = re.sub(r'\[\[(?:[^|\]]*\|)?([^\]]+)\]\]', r'\1', text) # 移除链接标记 [[A|B]] -> B
    text = re.sub(r'\{\{[^\|\}]*\}\}', '', text) # 移除简单模板
    text = re.sub(r'={2,}\s*(.*?)\s*={2,}', r'\1', text) # 移除标题符号 === Title === -> Title
    return text.strip()

all_chunks = []
chunk_size = 300  # 适配 BERT 的 512 token 限制

print("正在流式解析压缩包并生成文本块...")

# 使用 bz2.open 以流式方式读取，避免内存溢出
with bz2.open(compressed_file, 'rt', encoding='utf-8') as f:
    # 构造迭代器，逐个解析其中的 <page> 标签
    context = ET.iterparse(f, events=('end',))
    
    for event, elem in context:
        # 匹配维基百科的页面标签（注意带有名空间）
        if elem.tag.endswith('page'):
            title_elem = elem.find('{*}title')
            id_elem = elem.find('{*}id')
            revision = elem.find('{*}revision')
            text_elem = revision.find('{*}text') if revision is not None else None
            
            if title_elem is not None and text_elem is not None and text_elem.text:
                title = title_elem.text
                page_id = id_elem.text if id_elem is not None else "0"
                raw_text = text_elem.text
                
                # 过滤掉重定向页面和特殊无用页面
                if raw_text.startswith('#REDIRECT') or title.startswith('Wikipedia:') or title.startswith('Template:'):
                    elem.clear()
                    continue
                
                cleaned_text = clean_wikitext(raw_text)
                words = cleaned_text.split()
                
                # 按照固定长度进行文本切块 (Chunking)
                for i in range(0, len(words), chunk_size):
                    chunk_text = " ".join(words[i:i+chunk_size])
                    if len(words[i:i+chunk_size]) > 50: # 过滤掉太短的无意义文本块
                        all_chunks.append({
                            "id": f"{page_id}_{i//chunk_size}",
                            "title": title,
                            "text": chunk_text
                        })
            
            # 清理处理过的节点，释放内存
            elem.clear()
            
            # 限制测试数量：如果只做环境跑通和测试，收集到5000个块就可以停止了，避免生成太慢
            if len(all_chunks) >= 5000:
                break

print(f"数据切块完成，共生成 {len(all_chunks)} 个 Chunks。开始切分验证集...")

# 随机打乱并切分出验证集
random.shuffle(all_chunks)
val_size = min(1000, int(len(all_chunks) * 0.2)) # 提取1000条或20%作为验证集

val_set = all_chunks[:val_size]
train_set = all_chunks[val_size:]

# 写入目标 E 盘目录
with open(os.path.join(train_dir, "wiki_train.jsonl"), "w", encoding="utf-8") as f:
    for chunk in train_set:
        f.write(json.dumps(chunk, ensure_ascii=False) + "\n")

with open(os.path.join(val_dir, "wiki_val.jsonl"), "w", encoding="utf-8") as f:
    for chunk in val_set:
        f.write(json.dumps(chunk, ensure_ascii=False) + "\n")

print(f"🎉 Curation 成功完成！\n训练集路径: {train_dir}\\wiki_train.jsonl ({len(train_set)} 条)\n验证集路径: {val_dir}\\wiki_val.jsonl ({len(val_set)} 条)")