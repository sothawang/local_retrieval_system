// 图片缩放到 224×224、归一化
// ImagePreprocessor的目的就是为了得到符合mobileclip模型的input
// Input:
// [1,224,224,3]
// float32
//
// Output:
// [1,512]
// float32

import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';
/// Image preprocessing for MobileCLIP.
///
/// Pipeline:
/// Decode
///     ↓
/// Resize (224×224)
///     ↓
/// RGB
///     ↓
/// Normalize to [0,1]
///     ↓
/// Tensor [1,224,224,3]
class ImagePreprocessor{
  // batch层 → 高度层 → 宽度层 → 通道层。
  // imageBytes: 图像输入流
  // Future<...> + async：因为图片解码/缩放这种操作对于较大图片可能比较耗时，
  // -用异步方法避免阻塞UI线程（虽然这个方法体内部实际上没有用到 await，但保留异步接口方便未来扩展，
  // -比如以后想用 compute() 把这个计算丢到另一个isolate里做，接口不用改）。
  Future<List<List<List<List<double>>>>> preprocess(Uint8List imageBytes)async{
    // 解码图片
    // 把原始字节流（比如一段JPEG/PNG格式的二进制数据）解析成一个可操作的 Image 对象（这个库内部会自动识别是JPEG还是PNG还是其他格式）。
    final decoded = img.decodeImage(imageBytes);
    if(decoded==null){
      throw Exception('Failed to decode image.');
    }

    // 缩放图片
    // 强制把解码后的Image对象缩放成224*224的大小
    // 因为MobileCLIP模型的输入shape是固定的（[1,224,224,3]），
    // -无论用户上传的原图是1920×1080还是500×300，都必须统一缩放成224×224，否则张量形状对不上，模型没法处理。
    final resized = img.copyResize(
      decoded,
      width: EmbeddingConstants.imageSize,
      height: EmbeddingConstants.imageSize,
    );

    // 构建4维张量
    // 第1层（最外层）：batch维度,生成1个元素，对应 [1, ...] 的batch维度。因为一次只处理1张图，所以固定是1
    final tensor = List.generate(
        1,
        (_) => List.generate(
          // 第二层：高度维度（y坐标），row
          EmbeddingConstants.imageSize,
          (y) => List.generate(
            // 第三层：宽度维度（x坐标），column
            EmbeddingConstants.imageSize,
            (x) {
              // 这一层的函数体内部，同时用到了内层的 x 和外层的 y——这是Dart闭包（closure）的特性：内层函数可以访问外层函数作用域里的变量。
              // 所以 resized.getPixel(x, y) 精确取出了第y行第x列这一个像素点的颜色数据。
              final pixel = resized.getPixel(x, y);
              // 归一化到 [0, 1],神经网络对输入数值的量级很敏感，如果直接把0~255的整数喂给模型，数值偏大且方差较大，会导致训练/推理时梯度计算不稳定、收敛变慢。
              // 归一化到0~1（或者有些模型要求归一化到-1~1，甚至用ImageNet的均值方差做标准化）是几乎所有视觉模型的标准预处理步骤，
              // 这也正好呼应了我们最早聊MobileCLIP输入格式时提到的"float32，归一化后的浮点数"这个点。
              // 也就是第四维度：RGB的3
              return [
                pixel.r / 255.0,
                pixel.g / 255.0,
                pixel.b / 255.0,
              ];
            },
            // 参数控制生成的List是否可以动态增删元素
            // growable: true（默认值）：List长度可变，可以调用 .add()、.remove() 等方法。
            // growable: false：List长度固定，创建后不能再增删元素（但依然可以修改已有位置的值，比如 list[0] = 1.0 是合法的，只是不能 list.add(2.0)）
            // 因为图像张量的形状是严格固定的（1×224×224×3），生成之后永远不需要再增删元素，只需要按索引读写。
            // Dart内部对定长List有专门的内存优化，不需要像可变长List那样预留额外的扩容空间。
            growable: false,
          ),
          growable: false,
        ),
      growable: false,
    );
    return tensor;
  }
}