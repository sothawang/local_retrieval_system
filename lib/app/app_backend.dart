import 'package:local_retrieval_system/embedding/embedding_engine.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/services/image_embedding_service.dart';
import 'package:local_retrieval_system/embedding/services/mobileclip_text_embedding_service.dart';
import 'package:local_retrieval_system/embedding/services/text_embedding_service.dart';
import 'package:local_retrieval_system/embedding/tokenizer/bert_tokenizer.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';
import 'package:local_retrieval_system/parsing/local_file_parser.dart';
import 'package:local_retrieval_system/retrieval/indexing/document_indexer.dart';
import 'package:local_retrieval_system/retrieval/keyword_index/keyword_index.dart';
import 'package:local_retrieval_system/retrieval/retrieval_engine.dart';
import 'package:local_retrieval_system/retrieval/retrievers/hybrid_retriever.dart';
import 'package:local_retrieval_system/retrieval/retrievers/keyword_retriever.dart';
import 'package:local_retrieval_system/retrieval/retrievers/vector_retriever.dart';
import 'package:local_retrieval_system/retrieval/token_filter/domain_detector.dart';
import 'package:local_retrieval_system/retrieval/token_filter/stop_word_policy.dart';
import 'package:local_retrieval_system/retrieval/vector_store/chroma_vector_store.dart';

Future<RetrievalEngine> buildRetrievalEngine() async {
  final TFLiteModelManager modelManager =
      TFLiteModelManager.instance;

  await modelManager.initialize();
  await BertTokenizer.instance.initialize();
  await ClipTokenizer.instance.initialize();

  final EmbeddingEngine embeddingEngine =
  EmbeddingEngine(
    textEmbeddingService: TextEmbeddingService(),
    mobileClipTextEmbeddingService:
    MobileClipTextEmbeddingService(),
    imageEmbeddingService: ImageEmbeddingService(),
  );

  final StopWordPolicy stopWordPolicy =
  StopWordPolicy();

  await stopWordPolicy.initialize(
    englishAssetPath:
    'assets/retrieval/stopwords_en.json',
  );

  final KeywordIndex keywordIndex =
  KeywordIndex(
    stopWordPolicy: stopWordPolicy,
    domainDetector: const DomainDetector(),
  );

  final ChromaVectorStore vectorStore =
  ChromaVectorStore();

  final DocumentIndexer documentIndexer =
  DocumentIndexer(
    fileParser: LocalFileParser(),
    embeddingEngine: embeddingEngine,
    vectorStore: vectorStore,
    keywordIndex: keywordIndex,
  );

  final VectorRetriever vectorRetriever =
  VectorRetriever(
    embeddingEngine: embeddingEngine,
    vectorStore: vectorStore,
  );

  final KeywordRetriever keywordRetriever =
  KeywordRetriever(
    keywordIndex: keywordIndex,
  );

  final HybridRetriever hybridRetriever =
  HybridRetriever(
    vectorRetriever: vectorRetriever,
    keywordRetriever: keywordRetriever,

    // 当前 benchmark 选择的权重。
    vectorWeight: 0.3,
    keywordWeight: 0.7,
  );

  final RetrievalEngine retrievalEngine =
  RetrievalEngine(
    documentIndexer: documentIndexer,
    hybridRetriever: hybridRetriever,
    vectorStore: vectorStore,
  );

  await retrievalEngine.initialize();

  return retrievalEngine;
}