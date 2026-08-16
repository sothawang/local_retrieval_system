import 'dart:typed_data';

import 'embedding_engine.dart';
import 'models/embedding_result.dart';
import 'models/embedding_task.dart';

// 定义三个公开接口
abstract interface class EmbeddingEngineInterface {
  /// 生成文本向量，可通过 [mode] 指定编码方式。
  ///
  /// - [TextEmbeddingMode.bert]（默认）：768维，用于文本-文本检索。
  /// - [TextEmbeddingMode.mobileClip]：512维，与 [generateImageEmbedding]
  ///   共享同一语义空间，用于图文匹配检索。
  Future<Float32List> generateTextEmbeddingWithMode(
      String text, {
        TextEmbeddingMode mode = TextEmbeddingMode.bert,
      });

  /// 生成图片向量（512维，MobileCLIP空间）。
  Future<Float32List> generateImageEmbedding(Uint8List imageBytes);

  /// 批量生成文本/图片向量。单个任务失败不影响其他任务。
  /// 文本任务的编码模式由 [EmbeddingTask.textMode] 决定。
  Future<List<EmbeddingResult>> generateBatchEmbeddings(
      List<EmbeddingTask> tasks,
      );
}