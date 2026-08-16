import 'dart:typed_data';

import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:local_retrieval_system/embedding/exceptions/embedding_exception.dart';
import 'package:local_retrieval_system/embedding/models/bert_input.dart';
import 'package:local_retrieval_system/embedding/preprocess/text_preprocessor.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';

// 调用 BERT TFLite 推理
class TextEmbeddingService{
  TextEmbeddingService({
    TFLiteModelManager? modelManager,
    TextPreprocessor? textPreprocessor,
  }) : _modelManager = modelManager ?? TFLiteModelManager.instance,
       _textPreprocessor = textPreprocessor ?? TextPreprocessor();

  final TFLiteModelManager _modelManager;
  final TextPreprocessor _textPreprocessor;

  // Generate text embedding using BERT-TFLite.
  //
  // Returns:
  // Float32List(768)
  Future<Float32List> generateTextEmbedding(String textChunk) async{
    if(!_modelManager.isBertReady){
      // const的存在意义是，无论抛出多少次，内存中始终只有这一个异常对象
      // 避免了重复对象的创建和 GC 开销
      throw const EmbeddingException(
          code: EmbeddingErrorCode.modelNotReady,
          message: 'BERT model is not initialized.'
      );
    }

    try{
      final BertInput bertInput = _textPreprocessor.preprocess(textChunk);
      final inputs = bertInput.toInterpreterInputs();
      final interpreter = _modelManager.bertInterpreter;

      // Output0
      // 句子级别/Sentence 级别表示
      // 模型在最后一层的基础上，额外增加了一个浓缩层（Dense Layer），把整个句子的信息浓缩成了一个向量。
      // poolerOutput
      //   = [                          ← 外层：1个batch
      //      [0.0, 0.0, ..., 0.0]      ← 内层：768维的"整句话"向量
      //     ]
      final poolerOutput = List.generate(
          1,
          (_) => List<double>.filled(768, 0.0),
      );

      // Output1
      // 词级别/Token 级别表示
      // 模型最后一层输出的原始状态。它保留了文本中每一个词的向量。
      // last_hidden_state
      // 第 1 维（Batch Size = 1）：代表“一次喂给模型几段文本”。即使你现在只处理 1 句话，TFLite 引擎也要求必须有这个批次维度，这样它才能支持未来一次性处理 32 句或 64 句文本（并行计算）
      // 第 2 维（Sequence Length = 128）：代表“这段文本被切分成了几个词”
      // 第 3 维（Hidden Size = 768）：代表“每个词用多少个浮点数来表示它的语义”
      // lastHiddenState
      //   = [                                    ← 外层：1个batch
      //        [                                  ← 中层：128个token
      //          [0.0, 0.0, ..., 0.0],  (768个)   ← 内层：token 1 的向量
      //          [0.0, 0.0, ..., 0.0],  (768个)   ← 内层：token 2 的向量
      //          ...
      //          [0.0, 0.0, ..., 0.0],  (768个)   ← 内层：token 128 的向量
      //        ]
      //     ]
      final lastHiddenState = List.generate(
          1,
              (_) => List.generate(
            EmbeddingConstants.maxSequence,
                (_) => List<double>.filled(768, 0.0),
          )
      );

      // Output 2: 模型的第3个输出节点 [1, 768]（必须提供占位，防止 tflite_flutter 报 null 错误）
      final output2 = List.generate(
        1,
            (_) => List<double>.filled(768, 0.0),
      );

      // 一个容器，当bert通过内部的12个transformer矩阵计算完后得出的结果需要容器承载，这样写是因为这是bert的固定输出格式要求
      // 这里的0和1对应的是导出 .tflite 模型文件时，模型定义里输出节点的索引顺序：
      // output index 0  →  pooler_output       (句子级别输出) [1, 768]
      // output index 1  →  last_hidden_state   (词级别输出) [1, 128, 768]
      // Output index 2  →  形状 [1, 768] (StatefulPartitionedCall:2)
      final outputs = <int,Object>{
        0: poolerOutput,
        1: lastHiddenState,
        2: output2,
      };

      // 接收 Dart 格式的输入数据（你的 inputs）
      // 通过 Foreign Function Interface (FFI)，将这些数据传递给底层的 TensorFlow Lite C++ 库。
      // 调用 TFLite C++ 库中的 Interpreter::Invoke() 方法，执行模型计算。
      // 将计算结果写入你提供的 outputs 容器中。
      interpreter.runForMultipleInputs(inputs, outputs);

      // poolerOutput.first指的是poolerOutput的第一个元素（768维）
      // 对于List<double>来说，这里的list存储的是一个个double对象，每个double对象都存在"对象头“
      // 和指针开销，对象头指的是各种元数据以及标记用的数据，64位数据类型的指针开销位8字节。而typed data
      // 在内存中是连续的，不需要对象头以及指针开销，额外内存占用就比List<double>少很多。
      // 其次double对象在内存中的分布是分散的，而typed data在内存中是连续的，根据缓存机制，每一次访问内存时
      // 拿到的数据由于是连续的，命中率更高，不需要再去内存中去替换需要的data block，因此速度更快。
      return Float32List.fromList(
        // poolerOutput.first 等价于 poolerOutput[0]，作用是去掉最外层那个多余的batch维度，把二维数组 [1, 768] 降维成一维的 [768]
        // 这里只用poolerOutput也就是句子级别输出是因为这是一个本地检索系统，不需要逐词分析，只需要每句话大意便可以通过相似度进行检索
        List<double>.from(poolerOutput.first)
      );
    } on EmbeddingException{
      rethrow;
    } catch (e){
      throw EmbeddingException(
          code: EmbeddingErrorCode.inferenceFailed,
          message: e.toString(),
      );
    }
  }
}