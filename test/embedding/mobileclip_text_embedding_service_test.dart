import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/services/mobileclip_text_embedding_service.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MobileClipTextEmbeddingService service;

  setUpAll(() async {
    // Initialize TFLite models.
    await TFLiteModelManager.instance.initialize();

    // Initialize OpenCLIP tokenizer.
    await ClipTokenizer.instance.initialize();

    service = MobileClipTextEmbeddingService();
  });

  tearDownAll(() async {
     TFLiteModelManager.instance.dispose();
  });

  group('MobileClipTextEmbeddingService', () {
    test(
      'Generate MobileCLIP text embedding successfully',
          () async {
        final embedding =
        await service.generateTextEmbedding(
          'a photo of a cat',
        );

        expect(
          embedding.length,
          equals(EmbeddingConstants.clipEmbeddingSize),
        );

        expect(
          embedding.any((value) => value.isNaN),
          isFalse,
        );

        expect(
          embedding.any((value) => !value.isFinite),
          isFalse,
        );

        expect(
          embedding.any((value) => value != 0.0),
          isTrue,
        );

        print('');
        print('========================================');
        print('MOBILECLIP TEXT EMBEDDING');
        print('========================================');
        print('Input text      : a photo of a cat');
        print('Embedding length: ${embedding.length}');
        print(
          'First 10 values : '
              '${embedding.take(10).toList()}',
        );
        print('========================================');
      },
    );

    test(
      'Embedding dimension is exactly 512',
          () async {
        final embedding =
        await service.generateTextEmbedding(
          'A black Honda motorcycle parked in front of a garage.',
        );

        expect(
          embedding.length,
          equals(512),
        );
      },
    );

    test(
      'Embedding does not contain NaN',
          () async {
        final embedding =
        await service.generateTextEmbedding(
          'Two women waiting at a bench next to a street.',
        );

        for (int i = 0; i < embedding.length; i++) {
          expect(
            embedding[i].isNaN,
            isFalse,
            reason:
            'NaN detected at embedding index $i.',
          );
        }
      },
    );

    test(
      'Embedding does not contain Infinity',
          () async {
        final embedding =
        await service.generateTextEmbedding(
          'A cat eating a bird it has caught.',
        );

        for (int i = 0; i < embedding.length; i++) {
          expect(
            embedding[i].isFinite,
            isTrue,
            reason:
            'Infinity detected at embedding index $i.',
          );
        }
      },
    );

    test(
      'Embedding is not a zero vector',
          () async {
        final embedding =
        await service.generateTextEmbedding(
          'An airplane flying through the sky.',
        );

        final bool containsNonZeroValue =
        embedding.any(
              (value) => value.abs() > 1e-8,
        );

        expect(
          containsNonZeroValue,
          isTrue,
        );
      },
    );

    test(
      'Embedding is L2 normalized',
          () async {
        final embedding =
        await service.generateTextEmbedding(
          'a photo of a dog',
        );

        double squaredNorm = 0.0;

        for (final value in embedding) {
          squaredNorm += value * value;
        }

        final double norm =
        math.sqrt(squaredNorm);

        print('');
        print('MobileCLIP text embedding norm: $norm');

        expect(
          norm,
          closeTo(1.0, 1e-4),
        );
      },
    );

    test(
      'Same text produces deterministic embedding',
          () async {
        const String text =
            'a photo of a cat';

        final first =
        await service.generateTextEmbedding(
          text,
        );

        final second =
        await service.generateTextEmbedding(
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
            'Embedding differs at index $i.',
          );
        }
      },
    );

    test(
      'Different texts produce different embeddings',
          () async {
        final catEmbedding =
        await service.generateTextEmbedding(
          'a photo of a cat',
        );

        final airplaneEmbedding =
        await service.generateTextEmbedding(
          'a photo of an airplane',
        );

        double difference = 0.0;

        for (int i = 0;
        i < catEmbedding.length;
        i++) {
          difference +=
              (catEmbedding[i] -
                  airplaneEmbedding[i])
                  .abs();
        }

        expect(
          difference,
          greaterThan(1e-5),
        );
      },
    );
  });
}