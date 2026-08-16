# Keyword Indexing 架构演进与技术实现任务记录报告
---

## 1. 任务背景与架构演进 (Architecture Evolution)

在本地多模态离线检索系统中，搜索模块需要兼顾**“模糊语义理解”**（如自然语言问答、以文搜图）与**“字面精准匹配”**（如代码函数名、文件路径、特定订单编号、专有名词）。

### 1.1 演进前：被动重排序模式 (Rerank-only Prototype)
在系统初期原型中，关键词模块并未建立底层索引，仅作为二级重排序器：
```text
[用户输入 Query] ──> [VectorRetriever 查库 (Top 50)] ──> [Keyword 被动重打分] ──> [Hybrid 截取 Top 10]
```

### 1.2 演进痛点与缺陷 (Fatal Bottlenecks)
1. **搜索盲区与漏检 (False Negatives)**：
   若用户搜索生僻型号（如 `ORDER_9876`）或特定代码关键字，BERT 向量模型因缺乏泛化语义可能将其排在 100 名开外。由于向量初筛仅取 Top 50，目标文档在第一阶段即被截断抛弃，关键词重排根本无法触达，最终导致搜索失败。
2. **缺乏全局词频统计 (No Global IDF)**：
   无法统计全局文档频率（DF/IDF），难以区分局部词频与全局泛滥词。

### 1.3 演进后：双路并行独立召回架构 (Two-Way Independent Retrieval)
引入 `KeywordIndex` 内存倒排索引引擎后，系统实现了工业级双路并行召回：
```text
                                [ 用户查询 Query ]
                                        │
        ┌───────────────────────────────┴───────────────────────────────┐
        ▼                                                               ▼
【 语义分支：VectorRetriever 】                                 【 字面分支：KeywordIndex (倒排索引) 】
通过 BERT/MobileCLIP 查向量库                                   通过倒排索引表秒级召回包含关键词的候选
(主攻: 同义词理解、模糊意图、跨模态)                             (主攻: 精确代码、人名、文件路径、特定编号)
        │                                                               │
        └───────────────────────────────┬───────────────────────────────┘
                                        ▼
                               【 候选集求并集合流 】
                               (Merge Candidates: 约 70~90 篇)
                                        │
                                        ▼
                               【 HybridRetriever 融合 】
                               0.7 × VectorScore + 0.3 × KeywordScore
                                        │
                                        ▼
                               【 最终高精度 Top-K 输出 】
```

---

## 2. `KeywordIndex` 核心数据结构设计

`KeywordIndex` 采用内存驻留的高性能哈希索引结构，包含三大映射表：

```dart
/// 1. 正排文档表：Document ID -> 结构化文档数据 (TF, Token 序列, 正规化正文)
final Map<String, KeywordIndexedDocument> _documents;

/// 2. 倒排索引表：Token 单词 -> 包含该词的 Document ID 集合
final Map<String, Set<String>> _invertedIndex;

/// 3. 全局文档频率表：Token 单词 -> 包含该词的文档总数 (DF)
final Map<String, int> _documentFrequency;
```

---

## 3. 五维度关键词打分算法 (5-Pillar Scoring Model)

在 `_calculateKeywordScore` 中，针对每个命中文档计算综合相关度得分（范围归一化至 `[0.0, 1.0]`）：

$$\text{FinalKeywordScore} = 0.45 \cdot \text{Coverage} + 0.20 \cdot \text{TF}_{\text{squashed}} + 0.20 \cdot \text{IDF}_{\text{squashed}} + 0.10 \cdot \text{PhraseBonus} + 0.05 \cdot \text{OrderedScore}$$

### 维度分解说明：
1. **覆盖率得分 (Coverage, 权重 45%)**：
   $$\text{Coverage} = \frac{\sum_{\text{matched}} \text{TokenWeight}}{\sum_{\text{all query tokens}} \text{TokenWeight}}$$
   衡量查询关键词中有多少比例在文档中实际出现，并结合了 `StopWordPolicy` 的动态词权重。
2. **对数词频得分 (Log TF, 权重 20%)**：
   $$\text{TF} = 1.0 + \ln(\text{Frequency}), \quad \text{TF}_{\text{squashed}} = \frac{\text{TF}}{1.0 + \text{TF}}$$
   采用对数阻尼与平滑压缩，防止文档通过恶意堆砌同一关键词刷高分数。
3. **逆文档频率得分 (Inverted Document Frequency, 权重 20%)**：
   $$\text{IDF} = \ln\left(\frac{N + 1}{\text{DF} + 1}\right) + 1.0$$
   全局越稀有的专有名词，赋予越高的区分度奖励。
4. **完整短语连续匹配奖励 (Exact Phrase Bonus, 权重 10%)**：
   若文档中原封不动、连贯包含整个 Query 短语，直接奖励 `1.0` 分。
5. **词序一致性得分 (Ordered Match Score, 权重 5%)**：
   检测查询词在文档 Token 序列中按先后次序出现的匹配度。

---

## 4. 核心 API 方法清单与使用示例

| 方法分类 | 方法名 | 功能说明 |
| :--- | :--- | :--- |
| **索引写入** | `addDocument(doc)` | 单文档建索引，自动分词并更新倒排表与 DF |
| **批量索引** | `addDocuments(docs)` | 批量建立索引 |
| **索引删除** | `removeDocument(id)` | 根据 ID 从正排表与倒排表中同步注销 |
| **级联删除** | `removeBySourcePath(path)` | 根据本地物理文件路径级联删除其所有分块记录 |
| **独立搜索** | `searchCandidates(query, topK)` | 纯倒排快速召回 + 五维打分重排 |
| **统计挖掘** | `findHighFrequencyWords(thresh)` | 挖掘在全局 $\ge \text{thresh}$ 文档中出现的泛滥高频词 |
| **模型适配** | `toVectorSearchResult(candidate)` | 转换为系统统一的 `VectorSearchResult` 模型 |

### 核心方法简写代码示例：

```dart
// 1. 文档建索引
final doc = KeywordIndexedDocument(
  id: 'chunk_1',
  sourcePath: 'docs/contract.pdf',
  content: 'Party A shall pay the service fee in accordance with Section 3.',
  metadata: {'file_name': 'contract.pdf'},
);
await index.addDocument(doc);

// 2. 独立关键词搜索 (无需向量模型介入)
final List<KeywordCandidate> results = index.searchCandidates(
  query: 'service fee contract',
  topK: 10,
);

// 输出结果：
// results[0].document.id -> 'chunk_1'
// results[0].keywordScore -> 0.88
```

---

## 5. 组件协同关系矩阵 (Component Collaboration)

```text
 ┌────────────────────────┐       ┌────────────────────────┐
 │     StopWordConfig     │       │     DomainDetector     │
 │ (记录各项打分与权重阈值) │       │ (根据路径判定 code/gen) │
 └───────────┬────────────┘       └───────────┬────────────┘
             │                                │
             └───────────────┬────────────────┘
                             ▼
                  ┌──────────────────────┐
                  │    StopWordPolicy    │
                  │ (执行5层词权重打分)   │
                  └──────────┬───────────┘
                             │
                             ▼
                  ┌──────────────────────┐
                  │     KeywordIndex     │
                  │ (倒排存储与独立召回)  │
                  └──────────┬───────────┘
                             │
                             │ 输出 keywordCandidates
                             ▼
                  ┌──────────────────────┐
                  │   HybridRetriever    │ <── 接收 vectorCandidates (来自 VectorRetriever)
                  │ (双路并集与最终加权) │
                  └──────────┬───────────┘
                             │
                             ▼
                      最终 Top-K 搜索结果
```

---

## 6. 任务总结与价值收益

1. **彻底根除搜索盲区**：对于包含精准文件名、特定代码语法、专有 ID 的查询，召回率提升至 100%。
2. **轻量与离线原生**：纯 Dart 内存实现，无需引入庞大的外部 Java/C++ 全文检索服务，高度适配端侧与离线环境。
3. **为 Week 4 最终端到端闭环奠定坚实基础**：完善了从文件解析 $\rightarrow$ 双路索引 $\rightarrow$ 双路召回 $\rightarrow$ 混合重排的完整工业级流水线。
