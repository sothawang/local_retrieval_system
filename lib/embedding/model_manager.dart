import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// 管理 BERT、MobileCLIP 的 Interpreter 生命周期
class TFLiteModelManager{
  // 因为整个生命周期只需要一个ModelManager
  TFLiteModelManager._();
  static final TFLiteModelManager instance = TFLiteModelManager._();

  Interpreter? _bertInterpreter;
  Interpreter? _mobileClipImageInterpreter;
  Interpreter? _mobileClipTextInterpreter;

  /// 模型是否准备
  bool get isBertReady => _bertInterpreter != null;
  bool get isMobileClipImageReady => _mobileClipImageInterpreter != null;
  bool get isMobileClipTextReady => _mobileClipTextInterpreter != null;

  bool get isInitialized =>
      isBertReady && isMobileClipImageReady && isMobileClipTextReady;

  /// 解释器获得
  Interpreter get bertInterpreter {
    if(_bertInterpreter == null){
      throw Exception(
          "BERT model is not initialized.");
    }
    return _bertInterpreter!;
  }

  Interpreter get mobileClipImageInterpreter {
    if(_mobileClipImageInterpreter == null){
      throw Exception(
          "MobileCLIP model is not initialized.");
    }
    return _mobileClipImageInterpreter!;
  }

  Interpreter get mobileClipTextInterpreter {
    if (_mobileClipTextInterpreter == null) {
      throw StateError(
          'MobileCLIP Text model not initialized.');
    }
    return _mobileClipTextInterpreter!;
  }

  // 加载模型
  // 磁盘上的模型文件”到“内存中可执行的推理引擎”的转化
  // 初始化 BERT
  Future<void> initializeBert() async{
    if(isBertReady){
      return;
    }

    final options = InterpreterOptions()
      ..threads = EmbeddingConstants.maxConcurrentInference;

    // 如果初始化成功了，但是突然中途两个模型有一个没成功，即为null，则触发"??="把右边的给左边，
    // 如果某个模型是启动了，那就跳过“再启动”这个行为，节省资源
    _bertInterpreter ??= await Interpreter.fromAsset(
      EmbeddingConstants.bertModelPath,
      options: options,
    );
  }

  // 初始化 MobileCLIP
  Future<void> initializeMobileClip() async{
    if(isMobileClipImageReady){
      return;
    }
    final options = InterpreterOptions()
      ..threads = EmbeddingConstants.maxConcurrentInference;

    _mobileClipImageInterpreter ??= await Interpreter.fromAsset(
      EmbeddingConstants.mobileClipImageModelPath,
      options: options,
    );
    _mobileClipTextInterpreter ??= await Interpreter.fromAsset(
      EmbeddingConstants.mobileClipTextModelPath,
      options: options,
    );
  }

  // 初始化所有模型
  Future<void> initialize() async{
    await initializeBert();
    await initializeMobileClip();
  }

  // 释放模型
  // 由于.tflite模型的底层是C/C++，当.tflite模型加载后，庞大的神经网络权重是存储在原生内存上的，
  // Dart的垃圾回收机制只能关闭dart层面的对象，看不见也管不着原生内存上的内容，如果不手动释放这部分内存
  // 会一致被霸占影响性能

  // 释放 BERT
  void disposeBert(){
    // 因为模型可能为null，所以要加"?"
    _bertInterpreter?.close();
    // 切断Dart变量和这个对象的联系，那么使用这个对象的Dart变量变成没有指向的变量，垃圾回收机制会回收当下次扫描的时候
    // 在Dart堆内存上被清除
    _bertInterpreter = null;
  }

  // 释放 MobileCLIP
  void disposeMobileClip(){
    _mobileClipImageInterpreter?.close();
    _mobileClipImageInterpreter = null;

    _mobileClipTextInterpreter?.close();
    _mobileClipTextInterpreter = null;
  }
  void dispose() {
   disposeBert();
   disposeMobileClip();
  }
}