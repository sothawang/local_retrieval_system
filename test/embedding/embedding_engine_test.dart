import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:local_retrieval_system/embedding/embedding_engine.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/models/embedding_task.dart';
import 'package:local_retrieval_system/embedding/tokenizer/bert_tokenizer.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EmbeddingEngine engine;

  setUpAll(() async {
    // Initialize all TFLite interpreters:
    // - BERT
    // - MobileCLIP Image
    // - MobileCLIP Text
    await TFLiteModelManager.instance.initialize();

    // MobileCLIP text inference requires OpenCLIP tokenizer.
    await ClipTokenizer.instance.initialize();
    // BERT text inference requires its own WordPiece tokenizer + vocab.
    await BertTokenizer.instance.initialize();

    engine = EmbeddingEngine();
  });

  tearDownAll(() async {
    TFLiteModelManager.instance.dispose();
  });

  group('EmbeddingEngine Integration Test', () {
    // ------------------------------------------------------------------------
    // 1. BERT text embedding
    // ------------------------------------------------------------------------
    test(
      'Generate BERT text embedding with 768 dimensions',
          () async {
        final Float32List embedding =
        await engine.generateTextEmbeddingWithMode(
          'This is a test sentence for BERT.',
          mode: TextEmbeddingMode.bert,
        );

        expect(
          embedding.length,
          equals(EmbeddingConstants.bertEmbeddingSize),
        );

        expect(
          embedding.any((double value) => value.isNaN),
          isFalse,
        );

        expect(
          embedding.any((double value) => !value.isFinite),
          isFalse,
        );

        expect(
          embedding.any((double value) => value != 0.0),
          isTrue,
        );

        print('');
        print('==========================================');
        print('BERT TEXT EMBEDDING');
        print('==========================================');
        print('Dimension       : ${embedding.length}');
        print(
          'First 10 values : ${embedding.take(10).toList()}',
        );
        print('==========================================');
      },
    );

    // ------------------------------------------------------------------------
    // 2. Default text mode should still be BERT
    // ------------------------------------------------------------------------
    test(
      'Default text embedding mode is BERT',
          () async {
        final Float32List embedding =
        await engine.generateTextEmbeddingWithMode(
          'Default text embedding test.',
        );

        expect(
          embedding.length,
          equals(EmbeddingConstants.bertEmbeddingSize),
        );
      },
    );

    // ------------------------------------------------------------------------
    // 3. MobileCLIP text embedding
    // ------------------------------------------------------------------------
    test(
      'Generate MobileCLIP text embedding with 512 dimensions',
          () async {
        final Float32List embedding =
        await engine.generateTextEmbeddingWithMode(
          'a photo of a cat',
          mode: TextEmbeddingMode.mobileClip,
        );

        expect(
          embedding.length,
          equals(EmbeddingConstants.clipEmbeddingSize),
        );

        expect(
          embedding.any((double value) => value.isNaN),
          isFalse,
        );

        expect(
          embedding.any((double value) => !value.isFinite),
          isFalse,
        );

        expect(
          embedding.any((double value) => value != 0.0),
          isTrue,
        );

        print('');
        print('==========================================');
        print('MOBILECLIP TEXT EMBEDDING');
        print('==========================================');
        print('Dimension       : ${embedding.length}');
        print(
          'First 10 values : ${embedding.take(10).toList()}',
        );
        print('==========================================');
      },
    );

    // ------------------------------------------------------------------------
    // 4. Convenience multimodal text API
    // ------------------------------------------------------------------------
    test(
      'Generate multimodal text embedding',
          () async {
        final Float32List embedding =
        await engine.generateMultimodalTextEmbedding(
          'a motorcycle parked in front of a garage',
        );

        expect(
          embedding.length,
          equals(EmbeddingConstants.clipEmbeddingSize),
        );

        expect(
          embedding.every(
                (double value) => value.isFinite,
          ),
          isTrue,
        );
      },
    );

    // ------------------------------------------------------------------------
    // 5. MobileCLIP image embedding
    // ------------------------------------------------------------------------
    test(
      'Generate MobileCLIP image embedding with 512 dimensions',
          () async {
        final ByteData data =
        await rootBundle.load(
          'test/test_resources/sample.png',
        );

        final Uint8List imageBytes =
        data.buffer.asUint8List();

        final Float32List embedding =
        await engine.generateImageEmbedding(
          imageBytes,
        );

        expect(
          embedding.length,
          equals(EmbeddingConstants.clipEmbeddingSize),
        );

        expect(
          embedding.any((double value) => value.isNaN),
          isFalse,
        );

        expect(
          embedding.any((double value) => !value.isFinite),
          isFalse,
        );

        expect(
          embedding.any((double value) => value != 0.0),
          isTrue,
        );

        print('');
        print('==========================================');
        print('MOBILECLIP IMAGE EMBEDDING');
        print('==========================================');
        print('Dimension       : ${embedding.length}');
        print(
          'First 10 values : ${embedding.take(10).toList()}',
        );
        print('==========================================');
      },
    );

    // ------------------------------------------------------------------------
    // 6. MobileCLIP text and image share same dimensional space
    // ------------------------------------------------------------------------
    test(
      'MobileCLIP text and image embeddings have matching dimensions',
          () async {
        final ByteData data =
        await rootBundle.load(
          'test/test_resources/sample.png',
        );

        final Uint8List imageBytes =
        data.buffer.asUint8List();

        final Float32List textEmbedding =
        await engine.generateMultimodalTextEmbedding(
          'a photo describing the image',
        );

        final Float32List imageEmbedding =
        await engine.generateImageEmbedding(
          imageBytes,
        );

        expect(
          textEmbedding.length,
          equals(512),
        );

        expect(
          imageEmbedding.length,
          equals(512),
        );

        expect(
          textEmbedding.length,
          equals(imageEmbedding.length),
        );
      },
    );

    // ------------------------------------------------------------------------
    // 7. Cross-modal cosine similarity can be calculated
    // ------------------------------------------------------------------------
    test(
      'Calculate cosine similarity between MobileCLIP text and image',
          () async {
        final ByteData data =
        await rootBundle.load(
          'test/test_resources/sample.png',
        );

        final Uint8List imageBytes =
        data.buffer.asUint8List();

        final Float32List textEmbedding =
        await engine.generateMultimodalTextEmbedding(
          'a photo of an object',
        );

        final Float32List imageEmbedding =
        await engine.generateImageEmbedding(
          imageBytes,
        );

        final double similarity =
        engine.cosineSimilarity(
          textEmbedding,
          imageEmbedding,
        );

        expect(
          similarity.isFinite,
          isTrue,
        );

        expect(
          similarity.isNaN,
          isFalse,
        );

        // Cosine similarity should mathematically lie
        // between -1 and 1 (allow tiny floating-point tolerance).
        expect(
          similarity,
          inInclusiveRange(-1.0001, 1.0001),
        );

        print('');
        print('==========================================');
        print('MULTIMODAL COSINE SIMILARITY');
        print('==========================================');
        print('Similarity: $similarity');
        print('==========================================');
      },
    );

    // ------------------------------------------------------------------------
    // 8. BERT cannot be directly compared with MobileCLIP image embedding
    // ------------------------------------------------------------------------
    test(
      'Reject cosine similarity between BERT and MobileCLIP vectors',
          () async {
        final ByteData data =
        await rootBundle.load(
          'test/test_resources/sample.png',
        );

        final Uint8List imageBytes =
        data.buffer.asUint8List();

        final Float32List bertEmbedding =
        await engine.generateTextEmbeddingWithMode(
          'a photo of a cat',
          mode: TextEmbeddingMode.bert,
        );

        final Float32List imageEmbedding =
        await engine.generateImageEmbedding(
          imageBytes,
        );

        expect(
          bertEmbedding.length,
          equals(EmbeddingConstants.bertEmbeddingSize),
        );

        expect(
          imageEmbedding.length,
          equals(EmbeddingConstants.clipEmbeddingSize),
        );

        expect(
              () => engine.cosineSimilarity(
            bertEmbedding,
            imageEmbedding,
          ),
          throwsArgumentError,
        );
      },
    );

    // ------------------------------------------------------------------------
    // 9. Batch: BERT + MobileCLIP Text + Image
    // ------------------------------------------------------------------------
    test(
      'Generate mixed batch embeddings with independent text modes',
          () async {
        final ByteData data =
        await rootBundle.load(
          'test/test_resources/sample.png',
        );

        final Uint8List imageBytes =
        data.buffer.asUint8List();

        final List<EmbeddingTask> tasks =
        <EmbeddingTask>[
          EmbeddingTask.text(
            taskId: 'bert_text_1',
            text:
            'Natural language retrieval using BERT.',
            mode: TextEmbeddingMode.bert,
          ),
          EmbeddingTask.text(
            taskId: 'clip_text_1',
            text: 'a photo of a cat',
            mode: TextEmbeddingMode.mobileClip,
          ),
          EmbeddingTask.image(
            taskId: 'image_1',
            imageBytes: imageBytes,
          ),
        ];

        final results =
        await engine.generateBatchEmbeddings(
          tasks,
        );

        expect(
          results.length,
          equals(3),
        );

        // BERT
        expect(
          results[0].taskId,
          equals('bert_text_1'),
        );

        expect(
          results[0].isSuccess,
          isTrue,
        );

        expect(
          results[0].vector,
          isNotNull,
        );

        expect(
          results[0].vector!.length,
          equals(EmbeddingConstants.bertEmbeddingSize),
        );

        // MobileCLIP Text
        expect(
          results[1].taskId,
          equals('clip_text_1'),
        );

        expect(
          results[1].isSuccess,
          isTrue,
        );

        expect(
          results[1].vector,
          isNotNull,
        );

        expect(
          results[1].vector!.length,
          equals(EmbeddingConstants.clipEmbeddingSize),
        );

        // MobileCLIP Image
        expect(
          results[2].taskId,
          equals('image_1'),
        );

        expect(
          results[2].isSuccess,
          isTrue,
        );

        expect(
          results[2].vector,
          isNotNull,
        );

        expect(
          results[2].vector!.length,
          equals(EmbeddingConstants.clipEmbeddingSize),
        );

        print('');
        print('==========================================');
        print('MIXED BATCH RESULT');
        print('==========================================');

        for (final result in results) {
          print(
            '${result.taskId}: '
                'success=${result.isSuccess}, '
                'dimension=${result.vector?.length}',
          );
        }

        print('==========================================');
      },
    );

    // ------------------------------------------------------------------------
    // 10. Same MobileCLIP text produces deterministic result
    // ------------------------------------------------------------------------
    test(
      'MobileCLIP text embedding is deterministic through EmbeddingEngine',
          () async {
        const String text =
            'a photo of a cat';

        final Float32List first =
        await engine.generateMultimodalTextEmbedding(
          text,
        );

        final Float32List second =
        await engine.generateMultimodalTextEmbedding(
          text,
        );

        expect(
          first.length,
          equals(second.length),
        );

        for (int i = 0; i < first.length; i++) {
          expect(
            first[i],
            closeTo(second[i], 1e-6),
            reason:
            'Different value at embedding index $i.',
          );
        }
      },
    );
  });
}