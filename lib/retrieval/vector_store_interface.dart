import 'dart:typed_data';

import 'models/vector_document.dart';
import 'models/vector_search_result.dart';

/// Week 4 Vector Database Layer 统一接口。
///
/// 上层 RetrievalEngine 不应该直接依赖 Chroma DB。
///```
/// RetrievalEngine
///       ↓
/// VectorStoreInterface
///       ↓
/// ChromaVectorStore
///```
/// 后面即使把 Chroma 替换成其他数据库，
/// RetrievalEngine 也不需要改。
abstract interface class VectorStoreInterface {
  /// 初始化数据库。
  Future<void> initialize();

  /// 插入单条向量记录。
  Future<void> addDocument(
      VectorDocument document,
      );

  /// 批量插入向量记录。
  Future<void> addDocuments(
      List<VectorDocument> documents,
      );

  /// 根据 query embedding 搜索最相似记录。
  Future<List<VectorSearchResult>> search({
    required Float32List queryEmbedding,
    required VectorEmbeddingType embeddingType,
    int topK = 10,
    Map<String, dynamic>? filters,
  });

  /// 根据 ID 删除记录。
  Future<void> deleteDocument(
      String id,
      );

  /// 根据文件路径删除相关记录。
  ///
  /// 一个文件可能被拆成多个 chunk，
  /// 所以这里可能删除多条记录。
  Future<void> deleteBySourcePath(
      String sourcePath,
      );

  /// 删除指定 embedding space 中的所有记录。
  Future<void> clear(
      VectorEmbeddingType embeddingType,
      );

  /// 数据库中记录数量。
  Future<int> count(
      VectorEmbeddingType embeddingType,
      );

  /// 是否已经初始化。
  bool get isInitialized;

  /// 释放资源。
  Future<void> dispose();
}