import 'dart:typed_data';

import 'package:local_retrieval_system/embedding/embedding_engine.dart';
import 'package:local_retrieval_system/embedding/embedding_engine_interface.dart';
import 'package:local_retrieval_system/retrieval/models/vector_document.dart';
import 'package:local_retrieval_system/retrieval/models/vector_search_result.dart';
import 'package:local_retrieval_system/retrieval/vector_store_interface.dart';

/// 数据查询流水线。
/// 将人类可读的查询输入（文字或图片）转化为数学向量，并去向量数据库中把最相似的结果找出来。
/// 1. 将自然语言 / 图片转化为“查询向量（Query Vector）
/// 2. 路由选择正确的检索空间进行搜索
/// 3. 支持元数据过滤
/// 4. 为上层（如 HybridRetriever / UI）屏蔽复杂的向量计算细节
// 负责：
//
// 用户 Query
//     ↓
// EmbeddingEngine
//     ↓
// 生成 Query 向量
//     ↓
// VectorStore
//     ↓
// Similarity Search
//     ↓
// Top-K VectorSearchResult
//
// 支持两种检索空间：
//
// 1. BERT
//    text query -> text documents
//
// 2. MobileCLIP
//    text query -> images / multimodal records
class VectorRetriever {
  VectorRetriever({
    required EmbeddingEngineInterface embeddingEngine,
    required VectorStoreInterface vectorStore,
  })  : _embeddingEngine = embeddingEngine,
        _vectorStore = vectorStore;

  final EmbeddingEngineInterface _embeddingEngine;
  final VectorStoreInterface _vectorStore;

  // ===========================================================================
  // Text -> Text retrieval
  // ===========================================================================

  /// 使用 BERT 做文本语义检索。
  ///
  /// Query:
  ///   String
  ///      ↓
  ///   BERT
  ///      ↓
  ///   768D
  ///      ↓
  ///   Search BERT collection
  ///
  /// 适合：
  /// - PDF
  /// - Word
  /// - TXT
  /// - OCR text
  /// - parsed document chunks
  Future<List<VectorSearchResult>> searchText({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    _validateQuery(
      query,
      topK,
    );

    _ensureVectorStoreReady();

    final Float32List queryEmbedding =
    await _embeddingEngine
        .generateTextEmbeddingWithMode(
      query,
      mode: TextEmbeddingMode.bert,
    );

    return _vectorStore.search(
      queryEmbedding: queryEmbedding,
      embeddingType: VectorEmbeddingType.bert,
      topK: topK,
      filters: filters,
    );
  }

  // ===========================================================================
  // Text -> Image / Multimodal retrieval
  // ===========================================================================

  /// 使用 MobileCLIP Text Encoder 搜索
  /// MobileCLIP embedding space 中的内容。
  ///```
  /// Query:
  ///   String
  ///      ↓
  /// ClipTokenizer
  ///      ↓
  /// MobileCLIP Text
  ///      ↓
  /// 512D
  ///      ↓
  /// Search MobileCLIP collection
  ///```
  /// 当前主要用于：
  /// - text -> image retrieval
  /// - searchMultimodal(query: "跑车", filters: {...}) 的场景：
  ///
  ///   - 需要追加额外的自定义筛选条件（例如：“只要 2026 年创建的 .png 格式图片”）。
  ///   - 此时 searchImages 不支持传 filters，你必须使用 searchMultimodal 并自己传入 filters: {'data_type': 'image', 'file_extension': '.png'}。
  Future<List<VectorSearchResult>> searchMultimodal({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    _validateQuery(
      query,
      topK,
    );

    _ensureVectorStoreReady();

    final Float32List queryEmbedding =
    await _embeddingEngine
        .generateTextEmbeddingWithMode(
      query,
      mode: TextEmbeddingMode.mobileClip,
    );

    return _vectorStore.search(
      queryEmbedding: queryEmbedding,
      embeddingType:
      VectorEmbeddingType.mobileClip,
      topK: topK,
      filters: filters,
    );
  }

  // ===========================================================================
  // Search using an already generated embedding
  // ===========================================================================

  /// 如果上层已经有 embedding，
  /// 可以直接查询数据库，不需要再次运行模型。
  Future<List<VectorSearchResult>>
  searchByEmbedding({
    required Float32List queryEmbedding,
    required VectorEmbeddingType embeddingType,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    if (topK <= 0) {
      throw ArgumentError.value(
        topK,
        'topK',
        'topK must be greater than 0.',
      );
    }

    _ensureVectorStoreReady();

    return _vectorStore.search(
      queryEmbedding: queryEmbedding,
      embeddingType: embeddingType,
      topK: topK,
      filters: filters,
    );
  }

  // ===========================================================================
  // Image -> Image / Multimodal retrieval
  // ===========================================================================

  /// 使用一张图片作为 query。
  ///
  /// Image bytes
  ///      ↓
  /// MobileCLIP Image Encoder
  ///      ↓
  /// 512D
  ///      ↓
  /// Search MobileCLIP collection
  ///
  /// 可以用于：
  /// - image -> image retrieval
  /// - image -> multimodal retrieval
  Future<List<VectorSearchResult>>
  searchByImage({
    required Uint8List imageBytes,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    if (imageBytes.isEmpty) {
      throw ArgumentError(
        'imageBytes cannot be empty.',
      );
    }

    if (topK <= 0) {
      throw ArgumentError.value(
        topK,
        'topK',
        'topK must be greater than 0.',
      );
    }

    _ensureVectorStoreReady();

    final Float32List queryEmbedding =
    await _embeddingEngine
        .generateImageEmbedding(
      imageBytes,
    );

    return _vectorStore.search(
      queryEmbedding: queryEmbedding,
      embeddingType:
      VectorEmbeddingType.mobileClip,
      topK: topK,
      filters: filters,
    );
  }

  // ===========================================================================
  // Search only images
  // ===========================================================================

  /// Text -> Image retrieval。
  ///
  /// 在 MobileCLIP collection 中只返回图片相关：
  ///
  /// metadata:
  ///   data_type = image
  /// - searchImages(query: "跑车") 的场景：
  ///
  /// 在 UI 界面点击了 “图片搜索” 选项卡。
  /// 只希望拿到纯粹的图片结果，且不需要额外的复杂筛选条件。直接调 searchImages 最方便、最安全。
  Future<List<VectorSearchResult>> searchImages({
    required String query,
    int topK = 10,
  }) {
    return searchMultimodal(
      query: query,
      topK: topK,
      filters: <String, dynamic>{
        'data_type': 'image',
      },
    );
  }

  // ===========================================================================
  // Search only text
  // ===========================================================================

  /// BERT 文本检索，只返回文本 chunk。
  Future<List<VectorSearchResult>>
  searchTextDocuments({
    required String query,
    int topK = 10,
  }) {
    return searchText(
      query: query,
      topK: topK,
      filters: <String, dynamic>{
        'data_type': 'text',
      },
    );
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// 验证输入的查询语句是否为空，以及topK是否大于0
  void _validateQuery(
      String query,
      int topK,
      ) {
    if (query.trim().isEmpty) {
      throw ArgumentError(
        'Search query cannot be empty.',
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

  /// 确保vectorStore已经初始化
  void _ensureVectorStoreReady() {
    if (!_vectorStore.isInitialized) {
      throw StateError(
        'VectorStore is not initialized. '
            'Call initialize() before searching.',
      );
    }
  }
}