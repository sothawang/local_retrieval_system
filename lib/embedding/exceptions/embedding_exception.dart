// 定义 ERR_MODEL_NOT_READY、ERR_TXT_EMBED_TIMEOUT 等错误
class EmbeddingErrorCode {
  // 请不要尝试创建这个类的对象，它不是用来实例化的。请直接使用它的静态成员
  const EmbeddingErrorCode._();

  // Common
  static const String modelNotReady = 'ERR_MODEL_NOT_READY';

  // text
  static const String textEmbeddingTimeout = 'ERR_TXT_EMBED_TIMEOUT';

  // Image
  static const String imageEmbeddingTimeout = 'ERR_IMG_EMBED_TIMEOUT';

  // Tokenizer
  static const String tokenizerNotInitialized = 'ERR_TOKENIZER_NOT_INITIALIZED';
  static const String vocabularyLoadFailed = 'ERR_VOCABULARY_LOAD_FAILED';
  static const String invalidInput = 'ERR_INVALID_INPUT';
  static const String inferenceFailed = 'ERR_INFERENCE_FAILED';
}

class EmbeddingException implements Exception{
  final String code;
  final String message;
  const EmbeddingException({
    required this.code,
    required this.message,
  });

  @override
  String toString(){
    return 'EmbeddingException(code: $code, message: $message)';
  }
}