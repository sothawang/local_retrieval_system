import 'package:local_retrieval_system/retrieval/models/vector_search_result.dart';
import 'package:local_retrieval_system/retrieval/retrievers/keyword_retriever.dart';
import 'package:local_retrieval_system/retrieval/retrievers/vector_retriever.dart';

/// 这是双路检索融合器，把 VectorRetriever（语义）和 KeywordRetriever（关键词）的结果做候选并集(UNION) + 分数归一化 + 加权融合，
/// 而不是像旧版那样让关键词只对向量候选做重排（rerank）。这样即使BERT语义检索完全没召回某文档，只要关键词命中了，该文档依然能进入最终排序。
/// Query
///   ├─ VectorRetriever  → Vector Top-N (candidateCount = topK * candidateMultiplier)
///   └─ KeywordRetriever → Keyword Top-N (同样的candidateCount)
///         ↓
///    候选并集 UNION（两边各自min-max归一化分数）
///         ↓
///    finalScore = normalizedVectorWeight*normVectorScore + normalizedKeywordWeight*normKeywordScore
///         ↓
///    按finalScore降序排序（同分再按keyword、vector分数tie-break）
///         ↓
///    取前topK
class HybridRetriever {
  HybridRetriever({
    required VectorRetriever vectorRetriever,
    required KeywordRetriever keywordRetriever,
    this.vectorWeight = 0.3,
    this.keywordWeight = 0.7,
    this.candidateMultiplier = 5,
  })  : _vectorRetriever = vectorRetriever,
        _keywordRetriever = keywordRetriever {
    if (vectorWeight < 0.0) {
      throw ArgumentError(
        'vectorWeight cannot be negative.',
      );
    }

    if (keywordWeight < 0.0) {
      throw ArgumentError(
        'keywordWeight cannot be negative.',
      );
    }

    if (vectorWeight == 0.0 && keywordWeight == 0.0) {
      throw ArgumentError(
        'vectorWeight and keywordWeight cannot both be zero.',
      );
    }

    if (candidateMultiplier <= 0) {
      throw ArgumentError(
        'candidateMultiplier must be greater than 0.',
      );
    }
  }

  final VectorRetriever _vectorRetriever;
  final KeywordRetriever _keywordRetriever;

  /// Semantic retrieval contribution.
  ///
  /// Default:
  /// 0.3
  final double vectorWeight;

  /// Lexical retrieval contribution.
  ///
  /// Default:
  /// 0.7
  final double keywordWeight;

  /// Number of candidates retrieved from EACH retrieval branch.
  ///
  /// Example:
  ///
  /// topK = 10
  /// candidateMultiplier = 5
  ///
  /// VectorRetriever  -> Top 50
  /// KeywordRetriever -> Top 50
  ///
  /// Then UNION the two sets before final ranking.
  final int candidateMultiplier;

  // ===========================================================================
  // General BERT text search
  // ===========================================================================

  /// 通用文本混合检索。先算候选数量 candidateCount = topK * candidateMultiplier，
  /// 分别从两个retriever各取 candidateCount 条候选（若有filters则关键词分支走searchWithFilters），最后调用 _fuse 融合
  /// - 输入：
  /// ```
  /// searchText(query: 'flutter riverpod', topK: 10)（candidateMultiplier=5 → 每路各取50条候选）
  /// ```
  /// - 输出：
  /// ```
  /// [
  ///   HybridSearchResult(id: 'doc_3', finalScore: 0.91, foundByVector: true, foundByKeyword: true, ...),
  ///   HybridSearchResult(id: 'doc_7', finalScore: 0.85, foundByVector: true, foundByKeyword: false, ...),
  ///   ... // 最多10条
  /// ]
  Future<List<HybridSearchResult>> searchText({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    _validateQuery(
      query,
      topK,
    );

    final int candidateCount = _calculateCandidateCount(topK);

    // -------------------------------------------------------------------------
    // Branch 1 - Vector retrieval
    // -------------------------------------------------------------------------

    final List<VectorSearchResult> vectorResults =
    await _vectorRetriever.searchText(
      query: query,
      topK: candidateCount,
      filters: filters,
    );

    // -------------------------------------------------------------------------
    // Branch 2 - Keyword retrieval
    // -------------------------------------------------------------------------

    final List<KeywordSearchResult> keywordResults;

    if (filters == null || filters.isEmpty) {
      keywordResults =
          _keywordRetriever.search(
            query: query,
            topK: candidateCount,
          );
    } else {
      keywordResults =
          _keywordRetriever.searchWithFilters(
            query: query,
            filters: filters,
            topK: candidateCount,
          );
    }

    // -------------------------------------------------------------------------
    // Candidate UNION + fusion
    // -------------------------------------------------------------------------

    return _fuse(
      vectorResults: vectorResults,
      keywordResults: keywordResults,
      topK: topK,
    );
  }

  // ===========================================================================
  // Text-document-only retrieval
  // ===========================================================================

  /// 只检索"文本类型"文档的混合版本，
  /// 分别调用 _vectorRetriever.searchTextDocuments 和 _keywordRetriever.searchTextDocuments（这两个方法内部按data_type: text过滤），
  /// 再融合。不支持自定义filters参数。
  /// - 输入：
  /// ```
  /// searchTextDocuments(query: 'project deadline', topK: 5)
  /// ```
  /// - 输出：
  /// ```
  /// 最多5条 HybridSearchResult，全部是文本类文档（图片不会出现）。
  Future<List<HybridSearchResult>> searchTextDocuments({
    required String query,
    int topK = 10,
  }) async {
    _validateQuery(
      query,
      topK,
    );

    final int candidateCount = _calculateCandidateCount(topK);

    // -------------------------------------------------------------------------
    // Vector Top-N
    // -------------------------------------------------------------------------

    final List<VectorSearchResult> vectorResults =
    await _vectorRetriever
        .searchTextDocuments(
      query: query,
      topK: candidateCount,
    );

    // -------------------------------------------------------------------------
    // Keyword Top-N
    // -------------------------------------------------------------------------

    final List<KeywordSearchResult> keywordResults =
    _keywordRetriever.searchTextDocuments(
      query: query,
      topK: candidateCount,
    );

    return _fuse(
      vectorResults: vectorResults,
      keywordResults: keywordResults,
      topK: topK,
    );
  }

  // ===========================================================================
  // MobileCLIP multimodal retrieval
  // ===========================================================================

  /// 跨模态检索（文本查询同时匹配文本和图片，走MobileCLIP文本向量分支），加上关键词分支融合。
  /// - 输入：
  /// ```
  /// searchMultimodal(query: 'sunset beach', topK: 8)
  /// ```
  /// - 输出：
  /// ```
  /// 结果可能同时包含文本chunk和图片记录，按融合分数排序，最多8条。
  Future<List<HybridSearchResult>> searchMultimodal({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    _validateQuery(
      query,
      topK,
    );

    final int candidateCount =
    _calculateCandidateCount(topK);

    // -------------------------------------------------------------------------
    // MobileCLIP vector branch
    // -------------------------------------------------------------------------

    final List<VectorSearchResult> vectorResults =
    await _vectorRetriever
        .searchMultimodal(
      query: query,
      topK: candidateCount,
      filters: filters,
    );

    // -------------------------------------------------------------------------
    // Keyword branch
    // -------------------------------------------------------------------------

    final List<KeywordSearchResult> keywordResults;

    if (filters == null || filters.isEmpty) {
      keywordResults =
          _keywordRetriever.search(
            query: query,
            topK: candidateCount,
          );
    } else {
      keywordResults =
          _keywordRetriever.searchWithFilters(
            query: query,
            filters: filters,
            topK: candidateCount,
          );
    }

    return _fuse(
      vectorResults: vectorResults,
      keywordResults: keywordResults,
      topK: topK,
    );
  }

  // ===========================================================================
  // Text -> Image retrieval
  // ===========================================================================

  /// 文本→图片检索。向量分支用 _vectorRetriever.searchImages（MobileCLIP的text-to-image检索），
  /// 关键词分支用 _keywordRetriever.searchImages（基于file_name/caption等metadata关键词匹配）。
  /// - 输入：
  /// ```
  /// searchImages(query: 'cat sitting on sofa', topK: 6)
  /// ```
  /// - 输出：
  /// ```
  /// 最多6条图片类 HybridSearchResult。
  Future<List<HybridSearchResult>> searchImages({
    required String query,
    int topK = 10,
  }) async {
    _validateQuery(
      query,
      topK,
    );

    final int candidateCount =
    _calculateCandidateCount(topK);

    // -------------------------------------------------------------------------
    // MobileCLIP Text -> Image vector retrieval
    // -------------------------------------------------------------------------

    final List<VectorSearchResult> vectorResults =
    await _vectorRetriever.searchImages(
      query: query,
      topK: candidateCount,
    );

    // -------------------------------------------------------------------------
    // Image metadata keyword retrieval
    // -------------------------------------------------------------------------

    final List<KeywordSearchResult> keywordResults =
    _keywordRetriever.searchImages(
      query: query,
      topK: candidateCount,
    );

    return _fuse(
      vectorResults: vectorResults,
      keywordResults: keywordResults,
      topK: topK,
    );
  }

  // ===========================================================================
  // Fusion
  // ===========================================================================

  /// 混合检索结果逻辑
  /// 1. 若两路都为空 → 直接返回空列表
  /// 2. 分别对 vectorResults 和 keywordResults 做min-max归一化（各自独立归一化，不是跨集合归一化）
  /// 3. 建立 `candidateMap<id, _HybridCandidate>`：
  ///     - 先把所有vector结果放入map，标记 foundByVector: true
  ///     - 再遍历keyword结果：若id已存在（说明双路都召回了）→ 用copyWith补上keyword分数、标记foundByKeyword: true；
  ///     若id不存在（说明是keyword独有的新文档）→ 新建一个候选，rawVectorScore=0, normalizedVectorScore=0
  /// 4. 归一化融合权重：normalizedVectorWeight = vectorWeight/(vectorWeight+keywordWeight)（同理keyword），保证两个权重和为1
  /// 5. 对每个候选算 finalScore = normalizedVectorWeight*normVectorScore + normalizedKeywordWeight*normKeywordScore，clamp到[0,1]
  /// 6. 排序规则：先按finalScore降序；若相同，按normalizedKeywordScore降序tie-break；仍相同则按normalizedVectorScore降序
  /// 7. 截取前topK
  /// - 输入：
  /// ```
  /// vectorResults = [ {id:'A', score:0.9}, {id:'B', score:0.5} ]   // min-max归一化后 A→1.0, B→0.0
  /// keywordResults = [ {id:'B', keywordScore:0.8}, {id:'X', keywordScore:0.6} ]  // 归一化后 B→1.0, X→0.0
  /// vectorWeight=0.3, keywordWeight=0.7
  /// ```
  /// - 输出：
  /// ```
  /// 候选并集：{A, B, X}
  /// A: normVec=1.0, normKw=0.0 → final = 0.3*1.0 + 0.7*0.0 = 0.30   (vectorOnly)
  /// B: normVec=0.0, normKw=1.0 → final = 0.3*0.0 + 0.7*1.0 = 0.70   (foundByBoth)
  /// X: normVec=0.0, normKw=0.0 → final = 0.0                        (keywordOnly)
  ///
  /// 排序后: [A(0.70), B(0.30), X(0.0)]
  /// B虽然在两路里都出现（本该更可信），但因为它在vector分支里分数最低被压到0，
  /// 在keyword分支里分数最高被拉到1.0，最终分数取决于原始分数在各自候选集里的相对位置，而不是绝对语义相关性——这是min-max归一化的局限性
  List<HybridSearchResult> _fuse({
    required List<VectorSearchResult> vectorResults,
    required List<KeywordSearchResult> keywordResults,
    required int topK,
  }) {
    if (vectorResults.isEmpty &&
        keywordResults.isEmpty) {
      return const <HybridSearchResult>[];
    }

    // -------------------------------------------------------------------------
    // Normalize vector scores
    // -------------------------------------------------------------------------

    final Map<String, double>
    normalizedVectorScores =
    _normalizeVectorScores(
      vectorResults,
    );

    // -------------------------------------------------------------------------
    // Normalize keyword scores
    // -------------------------------------------------------------------------

    final Map<String, double>
    normalizedKeywordScores =
    _normalizeKeywordScores(
      keywordResults,
    );

    // -------------------------------------------------------------------------
    // Candidate UNION
    // -------------------------------------------------------------------------
    //
    // Example:
    //
    // Vector:
    // A B C D
    //
    // Keyword:
    // B D X Y
    //
    // UNION:
    // A B C D X Y
    //
    // X / Y can now enter final ranking even if BERT completely missed them.

    final Map<String, _HybridCandidate> candidateMap =
    <String, _HybridCandidate>{};

    // -------------------------------------------------------------------------
    // Add vector candidates
    // -------------------------------------------------------------------------

    for (final VectorSearchResult result in vectorResults) {
      candidateMap[result.id] =
          _HybridCandidate(
            id: result.id,
            sourcePath:
            result.sourcePath,
            content:
            result.content,
            metadata:
            result.metadata,

            rawVectorScore:
            result.score,

            normalizedVectorScore:
            normalizedVectorScores[result.id] ??
                0.0,

            keywordScore: 0.0,

            normalizedKeywordScore:
            0.0,

            foundByVector: true,
            foundByKeyword: false,
          );
    }

    // -------------------------------------------------------------------------
    // Merge keyword candidates
    // -------------------------------------------------------------------------

    for (final KeywordSearchResult result in keywordResults) {
      final _HybridCandidate? existing =
      candidateMap[result.id];

      if (existing != null) {
        candidateMap[result.id] =
            existing.copyWith(
              keywordScore:
              result.keywordScore,
              normalizedKeywordScore:
              normalizedKeywordScores[
              result.id] ??
                  0.0,
              foundByKeyword: true,
            );
      } else {
        // This is the important part of the new architecture:
        //
        // Keyword retrieval can introduce a document that was NOT present
        // in the vector candidate list.

        candidateMap[result.id] =
            _HybridCandidate(
              id: result.id,
              sourcePath:
              result.sourcePath,
              content:
              result.content,
              metadata:
              result.metadata,

              rawVectorScore: 0.0,

              normalizedVectorScore: 0.0,

              keywordScore:
              result.keywordScore,

              normalizedKeywordScore:
              normalizedKeywordScores[
              result.id] ??
                  0.0,

              foundByVector: false,
              foundByKeyword: true,
            );
      }
    }

    // -------------------------------------------------------------------------
    // Normalize fusion weights
    // -------------------------------------------------------------------------

    final double weightSum = vectorWeight + keywordWeight;

    final double normalizedVectorWeight = vectorWeight / weightSum;

    final double normalizedKeywordWeight = keywordWeight / weightSum;

    // -------------------------------------------------------------------------
    // Calculate final score
    // -------------------------------------------------------------------------

    final List<HybridSearchResult> results = <HybridSearchResult>[];

    for (final _HybridCandidate candidate in candidateMap.values) {
      final double finalScore =
          normalizedVectorWeight *
              candidate
                  .normalizedVectorScore +
              normalizedKeywordWeight *
                  candidate
                      .normalizedKeywordScore;

      results.add(
        HybridSearchResult(
          id: candidate.id,
          sourcePath:
          candidate.sourcePath,
          content:
          candidate.content,

          vectorScore:
          candidate.rawVectorScore,

          normalizedVectorScore:
          candidate.normalizedVectorScore,

          keywordScore:
          candidate.keywordScore,

          normalizedKeywordScore:
          candidate
              .normalizedKeywordScore,

          finalScore:
          finalScore.clamp(
            0.0,
            1.0,
          ),

          foundByVector:
          candidate.foundByVector,

          foundByKeyword:
          candidate.foundByKeyword,

          metadata:
          candidate.metadata,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Final ranking
    // -------------------------------------------------------------------------

    results.sort(
          (
          HybridSearchResult a,
          HybridSearchResult b,
          ) {
        // 1. Final hybrid score
        final int finalComparison =
        b.finalScore.compareTo(
          a.finalScore,
        );

        if (finalComparison != 0) {
          return finalComparison;
        }

        // 2. Keyword score tie-break
        final int keywordComparison =
        b.normalizedKeywordScore
            .compareTo(
          a.normalizedKeywordScore,
        );

        if (keywordComparison != 0) {
          return keywordComparison;
        }

        // 3. Vector score tie-break
        return b.normalizedVectorScore
            .compareTo(
          a.normalizedVectorScore,
        );
      },
    );

    if (results.length <= topK) {
      return results;
    }

    return results
        .take(topK)
        .toList(
      growable: false,
    );
  }

  // ===========================================================================
  // Vector normalization
  // ===========================================================================

  /// 把 VectorSearchResult.score 列表喂给 _minMaxNormalize，再组装成 id → normalizedScore 的Map，方便_fuse按id查找。
  /// - 输入：
  /// ```
  /// _normalizeVectorScores([{id:'A',score:0.9},{id:'B',score:0.5}])
  /// ```
  /// - 输出：
  /// ```
  /// {'A': 1.0, 'B': 0.0}
  Map<String, double> _normalizeVectorScores(
      List<VectorSearchResult> results,
      ) {
    if (results.isEmpty) {
      return const <String, double>{};
    }

    final List<double> scores =
    results
        .map(
          (VectorSearchResult result) =>
      result.score,
    )
        .toList(
      growable: false,
    );

    final List<double> normalized =
    _minMaxNormalize(
      scores,
    );

    final Map<String, double> result =
    <String, double>{};

    for (int i = 0;
    i < results.length;
    i++) {
      result[results[i].id] =
      normalized[i];
    }

    return result;
  }

  // ===========================================================================
  // Keyword normalization
  // ===========================================================================

  /// 把KeywordSearchResult.keywordScore 列表喂给 _minMaxNormalize，再组装成 id → normalizedScore 的Map，方便_fuse按id查找。
  /// - 输入：
  /// ```
  /// _normalizeKeywordScores([{id:'A',score:0.9},{id:'B',score:0.5}])
  /// ```
  /// -输出：
  /// ```
  /// {'A': 1.0, 'B': 0.0}
  Map<String, double> _normalizeKeywordScores(
      List<KeywordSearchResult> results,
      ) {
    if (results.isEmpty) {
      return const <String, double>{};
    }

    final List<double> scores =
    results
        .map(
          (KeywordSearchResult result) =>
      result.keywordScore,
    )
        .toList(
      growable: false,
    );

    final List<double> normalized =
    _minMaxNormalize(
      scores,
    );

    final Map<String, double> result =
    <String, double>{};

    for (int i = 0;
    i < results.length;
    i++) {
      result[results[i].id] =
      normalized[i];
    }

    return result;
  }

  // ===========================================================================
  // Min-max normalization
  // ===========================================================================

  /// 标准min-max归一化到[0,1]。边界情况处理：
  /// 1. 空列表 → 返回空
  /// 2. 只有1个元素 → 直接给1.0（避免除0，且单一候选默认给满分权重）
  /// 3. 所有值相同（range接近0）→ 全部设为1.0（而不是全变0），避免"分数打平时全都被判为不重要"这种偏差
  /// - 输入：
  /// ```
  /// _minMaxNormalize([0.9, 0.5, 0.5])
  /// ```
  /// - 输出：
  /// ```
  /// [1.0, 0.0, 0.0]
  /// ```
  /// - 输入：
  /// ```
  /// _minMaxNormalize([0.7, 0.7, 0.7])（全相同）
  /// ```
  /// - 输出：
  /// ```
  /// [1.0, 1.0, 1.0]
  /// ```
  /// - 输入：
  /// ```
  /// _minMaxNormalize([0.5])（单元素）
  /// ```
  /// - 输出：
  /// ```
  /// [1.0]
  List<double> _minMaxNormalize(
      List<double> scores,
      ) {
    if (scores.isEmpty) {
      return const <double>[];
    }

    if (scores.length == 1) {
      return const <double>[1.0];
    }

    double minimum =
        scores.first;

    double maximum =
        scores.first;

    for (final double score in scores) {
      if (score < minimum) {
        minimum = score;
      }

      if (score > maximum) {
        maximum = score;
      }
    }

    final double range =
        maximum - minimum;

    // All results are tied.
    //
    // They should receive equal retrieval contribution instead of all
    // becoming zero.
    if (range.abs() < 1e-12) {
      return List<double>.filled(
        scores.length,
        1.0,
        growable: false,
      );
    }

    return scores
        .map(
          (double score) =>
          ((score - minimum) /
              range)
              .clamp(
            0.0,
            1.0,
          ),
    )
        .toList(
      growable: false,
    );
  }

  // ===========================================================================
  // Candidate count
  // ===========================================================================

  /// topK * candidateMultiplier，决定向每个分支索取多少候选（先扩大候选池，再做融合排序，避免漏掉potentially relevant的文档）。
  /// - 输入：
  /// ```
  /// _calculateCandidateCount(10)（candidateMultiplier=5）
  /// ```
  /// - 输出：
  /// ```
  /// 50
  int _calculateCandidateCount(
      int topK,
      ) {
    return topK *
        candidateMultiplier;
  }

  // ===========================================================================
  // Validation
  // ===========================================================================

  /// 验证query和topK是否合法。query非空、topK>0，否则抛ArgumentError。
  void _validateQuery(
      String query,
      int topK,
      ) {
    if (query.trim().isEmpty) {
      throw ArgumentError(
        'Hybrid search query cannot be empty.',
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

// =============================================================================
// Internal candidate
// =============================================================================

/// 融合过程中的临时候选对象，携带原始分数+归一化分数+双路命中标记，copyWith用于在keyword结果合并时"补全"已存在的vector候选。
class _HybridCandidate {
  const _HybridCandidate({
    required this.id,
    required this.sourcePath,
    required this.rawVectorScore,
    required this.normalizedVectorScore,
    required this.keywordScore,
    required this.normalizedKeywordScore,
    required this.foundByVector,
    required this.foundByKeyword,
    this.content,
    this.metadata =
    const <String, dynamic>{},
  });

  final String id;

  final String sourcePath;

  final String? content;

  final double rawVectorScore;

  final double normalizedVectorScore;

  final double keywordScore;

  final double normalizedKeywordScore;

  final bool foundByVector;

  final bool foundByKeyword;

  final Map<String, dynamic> metadata;

  _HybridCandidate copyWith({
    double? rawVectorScore,
    double? normalizedVectorScore,
    double? keywordScore,
    double? normalizedKeywordScore,
    bool? foundByVector,
    bool? foundByKeyword,
  }) {
    return _HybridCandidate(
      id: id,
      sourcePath:
      sourcePath,
      content:
      content,

      rawVectorScore:
      rawVectorScore ??
          this.rawVectorScore,

      normalizedVectorScore:
      normalizedVectorScore ??
          this.normalizedVectorScore,

      keywordScore:
      keywordScore ??
          this.keywordScore,

      normalizedKeywordScore:
      normalizedKeywordScore ??
          this.normalizedKeywordScore,

      foundByVector:
      foundByVector ??
          this.foundByVector,

      foundByKeyword:
      foundByKeyword ??
          this.foundByKeyword,

      metadata:
      metadata,
    );
  }
}

// =============================================================================
// Public hybrid result
// =============================================================================

/// 最终返回给调用方的结果，
/// 字段包括：vectorScore/normalizedVectorScore/keywordScore/normalizedKeywordScore/finalScore/foundByVector/foundByKeyword，
/// 并提供三个便捷getter：
/// 1. foundByBoth：双路都命中
/// 2. vectorOnly：只有向量召回
/// 3. keywordOnly：只有关键词召回
class HybridSearchResult {
  const HybridSearchResult({
    required this.id,
    required this.sourcePath,
    required this.vectorScore,
    required this.normalizedVectorScore,
    required this.keywordScore,
    required this.normalizedKeywordScore,
    required this.finalScore,
    required this.foundByVector,
    required this.foundByKeyword,
    this.content,
    this.metadata =
    const <String, dynamic>{},
  });

  final String id;

  final String sourcePath;

  final String? content;

  /// Original vector score returned by VectorStore.
  ///
  /// If the document was retrieved only through KeywordRetriever:
  ///
  /// vectorScore = 0.0
  final double vectorScore;

  /// Vector score normalized within the vector candidate set.
  ///
  /// Range:
  /// [0,1]
  final double normalizedVectorScore;

  /// Original keyword score returned by KeywordIndex.
  ///
  /// If the document was retrieved only through VectorRetriever:
  ///
  /// keywordScore = 0.0
  final double keywordScore;

  /// Keyword score normalized within the keyword candidate set.
  ///
  /// Range:
  /// [0,1]
  final double normalizedKeywordScore;

  /// Final hybrid score.
  ///
  /// Default:
  ///
  /// 0.3 * normalizedVectorScore
  /// +
  /// 0.7 * normalizedKeywordScore
  final double finalScore;

  /// Whether this document appeared in Vector Top-N.
  final bool foundByVector;

  /// Whether this document appeared in Keyword Top-N.
  final bool foundByKeyword;

  final Map<String, dynamic> metadata;

  /// Candidate was retrieved by both branches.
  bool get foundByBoth => foundByVector && foundByKeyword;

  /// Candidate entered through vector retrieval only.
  bool get vectorOnly => foundByVector && !foundByKeyword;

  /// Candidate entered through keyword retrieval only.
  bool get keywordOnly => !foundByVector && foundByKeyword;

  @override
  String toString() {
    return 'HybridSearchResult('
        'id: $id, '
        'vector=${normalizedVectorScore.toStringAsFixed(4)}, '
        'keyword=${normalizedKeywordScore.toStringAsFixed(4)}, '
        'final=${finalScore.toStringAsFixed(4)}, '
        'vectorHit=$foundByVector, '
        'keywordHit=$foundByKeyword'
        ')';
  }
}