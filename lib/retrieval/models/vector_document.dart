import 'dart:typed_data';

/// 向量数据库中存储的一条记录。
///
/// 一条记录可以代表：
/// - 一个文本 chunk
/// - 一张图片
/// - 一个文档片段
///
/// embedding 已经由 Week 3 的 EmbeddingEngine 生成。
class VectorDocument {
  final String id;

  /// 原始文件路径
  final String sourcePath;

  /// 文本内容。
  ///
  /// 图片记录可以为空。
  final String? content;

  /// 向量数据
  final Float32List embedding;

  /// 向量所属空间。
  ///
  /// bert:
  ///   768维文本向量
  ///
  /// mobileClip:
  ///   512维图文共享向量
  final VectorEmbeddingType embeddingType;

  /// 可扩展 metadata
  final Map<String, dynamic> metadata;

  // 这里的const表示编译期创建，零运行时开销。这符合它作为"数据传输对象（DTO）"的定位——只用来携带数据，不需要有可变状态。
  /// 向量数据库中存储的一条记录。包含许多信息
  const VectorDocument({
    required this.id,
    required this.sourcePath,
    required this.embedding,
    required this.embeddingType,
    this.content,
    this.metadata = const <String, dynamic>{},
  });
}

/// 防止 BERT 768D 和 MobileCLIP 512D
/// 被错误放到同一个检索空间中比较。
enum VectorEmbeddingType {
  bert,
  mobileClip,
}