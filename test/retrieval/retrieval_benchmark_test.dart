import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_retrieval_system/embedding/embedding_engine.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/tokenizer/bert_tokenizer.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';

import 'package:local_retrieval_system/retrieval/models/vector_document.dart';
import 'package:local_retrieval_system/retrieval/models/vector_search_result.dart';
import 'package:local_retrieval_system/retrieval/retrievers/hybrid_retriever.dart';
import 'package:local_retrieval_system/retrieval/retrievers/keyword_retriever.dart';
import 'package:local_retrieval_system/retrieval/retrievers/vector_retriever.dart';
import 'package:local_retrieval_system/retrieval/token_filter/domain_detector.dart';
import 'package:local_retrieval_system/retrieval/token_filter/stop_word_policy.dart';
import 'package:local_retrieval_system/retrieval/vector_store/chroma_vector_store.dart';
import 'package:local_retrieval_system/retrieval/keyword_index/keyword_index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // Benchmark configuration
  // ===========================================================================

  const int nqBenchmarkSize = 100;
  const int cocoBenchmarkSize = 100;

  const String nqDatasetPath =
      '../curated_datasets/Natural_Questions/nq_val_500.json';

  const String cocoPairsPath =
      '../curated_datasets/coco_curated_500/image_caption_pairs.json';

  const String cocoImageDirectory =
      '../curated_datasets/coco_curated_500/images';

  late TFLiteModelManager modelManager;
  late EmbeddingEngine embeddingEngine;

  late StopWordPolicy stopWordPolicy;

  late ChromaVectorStore vectorStore;

  late KeywordIndex keywordIndex;

  late VectorRetriever vectorRetriever;
  late KeywordRetriever keywordRetriever;
  late HybridRetriever hybridRetriever;

  setUpAll(() async {
    // =========================================================================
    // Week 3 - Embedding Layer
    // =========================================================================

    HttpOverrides.global = null;
    modelManager = TFLiteModelManager.instance;

    await modelManager.initialize();

    await ClipTokenizer.instance.initialize();
    await BertTokenizer.instance.initialize();

    embeddingEngine = EmbeddingEngine();

    // =========================================================================
    // Week 4 - Token policy
    // =========================================================================

    stopWordPolicy = StopWordPolicy();

    await stopWordPolicy.initialize(
      englishAssetPath:
      'assets/retrieval/stopwords_en.json',
    );

    keywordIndex = KeywordIndex(
      stopWordPolicy: stopWordPolicy,
      domainDetector: const DomainDetector(),
    );

    // =========================================================================
    // Week 4 - Vector Store
    // =========================================================================

    vectorStore = ChromaVectorStore(
      bertCollectionName:
      'benchmark_bert_embeddings',
      mobileClipCollectionName:
      'benchmark_mobileclip_embeddings',
    );

    await vectorStore.initialize();

    // Ensure benchmark starts clean.
    await vectorStore.clear(
      VectorEmbeddingType.bert,
    );

    await vectorStore.clear(
      VectorEmbeddingType.mobileClip,
    );

    keywordIndex.clear();

    // =========================================================================
    // Retrieval components
    // =========================================================================

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

      // Current Week 4 default.
      vectorWeight: 0.7,
      keywordWeight: 0.3,

      candidateMultiplier: 5,
    );
  });

  tearDownAll(() async {
    try {
      keywordIndex.clear();
    } catch (_) {}

    try {
      await vectorStore.clear(
        VectorEmbeddingType.bert,
      );
    } catch (_) {}

    try {
      await vectorStore.clear(
        VectorEmbeddingType.mobileClip,
      );
    } catch (_) {}

    try {
      await vectorStore.dispose();
    } catch (_) {}

    try {
      modelManager.dispose();
    } catch (_) {}
  });

  group(
    'Week 4 Retrieval Benchmark',
        () {
      // =======================================================================
      // NQ BENCHMARK
      // =======================================================================
      //
      // Corpus:
      // answer_0
      // answer_1
      // ...
      //
      // Query:
      // question_i
      //
      // Relevant result:
      // answer_i
      //
      // Compare:
      //
      // 1. Vector-only
      // 2. Keyword-only
      // 3. Hybrid
      //
      // Metrics:
      //
      // Recall@1
      // Recall@5
      // Recall@10
      // MRR
      // Average query latency
      // =======================================================================

      test(
        'NQ benchmark - Vector vs Keyword vs Hybrid',
            () async {
          // -------------------------------------------------------------------
          // Load NQ
          // -------------------------------------------------------------------

          final File datasetFile =
          File(nqDatasetPath);

          expect(
            await datasetFile.exists(),
            isTrue,
            reason:
            'NQ dataset not found: $nqDatasetPath',
          );

          final List<dynamic> raw =
          jsonDecode(
            await datasetFile.readAsString(),
          ) as List<dynamic>;

          expect(
            raw.length,
            greaterThanOrEqualTo(
              nqBenchmarkSize,
            ),
          );

          final List<_NqItem> items =
          raw
              .take(nqBenchmarkSize)
              .map(
                (dynamic item) {
              final map =
              item as Map<String, dynamic>;

              return _NqItem(
                question:
                map['question'] as String,
                answer:
                map['answer'] as String,
              );
            },
          )
              .toList(
            growable: false,
          );

          print('');
          print(
            '============================================================',
          );
          print(
            'WEEK 4 - NQ RETRIEVAL BENCHMARK',
          );
          print(
            '============================================================',
          );
          print(
            'Samples: ${items.length}',
          );

          // -------------------------------------------------------------------
          // Clear previous benchmark index
          // -------------------------------------------------------------------

          await vectorStore.clear(
            VectorEmbeddingType.bert,
          );

          // -------------------------------------------------------------------
          // Generate + index answer embeddings
          // -------------------------------------------------------------------

          print('');
          print(
            'Indexing NQ answer corpus...',
          );

          final Stopwatch indexingWatch =
          Stopwatch()..start();

          final List<VectorDocument> documents =
          <VectorDocument>[];

          final List<KeywordIndexedDocument> keywordDocuments =
          <KeywordIndexedDocument>[];

          for (int i = 0;
          i < items.length;
          i++) {
            final Float32List embedding =
            await embeddingEngine
                .generateTextEmbeddingWithMode(
              items[i].answer,
              mode: TextEmbeddingMode.bert,
            );

            final String id =
                'nq_answer_$i';

            documents.add(
              VectorDocument(
                id: id,
                sourcePath:
                'nq://answer/$i',
                content:
                items[i].answer,
                embedding:
                embedding,
                embeddingType:
                VectorEmbeddingType.bert,
                metadata:
                <String, dynamic>{
                  'data_type': 'text',
                  'dataset': 'nq',
                  'answer_index': i,
                },
              ),
            );

            keywordDocuments.add(
              KeywordIndexedDocument(
                id: id,
                sourcePath:
                'nq://answer/$i',
                content:
                items[i].answer,
                metadata:
                <String, dynamic>{
                  'data_type': 'text',
                  'dataset': 'nq',
                  'answer_index': i,
                },
              ),
            );

            if ((i + 1) % 10 == 0) {
              print(
                'Embeddings: '
                    '${i + 1}/${items.length}',
              );
            }
          }

          await vectorStore.addDocuments(
            documents,
          );

          await keywordIndex.addDocuments(
            keywordDocuments,
          );

          indexingWatch.stop();

          final double indexingMs =
              indexingWatch
                  .elapsedMicroseconds /
                  1000.0;

          print(
            'Indexing completed: '
                '${indexingMs.toStringAsFixed(2)} ms',
          );

          // -------------------------------------------------------------------
          // VECTOR ONLY
          // -------------------------------------------------------------------

          final _BenchmarkAccumulator
          vectorMetrics =
          _BenchmarkAccumulator();

          print('');
          print(
            'Running Vector-only benchmark...',
          );

          for (int i = 0;
          i < items.length;
          i++) {
            final Stopwatch watch =
            Stopwatch()..start();

            final List<VectorSearchResult>
            results =
            await vectorRetriever
                .searchTextDocuments(
              query:
              items[i].question,

              // Need at least 10 for R@10.
              topK: mathMin(
                10,
                items.length,
              ),
            );

            watch.stop();

            final List<String> rankedIds =
            results
                .map(
                  (result) =>
              result.id,
            )
                .toList(
              growable: false,
            );

            vectorMetrics.add(
              expectedId:
              'nq_answer_$i',
              rankedIds:
              rankedIds,
              latency:
              watch.elapsed,
            );
          }

          // -------------------------------------------------------------------
          // KEYWORD ONLY
          // -------------------------------------------------------------------

          final _BenchmarkAccumulator keywordMetrics =
          _BenchmarkAccumulator();

          print(
            'Running Keyword-only benchmark...',
          );

          for (int i = 0;
          i < items.length;
          i++) {
            final Stopwatch watch =
            Stopwatch()..start();

            final results =
            keywordRetriever.searchTextDocuments(
              query: items[i].question,
              topK: mathMin(
                10,
                items.length,
              ),
            );

            watch.stop();

            final List<String> rankedIds =
            results
                .map(
                  (result) => result.id,
            )
                .toList(
              growable: false,
            );

            keywordMetrics.add(
              expectedId:
              'nq_answer_$i',
              rankedIds:
              rankedIds,
              latency:
              watch.elapsed,
            );
          }

          // -------------------------------------------------------------------
          // HYBRID
          // -------------------------------------------------------------------

          final _BenchmarkAccumulator
          hybridMetrics =
          _BenchmarkAccumulator();

          print(
            'Running Hybrid benchmark...',
          );

          for (int i = 0;
          i < items.length;
          i++) {
            final Stopwatch watch =
            Stopwatch()..start();

            final results =
            await hybridRetriever
                .searchTextDocuments(
              query:
              items[i].question,
              topK:
              mathMin(
                10,
                items.length,
              ),
            );

            watch.stop();

            final List<String> rankedIds =
            results
                .map(
                  (result) =>
              result.id,
            )
                .toList(
              growable: false,
            );

            hybridMetrics.add(
              expectedId:
              'nq_answer_$i',
              rankedIds:
              rankedIds,
              latency:
              watch.elapsed,
            );
          }

          // -------------------------------------------------------------------
          // Print results
          // -------------------------------------------------------------------

          print('');
          print(
            '============================================================',
          );
          print(
            'NQ BENCHMARK RESULTS',
          );
          print(
            '============================================================',
          );

          _printBenchmark(
            'VECTOR ONLY',
            vectorMetrics,
          );

          _printBenchmark(
            'KEYWORD ONLY',
            keywordMetrics,
          );

          _printBenchmark(
            'HYBRID',
            hybridMetrics,
          );

          print(
            '------------------------------------------------------------',
          );
          print(
            'Indexing latency: '
                '${indexingMs.toStringAsFixed(2)} ms',
          );
          print(
            '============================================================',
          );

          // -------------------------------------------------------------------
          // Validate benchmark values
          // -------------------------------------------------------------------

          _validateBenchmark(
            vectorMetrics,
          );

          _validateBenchmark(
            keywordMetrics,
          );

          _validateBenchmark(
            hybridMetrics,
          );
        },
        timeout: const Timeout(
          Duration(minutes: 30),
        ),
      );

      // =======================================================================
      // COCO BENCHMARK
      // =======================================================================
      //
      // Corpus:
      // images
      //
      // Query:
      // caption
      //
      // Relevant result:
      // corresponding image
      //
      // Compare:
      //
      // 1. MobileCLIP Vector-only
      // 2. Hybrid
      //
      // We intentionally DO NOT report Keyword-only retrieval here.
      //
      // Why?
      //
      // If the ground-truth image metadata stores its own caption, and we query
      // with that exact caption, Keyword-only would directly match the answer
      // metadata and create artificial ground-truth leakage.
      //
      // Therefore the meaningful COCO benchmark is:
      //
      // MobileCLIP Text -> Image vector retrieval
      // vs
      // Hybrid reranking
      // =======================================================================

      test(
        'COCO benchmark - MobileCLIP Vector vs Hybrid',
            () async {
          final File pairsFile =
          File(cocoPairsPath);

          expect(
            await pairsFile.exists(),
            isTrue,
            reason:
            'COCO mapping not found: '
                '$cocoPairsPath',
          );

          final Map<String, dynamic> rawPairs =
          jsonDecode(
            await pairsFile.readAsString(),
          ) as Map<String, dynamic>;

          expect(
            rawPairs.length,
            greaterThanOrEqualTo(
              cocoBenchmarkSize,
            ),
          );

          final List<_CocoItem> items =
          rawPairs.entries
              .take(
            cocoBenchmarkSize,
          )
              .map(
                (
                MapEntry<String, dynamic>
                entry,
                ) {
              return _CocoItem(
                fileName:
                entry.key,
                caption:
                entry.value
                as String,
              );
            },
          )
              .toList(
            growable: false,
          );

          print('');
          print(
            '============================================================',
          );
          print(
            'WEEK 4 - COCO RETRIEVAL BENCHMARK',
          );
          print(
            '============================================================',
          );
          print(
            'Samples: ${items.length}',
          );

          await vectorStore.clear(
            VectorEmbeddingType.mobileClip,
          );

          keywordIndex.clear();
          // -------------------------------------------------------------------
          // Image indexing
          // -------------------------------------------------------------------

          print('');
          print(
            'Indexing COCO image corpus...',
          );

          final Stopwatch indexingWatch =
          Stopwatch()..start();

          final List<VectorDocument> imageDocuments =
          <VectorDocument>[];

          final List<KeywordIndexedDocument>
          keywordImageDocuments =
          <KeywordIndexedDocument>[];

          for (int i = 0;
          i < items.length;
          i++) {
            final String path =
                '$cocoImageDirectory/'
                '${items[i].fileName}';

            final File file =
            File(path);

            expect(
              await file.exists(),
              isTrue,
              reason:
              'Missing COCO image: $path',
            );

            final Uint8List bytes =
            await file.readAsBytes();

            final Float32List embedding =
            await embeddingEngine
                .generateImageEmbedding(
              bytes,
            );

            imageDocuments.add(
              VectorDocument(
                id:
                'coco_image_$i',
                sourcePath:
                path,
                content: null,
                embedding:
                embedding,
                embeddingType:
                VectorEmbeddingType
                    .mobileClip,
                metadata:
                <String, dynamic>{
                  'data_type':
                  'image',
                  'dataset':
                  'coco',
                  'image_index':
                  i,

                  // This is useful for HybridRetriever's
                  // lexical branch.
                  //
                  // Do NOT use this metadata to claim a
                  // keyword-only COCO benchmark.
                  'caption':
                  items[i].caption,
                  'file_name':
                  items[i].fileName,
                },
              ),
            );

            keywordImageDocuments.add(
              KeywordIndexedDocument(
                id: 'coco_image_$i',
                sourcePath: path,
                content: null,
                metadata:
                <String, dynamic>{
                  'data_type': 'image',
                  'dataset': 'coco',
                  'image_index': i,
                  'caption':
                  items[i].caption,
                  'file_name':
                  items[i].fileName,
                },
              ),
            );

            if ((i + 1) % 10 == 0) {
              print(
                'Images: '
                    '${i + 1}/${items.length}',
              );
            }
          }

          await vectorStore.addDocuments(
            imageDocuments,
          );

          await keywordIndex.addDocuments(
            keywordImageDocuments,
          );

          indexingWatch.stop();

          final double indexingMs =
              indexingWatch
                  .elapsedMicroseconds /
                  1000.0;

          // -------------------------------------------------------------------
          // MobileCLIP Vector-only
          // -------------------------------------------------------------------

          final _BenchmarkAccumulator
          vectorMetrics =
          _BenchmarkAccumulator();

          print('');
          print(
            'Running MobileCLIP Vector-only benchmark...',
          );

          for (int i = 0;
          i < items.length;
          i++) {
            final Stopwatch watch =
            Stopwatch()..start();

            final results =
            await vectorRetriever
                .searchImages(
              query:
              items[i].caption,
              topK:
              mathMin(
                10,
                items.length,
              ),
            );

            watch.stop();

            vectorMetrics.add(
              expectedId:
              'coco_image_$i',
              rankedIds:
              results
                  .map(
                    (result) =>
                result.id,
              )
                  .toList(
                growable:
                false,
              ),
              latency:
              watch.elapsed,
            );
          }

          // -------------------------------------------------------------------
          // Hybrid
          // -------------------------------------------------------------------

          final _BenchmarkAccumulator
          hybridMetrics =
          _BenchmarkAccumulator();

          print(
            'Running COCO Hybrid benchmark...',
          );

          for (int i = 0;
          i < items.length;
          i++) {
            final Stopwatch watch =
            Stopwatch()..start();

            final results =
            await hybridRetriever
                .searchImages(
              query:
              items[i].caption,
              topK:
              mathMin(
                10,
                items.length,
              ),
            );

            watch.stop();

            hybridMetrics.add(
              expectedId:
              'coco_image_$i',
              rankedIds:
              results
                  .map(
                    (result) =>
                result.id,
              )
                  .toList(
                growable:
                false,
              ),
              latency:
              watch.elapsed,
            );
          }

          // -------------------------------------------------------------------
          // Results
          // -------------------------------------------------------------------

          print('');
          print(
            '============================================================',
          );
          print(
            'COCO BENCHMARK RESULTS',
          );
          print(
            '============================================================',
          );

          _printBenchmark(
            'MOBILECLIP VECTOR ONLY',
            vectorMetrics,
          );

          _printBenchmark(
            'HYBRID',
            hybridMetrics,
          );

          print(
            '------------------------------------------------------------',
          );

          print(
            'Image indexing latency: '
                '${indexingMs.toStringAsFixed(2)} ms',
          );

          print(
            '============================================================',
          );

          _validateBenchmark(
            vectorMetrics,
          );

          _validateBenchmark(
            hybridMetrics,
          );
        },
        timeout: const Timeout(
          Duration(minutes: 30),
        ),
      );
    },
  );
}

// =============================================================================
// NQ item
// =============================================================================

class _NqItem {
  const _NqItem({
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;
}

// =============================================================================
// COCO item
// =============================================================================

class _CocoItem {
  const _CocoItem({
    required this.fileName,
    required this.caption,
  });

  final String fileName;
  final String caption;
}

// =============================================================================
// Benchmark accumulator
// =============================================================================

class _BenchmarkAccumulator {
  int queryCount = 0;

  int recallAt1Hits = 0;
  int recallAt5Hits = 0;
  int recallAt10Hits = 0;

  double reciprocalRankSum = 0.0;

  int totalLatencyMicroseconds = 0;

  void add({
    required String expectedId,
    required List<String> rankedIds,
    required Duration latency,
  }) {
    queryCount++;

    totalLatencyMicroseconds +=
        latency.inMicroseconds;

    final int index =
    rankedIds.indexOf(expectedId);

    // Not present in returned top-K.
    if (index < 0) {
      return;
    }

    final int rank = index + 1;

    if (rank <= 1) {
      recallAt1Hits++;
    }

    if (rank <= 5) {
      recallAt5Hits++;
    }

    if (rank <= 10) {
      recallAt10Hits++;
    }

    reciprocalRankSum +=
        1.0 / rank;
  }

  double get recallAt1 {
    if (queryCount == 0) {
      return 0.0;
    }

    return recallAt1Hits /
        queryCount;
  }

  double get recallAt5 {
    if (queryCount == 0) {
      return 0.0;
    }

    return recallAt5Hits /
        queryCount;
  }

  double get recallAt10 {
    if (queryCount == 0) {
      return 0.0;
    }

    return recallAt10Hits /
        queryCount;
  }

  double get mrr {
    if (queryCount == 0) {
      return 0.0;
    }

    return reciprocalRankSum /
        queryCount;
  }

  double get averageLatencyMs {
    if (queryCount == 0) {
      return 0.0;
    }

    return totalLatencyMicroseconds /
        queryCount /
        1000.0;
  }
}

// =============================================================================
// Print benchmark
// =============================================================================

void _printBenchmark(
    String name,
    _BenchmarkAccumulator metrics,
    ) {
  print('');
  print(name);
  print(
    '------------------------------------------------------------',
  );

  print(
    'Queries    : ${metrics.queryCount}',
  );

  print(
    'Recall@1   : '
        '${metrics.recallAt1.toStringAsFixed(4)} '
        '(${(metrics.recallAt1 * 100).toStringAsFixed(2)}%)',
  );

  print(
    'Recall@5   : '
        '${metrics.recallAt5.toStringAsFixed(4)} '
        '(${(metrics.recallAt5 * 100).toStringAsFixed(2)}%)',
  );

  print(
    'Recall@10  : '
        '${metrics.recallAt10.toStringAsFixed(4)} '
        '(${(metrics.recallAt10 * 100).toStringAsFixed(2)}%)',
  );

  print(
    'MRR        : '
        '${metrics.mrr.toStringAsFixed(4)}',
  );

  print(
    'Avg latency: '
        '${metrics.averageLatencyMs.toStringAsFixed(2)} ms/query',
  );
}

// =============================================================================
// Validate benchmark
// =============================================================================

void _validateBenchmark(
    _BenchmarkAccumulator metrics,
    ) {
  expect(
    metrics.queryCount,
    greaterThan(0),
  );

  expect(
    metrics.recallAt1,
    inInclusiveRange(0.0, 1.0),
  );

  expect(
    metrics.recallAt5,
    inInclusiveRange(0.0, 1.0),
  );

  expect(
    metrics.recallAt10,
    inInclusiveRange(0.0, 1.0),
  );

  expect(
    metrics.mrr,
    inInclusiveRange(0.0, 1.0),
  );

  expect(
    metrics.recallAt5,
    greaterThanOrEqualTo(
      metrics.recallAt1,
    ),
  );

  expect(
    metrics.recallAt10,
    greaterThanOrEqualTo(
      metrics.recallAt5,
    ),
  );

  expect(
    metrics.averageLatencyMs,
    greaterThanOrEqualTo(0.0),
  );
}

// =============================================================================
// Utility
// =============================================================================

int mathMin(
    int first,
    int second,
    ) {
  return first < second
      ? first
      : second;
}