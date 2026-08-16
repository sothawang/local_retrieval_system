import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

// 数组 → TFLite Interpreter
// BERT 三个输入 Tensor 的数据结构
// BERT 模型输入数据结构
// 这个文件夹里的任何处理方法都是针对BertInput这个类型的，通过职责分离来解耦
// 本质上是一个中间数据模型，如果某次想要知道中间的内容是否正确可以直接访问而不是通过结果反向得到中间值

// 如果以后你想把推理后端从 tflite_flutter 换成别的（比如 ONNX Runtime、或者调用云端 API），
// 你只需要改 BertInput 里的转换方法（或者新增一个 toOnnxInputs()），TextPreprocessor 完全不用动。
// 如果分词逻辑要改（比如换一个 tokenizer 实现），也不会影响 BertInput 的接口。

// 对应 TFLite 输入：
//
// attentionMask -> [1, maxSequenceLength]
// inputIds      -> [1, maxSequenceLength]
// tokenTypeIds  -> [1, maxSequenceLength]
class BertInput {
  // 因为tflite的embedding算子在要求输入的tensor的类型必须是Int32，词表对应的索引都是整数所以用Int32而不是Float32
  final Int32List attentionMask; // 1表示有效，0表示这里的inputIds对应的内容是没用的
  final Int32List inputIds; // 用户输入的内容在vocab.txt文件中对应的行数组成的List
  final Int32List tokenTypeIds; // 判断是第一个句子还是第二个句子

  // const是complier-time常量，final static是run-time常量
  const BertInput({
    required this.attentionMask,
    required this.inputIds,
    required this.tokenTypeIds,
  });
  // BERT 输入长度(128)
  int get sequenceLength => inputIds.length;

  // 转换为 TFLite Interpreter 所需输入格式
  // 这里需要转换格式的原因时tflite interpreter要求的输入格式就必须时[batch number, sequence]
  // 这里的有多少列取决于sequenceLength也就是设置的截断值
  // 这里最外围的中括号表示List，这是Dart语言独有特性
  // [
  //    [[1, 1, 1, 1, 0]],           // attentionMask
  //    [[101, 2023, 2003, 102, 0]],   // inputIds
  //    [[0, 0, 0, 0, 0]]            // tokenTypeIds
  // ]
  List<Object> toInterpreterInputs(){
    return <Object>[
      attentionMask.reshape([1, sequenceLength]),
      inputIds.reshape([1, sequenceLength]),
      tokenTypeIds.reshape([1, sequenceLength])
    ];
  }
}