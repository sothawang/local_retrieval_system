import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/services/image_embedding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ImageEmbeddingService imageEmbeddingService;

  setUpAll(() async {
    await TFLiteModelManager.instance.initialize();
    imageEmbeddingService = ImageEmbeddingService();
  });

  tearDownAll(() async {
    TFLiteModelManager.instance.dispose();
  });

  group('ImageEmbeddingService', () {
    test('Generate embedding from image', () async {
      final Uint8List imageBytes =
      await File('test/test_resources/sample.png').readAsBytes();

      final embedding =
      await imageEmbeddingService.generateImageEmbedding(imageBytes);

      expect(embedding, isNotNull);
      expect(embedding.length, equals(512)); // MobileCLIP 输出维度
      expect(embedding.any((e) => e.isNaN), isFalse);
      expect(embedding.any((e) => !e.isFinite), isFalse);
      expect(embedding.any((e) => e != 0), isTrue);

      print('');
      print('========== IMAGE EMBEDDING ==========');
      print('Embedding length : ${embedding.length}');
      print('First 10 values :');
      for (int i = 0; i < 10; i++) {
        print('[$i] ${embedding[i]}');
      }
      print('=====================================');
    });

    test('Throws when image bytes are invalid', () async {
      final invalidBytes = Uint8List.fromList([1, 2, 3]);

      expect(
            () => imageEmbeddingService.generateImageEmbedding(invalidBytes),
        throwsA(isA<Exception>()),
      );
    });
  });
}