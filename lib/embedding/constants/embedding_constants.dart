// maxSequenceLength=128、模型路径、图片尺寸等常量
// 全局配置中心
class EmbeddingConstants {
  // 防止外部创建这个工具类的实例
  const EmbeddingConstants._();

  // =========================
  // BERT
  // =========================
  static const int maxSequence = 128;
  static const int bertEmbeddingSize = 768;

  static const String clsToken = '[CLS]';
  static const String sepToken = '[SEP]';
  static const String padToken = '[PAD]';
  static const String unkToken = '[UNK]';
  static const String bertModelPath = 'assets/bert_model/bert.tflite';
  static const String bertVocabPath = 'assets/bert_model/vocab.txt';

  // =========================
  // MobileCLIP
  // =========================
  static const String mobileClipImageModelPath = 'assets/mobileclip_model/mobileclip_image.tflite';
  static const int imageSize = 224;

  static const String mobileClipTextModelPath = 'assets/mobileclip_model/mobileclip_text.tflite';
  static const String mobileClipVocabPath = 'assets/mobileclip_model/bpe_simple_vocab_16e6.txt';
  static const int mobileClipMaxSequence = 77;
  static const int clipEmbeddingSize = 512;
  static const int clipVocabSize = 49408;
  static const int clipMergeCount = 48894;

  static const int clipPaddingTokenId = 0;
  static const int clipSotTokenId = 49406;
  static const int clipEotTokenId = 49407;

  static const String clipSotToken = '<start_of_text>';
  static const String clipEotToken = '<end_of_text>';

  // =========================
  // Inference
  // =========================
  static const int maxConcurrentInference = 2;
  static const Duration inferenceTimeout = Duration(seconds: 30);
}