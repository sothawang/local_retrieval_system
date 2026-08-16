import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_retrieval_system/embedding/tokenizer/bert_tokenizer.dart';
import 'package:local_retrieval_system/embedding/services/text_embedding_service.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TFLiteModelManager modelManager;
  late BertTokenizer tokenizer;
  late TextEmbeddingService textEmbeddingService;

  setUpAll(() async {
    modelManager = TFLiteModelManager.instance;

    await modelManager.initializeBert();

    tokenizer = BertTokenizer.instance;
    await tokenizer.initialize();

    textEmbeddingService = TextEmbeddingService(
      modelManager: modelManager,
    );
  });

  tearDownAll(() {
    modelManager.dispose();
  });

  group('TextEmbeddingService', () {
    test('Generate embedding from normal sentence', () async {
      const text =
          'This is a test sentence for BERT embedding generation.';

      final Float32List embedding =
      await textEmbeddingService.generateTextEmbedding(text);

      print('==============================');
      print('Embedding Length: ${embedding.length}');
      print('==============================');

      expect(embedding.length, 768);
    });

    test('Generate embedding from short sentence', () async {
      final embedding =
      await textEmbeddingService.generateTextEmbedding(
        'Hello World',
      );

      expect(embedding.length, 768);
    });

    test('Generate embedding from long paragraph', () async {
      final text = List.generate(
        300,
            (index) => 'word$index',
      ).join(' ');

      final embedding =
      await textEmbeddingService.generateTextEmbedding(
        text,
      );

      expect(embedding.length, 768);
    });

    test('Embedding should not contain NaN', () async {
      final embedding =
      await textEmbeddingService.generateTextEmbedding(
        'Artificial Intelligence',
      );

      for (final value in embedding) {
        expect(value.isNaN, false);
      }
    });

    test('Embedding should not contain Infinity', () async {
      final embedding =
      await textEmbeddingService.generateTextEmbedding(
        'Offline Accessible Multimodal Retrieval System',
      );

      for (final value in embedding) {
        expect(value.isInfinite, false);
      }
    });

    test('Embedding should be deterministic', () async {
      const text =
          'The quick brown fox jumps over the lazy dog.';

      final embedding1 =
      await textEmbeddingService.generateTextEmbedding(
        text,
      );

      final embedding2 =
      await textEmbeddingService.generateTextEmbedding(
        text,
      );

      expect(embedding1.length, embedding2.length);

      for (int i = 0; i < embedding1.length; i++) {
        expect(
          embedding1[i],
          closeTo(embedding2[i], 1e-6),
        );
      }
    });
  });
}