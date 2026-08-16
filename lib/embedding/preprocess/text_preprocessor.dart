import 'dart:typed_data';

import 'package:local_retrieval_system/embedding/tokenizer/bert_tokenizer.dart';
import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:local_retrieval_system/embedding/models/bert_input.dart';

// 文本 → BERT 三个输入数组
// 文本清洗、Token→ID、Padding、Attention Mask、Token Type
// TextPreprocessor
//
// Responsibilities:
// - Text cleaning
// - Tokenization
// - Convert Token -> IDs
// - Add [CLS] / [SEP]
// - Truncate to maxSequenceLength
// - Padding
// - Generate Attention Mask
// - Generate Token Type IDs

class TextPreprocessor {
  // _tokenizer = tokenizer是负责测试的时候用的，负责调用bert_tokenizer里的instance
  TextPreprocessor({
    BertTokenizer? tokenizer,
  }):_tokenizer = tokenizer ?? BertTokenizer.instance;

  final BertTokenizer _tokenizer;

  BertInput preprocess(String text, {
    int maxSequenceLength = EmbeddingConstants.maxSequence,
  }){
    final tokens = _tokenizer.tokenize(text);

    // 获取bert要求的输入格式
    final processedTokens = <String>[
      EmbeddingConstants.clsToken,
      // take方法可以把list里面的String内容单独分离出来
      // “...”操作符表示把take后拿出来的内容放入到外层数组中
      ...tokens.take(maxSequenceLength-2),
      EmbeddingConstants.sepToken,
    ];

    final attentionMask = Int32List(maxSequenceLength);
    final inputIds = Int32List(maxSequenceLength);
    final tokenTypeIds = Int32List(maxSequenceLength);

    final padId = _tokenizer.tokenToId(EmbeddingConstants.padToken);

    // Initialize with PAD
    for(int i = 0;i<maxSequenceLength;i++){
      inputIds[i] = padId;
      attentionMask[i] = 0;
      tokenTypeIds[i] = 0;
    }

    // Fill actual tokens
    for(int i = 0;i<processedTokens.length;i++){
      inputIds[i] = _tokenizer.tokenToId(processedTokens[i]);
      attentionMask[i] = 1;
      tokenTypeIds[i] = 0;
    }

    return BertInput(
        attentionMask: attentionMask,
        inputIds: inputIds,
        tokenTypeIds: tokenTypeIds,
    );
  }
  // 返回切分后的list，但不转换成bert要求的输入形式
  List<String> tokenize(String text){
    return _tokenizer.tokenize(text);
  }

  // 计算WordPiece后的tokens有多少个
  int tokenCount(String text){
    return _tokenizer.tokenize(text).length;
  }
}