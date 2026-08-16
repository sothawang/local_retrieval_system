import 'dart:typed_data';

// Batch 输出结果
class EmbeddingResult {
  final String taskId;
  final bool isSuccess;
  final Float32List? vector;
  final String? errorCode;

  const EmbeddingResult({
    required this.taskId,
    required this.isSuccess,
    this.vector,
    this.errorCode,
  });

  factory EmbeddingResult.success({
    required String taskId,
    required Float32List vector,
  }){
    return EmbeddingResult(
        taskId: taskId,
        isSuccess: true,
        vector: vector,
        errorCode: null,
    );
  }

  factory EmbeddingResult.failure({
    required String taskId,
    required String errorCode,
  }){
    return EmbeddingResult(
        taskId: taskId,
        isSuccess: false,
        vector: null,
        errorCode: errorCode,
    );
  }
}