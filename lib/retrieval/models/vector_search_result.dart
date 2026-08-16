/// 向量检索返回结果。
class VectorSearchResult {
  final String id;

  final String sourcePath;

  final String? content;

  /// 相似度分数。
  ///
  /// 分数越高代表越相似。
  final double score;

  final Map<String, dynamic> metadata;

  const VectorSearchResult({
    required this.id,
    required this.sourcePath,
    required this.score,
    this.content,
    this.metadata = const <String, dynamic>{},
  });

  @override
  String toString() {
    return 'VectorSearchResult('
        'id: $id, '
        'sourcePath: $sourcePath, '
        'score: $score'
        ')';
  }
}