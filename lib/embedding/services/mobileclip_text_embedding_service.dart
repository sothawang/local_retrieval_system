import 'dart:typed_data';

import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:local_retrieval_system/embedding/exceptions/embedding_exception.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';
import 'package:local_retrieval_system/embedding/tokenizer/clip_tokenizer.dart';

/// Generates text embeddings in the MobileCLIP shared embedding space.
///
/// Pipeline:
///
/// String
///   -> OpenCLIP-compatible ClipTokenizer
///   -> input_ids [1, 77] int32
///   -> MobileCLIP text encoder
///   -> embedding [1, 512] float32
///
/// The returned embedding can be compared directly with embeddings generated
/// by the matching MobileCLIP image encoder.
class MobileClipTextEmbeddingService {
  MobileClipTextEmbeddingService({
    TFLiteModelManager? modelManager,
    ClipTokenizer? tokenizer,
  })  : _modelManager =
      modelManager ?? TFLiteModelManager.instance,
        _tokenizer = tokenizer ?? ClipTokenizer.instance;

  final TFLiteModelManager _modelManager;
  final ClipTokenizer _tokenizer;

  /// Generates a 512-dimensional MobileCLIP text embedding.
  Future<Float32List> generateTextEmbedding(
      String text,
      ) async {
    if (!_modelManager.isMobileClipTextReady) {
      throw const EmbeddingException(
        code: EmbeddingErrorCode.modelNotReady,
        message:
        'MobileCLIP text model is not initialized.',
      );
    }

    if (!_tokenizer.isInitialized) {
      throw const EmbeddingException(
        code: EmbeddingErrorCode.tokenizerNotInitialized,
        message:
        'ClipTokenizer is not initialized.',
      );
    }

    try {
      // TFLite input shape:
      // [1, 77]
      final List<List<int>> input = _tokenizer.encodeForInterpreter(
        text,
        maxSequenceLength: EmbeddingConstants.mobileClipMaxSequence,
      );

      // TFLite output shape:
      // [1, 512]
      final List<List<double>> output =
      List<List<double>>.generate(
        1,
            (_) => List<double>.filled(
          EmbeddingConstants.clipEmbeddingSize,
          0.0,
        ),
        growable: false,
      );

      final interpreter = _modelManager.mobileClipTextInterpreter;

      interpreter.run(
        input,
        output,
      );

      final List<double> rawEmbedding = output.first;
      // 防御性检查，万一模型输出形状不对（比如换了个模型文件但常量没改），立刻报错而不是让错误数据继续往下传
      if (rawEmbedding.length !=
          EmbeddingConstants.clipEmbeddingSize) {
        throw EmbeddingException(
          code: EmbeddingErrorCode.inferenceFailed,
          message:
          'Unexpected MobileCLIP text embedding length: '
              '${rawEmbedding.length}. Expected '
              '${EmbeddingConstants.clipEmbeddingSize}.',
        );
      }
      // 从普通 List<double> 转成定长的 Float32List，更节省内存、也是很多下游向量数据库/相似度计算库期望的格式
      final Float32List embedding = Float32List.fromList(rawEmbedding);
      _validateEmbedding(embedding);

      return _l2Normalize(embedding);
    } on EmbeddingException {
      rethrow;
    } catch (e) {
      throw EmbeddingException(
        code: EmbeddingErrorCode.inferenceFailed,
        message:
        'MobileCLIP text inference failed: $e',
      );
    }
  }

  // 神经网络推理有个常见的"隐性故障模式"：不崩溃，但输出 NaN（非数字）或 Infinity（无穷大）。
  // 这种情况常见于：
  // 1. 模型权重加载出错但没报错
  // 2. 数值计算中出现了除以0之类的异常
  // 3. TFLite 底层/硬件加速库有兼容性问题
  // 如果不做这个检查，一个包含 NaN 的向量会悄无声息地混进你的向量数据库，
  // 后续做相似度检索时这条数据会永远匹配不上任何东西（NaN 和任何数比较都是 false），排查起来会非常痛苦。
  void _validateEmbedding(
      Float32List embedding,
      ) {
    for (int i = 0; i < embedding.length; i++) {
      final double value = embedding[i];
      // 一个包含 NaN 或 Infinity 的 embedding 向量会导致
      // 余弦相似度计算结果为 NaN → 检索排序完全失效
      // 存入 Chroma DB 后污染索引 → 后续所有查询都可能返回错误结果
      // 静默失败：用户看不到报错，只是搜索结果"不对劲"，极难排查
      // !value.isFinite: 值是否不是有限数（即 ±Infinity 或 NaN）
      if (value.isNaN || !value.isFinite) {
        throw EmbeddingException(
          code: EmbeddingErrorCode.inferenceFailed,
          message:
          'Invalid MobileCLIP text embedding value '
              'at index $i: $value.',
        );
      }
    }
  }

  /// Applies L2 normalization so cosine similarity can be calculated
  /// efficiently using a dot product.
  // L2归一化：把一个向量除以它自己的"长度"（L2范数），让结果变成一个长度恰好为1的向量（方向不变，只改变"长度"）。
  // CLIP 这类模型做"文本-图像匹配"，衡量两个向量"像不像"通常用余弦相似度
  // cosine_similarity(A, B) = (A · B) / (|A| × |B|)
  // 如果提前把所有向量都归一化成"长度=1"（也就是 |A|=1, |B|=1）
  // cosine_similarity(A, B) = A · B   （直接点积，不用再除）
  Float32List _l2Normalize(
      Float32List embedding,
      ) {
    double squaredNorm = 0.0;

    for (final double value in embedding) {
      squaredNorm += value * value;
    }
    // squaredNorm == 0.0 的检查是防止"零向量"（所有值都是0，说明模型彻底没算出任何有效信息）导致除以0出现 NaN
    if (squaredNorm == 0.0) {
      throw const EmbeddingException(
        code: EmbeddingErrorCode.inferenceFailed,
        message:
        'MobileCLIP text encoder returned a zero vector.',
      );
    }
    // 采用自定义的sqrt方法进行开平方计算
    final double norm = squaredNorm.sqrt();
    final Float32List normalized = Float32List(embedding.length);
    for (int i = 0; i < embedding.length; i++) {
      normalized[i] = embedding[i] / norm;
    }

    return normalized;
  }
}
// Dart 的扩展方法（Extension Methods） 语法，用于给现有类型添加新方法，而无需修改原始类型的源码或使用继承。
// 定义后，所有 double 值都可以直接调用 .sqrt()，就像它是内置方法一样
// 这是牛顿迭代法（Newton's method） 手写实现的开平方，而不是用 Dart 标准库 dart:math 里现成的 sqrt() 函数。
// 想求 this 的平方根，先随便猜一个初始值 estimate = this / 2，
// 然后不断用公式 estimate = (estimate + this/estimate) / 2 修正猜测值——每次迭代结果都会更接近真实的平方根，循环 20 次后精度已经足够高
extension on double {
  double sqrt() {
    if (this < 0) {
      throw StateError(
        'Cannot calculate square root of a negative value.',
      );
    }
    // this == 0 || this == 1 是特殊情况的快捷处理（0的平方根是0，1的平方根是1，不需要跑迭代浪费性能）
    if (this == 0 || this == 1) {
      return this;
    }
    double estimate = this / 2.0;
    for (int i = 0; i < 20; i++) {
      estimate =
          (estimate + this / estimate) / 2.0;
    }
    return estimate;
  }
}