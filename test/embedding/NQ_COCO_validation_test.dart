import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_retrieval_system/embedding/embedding_engine.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';
import 'package:local_retrieval_system/embedding/tokenizer/bert_tokenizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmbeddingEngine engine;

  // ===========================================================================
  // Dataset configuration
  // ===========================================================================

  const int nqEvaluationSize = 100;
  const int cocoEvaluationSize = 100;

  const String nqDatasetPath =
      '../curated_datasets/Natural_Questions/nq_val_500.json';

  const String cocoDatasetPath =
      '../curated_datasets/coco_curated_500/image_caption_pairs.json';

  const String cocoImageDirectory =
      '../curated_datasets/coco_curated_500/images';

  setUpAll(() async {
    // Initialize:
    // - BERT
    // - MobileCLIP Image Encoder
    // - MobileCLIP Text Encoder
    await TFLiteModelManager.instance.initialize();

    // MobileCLIP Text Encoder requires the OpenCLIP tokenizer.
    await ClipTokenizer.instance.initialize();
    await BertTokenizer.instance.initialize();

    engine = EmbeddingEngine();
  });

  tearDownAll(() async {
    TFLiteModelManager.instance.dispose();
  });

  group('Embedding Validation - NQ + COCO', () {
    // =========================================================================
    // NQ
    // =========================================================================
    //
    // Question:
    //      BERT
    //        ↓
    //      768D
    //
    // Answer:
    //      BERT
    //        ↓
    //      768D
    //
    // Then:
    //
    // question_i
    //      ↓
    // compare with all answer embeddings
    //      ↓
    // rank answers
    //      ↓
    // correct answer = answer_i
    //
    // Metrics:
    // - Recall@1
    // - Recall@5
    // - Recall@10
    // - MRR
    // =========================================================================

    test(
      'Natural Questions - BERT text retrieval evaluation',
          () async {
        final File nqFile = File(nqDatasetPath);

        expect(
          await nqFile.exists(),
          isTrue,
          reason:
          'NQ dataset does not exist at: $nqDatasetPath',
        );

        final String jsonString =
        await nqFile.readAsString();

        final dynamic decoded =
        jsonDecode(jsonString);

        expect(
          decoded,
          isA<List<dynamic>>(),
        );

        final List<dynamic> rawItems =
        decoded as List<dynamic>;

        expect(
          rawItems.length,
          greaterThanOrEqualTo(nqEvaluationSize),
        );

        final List<_NqItem> items =
        rawItems
            .take(nqEvaluationSize)
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
            .toList();

        print('');
        print(
          '============================================================',
        );
        print(
          'NQ BERT RETRIEVAL EVALUATION',
        );
        print(
          '============================================================',
        );
        print(
          'Dataset size: ${items.length}',
        );
        print(
          'Generating question embeddings...',
        );

        final List<Float32List> questionEmbeddings =
        <Float32List>[];

        for (int i = 0; i < items.length; i++) {
          final Float32List embedding =
          await engine
              .generateTextEmbeddingWithMode(
            items[i].question,
            mode: TextEmbeddingMode.bert,
          );

          expect(
            embedding.length,
            equals(768),
          );

          questionEmbeddings.add(embedding);

          if ((i + 1) % 10 == 0) {
            print(
              'Questions: ${i + 1}/${items.length}',
            );
          }
        }

        print('');
        print(
          'Generating answer embeddings...',
        );

        final List<Float32List> answerEmbeddings =
        <Float32List>[];

        for (int i = 0; i < items.length; i++) {
          final Float32List embedding =
          await engine
              .generateTextEmbeddingWithMode(
            items[i].answer,
            mode: TextEmbeddingMode.bert,
          );

          expect(
            embedding.length,
            equals(768),
          );

          answerEmbeddings.add(embedding);

          if ((i + 1) % 10 == 0) {
            print(
              'Answers: ${i + 1}/${items.length}',
            );
          }
        }

        int recallAt1Hits = 0;
        int recallAt5Hits = 0;
        int recallAt10Hits = 0;

        double reciprocalRankSum = 0.0;

        print('');
        print(
          'Calculating retrieval rankings...',
        );

        for (int queryIndex = 0;
        queryIndex < questionEmbeddings.length;
        queryIndex++) {
          final Float32List queryEmbedding =
          questionEmbeddings[queryIndex];

          final List<_SimilarityResult>
          similarities = <_SimilarityResult>[];

          for (int candidateIndex = 0;
          candidateIndex <
              answerEmbeddings.length;
          candidateIndex++) {
            final double similarity =
            engine.cosineSimilarity(
              queryEmbedding,
              answerEmbeddings[candidateIndex],
            );

            similarities.add(
              _SimilarityResult(
                index: candidateIndex,
                similarity: similarity,
              ),
            );
          }

          similarities.sort(
                (
                _SimilarityResult a,
                _SimilarityResult b,
                ) =>
                b.similarity.compareTo(
                  a.similarity,
                ),
          );

          final int rank =
              similarities.indexWhere(
                    (_SimilarityResult result) =>
                result.index ==
                    queryIndex,
              ) +
                  1;

          expect(
            rank,
            greaterThan(0),
          );

          if (rank <= 1) {
            recallAt1Hits++;
          }

          if (rank <= 5) {
            recallAt5Hits++;
          }

          if (rank <= 10) {
            recallAt10Hits++;
          }

          reciprocalRankSum += 1.0 / rank;
        }

        final double recallAt1 =
            recallAt1Hits / items.length;

        final double recallAt5 =
            recallAt5Hits / items.length;

        final double recallAt10 =
            recallAt10Hits / items.length;

        final double mrr =
            reciprocalRankSum / items.length;

        print('');
        print(
          '============================================================',
        );
        print(
          'NQ RESULTS',
        );
        print(
          '============================================================',
        );
        print(
          'Samples   : ${items.length}',
        );
        print(
          'Recall@1  : ${recallAt1.toStringAsFixed(4)} '
              '(${(recallAt1 * 100).toStringAsFixed(2)}%)',
        );
        print(
          'Recall@5  : ${recallAt5.toStringAsFixed(4)} '
              '(${(recallAt5 * 100).toStringAsFixed(2)}%)',
        );
        print(
          'Recall@10 : ${recallAt10.toStringAsFixed(4)} '
              '(${(recallAt10 * 100).toStringAsFixed(2)}%)',
        );
        print(
          'MRR       : ${mrr.toStringAsFixed(4)}',
        );
        print(
          '============================================================',
        );

        expect(
          recallAt1,
          inInclusiveRange(0.0, 1.0),
        );

        expect(
          recallAt5,
          inInclusiveRange(0.0, 1.0),
        );

        expect(
          recallAt10,
          inInclusiveRange(0.0, 1.0),
        );

        expect(
          mrr,
          inInclusiveRange(0.0, 1.0),
        );

        // Recall should be monotonically increasing.
        expect(
          recallAt5,
          greaterThanOrEqualTo(recallAt1),
        );

        expect(
          recallAt10,
          greaterThanOrEqualTo(recallAt5),
        );
      },
      timeout: const Timeout(
        Duration(minutes: 30),
      ),
    );

    // =========================================================================
    // COCO
    // =========================================================================
    //
    // Caption:
    //     ClipTokenizer
    //          ↓
    // MobileCLIP Text Encoder
    //          ↓
    //        512D
    //
    // Image:
    // MobileCLIP Image Encoder
    //          ↓
    //        512D
    //
    // BOTH encoders come from the same MobileCLIP model.
    //
    // Therefore:
    //
    // MobileCLIP Text 512D
    //           ↕
    //     cosine similarity
    //           ↕
    // MobileCLIP Image 512D
    //
    // Metrics:
    //
    // Text -> Image
    // - Recall@1
    // - Recall@5
    // - Recall@10
    // - MRR
    //
    // Image -> Text
    // - Recall@1
    // - Recall@5
    // - Recall@10
    // - MRR
    // =========================================================================

    test(
      'COCO - MobileCLIP multimodal retrieval evaluation',
          () async {
        final File pairsFile =
        File(cocoDatasetPath);

        expect(
          await pairsFile.exists(),
          isTrue,
          reason:
          'COCO caption mapping does not exist at: '
              '$cocoDatasetPath',
        );

        final String jsonString =
        await pairsFile.readAsString();

        final dynamic decoded =
        jsonDecode(jsonString);

        expect(
          decoded,
          isA<Map<String, dynamic>>(),
        );

        final Map<String, dynamic> rawPairs =
        decoded as Map<String, dynamic>;

        expect(
          rawPairs.length,
          greaterThanOrEqualTo(
            cocoEvaluationSize,
          ),
        );

        final List<_CocoItem> items =
        rawPairs.entries
            .take(cocoEvaluationSize)
            .map(
              (
              MapEntry<String, dynamic>
              entry,
              ) {
            return _CocoItem(
              imageFileName: entry.key,
              caption:
              entry.value as String,
            );
          },
        )
            .toList();

        print('');
        print(
          '============================================================',
        );
        print(
          'COCO MOBILECLIP MULTIMODAL EVALUATION',
        );
        print(
          '============================================================',
        );
        print(
          'Dataset size: ${items.length}',
        );

        // ---------------------------------------------------------------------
        // Generate text embeddings
        // ---------------------------------------------------------------------

        print('');
        print(
          'Generating MobileCLIP text embeddings...',
        );

        final List<Float32List> textEmbeddings =
        <Float32List>[];

        for (int i = 0; i < items.length; i++) {
          final Float32List embedding =
          await engine
              .generateTextEmbeddingWithMode(
            items[i].caption,
            mode: TextEmbeddingMode.mobileClip,
          );

          expect(
            embedding.length,
            equals(512),
          );

          expect(
            embedding.every(
                  (double value) =>
              value.isFinite,
            ),
            isTrue,
          );

          textEmbeddings.add(embedding);

          if ((i + 1) % 10 == 0) {
            print(
              'Text: ${i + 1}/${items.length}',
            );
          }
        }

        // ---------------------------------------------------------------------
        // Generate image embeddings
        // ---------------------------------------------------------------------

        print('');
        print(
          'Generating MobileCLIP image embeddings...',
        );

        final List<Float32List> imageEmbeddings =
        <Float32List>[];

        for (int i = 0; i < items.length; i++) {
          final String imagePath =
              '$cocoImageDirectory/'
              '${items[i].imageFileName}';

          final File imageFile =
          File(imagePath);

          expect(
            await imageFile.exists(),
            isTrue,
            reason:
            'COCO image does not exist: '
                '$imagePath',
          );

          final Uint8List imageBytes =
          await imageFile.readAsBytes();

          final Float32List embedding =
          await engine
              .generateImageEmbedding(
            imageBytes,
          );

          expect(
            embedding.length,
            equals(512),
          );

          expect(
            embedding.every(
                  (double value) =>
              value.isFinite,
            ),
            isTrue,
          );

          imageEmbeddings.add(embedding);

          if ((i + 1) % 10 == 0) {
            print(
              'Images: ${i + 1}/${items.length}',
            );
          }
        }

        expect(
          textEmbeddings.length,
          equals(imageEmbeddings.length),
        );

        // ---------------------------------------------------------------------
        // Text -> Image
        // ---------------------------------------------------------------------

        print('');
        print(
          'Evaluating Text -> Image retrieval...',
        );

        final _RetrievalMetrics textToImage =
        _evaluateRetrieval(
          queries: textEmbeddings,
          candidates: imageEmbeddings,
          engine: engine,
        );

        // ---------------------------------------------------------------------
        // Image -> Text
        // ---------------------------------------------------------------------

        print(
          'Evaluating Image -> Text retrieval...',
        );

        final _RetrievalMetrics imageToText =
        _evaluateRetrieval(
          queries: imageEmbeddings,
          candidates: textEmbeddings,
          engine: engine,
        );

        // ---------------------------------------------------------------------
        // Results
        // ---------------------------------------------------------------------

        print('');
        print(
          '============================================================',
        );
        print(
          'COCO RESULTS',
        );
        print(
          '============================================================',
        );

        print('');
        print(
          'TEXT -> IMAGE',
        );
        print(
          '------------------------------------------------------------',
        );
        _printMetrics(textToImage);

        print('');
        print(
          'IMAGE -> TEXT',
        );
        print(
          '------------------------------------------------------------',
        );
        _printMetrics(imageToText);

        print('');
        print(
          '============================================================',
        );

        _validateMetrics(textToImage);
        _validateMetrics(imageToText);
      },
      timeout: const Timeout(
        Duration(minutes: 30),
      ),
    );
  });
}

// =============================================================================
// NQ model
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
// COCO model
// =============================================================================

class _CocoItem {
  const _CocoItem({
    required this.imageFileName,
    required this.caption,
  });

  final String imageFileName;
  final String caption;
}

// =============================================================================
// Similarity result
// =============================================================================

class _SimilarityResult {
  const _SimilarityResult({
    required this.index,
    required this.similarity,
  });

  final int index;
  final double similarity;
}

// =============================================================================
// Retrieval metrics
// =============================================================================

class _RetrievalMetrics {
  const _RetrievalMetrics({
    required this.recallAt1,
    required this.recallAt5,
    required this.recallAt10,
    required this.mrr,
  });

  final double recallAt1;
  final double recallAt5;
  final double recallAt10;
  final double mrr;
}

// =============================================================================
// Generic retrieval evaluation
// =============================================================================
//
// Assumption:
//
// query[i]'s correct candidate is candidate[i].
//
// This matches the curated COCO dataset structure:
//
// image_0 <-> caption_0
// image_1 <-> caption_1
// ...
//
// For every query:
//
// 1. Compare against every candidate.
// 2. Sort by cosine similarity.
// 3. Find rank of the matching index.
// 4. Update Recall@K and reciprocal rank.
// =============================================================================

_RetrievalMetrics _evaluateRetrieval({
  required List<Float32List> queries,
  required List<Float32List> candidates,
  required EmbeddingEngine engine,
}) {
  if (queries.length != candidates.length) {
    throw ArgumentError(
      'Query/candidate size mismatch: '
          '${queries.length} vs ${candidates.length}.',
    );
  }

  int recallAt1Hits = 0;
  int recallAt5Hits = 0;
  int recallAt10Hits = 0;

  double reciprocalRankSum = 0.0;

  for (int queryIndex = 0;
  queryIndex < queries.length;
  queryIndex++) {
    final Float32List query =
    queries[queryIndex];

    final List<_SimilarityResult>
    similarities = <_SimilarityResult>[];

    for (int candidateIndex = 0;
    candidateIndex < candidates.length;
    candidateIndex++) {
      final double similarity =
      engine.cosineSimilarity(
        query,
        candidates[candidateIndex],
      );

      similarities.add(
        _SimilarityResult(
          index: candidateIndex,
          similarity: similarity,
        ),
      );
    }

    similarities.sort(
          (
          _SimilarityResult a,
          _SimilarityResult b,
          ) =>
          b.similarity.compareTo(
            a.similarity,
          ),
    );

    final int correctRank =
        similarities.indexWhere(
              (_SimilarityResult result) =>
          result.index ==
              queryIndex,
        ) +
            1;

    if (correctRank <= 0) {
      throw StateError(
        'Correct retrieval candidate '
            'was not found for query $queryIndex.',
      );
    }

    if (correctRank <= 1) {
      recallAt1Hits++;
    }

    if (correctRank <= 5) {
      recallAt5Hits++;
    }

    if (correctRank <= 10) {
      recallAt10Hits++;
    }

    reciprocalRankSum +=
        1.0 / correctRank;
  }

  final int count = queries.length;

  return _RetrievalMetrics(
    recallAt1:
    recallAt1Hits / count,
    recallAt5:
    recallAt5Hits / count,
    recallAt10:
    recallAt10Hits / count,
    mrr:
    reciprocalRankSum / count,
  );
}

// =============================================================================
// Print metrics
// =============================================================================

void _printMetrics(
    _RetrievalMetrics metrics,
    ) {
  print(
    'Recall@1  : '
        '${metrics.recallAt1.toStringAsFixed(4)} '
        '(${(metrics.recallAt1 * 100).toStringAsFixed(2)}%)',
  );

  print(
    'Recall@5  : '
        '${metrics.recallAt5.toStringAsFixed(4)} '
        '(${(metrics.recallAt5 * 100).toStringAsFixed(2)}%)',
  );

  print(
    'Recall@10 : '
        '${metrics.recallAt10.toStringAsFixed(4)} '
        '(${(metrics.recallAt10 * 100).toStringAsFixed(2)}%)',
  );

  print(
    'MRR       : '
        '${metrics.mrr.toStringAsFixed(4)}',
  );
}

// =============================================================================
// Validate metrics
// =============================================================================

void _validateMetrics(
    _RetrievalMetrics metrics,
    ) {
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
}