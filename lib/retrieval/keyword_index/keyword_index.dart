import 'package:local_retrieval_system/retrieval/models/vector_search_result.dart';
import 'package:local_retrieval_system/retrieval/token_filter/domain_detector.dart';
import 'package:local_retrieval_system/retrieval/token_filter/stop_word_policy.dart';
import 'dart:math' as math;
import '../token_filter/stop_word_config.dart';

/// 内存倒排索引引擎，实现了双路独立召回
/// - 构建经典倒排索引结构（Inverted Index）
///   - 维护 Token -> `Set<DocumentID>` 的倒排映射表。
///   - 维护 Token -> DF (Document Frequency) 的文档频率表。
/// - 完全独立的关键词秒级召回：
///   - 输入关键词后，无需走向量数据库，直接在倒排索引中通过哈希查找秒级定位所有包含该词的文档，并计算多维词频（TF-IDF + 覆盖率 + 短语匹配 + 顺序匹配）得分。
/// - 支持动态高频词挖掘
///   - 实时统计词在全局文档中的分布比率，为 StopWordPolicy 动态提供停用词判定依据。
/// ```
/// 文档写入阶段:
/// KeywordIndexedDocument → 提取可搜索文本(content+metadata) → 分词 → 统计词频(TF)
///   → 存入 _documents(id→文档) 和 _invertedIndex(token→文档ID集合) 和 _documentFrequency(token→DF)
///
/// 查询阶段:
/// query → 分词 → 用 _invertedIndex 查出候选文档ID(Set并集)
///   → 对每个候选文档算 keywordScore（coverage + TF + IDF + 短语匹配 + 顺序匹配 加权求和）
///   → 按分数降序排序 → 取 topK
/// ```
class KeywordIndex {
  /// 初始化倒排索引引擎，依赖注入停词策略 StopWordPolicy 与领域检测器 DomainDetector
  KeywordIndex({
    required StopWordPolicy stopWordPolicy,
    DomainDetector domainDetector = const DomainDetector(),
  })  : _stopWordPolicy = stopWordPolicy,
        _domainDetector = domainDetector;

  final StopWordPolicy _stopWordPolicy;
  final DomainDetector _domainDetector;

  /// id → KeywordIndexedDocument，存文档本身及其分词结果
  final Map<String, KeywordIndexedDocument> _documents = <String, KeywordIndexedDocument>{};

  /// token → 包含该token的文档ID集合（倒排索引主体）
  final Map<String, Set<String>> _invertedIndex = <String, Set<String>>{};

  /// token → 出现过该token的文档数（DF，用于算IDF）
  final Map<String, int> _documentFrequency = <String, int>{};

  /// 检查当前倒排索引库中是否为空（没有任何已索引文档）。
  /// - 输入：无
  /// - 输出：bool（true 表示索引库为空，false 表示已有文档）。
  bool get isEmpty => _documents.isEmpty;

  /// 获取当前索引库中收录的文档总数。
  /// - 输入：无
  /// - 输出：已索引文档数量
  int get documentCount => _documents.length;

  // ===========================================================================
  // Add document
  // ===========================================================================

  /// 把一篇文档加入索引：拼接可搜索文本→分词→统计TF→存入 _documents，
  /// 并把每个唯一token登记进倒排索引和DF表。若ID已存在，先删除旧版本再重新加入（保证幂等更新
  /// - 输入：
  /// ```
  /// KeywordIndexedDocument(
  ///   id: 'doc_1',
  ///   sourcePath: '/notes/a.txt',
  ///   content: 'Flutter state management with Riverpod',
  ///   metadata: {'data_type': 'text'},
  /// )
  /// ```
  /// - 输出：
  /// ```
  /// 无返回值，但是有下面副作用：
  /// 1. _documents['doc_1'] = 带有 tokens: ['flutter','state','management','with','riverpod']、tokenFrequencies: {flutter:1, state:1, ...} 等信息的新文档对象
  /// 2. _invertedIndex['flutter'] 中加入 'doc_1'（其他token同理）
  /// 3. _documentFrequency['flutter'] +1
  Future<void> addDocument(
      KeywordIndexedDocument document,
      ) async {
    _ensurePolicyReady();

    if (document.id.trim().isEmpty) {
      throw ArgumentError(
        'KeywordIndexedDocument id cannot be empty.',
      );
    }

    // 如果已经存在同 ID，先移除旧版本。
    if (_documents.containsKey(document.id)) {
      await removeDocument(document.id);
    }

    final String searchableText =
    _buildSearchableText(document);

    final List<String> tokens =
    _tokenize(searchableText);

    final Set<String> uniqueTokens =
    tokens.toSet();

    final Map<String, int> frequencies =
    <String, int>{};

    for (final String token in tokens) {
      frequencies[token] =
          (frequencies[token] ?? 0) + 1;
    }

    final KeywordIndexedDocument stored =
    document.copyWith(
      tokenFrequencies: frequencies,
      indexedTokens: uniqueTokens,
      tokens: tokens,
      normalizedText:
      _normalizeText(searchableText),
    );

    _documents[document.id] = stored;

    for (final String token in uniqueTokens) {
      final Set<String> ids =
      _invertedIndex.putIfAbsent(
        token,
            () => <String>{},
      );

      ids.add(document.id);

      _documentFrequency[token] =
          (_documentFrequency[token] ?? 0) + 1;
    }
  }

  // ===========================================================================
  // Add batch
  // ===========================================================================

  /// 批量调用 addDocument，逐个 await。
  /// - 输入：
  /// ```
  /// [doc_1, doc_2, doc_3]
  /// ```
  /// - 输出：
  /// ```
  /// 三篇文档依次被索引，效果等同于分别调用三次 addDocument。
  Future<void> addDocuments(
      List<KeywordIndexedDocument> documents,
      ) async {
    for (final KeywordIndexedDocument document
    in documents) {
      await addDocument(document);
    }
  }

  // ===========================================================================
  // Remove document
  // ===========================================================================

  /// 从索引中彻底移除一篇文档：从 _documents 删除；对其每个token，从倒排索引的对应Set中移除该id，DF减1（减到0则直接删除该token条目）。
  /// -输入：
  /// ```
  /// removeDocument('doc_1')
  /// ```
  /// - 输出：
  /// ```
  /// _documents 中不再有 doc_1
  /// _invertedIndex['flutter'] 中的 'doc_1' 被移除，若移除后集合为空则整个 'flutter' 键被删除
  /// _documentFrequency['flutter'] 减1
  /// 若 id 不存在：什么都不做（静默返回）。
  Future<void> removeDocument(
      String id,
      ) async {
    final KeywordIndexedDocument? existing =
    _documents.remove(id);

    if (existing == null) {
      return;
    }

    for (final String token
    in existing.indexedTokens) {
      final Set<String>? ids =
      _invertedIndex[token];

      if (ids == null) {
        continue;
      }

      ids.remove(id);

      final int currentDf =
          _documentFrequency[token] ?? 0;

      if (currentDf <= 1) {
        _documentFrequency.remove(token);
      } else {
        _documentFrequency[token] =
            currentDf - 1;
      }

      if (ids.isEmpty) {
        _invertedIndex.remove(token);
      }
    }
  }

  // ===========================================================================
  // Remove by source path
  // ===========================================================================

  /// 按来源文件路径批量删除（一个文件可能被拆成多个chunk文档，都共享同一个 sourcePath）。先筛出所有匹配的id，再逐个调用 removeDocument
  /// - 输入：
  /// ```
  /// removeBySourcePath('/notes/a.txt')
  /// ```
  /// - 输出：
  /// ```
  /// 所有 sourcePath == '/notes/a.txt' 的文档（可能是多个chunk）全部从索引中清除。
  Future<void> removeBySourcePath(
      String sourcePath,
      ) async {
    final List<String> idsToRemove =
    _documents.values
        .where(
          (KeywordIndexedDocument document) =>
      document.sourcePath ==
          sourcePath,
    )
        .map(
          (KeywordIndexedDocument document) =>
      document.id,
    )
        .toList(
      growable: false,
    );

    for (final String id in idsToRemove) {
      await removeDocument(id);
    }
  }

  // ===========================================================================
  // Document access
  // ===========================================================================

  /// 按ID直接查文档，不涉及打分。
  /// - 输入：
  /// ```
  /// getDocumentById('doc_1')
  /// ```
  /// - 输出：
  /// ```
  /// 对应的 KeywordIndexedDocument，找不到则返回 null。
  KeywordIndexedDocument? getDocumentById(
      String id,
      ) {
    return _documents[id];
  }

  // ===========================================================================
  // Clear
  // ===========================================================================

  /// 清空整个索引（三个Map全部清空），常用于重建索引前的重置。
  /// - 输入：
  /// ```
  /// 无参数
  /// ```
  /// - 输出：
  /// ```
  /// _documents、_invertedIndex、_documentFrequency 均变为空。
  void clear() {
    _documents.clear();
    _invertedIndex.clear();
    _documentFrequency.clear();
  }

  // ===========================================================================
  // Search candidate IDs
  // ===========================================================================

  /// 给定query，返回排序后的keyword候选。步骤：
  /// 1. 校验 _stopWordPolicy 已初始化，query非空，topK>0
  /// 2. 归一化+分词query
  /// 3. 对每个query token，从倒排索引取出文档ID集合，做并集（Set union）得到候选ID集合
  /// 4. 对每个候选文档调用 _calculateKeywordScore 打分
  /// 5. 按分数降序排序，取前topK个
  /// - 输入：
  /// ```
  /// searchCandidates(query: 'flutter state management', topK: 10)
  /// ```
  /// - 输出：
  /// ```
  /// 按 keywordScore 从高到低排列，最多10条
  /// 若query中所有token都不在索引里 → 返回空列表 []。
  /// 若query为空字符串或全是被过滤掉的字符 → 抛 ArgumentError。
  /// [
  ///   KeywordCandidate(document: doc_1, keywordScore: 0.87),
  ///   KeywordCandidate(document: doc_5, keywordScore: 0.62),
  ///   ...
  /// ]
  List<KeywordCandidate> searchCandidates({
    required String query,
    int topK = 50,
  }) {
    _ensurePolicyReady();

    final String normalizedQuery = _normalizeText(query);

    if (normalizedQuery.isEmpty) {
      throw ArgumentError(
        'Keyword query cannot be empty.',
      );
    }

    if (topK <= 0) {
      throw ArgumentError.value(
        topK,
        'topK',
        'topK must be greater than 0.',
      );
    }

    final List<String> queryTokens =
    _tokenize(normalizedQuery);

    if (queryTokens.isEmpty) {
      return const <KeywordCandidate>[];
    }

    final Set<String> candidateIds =
    <String>{};

    for (final String token in queryTokens) {
      final Set<String>? ids =
      _invertedIndex[token];

      if (ids != null) {
        candidateIds.addAll(ids);
      }
    }

    if (candidateIds.isEmpty) {
      return const <KeywordCandidate>[];
    }

    final List<KeywordCandidate> candidates =
    <KeywordCandidate>[];

    for (final String id in candidateIds) {
      final KeywordIndexedDocument? document =
      _documents[id];

      if (document == null) {
        continue;
      }

      final double score =
      _calculateKeywordScore(
        query: normalizedQuery,
        queryTokens: queryTokens,
        document: document,
      );

      candidates.add(
        KeywordCandidate(
          document: document,
          keywordScore: score,
        ),
      );
    }

    candidates.sort(
          (
          KeywordCandidate a,
          KeywordCandidate b,
          ) =>
          b.keywordScore.compareTo(
            a.keywordScore,
          ),
    );

    if (candidates.length <= topK) {
      return candidates;
    }

    return candidates
        .take(topK)
        .toList(growable: false);
  }

  // ===========================================================================
  // Keyword scoring
  // ===========================================================================

  /// 核心打分函数，对query中的每个唯一token做以下计算
  /// 1. tokenWeight：通过 _stopWordPolicy.getTokenWeight() 得到该token在这个领域(domain)下的权重（比如停用词权重为0会被跳过）
  /// 2. coverage：命中权重 / 总权重（衡量query中有多少比例的重要词命中了）
  /// 3. tfScore：1 + ln(tf) 加权后压缩(_squash)，衡量词频强度
  /// 4. idfScore：标准IDF公式 ln((N+1)/(df+1)) + 1 加权后压缩，衡量词的稀有度/区分度
  /// 5. phraseScore：文档是否整体包含归一化后的完整query字符串（精确短语命中给1.0）
  /// 6. orderedScore：query token是否按顺序（可跳跃）出现在文档token序列中（子序列匹配比例）
  /// ```
  /// 最终加权求和：
  /// score = 0.45*coverage + 0.20*tfScore + 0.20*idfScore + 0.10*phraseScore + 0.05*orderedScore
  /// 再clamp到 [0,1]。
  /// ```
  /// - 输入：
  /// ```
  /// query = 'state management'
  /// document.tokens = ['flutter','state','management','tutorial']
  /// document.tokenFrequencies = {'state':1, 'management':1, 'flutter':1, 'tutorial':1}
  /// ```
  /// - 输出：
  /// ```
  /// 一个 double，例如 0.78（因为coverage=1.0，tf不高，idf视语料库而定，短语可能命中，顺序也命中）
  double _calculateKeywordScore({
    required String query,
    required List<String> queryTokens,
    required KeywordIndexedDocument document,
  }) {
    if (document.tokenFrequencies.isEmpty) {
      return 0.0;
    }

    final RetrievalDomain domain =
    _domainDetector.detectFromPath(
      document.sourcePath,
    );

    final Set<String> uniqueQueryTokens =
    queryTokens.toSet();

    double totalQueryWeight = 0.0;
    double matchedWeight = 0.0;
    double weightedTf = 0.0;
    double weightedIdf = 0.0;

    for (final String token
    in uniqueQueryTokens) {
      final double tokenWeight =
      _stopWordPolicy.getTokenWeight(
        token: token,
        domain: domain,
      );

      if (tokenWeight <= 0.0) {
        continue;
      }

      totalQueryWeight += tokenWeight;

      final int tf =
          document.tokenFrequencies[token] ?? 0;

      if (tf <= 0) {
        continue;
      }

      matchedWeight += tokenWeight;

      final double tfScore =
          1.0 + math.log(tf.toDouble());

      weightedTf +=
          tokenWeight * tfScore;

      final int df =
          _documentFrequency[token] ?? 0;

      if (df > 0 &&
          documentCount > 0) {
        final double idf =
            math.log(
              (documentCount + 1) /
                  (df + 1),
            ) +
                1.0;

        weightedIdf +=
            tokenWeight * idf;
      }
    }

    if (totalQueryWeight <= 0.0) {
      return 0.0;
    }

    final double coverage =
        matchedWeight /
            totalQueryWeight;

    final double tfScore =
    _squash(
      weightedTf /
          totalQueryWeight,
    );

    final double idfScore =
    _squash(
      weightedIdf /
          totalQueryWeight,
    );

    final double phraseScore =
    document.normalizedText.contains(query)
        ? 1.0
        : 0.0;

    final double orderedScore =
    _calculateOrderedMatchScore(
      queryTokens,
      document.tokens,
    );

    double score =
        0.45 * coverage +
            0.20 * tfScore +
            0.20 * idfScore +
            0.10 * phraseScore +
            0.05 * orderedScore;

    return score.clamp(
      0.0,
      1.0,
    );
  }

  // ===========================================================================
  // Convert to VectorSearchResult
  // ===========================================================================

  /// 把 KeywordCandidate 转换成 VectorSearchResult 结构，
  /// 方便 HybridRetriever 用统一的数据结构做候选合并（union）。注意：这里塞进 score 字段的其实是 keywordScore，不是真正的向量分数
  /// - 输入：
  /// ```
  /// toVectorSearchResult(candidate)，其中 candidate.keywordScore = 0.78
  /// ```
  /// - 输出：
  /// ```
  /// VectorSearchResult(
  ///   id: 'doc_1',
  ///   sourcePath: '/notes/a.txt',
  ///   content: '...',
  ///   score: 0.78,   // 实际是keywordScore
  ///   metadata: {...},
  /// )
  VectorSearchResult toVectorSearchResult(
      KeywordCandidate candidate,
      ) {
    final KeywordIndexedDocument document =
        candidate.document;

    return VectorSearchResult(
      id: document.id,
      sourcePath: document.sourcePath,
      content: document.content,

      // 这里放 keyword score 只是为了复用
      // VectorSearchResult 数据结构。
      //
      // HybridRetriever 后面不会把它当 vectorScore。
      score: candidate.keywordScore,

      metadata: document.metadata,
    );
  }

  // ===========================================================================
  // DF access
  // ===========================================================================

  /// 查询某个token在多少篇文档中出现过（原始DF计数），内部会先归一化token（转小写+去除首尾标点）。
  /// - 输入：
  /// ```
  /// getDocumentFrequency('Flutter')
  /// ```
  /// - 输出：
  /// 例如 12（表示有12篇文档包含"flutter"这个token）；不存在则返回 0。
  int getDocumentFrequency(
      String token,
      ) {
    return _documentFrequency[
    _normalizeToken(token)] ??
        0;
  }

  /// DF占比 = DF / documentCount，衡量该词有多"普遍"。
  /// - 输入：
  /// ```
  /// getDocumentFrequencyRatio('the')（假设索引里100篇文档，95篇含"the"）
  /// ```
  /// - 输出：
  /// ```
  /// 0.95
  /// 若 documentCount == 0，返回 0.0（避免除零）。
  double getDocumentFrequencyRatio(
      String token,
      ) {
    if (documentCount == 0) {
      return 0.0;
    }

    return getDocumentFrequency(token) /
        documentCount;
  }

  /// 找出DF占比超过阈值的"高频词"（潜在的语料库级停用词，供 StopWordPolicy 动态更新使用）。
  /// - 输入：
  /// ```
  /// findHighFrequencyWords(threshold: 0.90)
  /// ```
  /// - 输出：
  /// ```
  /// {'the', 'a', 'is'}（这些词在≥90%的文档中都出现过）
  /// 若 threshold 不在 (0, 1] 区间，抛 ArgumentError。
  Set<String> findHighFrequencyWords({
    required double threshold,
  }) {
    if (threshold <= 0.0 ||
        threshold > 1.0) {
      throw ArgumentError.value(
        threshold,
        'threshold',
        'threshold must be in (0, 1].',
      );
    }

    if (documentCount == 0) {
      return <String>{};
    }

    final Set<String> result =
    <String>{};

    for (final MapEntry<String, int> entry
    in _documentFrequency.entries) {
      final double ratio =
          entry.value / documentCount;

      if (ratio >= threshold) {
        result.add(entry.key);
      }
    }

    return result;
  }

  // ===========================================================================
  // Searchable text
  // ===========================================================================

  /// 把一篇文档"能搜到"的所有文本字段拼接成一个字符串，
  /// 优先级顺序为：content → metadata['file_name'] → metadata['title'] → metadata['caption'] → metadata['description']。
  /// 这样图片类文档（没有content，但有caption/title）也能被检索到。
  /// - 输入：
  /// ```
  /// KeywordIndexedDocument(
  ///   id: 'img_1',
  ///   sourcePath: 'a.png',
  ///   content: null,
  ///   metadata: {'file_name': 'sunset.png', 'caption': 'A beautiful sunset over the sea'},
  /// )
  /// - 输出：
  /// ```
  /// 'sunset.png A beautiful sunset over the sea '
  /// ```
  String _buildSearchableText(
      KeywordIndexedDocument document,
      ) {
    final StringBuffer buffer =
    StringBuffer();

    if (document.content != null &&
        document.content!.trim().isNotEmpty) {
      buffer.write(document.content);
      buffer.write(' ');
    }

    _appendMetadata(
      buffer,
      document.metadata,
      'file_name',
    );

    _appendMetadata(
      buffer,
      document.metadata,
      'title',
    );

    _appendMetadata(
      buffer,
      document.metadata,
      'caption',
    );

    _appendMetadata(
      buffer,
      document.metadata,
      'description',
    );

    return buffer.toString().trim();
  }

  /// 辅助方法，把 metadata[key] 的值（若为非空字符串）追加到 StringBuffer 中。
  /// - 输入：
  /// ```
  /// _appendMetadata(buffer, {'title': 'Hello'}, 'title')
  /// ```
  /// - 输出：
  /// ```
  /// buffer 内容追加 'Hello '
  void _appendMetadata(
      StringBuffer buffer,
      Map<String, dynamic> metadata,
      String key,
      ) {
    final dynamic value = metadata[key];

    if (value is String && value.trim().isNotEmpty) {
      buffer.write(value);
      buffer.write(' ');
    }
  }

  // ===========================================================================
  // English tokenization
  // ===========================================================================

  /// 文本归一化——转小写、去除除了 a-z0-9_-.' 和空白以外的所有字符（用空格替代）、合并连续空白、去首尾空格。
  /// - 输入：
  /// ```
  /// _normalizeText('Flutter, State-Management!! 2024')
  /// ```
  /// - 输出：
  /// ```
  /// 'flutter state-management 2024'
  String _normalizeText(
      String text,
      ) {
    String normalized = text.toLowerCase();

    normalized = normalized.replaceAll(
      RegExp(
        r"[^a-z0-9_\-.'\s]+",
      ),
      ' ',
    );

    normalized = normalized.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );

    return normalized.trim();
  }

  /// 先归一化，再按空格切分，并对每个token做首尾符号清理（_cleanToken），过滤空字符串。
  /// - 输入：
  /// ```
  /// _tokenize("Riverpod's state-management.")
  /// ```
  /// - 输出：
  /// ```
  /// ['riverpod', 'state-management']
  /// //注意：'s 会被 _cleanToken 去除首尾的 .'_-，但中间的连字符不受影响）
  List<String> _tokenize(
      String text,
      ) {
    final String normalized = _normalizeText(text);

    if (normalized.isEmpty) {
      return const <String>[];
    }

    return normalized
        .split(' ')
        .map(_cleanToken)
        .where(
          (String token) =>
      token.isNotEmpty,
    )
        .toList(
      growable: false,
    );
  }

  /// 去除token开头和结尾的 . ' _ - 字符（不影响中间部分）
  /// - 输入：
  /// ```
  /// _cleanToken("'flutter.")
  /// ```
  /// - 输出：
  /// ```
  /// 'flutter'
  String _cleanToken(
      String token,
      ) {
    String cleaned =
    token.trim();

    cleaned = cleaned.replaceFirst(
      RegExp(r"^[.'_-]+"),
      '',
    );

    cleaned = cleaned.replaceFirst(
      RegExp(r"[.'_-]+$"),
      '',
    );

    return cleaned;
  }

  /// 给外部调用（如 getDocumentFrequency）用的单token归一化：转小写+trim+清理首尾符号。
  /// - 输入：
  /// ```
  /// _normalizeToken(' Flutter. ')
  /// ```
  /// - 输出：
  /// ```
  /// 'flutter'
  String _normalizeToken(
      String token,
      ) {
    return _cleanToken(
      token.toLowerCase().trim(),
    );
  }

  // ===========================================================================
  // Ordered matching
  // ===========================================================================

  /// 衡量query token是否按顺序（允许跳跃，类似最长公共子序列的简化版）出现在文档token序列中。
  /// 用一个指针 queryIndex 扫描文档token，每命中一个就前进一位，最终返回 命中数/query长度。
  /// - 输入：
  /// ```
  /// queryTokens = ['state', 'management']
  /// documentTokens = ['flutter', 'state', 'tutorial', 'management', 'guide']
  /// ```
  /// - 输出：
  /// ```
  /// 1.0（'state'先命中，之后又命中'management'，顺序保持，两个都匹配→ 2/2=1.0）
  /// ```
  /// - 输入：
  /// ```
  /// queryTokens = ['management', 'state']
  /// documentTokens = ['flutter', 'state', 'management']
  /// ```
  /// - 输出：
  /// ```
  /// 0.5（先找'management'匹配失败因为还没轮到；实际扫描：
  /// 先看token='flutter'≠'management'跳过；'state'≠'management'跳过；'management'==queryTokens[0]→匹配，
  /// queryIndex=1；后面没有更多token了。结果 1/2=0.5）
  double _calculateOrderedMatchScore(
      List<String> queryTokens,
      List<String> documentTokens,
      ) {
    if (queryTokens.isEmpty ||
        documentTokens.isEmpty) {
      return 0.0;
    }

    int queryIndex = 0;

    for (final String token
    in documentTokens) {
      if (queryIndex >=
          queryTokens.length) {
        break;
      }

      if (token ==
          queryTokens[queryIndex]) {
        queryIndex++;
      }
    }

    return queryIndex /
        queryTokens.length;
  }

  // ===========================================================================
  // Math helpers
  // ===========================================================================

  /// 把无界的正数压缩到 [0,1) 区间，公式 value / (1+value)，防止TF/IDF原始值过大导致分数失控。
  /// - 输入：
  /// ```
  /// _squash(3.0) → 输出：0.75
  /// ```
  /// - 输出：
  /// ```
  /// _squash(0.0) → 输出：0.0
  double _squash(
      double value,
      ) {
    if (value <= 0.0) {
      return 0.0;
    }

    return value /
        (1.0 + value);
  }

  // ===========================================================================
  // State
  // ===========================================================================

  /// 守卫方法，检查 _stopWordPolicy.isInitialized，未初始化则抛 StateError，防止在词权重系统未就绪时索引/查询。
  void _ensurePolicyReady() {
    if (!_stopWordPolicy.isInitialized) {
      throw StateError(
        'StopWordPolicy is not initialized.',
      );
    }
  }
}

/// Keyword index 中保存的文档。不可变数据类，存储一篇文档的原始信息+索引后信息（tokenFrequencies、indexedTokens、tokens、normalizedText）。
class KeywordIndexedDocument {
  const KeywordIndexedDocument({
    required this.id,
    required this.sourcePath,
    this.content,
    this.metadata = const <String, dynamic>{},
    this.tokenFrequencies = const <String, int>{},
    this.indexedTokens = const <String>{},
    this.tokens = const <String>[],
    this.normalizedText = '',
  });

  final String id;

  final String sourcePath;

  final String? content;

  final Map<String, dynamic> metadata;

  /// token -> TF
  final Map<String, int> tokenFrequencies;

  /// inverted-index removal 时使用。
  final Set<String> indexedTokens;

  /// token 顺序，用于 ordered-match。
  final List<String> tokens;

  /// normalized full document text，
  /// 用于 exact phrase。
  final String normalizedText;

  /// copyWith() 用于在 addDocument 中生成"带上索引信息"的新版本。
  KeywordIndexedDocument copyWith({
    Map<String, int>? tokenFrequencies,
    Set<String>? indexedTokens,
    List<String>? tokens,
    String? normalizedText,
  }) {
    return KeywordIndexedDocument(
      id: id,
      sourcePath: sourcePath,
      content: content,
      metadata: metadata,
      tokenFrequencies:
      tokenFrequencies ??
          this.tokenFrequencies,
      indexedTokens:
      indexedTokens ??
          this.indexedTokens,
      tokens:
      tokens ??
          this.tokens,
      normalizedText:
      normalizedText ??
          this.normalizedText,
    );
  }
}

/// 独立 Keyword Retrieval 返回的候选。
class KeywordCandidate {
  const KeywordCandidate({
    required this.document,
    required this.keywordScore,
  });

  final KeywordIndexedDocument document;

  final double keywordScore;
}