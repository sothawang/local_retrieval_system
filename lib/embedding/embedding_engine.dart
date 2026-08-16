import 'dart:typed_data';

import 'dart:math' as math;
import 'package:local_retrieval_system/embedding/embedding_engine_interface.dart';
import 'package:local_retrieval_system/embedding/exceptions/embedding_exception.dart';
import 'package:local_retrieval_system/embedding/inference/inference_queue.dart';
import 'package:local_retrieval_system/embedding/models/embedding_result.dart';
import 'package:local_retrieval_system/embedding/models/embedding_task.dart';
import 'package:local_retrieval_system/embedding/services/image_embedding_service.dart';
import 'package:local_retrieval_system/embedding/services/mobileclip_text_embedding_service.dart';
import 'package:local_retrieval_system/embedding/services/text_embedding_service.dart';

/// Text embedding mode.
///
/// [bert]
/// Used for:
/// - NQ validation
/// - text-to-text retrieval
/// - long-document semantic retrieval
///
/// [mobileClip]
/// Used for:
/// - text-to-image retrieval
/// - image-to-text retrieval
/// - semantic multimodal search
enum TextEmbeddingMode {
  bert,
  mobileClip,
}
/// Supports:
/// - BERT text embedding: 768 dimensions
/// - MobileCLIP text embedding: 512 dimensions
/// - MobileCLIP image embedding: 512 dimensions
/// - batch embedding
// 外部调用方（比如UI层、检索逻辑层）
//      ↓ 只需要认识 EmbeddingEngine 这一个类
// EmbeddingEngine（统一门面）
//      ↓ 内部协调
// TextEmbeddingService / ImageEmbeddingService（具体推理逻辑）
//      ↓ 都要经过
// InferenceQueue（并发限流）
//      ↓
// 真正的TFLite模型推理
// 实现三个接口，作为整个 Embedding Layer 的统一入口
class EmbeddingEngine implements EmbeddingEngineInterface{
  // 构造函数——依赖注入模式
  // 如果调用方不传，就用默认实现（TextEmbeddingService()、ImageEmbeddingService()、InferenceQueue.instance）
  // 如果调用方传了（比如写单元测试时传入mock对象），就用调用方传入的实例
  EmbeddingEngine({
    TextEmbeddingService? textEmbeddingService,
    MobileClipTextEmbeddingService? mobileClipTextEmbeddingService,
    ImageEmbeddingService? imageEmbeddingService,
    InferenceQueue? inferenceQueue,
  }) : _textEmbeddingService = textEmbeddingService ?? TextEmbeddingService(),
       _mobileClipTextEmbeddingService =
           mobileClipTextEmbeddingService ?? MobileClipTextEmbeddingService(),
       _imageEmbeddingService = imageEmbeddingService ?? ImageEmbeddingService(),
       _inferenceQueue = inferenceQueue ?? InferenceQueue.instance;

  final TextEmbeddingService _textEmbeddingService;
  final MobileClipTextEmbeddingService _mobileClipTextEmbeddingService;
  final ImageEmbeddingService _imageEmbeddingService;
  final InferenceQueue _inferenceQueue;

  // Default text embedding entry.
  // Keeps compatibility with the existing
  // EmbeddingEngineInterface.
  //
  // Default:
  // BERT -> 768 dimensions
  // 单条文本embedding
  // 注意这里没有写 async，因为方法体只有一行 return，直接把 _inferenceQueue.enqueue(...) 返回的 Future<Float32List> 原样传递出去，
  // 不需要额外用 async/await 包一层（这是一个常见的Dart简化写法：如果一个异步方法体内只是"直接返回另一个Future"，不需要对它做任何处理，
  // 就不必声明 async，直接返回那个Future即可）。
  Future<Float32List> generateTextEmbedding(String textChunk){
    // 因为如果直接调用 _textEmbeddingService.generateTextEmbedding(textChunk)，
    // 这个推理会立刻开始执行，完全绕过了 InferenceQueue 的并发限流逻辑。通过把调用包装成一个"还没执行的函数"再交给队列，
    // 队列才能控制"什么时候真正开始执行这个任务"，从而实现"最多同时2个"的限流效果。
    // 回看InferenceQueue class中的enqueue内容会发现这个函数要求一个Function作为参数，
    // Function也就是“还没执行的函数”，并且返回一个completer.future空头支票给上方调用层
    return generateTextEmbeddingWithMode(textChunk);
  }

  // Generate text embedding using a selected encoder.
  // BERT:
  //   String
  //     -> BERT
  //     -> Float32List(768)
  //
  // MobileCLIP:
  //   String
  //     -> ClipTokenizer
  //     -> MobileCLIP Text Encoder
  //     -> Float32List(512)
  @override
  Future<Float32List> generateTextEmbeddingWithMode(
        String text,{
        TextEmbeddingMode mode = TextEmbeddingMode.bert,
  }) {
    switch(mode){
      case TextEmbeddingMode.bert :
        return _inferenceQueue.enqueue(
            () => _textEmbeddingService.generateTextEmbedding(text),
        );
      case TextEmbeddingMode.mobileClip :
        return _inferenceQueue.enqueue(
            () => _mobileClipTextEmbeddingService.generateTextEmbedding(text),
        );
    }
  }

  /// Convenience API for multimodal text embedding.
  ///
  /// Always returns a 512-dimensional embedding in the
  /// same shared space as MobileCLIP image embeddings.
  Future<Float32List> generateMultimodalTextEmbedding(
      String text,
      ) {
    return generateTextEmbeddingWithMode(
      text,
      mode: TextEmbeddingMode.mobileClip,
    );
  }

  /// Generate image embedding using MobileCLIP image encoder.
  ///
  /// Output:
  /// Float32List(512)
  @override
  // 单张图片embedding
  Future<Float32List> generateImageEmbedding(Uint8List imageBytes){
    return _inferenceQueue.enqueue(
        () => _imageEmbeddingService.generateImageEmbedding(imageBytes),
    );
  }

  /// Batch API.
  ///
  /// Each text task independently selects its embedding mode via
  /// [EmbeddingTask.textMode] (defaults to BERT for backward
  /// compatibility). Pass [TextEmbeddingMode.mobileClip] when the
  /// resulting vector needs to be compared against image embeddings.
  ///
  /// Individual failures do not stop the whole batch.
  // 如果是其他任何未预期的异常（_ 表示不关心具体是什么异常对象，因为反正也不知道怎么细分处理），
  // 统一归类为 EmbeddingErrorCode.inferenceFailed，作为兜底分类。
  @override
  // 批量处理
  Future<List<EmbeddingResult>> generateBatchEmbeddings(
      List<EmbeddingTask> tasks,
      ) async {
    // 存放批量处理结果的容器
    final List<Future<EmbeddingResult>> futures = <Future<EmbeddingResult>>[];

    for(final EmbeddingTask task in tasks){
      futures.add(
        _processTask(task)
      );
    }
    return Future.wait(futures);
  }

  // 这个方法负责"一个任务"从"输入"到"结果"的完整生命周期，包括错误处理。
  Future<EmbeddingResult> _processTask(
      EmbeddingTask task,
      ) async {
    try{
      // switch 分支赋值这种模式，Dart 编译器有时无法100%静态确认"一定会被赋值"
      // （哪怕逻辑上开发者自己很清楚一定会），所以需要 late 来告诉编译器"相信我"；
      // 而 final 则是表达"这个值一旦确定就不该再变"的正确语义。
      late final Float32List embedding;
      switch(task.dataType){
        case EmbeddingDataType.text :
          embedding = await generateTextEmbeddingWithMode(
            task.textContent!,
            mode : task.textMode,
          );
          break;
        case EmbeddingDataType.image :
          embedding = await generateImageEmbedding(task.imageBytes!);
          break;
      }
      return EmbeddingResult.success(
          taskId: task.taskId,
          vector: embedding
      );
    } on EmbeddingException catch (e){
      return EmbeddingResult.failure(
        taskId: task.taskId,
        errorCode: e.code,
      );
    } catch (_){
      return EmbeddingResult.failure(
        taskId: task.taskId,
        errorCode: EmbeddingErrorCode.inferenceFailed,
      );
    }
  }

  /// Compare two vectors using cosine similarity.
  ///
  /// Useful for:
  /// - BERT text-to-text retrieval
  /// - MobileCLIP text-to-image retrieval
  /// - MobileCLIP image-to-text retrieval
  double cosineSimilarity(
      Float32List first,
      Float32List second,
      ) {
    if (first.length != second.length) {
      throw ArgumentError(
        'Embedding dimension mismatch: '
            '${first.length} vs ${second.length}.',
      );
    }

    double dotProduct = 0.0;
    double normFirst = 0.0;
    double normSecond = 0.0;
    // 三个累加值是用同一次循环算出来的，而不是分三次循环各算各的。
    // 这样只需要遍历一次数组，而不是三次——对于512维、甚至更高维的向量，
    // 且要做海量向量两两比对的检索场景，这种"一次遍历算多个统计量"的写法能明显减少循环开销。
    for (int i = 0; i < first.length; i++) {
      final double a = first[i];
      final double b = second[i];

      dotProduct += a * b; // 累加 A·B = Σ(a_i × b_i)
      normFirst += a * a; // 累加 |A|² = Σ(a_i²)
      normSecond += b * b; // 累加 |B|² = Σ(b_i²)
    }

    if (normFirst == 0.0 || normSecond == 0.0) {
      return 0.0;
    }
    return dotProduct /
        // |A| * |B|
        (math.sqrt(normFirst) * math.sqrt(normSecond));
  }

}