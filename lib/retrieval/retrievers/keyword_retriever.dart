import 'package:local_retrieval_system/retrieval/keyword_index/keyword_index.dart';

/// 这是关键词检索的对外门面（Facade），包装了底层 KeywordIndex，把倒排索引的原始候选（KeywordCandidate）转换成统一的 KeywordSearchResult 格式，
/// 并在此基础上提供：文本专用检索、图片专用检索、metadata过滤检索、按ID查找、以及若干DF统计的透传方法。它是 HybridRetriever 融合流程中"关键词分支"的直接调用对象。
// 现在它已经是一个真正独立的 Retriever：
//
// Query
//   ↓
// KeywordIndex
//   ↓
// Inverted Index Candidate Retrieval
//   ↓
// Keyword Scoring
//   ↓
// Keyword Top-N
//
// 不再依赖 VectorRetriever 先提供 candidates。
class KeywordRetriever {
  KeywordRetriever({
    required KeywordIndex keywordIndex,
  }) : _keywordIndex = keywordIndex;

  final KeywordIndex _keywordIndex;

  // ===========================================================================
  // Public search API
  // ===========================================================================

  /// 核心检索方法。先校验参数，再调用 _keywordIndex.searchCandidates() 拿到打分排序后的候选，
  /// 最后把每个 KeywordCandidate（内部是 document + keywordScore）映射成对外的 KeywordSearchResult
  /// - 输入：
  /// ```
  /// search(query: 'flutter state management', topK: 10)
  /// ```
  /// - 输出：
  /// ```
  /// [
  ///   KeywordSearchResult(id: 'doc_1', sourcePath: '/notes/a.txt', content: '...', keywordScore: 0.87, metadata: {...}),
  ///   KeywordSearchResult(id: 'doc_5', sourcePath: '/notes/b.txt', content: '...', keywordScore: 0.62, metadata: {...}),
  ///   ...
  /// ]
  List<KeywordSearchResult> search({
    required String query,
    int topK = 50,
  }) {
    _validateQuery(
      query,
      topK,
    );

    final List<KeywordCandidate> candidates =
    _keywordIndex.searchCandidates(
      query: query,
      topK: topK,
    );

    return candidates
        .map(
          (KeywordCandidate candidate) =>
          KeywordSearchResult(
            id: candidate.document.id,
            sourcePath:
            candidate.document.sourcePath,
            content:
            candidate.document.content,
            keywordScore:
            candidate.keywordScore,
            metadata:
            candidate.document.metadata,
          ),
    )
        .toList(
      growable: false,
    );
  }

  // ===========================================================================
  // Text-only search
  // ===========================================================================

  /// 只返回metadata['data_type'] == 'text'的结果。因为过滤会丢掉一部分候选，
  /// 所以内部先用_expandCandidateCount(topK)（即topK*5）扩大候选池，过滤后再take(topK)截断，避免"过滤后数量不足topK"的问题。
  /// - 输入：
  /// ```
  /// searchTextDocuments(query: 'project deadline', topK: 5)（假设候选池50条里有8条是text）
  /// ```
  /// - 输出：
  /// ```
  /// [前5条text类型的KeywordSearchResult]（若过滤后不足5条，比如只有3条text，则返回这3条）
  List<KeywordSearchResult> searchTextDocuments({
    required String query,
    int topK = 50,
  }) {
    final List<KeywordSearchResult> results =
    search(
      query: query,
      topK: _expandCandidateCount(topK),
    );

    return results
        .where(
          (KeywordSearchResult result) =>
      result.metadata['data_type'] == 'text',
    ).take(topK).toList(
      growable: false,
    );
  }

  // ===========================================================================
  // Image-only search
  // ===========================================================================

  /// 只保留metadata['data_type'] == 'image'的结果。
  /// 因为图片没有正文content，主要靠file_name、caption、title、description这些metadata字段被KeywordIndex索引到。
  ///
  /// KeywordIndex 对图片主要依赖：
  ///
  /// - file_name
  /// - caption
  /// - title
  /// - description
  /// - 输入：
  /// ```
  /// searchImages(query: 'sunset beach', topK: 5)
  /// ```
  /// - 输出：
  /// ```
  /// [KeywordSearchResult(id: 'img_3', content: null, metadata: {'data_type':'image', 'file_name':'sunset.png', 'caption':'A beautiful sunset over the sea'}, keywordScore: 0.71), ...]（最多5条，content字段为null）
  List<KeywordSearchResult> searchImages({
    required String query,
    int topK = 50,
  }) {
    final List<KeywordSearchResult> results =
    search(
      query: query,
      topK: _expandCandidateCount(topK),
    );

    return results
        .where(
          (KeywordSearchResult result) =>
      result.metadata['data_type'] ==
          'image',
    )
        .take(topK)
        .toList(
      growable: false,
    );
  }

  // ===========================================================================
  // Search with metadata filter
  // ===========================================================================

  /// 在关键词检索基础上叠加metadata精确匹配过滤（等值匹配，非模糊）。若
  /// filters为空，直接退化成普通search()；否则同样先扩大候选池（_expandCandidateCount），过滤后截断到topK。
  /// - 输入：
  /// ```
  /// searchWithFilters(
  ///   query: 'annual report',
  ///   filters: {'data_type': 'text', 'file_extension': '.pdf'},
  ///   topK: 5,
  /// )
  /// ```
  /// - 输出：
  /// ```
  /// 只包含data_type=='text'且file_extension=='.pdf'的结果，最多5条。
  /// //若filters传入的key在某个候选的metadata里不存在 → 该候选被排除（_matchesFilters里containsKey检查失败即返回false）。
  /// ```
  List<KeywordSearchResult> searchWithFilters({
    required String query,
    required Map<String, dynamic> filters,
    int topK = 50,
  }) {
    _validateQuery(
      query,
      topK,
    );

    if (filters.isEmpty) {
      return search(
        query: query,
        topK: topK,
      );
    }

    final List<KeywordSearchResult> results =
    search(
      query: query,

      // 先扩大候选集，
      // 避免 metadata filter 后数量不足。
      topK: _expandCandidateCount(
        topK,
      ),
    );

    return results
        .where(
          (KeywordSearchResult result) =>
          _matchesFilters(
            result.metadata,
            filters,
          ),
    )
        .take(topK)
        .toList(
      growable: false,
    );
  }

  // ===========================================================================
  // Lookup by IDs
  // ===========================================================================

  /// 不做检索打分，纯粹按ID直接查文档（委托给_keywordIndex.getDocumentById），
  /// 常用于HybridRetriever做候选union时，已知ID但需要补齐完整字段的场景。由于没有query，keywordScore固定为0.0
  /// - 输入：
  /// ```
  /// getById('doc_1')
  /// ```
  /// - 输出：
  /// ```
  /// （存在）：KeywordSearchResult(id: 'doc_1', sourcePath: '...', content: '...', keywordScore: 0.0, metadata: {...})
  /// （不存在）：null
  KeywordSearchResult? getById(
      String id,
      ) {
    final KeywordIndexedDocument? document = _keywordIndex.getDocumentById(id);

    if (document == null) {
      return null;
    }

    return KeywordSearchResult(
      id: document.id,
      sourcePath:
      document.sourcePath,
      content:
      document.content,

      // 这里只是 lookup，没有 query，
      // 因此没有 keyword score。
      keywordScore: 0.0,

      metadata:
      document.metadata,
    );
  }

  // ===========================================================================
  // Dynamic DF support
  // ===========================================================================
  /// 透传_keywordIndex.documentCount，暴露当前索引中的文档总数。
  int get documentCount => _keywordIndex.documentCount;

  /// 透传_keywordIndex.getDocumentFrequency，查某个token的原始DF（出现过该词的文档数）。
  /// - 输入：
  /// ```
  /// getDocumentFrequency('flutter')
  /// ```
  /// - 输出：
  /// ```
  /// 12（表示有12篇文档含该词），不存在则0
  int getDocumentFrequency(
      String token,
      ) {
    return _keywordIndex
        .getDocumentFrequency(
      token,
    );
  }

  /// 透传_keywordIndex.getDocumentFrequencyRatio，返回DF占比。
  /// - 输入：
  /// ```
  /// getDocumentFrequencyRatio('the')
  /// ```
  /// - 输出：
  /// ```
  /// 0.95（95%的文档都含"the"）
  double getDocumentFrequencyRatio(
      String token,
      ) {
    return _keywordIndex
        .getDocumentFrequencyRatio(
      token,
    );
  }

  /// 透传_keywordIndex.findHighFrequencyWords，找出DF占比超过阈值的高频词（用于识别潜在停用词）。
  /// - 输入：
  /// ```
  /// findHighFrequencyWords(threshold: 0.90)
  /// ```
  /// - 输出：
  /// ```
  /// {'the', 'a', 'is'}
  Set<String> findHighFrequencyWords({
    double threshold = 0.90,
  }) {
    return _keywordIndex
        .findHighFrequencyWords(
      threshold: threshold,
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// 判断一条结果的metadata是否完全满足所有filter条件（AND逻辑，等值匹配）。任一filter字段缺失或值不等，立即返回false。
  /// - 输入：
  /// ```
  /// _matchesFilters(
  ///   {'data_type': 'text', 'file_extension': '.pdf', 'chunk_index': 0},
  ///   {'data_type': 'text', 'file_extension': '.pdf'},
  /// )
  /// ```
  /// - 输出：
  /// ```
  /// true（两个filter条件都满足，多余的metadata字段不影响）
  /// ```
  /// - 输入：
  /// ```
  /// _matchesFilters(
  ///   {'data_type': 'image'},
  ///   {'data_type': 'text'},
  /// )
  /// ```
  /// - 输出：
  /// ```
  /// false
  bool _matchesFilters(
      Map<String, dynamic> metadata,
      Map<String, dynamic> filters,
      ) {
    for (final MapEntry<String, dynamic> filter
    in filters.entries) {
      if (!metadata.containsKey(filter.key)) {
        return false;
      }

      if (metadata[filter.key] !=
          filter.value) {
        return false;
      }
    }

    return true;
  }

  /// 把topK放大5倍，作为向KeywordIndex要候选时的实际topK，为后续的过滤（text-only/image-only/metadata filter）预留足够的候选空间。
  /// - 输入：
  /// ```
  /// _expandCandidateCount(10)
  /// ```
  /// - 输出：
  /// ```
  /// 50
  int _expandCandidateCount(
      int topK,
      ) {
    // 当前先简单扩大 5 倍，
    // 后续可以提到配置类。
    return topK * 5;
  }

  /// 参数校验，query去除首尾空格后不能为空，topK必须大于0。
  /// 与KeywordIndex.searchCandidates、HybridRetriever._validateQuery里的逻辑完全一致（三处重复代码，未来可以考虑提取成共享工具函数）
  /// - 输入：
  /// ```
  /// _validateQuery('', 10)
  /// ```
  /// - 输出：
  /// ```
  /// 抛ArgumentError('Keyword search query cannot be empty.')
  void _validateQuery(
      String query,
      int topK,
      ) {
    if (query.trim().isEmpty) {
      throw ArgumentError(
        'Keyword search query cannot be empty.',
      );
    }

    if (topK <= 0) {
      throw ArgumentError.value(
        topK,
        'topK',
        'topK must be greater than 0.',
      );
    }
  }
}

/// 不可变数据类，是KeywordRetriever所有公开方法的统一返回单元。
/// 字段：id、sourcePath、content（可空，图片为null）、keywordScore（范围[0,1]）、metadata（默认空Map）。
/// 重写了toString()，方便调试时打印简洁信息（只显示id和分数，不显示完整content/metadata）。
class KeywordSearchResult {
  const KeywordSearchResult({
    required this.id,
    required this.sourcePath,
    required this.keywordScore,
    this.content,
    this.metadata =
    const <String, dynamic>{},
  });

  final String id;

  final String sourcePath;

  final String? content;

  /// Keyword lexical score。
  ///
  /// Range:
  /// [0,1]
  final double keywordScore;

  final Map<String, dynamic> metadata;

  @override
  String toString() {
    return 'KeywordSearchResult('
        'id: $id, '
        'keywordScore: '
        '${keywordScore.toStringAsFixed(4)}'
        ')';
  }
}