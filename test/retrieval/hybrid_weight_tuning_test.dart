import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_retrieval_system/embedding/embedding_engine.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/tokenizer/bert_tokenizer.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';

import 'package:local_retrieval_system/retrieval/keyword_index/keyword_index.dart';
import 'package:local_retrieval_system/retrieval/models/vector_document.dart';
import 'package:local_retrieval_system/retrieval/retrievers/hybrid_retriever.dart';
import 'package:local_retrieval_system/retrieval/retrievers/keyword_retriever.dart';
import 'package:local_retrieval_system/retrieval/retrievers/vector_retriever.dart';
import 'package:local_retrieval_system/retrieval/token_filter/domain_detector.dart';
import 'package:local_retrieval_system/retrieval/token_filter/stop_word_policy.dart';
import 'package:local_retrieval_system/retrieval/vector_store/chroma_vector_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ===========================================================================
  // Configuration
  // ===========================================================================

  const int benchmarkSize = 100;

  const String nqDatasetPath =
      '../curated_datasets/Natural_Questions/nq_val_500.json';

  late TFLiteModelManager modelManager;
  late EmbeddingEngine embeddingEngine;

  late StopWordPolicy stopWordPolicy;
  late KeywordIndex keywordIndex;

  late ChromaVectorStore vectorStore;

  late VectorRetriever vectorRetriever;
  late KeywordRetriever keywordRetriever;

  setUpAll(() async {
    // =========================================================================
    // Embedding layer
    // =========================================================================

    HttpOverrides.global = null;
    modelManager = TFLiteModelManager.instance;

    await modelManager.initialize();
    await ClipTokenizer.instance.initialize();
    await BertTokenizer.instance.initialize();

    embeddingEngine = EmbeddingEngine();

    // =========================================================================
    // Stop word / keyword layer
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
    // Vector Store
    // =========================================================================

    vectorStore = ChromaVectorStore(
      bertCollectionName:
      'weight_tuning_bert_embeddings',
      mobileClipCollectionName:
      'weight_tuning_mobileclip_embeddings',
    );

    await vectorStore.initialize();

    await vectorStore.clear(
      VectorEmbeddingType.bert,
    );

    keywordIndex.clear();

    // =========================================================================
    // Retrievers
    // =========================================================================

    vectorRetriever = VectorRetriever(
      embeddingEngine: embeddingEngine,
      vectorStore: vectorStore,
    );

    keywordRetriever = KeywordRetriever(
      keywordIndex: keywordIndex,
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
      await vectorStore.dispose();
    } catch (_) {}

    try {
      modelManager.dispose();
    } catch (_) {}
  });

  test(
    'Tune hybrid vector and keyword weights on NQ',
        () async {
      // =======================================================================
      // 1. Load dataset
      // =======================================================================

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
          benchmarkSize,
        ),
      );

      final List<_NqItem> items =
      raw
          .take(benchmarkSize)
          .map(
            (dynamic item) {
          final Map<String, dynamic> map =
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
        'HYBRID WEIGHT TUNING - NQ',
      );
      print(
        '============================================================',
      );
      print(
        'Samples: ${items.length}',
      );

      // =======================================================================
      // 2. Build corpus ONCE
      // =======================================================================

      await vectorStore.clear(
        VectorEmbeddingType.bert,
      );

      keywordIndex.clear();

      print('');
      print(
        'Building benchmark corpus once...',
      );

      final Stopwatch indexingWatch =
      Stopwatch()..start();

      final List<VectorDocument> vectorDocuments =
      <VectorDocument>[];

      final List<KeywordIndexedDocument>
      keywordDocuments =
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

        final Map<String, dynamic> metadata =
        <String, dynamic>{
          'data_type': 'text',
          'dataset': 'nq',
          'answer_index': i,
        };

        vectorDocuments.add(
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
            metadata,
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
            metadata,
          ),
        );

        if ((i + 1) % 10 == 0) {
          print(
            'Indexed embeddings: '
                '${i + 1}/${items.length}',
          );
        }
      }

      await vectorStore.addDocuments(
        vectorDocuments,
      );

      await keywordIndex.addDocuments(
        keywordDocuments,
      );

      indexingWatch.stop();

      print(
        'Corpus indexing time: '
            '${(indexingWatch.elapsedMicroseconds / 1000.0).toStringAsFixed(2)} ms',
      );

      // =======================================================================
      // 3. Weight configurations
      // =======================================================================

      const List<_WeightConfig> weightConfigs =
      <_WeightConfig>[
        _WeightConfig(
          vectorWeight: 0.7,
          keywordWeight: 0.3,
        ),
        _WeightConfig(
          vectorWeight: 0.5,
          keywordWeight: 0.5,
        ),
        _WeightConfig(
          vectorWeight: 0.4,
          keywordWeight: 0.6,
        ),
        _WeightConfig(
          vectorWeight: 0.3,
          keywordWeight: 0.7,
        ),
        _WeightConfig(
          vectorWeight: 0.2,
          keywordWeight: 0.8,
        ),
        _WeightConfig(
          vectorWeight: 0.1,
          keywordWeight: 0.9,
        ),
      ];

      final List<_WeightBenchmarkResult>
      benchmarkResults =
      <_WeightBenchmarkResult>[];

      // =======================================================================
      // 4. Run each weight configuration
      // =======================================================================

      for (final _WeightConfig config
      in weightConfigs) {
        print('');
        print(
          '------------------------------------------------------------',
        );
        print(
          'Testing vector=${config.vectorWeight.toStringAsFixed(1)} '
              'keyword=${config.keywordWeight.toStringAsFixed(1)}',
        );

        final HybridRetriever hybridRetriever =
        HybridRetriever(
          vectorRetriever:
          vectorRetriever,
          keywordRetriever:
          keywordRetriever,
          vectorWeight:
          config.vectorWeight,
          keywordWeight:
          config.keywordWeight,
          candidateMultiplier: 5,
        );

        final _BenchmarkAccumulator metrics =
        _BenchmarkAccumulator();

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
            topK: 10,
          );

          watch.stop();

          metrics.add(
            expectedId:
            'nq_answer_$i',
            rankedIds:
            results
                .map(
                  (result) =>
              result.id,
            )
                .toList(
              growable: false,
            ),
            latency:
            watch.elapsed,
          );
        }

        benchmarkResults.add(
          _WeightBenchmarkResult(
            config: config,
            metrics: metrics,
          ),
        );

        _printSingleResult(
          config,
          metrics,
        );
      }

      // =======================================================================
      // 5. Sort by MRR
      // =======================================================================

      benchmarkResults.sort(
            (
            _WeightBenchmarkResult a,
            _WeightBenchmarkResult b,
            ) =>
            b.metrics.mrr.compareTo(
              a.metrics.mrr,
            ),
      );

      // =======================================================================
      // 6. Final comparison table
      // =======================================================================

      print('');
      print(
        '============================================================',
      );
      print(
        'HYBRID WEIGHT TUNING RESULTS',
      );
      print(
        '============================================================',
      );

      print(
        'Vector | Keyword | R@1    | R@5    | R@10   | MRR    | Latency',
      );

      print(
        '------------------------------------------------------------',
      );

      for (final _WeightBenchmarkResult result
      in benchmarkResults) {
        final _WeightConfig config =
            result.config;

        final _BenchmarkAccumulator metrics =
            result.metrics;

        print(
          '${config.vectorWeight.toStringAsFixed(1).padRight(6)} '
              '| '
              '${config.keywordWeight.toStringAsFixed(1).padRight(7)} '
              '| '
              '${metrics.recallAt1.toStringAsFixed(3).padRight(6)} '
              '| '
              '${metrics.recallAt5.toStringAsFixed(3).padRight(6)} '
              '| '
              '${metrics.recallAt10.toStringAsFixed(3).padRight(6)} '
              '| '
              '${metrics.mrr.toStringAsFixed(3).padRight(6)} '
              '| '
              '${metrics.averageLatencyMs.toStringAsFixed(2)} ms',
        );
      }

      // =======================================================================
      // 7. Best configuration
      // =======================================================================

      final _WeightBenchmarkResult best =
          benchmarkResults.first;

      print('');
      print(
        '============================================================',
      );
      print(
        'BEST CONFIGURATION BY MRR',
      );
      print(
        '============================================================',
      );

      print(
        'Vector weight : '
            '${best.config.vectorWeight}',
      );

      print(
        'Keyword weight: '
            '${best.config.keywordWeight}',
      );

      print(
        'Recall@1      : '
            '${best.metrics.recallAt1.toStringAsFixed(4)}',
      );

      print(
        'Recall@5      : '
            '${best.metrics.recallAt5.toStringAsFixed(4)}',
      );

      print(
        'Recall@10     : '
            '${best.metrics.recallAt10.toStringAsFixed(4)}',
      );

      print(
        'MRR           : '
            '${best.metrics.mrr.toStringAsFixed(4)}',
      );

      print(
        'Avg latency   : '
            '${best.metrics.averageLatencyMs.toStringAsFixed(2)} ms/query',
      );

      print(
        '============================================================',
      );

      // =======================================================================
      // 8. Basic validation
      // =======================================================================

      expect(
        benchmarkResults.length,
        equals(
          weightConfigs.length,
        ),
      );

      for (final _WeightBenchmarkResult result
      in benchmarkResults) {
        _validateBenchmark(
          result.metrics,
        );
      }
    },
    timeout: const Timeout(
      Duration(minutes: 45),
    ),
  );
}

// =============================================================================
// NQ Item
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
// Weight configuration
// =============================================================================

class _WeightConfig {
  const _WeightConfig({
    required this.vectorWeight,
    required this.keywordWeight,
  });

  final double vectorWeight;

  final double keywordWeight;
}

// =============================================================================
// Weight benchmark result
// =============================================================================

class _WeightBenchmarkResult {
  const _WeightBenchmarkResult({
    required this.config,
    required this.metrics,
  });

  final _WeightConfig config;

  final _BenchmarkAccumulator metrics;
}

// =============================================================================
// Metrics
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
    rankedIds.indexOf(
      expectedId,
    );

    if (index < 0) {
      return;
    }

    final int rank =
        index + 1;

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
// Print one configuration
// =============================================================================

void _printSingleResult(
    _WeightConfig config,
    _BenchmarkAccumulator metrics,
    ) {
  print(
    'Vector weight : '
        '${config.vectorWeight}',
  );

  print(
    'Keyword weight: '
        '${config.keywordWeight}',
  );

  print(
    'Recall@1      : '
        '${metrics.recallAt1.toStringAsFixed(4)}',
  );

  print(
    'Recall@5      : '
        '${metrics.recallAt5.toStringAsFixed(4)}',
  );

  print(
    'Recall@10     : '
        '${metrics.recallAt10.toStringAsFixed(4)}',
  );

  print(
    'MRR           : '
        '${metrics.mrr.toStringAsFixed(4)}',
  );

  print(
    'Avg latency   : '
        '${metrics.averageLatencyMs.toStringAsFixed(2)} ms/query',
  );
}

// =============================================================================
// Validation
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
    inInclusiveRange(
      0.0,
      1.0,
    ),
  );

  expect(
    metrics.recallAt5,
    inInclusiveRange(
      0.0,
      1.0,
    ),
  );

  expect(
    metrics.recallAt10,
    inInclusiveRange(
      0.0,
      1.0,
    ),
  );

  expect(
    metrics.mrr,
    inInclusiveRange(
      0.0,
      1.0,
    ),
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
    greaterThanOrEqualTo(
      0.0,
    ),
  );
}