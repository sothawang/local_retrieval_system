import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ClipTokenizer tokenizer;

  setUpAll(() async {
    tokenizer = ClipTokenizer.instance;
    await tokenizer.initialize();
  });

  group('ClipTokenizer', () {
    test('Tokenizer initializes successfully', () {
      expect(tokenizer.isInitialized, isTrue);

      expect(
        tokenizer.vocabSize,
        equals(EmbeddingConstants.clipVocabSize),
      );
    });

    test('Tokenizes "a photo of a cat" exactly like OpenCLIP', () {
      final Int32List tokenIds = tokenizer.encode(
        'a photo of a cat',
      );

      final List<int> expectedPrefix = <int>[
        49406,
        320,
        1125,
        539,
        320,
        2368,
        49407,
      ];

      expect(
        tokenIds.length,
        equals(EmbeddingConstants.mobileClipMaxSequence),
      );

      expect(
        tokenIds.sublist(0, expectedPrefix.length),
        equals(expectedPrefix),
      );

      for (int i = expectedPrefix.length;
      i < tokenIds.length;
      i++) {
        expect(
          tokenIds[i],
          equals(EmbeddingConstants.clipPaddingTokenId),
          reason: 'Expected padding token at index $i.',
        );
      }

      print('');
      print('========== CLIP TOKENIZER RESULT ==========');
      print('Input       : a photo of a cat');
      print('Token count : ${tokenIds.length}');
      print('Token IDs   : ${tokenIds.toList()}');
      print('===========================================');
    });

    test('Empty text produces SOT, EOT and padding', () {
      final Int32List tokenIds = tokenizer.encode('');

      expect(
        tokenIds.length,
        equals(EmbeddingConstants.mobileClipMaxSequence),
      );

      expect(
        tokenIds[0],
        equals(EmbeddingConstants.clipSotTokenId),
      );

      expect(
        tokenIds[1],
        equals(EmbeddingConstants.clipEotTokenId),
      );

      for (int i = 2; i < tokenIds.length; i++) {
        expect(
          tokenIds[i],
          equals(EmbeddingConstants.clipPaddingTokenId),
        );
      }
    });

    test('Whitespace-only text produces SOT, EOT and padding', () {
      final Int32List tokenIds = tokenizer.encode(
        '     \n\t   ',
      );

      expect(
        tokenIds[0],
        equals(EmbeddingConstants.clipSotTokenId),
      );

      expect(
        tokenIds[1],
        equals(EmbeddingConstants.clipEotTokenId),
      );

      expect(
        tokenIds.skip(2).every(
              (int id) =>
          id == EmbeddingConstants.clipPaddingTokenId,
        ),
        isTrue,
      );
    });

    test('Output always has context length 77', () {
      final Int32List tokenIds = tokenizer.encode(
        'A cat sitting on a table beside a window.',
      );

      expect(
        tokenIds.length,
        equals(77),
      );
    });

    test('Output begins with SOT and contains EOT', () {
      final Int32List tokenIds = tokenizer.encode(
        'A black Honda motorcycle parked in front of a garage.',
      );

      expect(
        tokenIds.first,
        equals(EmbeddingConstants.clipSotTokenId),
      );

      expect(
        tokenIds.contains(
          EmbeddingConstants.clipEotTokenId,
        ),
        isTrue,
      );

      final int eotIndex = tokenIds.indexOf(
        EmbeddingConstants.clipEotTokenId,
      );

      expect(eotIndex, greaterThan(0));

      expect(
        tokenIds
            .skip(eotIndex + 1)
            .every(
              (int id) =>
          id == EmbeddingConstants.clipPaddingTokenId,
        ),
        isTrue,
      );
    });

    test('encodeForInterpreter returns shape [1, 77]', () {
      final List<List<int>> input =
      tokenizer.encodeForInterpreter(
        'a photo of a cat',
      );

      expect(input.length, equals(1));

      expect(
        input.first.length,
        equals(EmbeddingConstants.mobileClipMaxSequence),
      );

      expect(
        input.first.first,
        equals(EmbeddingConstants.clipSotTokenId),
      );

      expect(
        input.first[6],
        equals(EmbeddingConstants.clipEotTokenId),
      );
    });

    test('Long text is truncated while preserving EOT', () {
      final String longText = List<String>.filled(
        200,
        'mobileclip',
      ).join(' ');

      final Int32List tokenIds = tokenizer.encode(longText);

      expect(
        tokenIds.length,
        equals(EmbeddingConstants.mobileClipMaxSequence),
      );

      expect(
        tokenIds.first,
        equals(EmbeddingConstants.clipSotTokenId),
      );

      expect(
        tokenIds.last,
        equals(EmbeddingConstants.clipEotTokenId),
      );

      expect(
        tokenIds.contains(
          EmbeddingConstants.clipEotTokenId,
        ),
        isTrue,
      );
    });

    test('Token IDs are within vocabulary range', () {
      final Int32List tokenIds = tokenizer.encode(
        'Two women waiting at a bench next to a street.',
      );

      for (final int tokenId in tokenIds) {
        expect(
          tokenId,
          inInclusiveRange(
            0,
            EmbeddingConstants.clipVocabSize - 1,
          ),
        );
      }
    });

    test('Tokenizer is deterministic', () {
      final Int32List first = tokenizer.encode(
        'A cat eating a bird it has caught.',
      );

      final Int32List second = tokenizer.encode(
        'A cat eating a bird it has caught.',
      );

      expect(
        first.toList(),
        equals(second.toList()),
      );
    });

    test('Tokenizer normalizes case and whitespace', () {
      final Int32List normal = tokenizer.encode(
        'a photo of a cat',
      );

      final Int32List normalized = tokenizer.encode(
        '   A   PHOTO   OF   A   CAT   ',
      );

      expect(
        normal.toList(),
        equals(normalized.toList()),
      );
    });

    test('Contractions and punctuation can be tokenized', () {
      final Int32List tokenIds = tokenizer.encode(
        "I'm testing CLIP's tokenizer, and it works!",
      );

      expect(
        tokenIds.length,
        equals(EmbeddingConstants.mobileClipMaxSequence),
      );

      expect(
        tokenIds.first,
        equals(EmbeddingConstants.clipSotTokenId),
      );

      expect(
        tokenIds.contains(
          EmbeddingConstants.clipEotTokenId,
        ),
        isTrue,
      );

      expect(
        tokenIds.any(
              (int id) =>
          id != EmbeddingConstants.clipPaddingTokenId,
        ),
        isTrue,
      );
    });
  });
}