import 'dart:typed_data';

import '../embedding_engine.dart';

// Batch 输入任务

enum EmbeddingDataType{
  text,
  image,
}

class EmbeddingTask {
  final String taskId;
  final EmbeddingDataType dataType;
  final String? textContent;
  final Uint8List? imageBytes;
  final TextEmbeddingMode textMode;

  // 如果使用这个构造函数创建对象的时候不小心写错了textContent或者imageBytes参数，而这个错误只有在runtime的时候才会报错，
  // 而无法在编写代码阶段就判断是否正确，因此在下面使用两个工厂函数方便创建对象
  // assert 只能在运行时（且仅限debug模式）才会报错拦截，没办法在写代码的阶段就靠"接口设计"直接杜绝这种错误的发生。
  const EmbeddingTask({
    required this.taskId,
    required this.dataType,
    this.textContent,
    this.imageBytes,
    this.textMode = TextEmbeddingMode.bert,
  }) : assert(
  (dataType == EmbeddingDataType.text && textContent != null) ||
      (dataType == EmbeddingDataType.image && imageBytes != null),
  'TEXT task requires textContent, IMAGE task requires imageBytes.',
  );

  // 工厂函数无法创建new instance,只能通过return一个对象来创建
  // 这里使用factory关键字的意义是相比于无factory关键字能够使代码更灵活，比如这里可以利用默认构造函数中的assert逻辑而不用在当前代码块中再写一个。
  // 这里默认用的文本模型是bert，可以自己加入一个TextEmbeddingMode.mobileClip替换
  factory EmbeddingTask.text({
    required String taskId,
    required String text,
    TextEmbeddingMode mode = TextEmbeddingMode.bert,
  }) {
    return EmbeddingTask(
      taskId: taskId,
      dataType: EmbeddingDataType.text,
      textContent: text,
      textMode: mode,
    );
  }

  factory EmbeddingTask.image({
    required String taskId,
    required Uint8List imageBytes,
  }) {
    return EmbeddingTask(
      taskId: taskId,
      dataType: EmbeddingDataType.image,
      imageBytes: imageBytes,
    );
  }
}