import 'package:local_retrieval_system/retrieval/indexing/document_indexer.dart';
import 'package:local_retrieval_system/retrieval/retrievers/hybrid_retriever.dart';

/// Retrieval Layer 对外统一接口。
///
/// 上层 UI / Application Layer 不需要知道：
///
/// - ChromaVectorStore
/// - VectorRetriever
/// - KeywordRetriever
/// - HybridRetriever
/// - DocumentIndexer
///
/// 只通过 RetrievalEngineInterface 调用：
///
/// - indexFile()
/// - indexFiles()
/// - removeFile()
/// - searchText()
/// - searchImages()
abstract interface class RetrievalEngineInterface {
  /// 索引单个本地文件。
  Future<IndexingResult> indexFile(String filePath);

  /// 批量索引本地文件。
  Future<List<IndexingResult>> indexFiles(List<String> filePaths);

  /// 删除指定文件对应的索引。
  Future<void> removeFile(String filePath);

  /// 重新索引指定文件。
  Future<IndexingResult> reindexFile(String filePath);

  /// Hybrid text retrieval。
  ///
  /// 使用：
  ///
  /// BERT semantic similarity
  /// +
  /// keyword lexical similarity
  Future<List<HybridSearchResult>> searchText({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  });

  /// Text -> Image retrieval。
  ///
  /// 使用 MobileCLIP shared embedding space。
  Future<List<HybridSearchResult>> searchImages({
    required String query,
    int topK = 10,
  });
}