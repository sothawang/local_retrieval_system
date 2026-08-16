import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TFLiteModelManager modelManager;
  late EmbeddingEngine embeddingEngine;

  late StopWordPolicy stopWordPolicy;
  late KeywordIndex keywordIndex;

  late ChromaVectorStore vectorStore;
  late DocumentIndexer documentIndexer;
  late VectorRetriever vectorRetriever;
  late KeywordRetriever keywordRetriever;
  late HybridRetriever hybridRetriever;
  late RetrievalEngine retrievalEngine;

  late Directory tempDirectory;

  late File astronomyFile;
  late File cookingFile;
  late File accessibilityFile;

  setUpAll(() async {
    // ========================================================================
    // Week 3 - initialize embedding layer
    // ========================================================================

    HttpOverrides.global = null;
    modelManager = TFLiteModelManager.instance;

    await modelManager.initialize();

    await ClipTokenizer.instance.initialize();
    await BertTokenizer.instance.initialize();

    embeddingEngine = EmbeddingEngine(
      textEmbeddingService: TextEmbeddingService(),
      mobileClipTextEmbeddingService:
      MobileClipTextEmbeddingService(),
      imageEmbeddingService: ImageEmbeddingService(),
    );

    // ========================================================================
    // Week 4 - StopWordPolicy & KeywordIndex
    // ========================================================================

    stopWordPolicy = StopWordPolicy();

    await stopWordPolicy.initialize(
      englishAssetPath:
      'assets/retrieval/stopwords_en.json',
    );

    keywordIndex = KeywordIndex(
      stopWordPolicy: stopWordPolicy,
      domainDetector: const DomainDetector(),
    );

    // ========================================================================
    // Week 4 - Vector Store
    // ========================================================================

    vectorStore = ChromaVectorStore(
      bertCollectionName:
      'test_bert_text_embeddings',
      mobileClipCollectionName:
      'test_mobileclip_embeddings',
    );

    // ========================================================================
    // Week 2 - Parser
    // ========================================================================

    final LocalFileParser fileParser =
    LocalFileParser();

    // ========================================================================
    // Week 4 - Document Indexer
    // ========================================================================

    documentIndexer = DocumentIndexer(
      fileParser: fileParser,
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
      keywordIndex: keywordIndex,
    );

    // ========================================================================
    // Week 4 - Retriever chain
    // ========================================================================

    vectorRetriever = VectorRetriever(
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
    );

    keywordRetriever = KeywordRetriever(
      keywordIndex: keywordIndex,
    );

    hybridRetriever = HybridRetriever(
      vectorRetriever: vectorRetriever,
      keywordRetriever: keywordRetriever,
      vectorWeight: 0.7,
      keywordWeight: 0.3,
    );

    retrievalEngine = RetrievalEngine(
      documentIndexer: documentIndexer,
      hybridRetriever: hybridRetriever,
      vectorStore: vectorStore,
    );

    await retrievalEngine.initialize();

    // 初次清理测试集合，确保测试隔离
    await retrievalEngine.clearTextIndex();
    await retrievalEngine.clearMobileClipIndex();

    // ========================================================================
    // Create temporary local documents
    // ========================================================================

    tempDirectory =
    await Directory.systemTemp.createTemp(
      'retrieval_engine_test_',
    );

    astronomyFile = File(
      '${tempDirectory.path}/astronomy.txt',
    );

    cookingFile = File(
      '${tempDirectory.path}/cooking.txt',
    );

    accessibilityFile = File(
      '${tempDirectory.path}/accessibility.txt',
    );

    await astronomyFile.writeAsString(
      '''
The solar system contains the Sun, planets, moons, asteroids, and comets.
Earth revolves around the Sun once every year.
Mars is often called the red planet because of iron minerals in its soil.
Jupiter is the largest planet in the solar system.
''',
    );

    await cookingFile.writeAsString(
      '''
Pasta can be cooked by boiling water and adding salt.
Tomato sauce can contain tomatoes, garlic, onion, olive oil, and herbs.
Fresh basil is commonly used in Italian cooking.
''',
    );

    await accessibilityFile.writeAsString(
      '''
Web accessibility helps people with disabilities use digital content.
Screen readers convert text and interface semantics into speech or Braille.
WCAG provides guidelines for accessible web content.
Keyboard focus and sufficient contrast are important accessibility features.
''',
    );
  });

  tearDownAll(() async {
    try {
      await retrievalEngine.clearTextIndex();
    } catch (_) {}

    try {
      await retrievalEngine.clearMobileClipIndex();
    } catch (_) {}

    try {
      keywordIndex.clear();
    } catch (_) {}

    try {
      await retrievalEngine.dispose();
    } catch (_) {}

    try {
      modelManager.dispose();
    } catch (_) {}

    if (await tempDirectory.exists()) {
      await tempDirectory.delete(
        recursive: true,
      );
    }
  });

  group(
    'RetrievalEngine End-to-End Integration',
        () {
      // ======================================================================
      // 1. Initialization
      // ======================================================================

      test(
        'RetrievalEngine initializes successfully',
            () {
          expect(
            retrievalEngine.isInitialized,
            isTrue,
          );

          expect(
            vectorStore.isInitialized,
            isTrue,
          );

          expect(
            stopWordPolicy.isInitialized,
            isTrue,
          );
        },
      );

      // ======================================================================
      // 2. Index one text file
      // ======================================================================

      test(
        'Index a local text file successfully',
            () async {
          await retrievalEngine.clearTextIndex();
          keywordIndex.clear();

          final result =
          await retrievalEngine.indexFile(
            astronomyFile.path,
          );

          expect(
            result.isSuccess,
            isTrue,
            reason: result.message,
          );

          expect(
            result.indexedRecordCount,
            greaterThan(0),
          );

          final int count =
          await retrievalEngine
              .getTextIndexCount();

          expect(
            count,
            greaterThan(0),
          );

          print('');
          print(
            '==========================================',
          );
          print('INDEX SINGLE FILE');
          print(
            '==========================================',
          );
          print(
            'File: ${astronomyFile.path}',
          );
          print(
            'Indexed records: '
                '${result.indexedRecordCount}',
          );
          print(
            'Database count: $count',
          );
          print(
            '==========================================',
          );
        },
      );

      // ======================================================================
      // 3. Batch indexing
      // ======================================================================

      test(
        'Index multiple local files successfully',
            () async {
          await retrievalEngine.clearTextIndex();
          keywordIndex.clear();

          final results =
          await retrievalEngine.indexFiles(
            <String>[
              astronomyFile.path,
              cookingFile.path,
              accessibilityFile.path,
            ],
          );

          expect(
            results.length,
            equals(3),
          );

          for (final result in results) {
            expect(
              result.isSuccess,
              isTrue,
              reason:
              '${result.filePath}: ${result.message}',
            );

            expect(
              result.indexedRecordCount,
              greaterThan(0),
            );
          }

          final int count =
          await retrievalEngine
              .getTextIndexCount();

          expect(
            count,
            greaterThanOrEqualTo(3),
          );
        },
      );

      // ======================================================================
      // 4. Semantic text retrieval
      // ======================================================================

      test(
        'Retrieve astronomy document with semantic query',
            () async {
          await _prepareTextIndex(
            retrievalEngine,
            keywordIndex,
            <File>[
              astronomyFile,
              cookingFile,
              accessibilityFile,
            ],
          );

          final results =
          await retrievalEngine.searchTextDocuments(
            query:
            'Which planet is known for being red?',
            topK: 3,
          );

          expect(
            results,
            isNotEmpty,
          );

          expect(
            results.first.sourcePath,
            equals(astronomyFile.path),
          );

          print('');
          print(
            '==========================================',
          );
          print('SEMANTIC TEXT RETRIEVAL');
          print(
            '==========================================',
          );

          for (int i = 0;
          i < results.length;
          i++) {
            final result =
            results[i];

            print(
              '#${i + 1} '
                  '${result.sourcePath}',
            );

            print(
              'vector='
                  '${result.normalizedVectorScore.toStringAsFixed(4)} '
                  'keyword='
                  '${result.keywordScore.toStringAsFixed(4)} '
                  'final='
                  '${result.finalScore.toStringAsFixed(4)}',
            );

            print('');
          }
        },
      );

      // ======================================================================
      // 5. Exact keyword contribution
      // ======================================================================

      test(
        'Keyword score contributes to exact term retrieval',
            () async {
          await _prepareTextIndex(
            retrievalEngine,
            keywordIndex,
            <File>[
              astronomyFile,
              cookingFile,
              accessibilityFile,
            ],
          );

          final results =
          await retrievalEngine.searchTextDocuments(
            query: 'fresh basil pasta',
            topK: 3,
          );

          expect(
            results,
            isNotEmpty,
          );

          expect(
            results.first.sourcePath,
            equals(cookingFile.path),
          );

          expect(
            results.first.keywordScore,
            greaterThan(0.0),
          );
        },
      );

      // ======================================================================
      // 6. Accessibility terminology
      // ======================================================================

      test(
        'Accessibility terms are preserved in keyword retrieval',
            () async {
          await _prepareTextIndex(
            retrievalEngine,
            keywordIndex,
            <File>[
              astronomyFile,
              cookingFile,
              accessibilityFile,
            ],
          );

          final results =
          await retrievalEngine.searchTextDocuments(
            query:
            'WCAG screen reader keyboard focus',
            topK: 3,
          );

          expect(
            results,
            isNotEmpty,
          );

          expect(
            results.first.sourcePath,
            equals(accessibilityFile.path),
          );

          expect(
            results.first.keywordScore,
            greaterThan(0.0),
          );
        },
      );

      // ======================================================================
      // 7. Remove indexed file
      // ======================================================================

      test(
        'Remove indexed file',
            () async {
          await retrievalEngine.clearTextIndex();
          keywordIndex.clear();

          final result =
          await retrievalEngine.indexFile(
            astronomyFile.path,
          );

          expect(
            result.isSuccess,
            isTrue,
          );

          final int before =
          await retrievalEngine
              .getTextIndexCount();

          expect(
            before,
            greaterThan(0),
          );

          await retrievalEngine.removeFile(
            astronomyFile.path,
          );

          final int after =
          await retrievalEngine
              .getTextIndexCount();

          expect(
            after,
            equals(0),
          );
        },
      );

      // ======================================================================
      // 8. Re-index file
      // ======================================================================

      test(
        'Reindex replaces previous document index',
            () async {
          await retrievalEngine.clearTextIndex();
          keywordIndex.clear();

          final firstResult =
          await retrievalEngine.indexFile(
            astronomyFile.path,
          );

          expect(
            firstResult.isSuccess,
            isTrue,
          );

          final int firstCount =
          await retrievalEngine
              .getTextIndexCount();

          await astronomyFile.writeAsString(
            '''
Saturn is a planet famous for its large ring system.
The rings consist primarily of ice particles and rocky material.
''',
          );

          final secondResult =
          await retrievalEngine.reindexFile(
            astronomyFile.path,
          );

          expect(
            secondResult.isSuccess,
            isTrue,
          );

          final int secondCount =
          await retrievalEngine
              .getTextIndexCount();

          // Re-index should replace, not duplicate.
          expect(
            secondCount,
            equals(
              secondResult.indexedRecordCount,
            ),
          );

          expect(
            secondCount,
            lessThanOrEqualTo(
              firstCount + secondResult.indexedRecordCount,
            ),
          );

          final results =
          await retrievalEngine.searchTextDocuments(
            query:
            'Which planet has a large ring system?',
            topK: 1,
          );

          expect(
            results,
            isNotEmpty,
          );

          expect(
            results.first.sourcePath,
            equals(astronomyFile.path),
          );

          // Restore original content for other tests.
          await astronomyFile.writeAsString(
            '''
The solar system contains the Sun, planets, moons, asteroids, and comets.
Earth revolves around the Sun once every year.
Mars is often called the red planet because of iron minerals in its soil.
Jupiter is the largest planet in the solar system.
''',
          );
        },
      );

      // ======================================================================
      // 9. Empty query protection
      // ======================================================================

      test(
        'Reject empty search query',
            () async {
          expect(
                () => retrievalEngine.searchTextDocuments(
              query: '   ',
            ),
            throwsArgumentError,
          );
        },
      );

      // ======================================================================
      // 10. topK protection
      // ======================================================================

      test(
        'Reject invalid topK',
            () {
          expect(
                () => retrievalEngine.searchTextDocuments(
              query: 'planet',
              topK: 0,
            ),
            throwsArgumentError,
          );
        },
      );
    },
  );
}

/// Reset and populate the text index before a retrieval test.
///
/// 这样每个检索测试不会依赖前一个测试留下来的数据库状态。
Future<void> _prepareTextIndex(
    RetrievalEngine engine,
    KeywordIndex keywordIndex,
    List<File> files,
    ) async {
  await engine.clearTextIndex();
  keywordIndex.clear();

  final List<String> paths =
  files
      .map(
        (File file) => file.path,
  )
      .toList(growable: false);

  final results =
  await engine.indexFiles(paths);

  for (final result in results) {
    expect(
      result.isSuccess,
      isTrue,
      reason:
      '${result.filePath}: ${result.message}',
    );
  }
}