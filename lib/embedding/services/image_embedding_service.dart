import 'dart:typed_data';

import 'package:local_retrieval_system/embedding/exceptions/embedding_exception.dart';
import 'package:local_retrieval_system/embedding/preprocess/image_preprocessor.dart';
import 'package:local_retrieval_system/embedding/model_manager.dart';

// 调用 MobileCLIP TFLite 推理
class ImageEmbeddingService{
  ImageEmbeddingService({
    TFLiteModelManager? modelManager,
    ImagePreprocessor? imagePreprocessor,
  })  : _modelManager = modelManager ?? TFLiteModelManager.instance,
        _imagePreprocessor = imagePreprocessor ?? ImagePreprocessor();

  final TFLiteModelManager _modelManager;
  final ImagePreprocessor _imagePreprocessor;

  /// Generate image embedding using MobileCLIP-TFLite.
  ///
  /// Input:
  /// [1,224,224,3] float32
  ///
  /// Output:
  /// Float32List(512)
  Future<Float32List> generateImageEmbedding(Uint8List imageBytes) async {
    if(!_modelManager.isMobileClipImageReady){
      throw const EmbeddingException(
        code: EmbeddingErrorCode.modelNotReady,
        message: 'MobileCLIP model is not initialized.',
      );
    }

    try{
      final input = await _imagePreprocessor.preprocess(imageBytes);
      final interpreter = _modelManager.mobileClipImageInterpreter;
      final output = List.generate(
          1,
          (_) => List<double>.filled(512, 0.0),
      );

      interpreter.run(input, output);
      return Float32List.fromList(
        List<double>.from(output.first)
      );
      // 如果异常是EmbeddingException类里的本来的异常，就直接抛出去，因为已经写好了相关信息了，避免把已知异常和未知异常混在一起。
    } on EmbeddingException {
      rethrow;
      // 如果这是一个未在EmbeddingException类中定义的异常，则重新打包抛出。
    } catch(e){
      throw EmbeddingException(
          code: EmbeddingErrorCode.inferenceFailed,
          message: e.toString(),
      );
    }
  }
}