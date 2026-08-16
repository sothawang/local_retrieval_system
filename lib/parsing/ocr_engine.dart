import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'tika_bridge.dart';

/// 图像物理尺寸。
class ImageSize {
  const ImageSize(
      this.width,
      this.height,
      );

  final int width;
  final int height;
}

/// 本地图片 OCR 引擎。
///
/// OCR 流程：
/// Flutter → Tika Server → Tesseract OCR。
///
/// Windows 使用随应用提供的 Tesseract。
/// macOS 和 Linux 使用系统中安装的 Tesseract。
class OcrEngine {
  final TikaBridge _tikaBridge = TikaBridge();

  /// 获取图片宽度和高度。
  Future<ImageSize> getImageSize(
      String filePath,
      ) async {
    try {
      final File file = File(filePath);
      final Uint8List bytes = await file.readAsBytes();

      final img.Decoder? decoder = img.findDecoderForData(bytes);

      if (decoder != null) {
        final img.DecodeInfo? info = decoder.startDecode(bytes);

        if (info != null) {
          return ImageSize(
            info.width,
            info.height,
          );
        }
      }
    } catch (_) {
      // 图片损坏或格式无法识别时返回安全默认值。
    }

    return const ImageSize(0, 0);
  }

  /// 使用 Tika 和 Tesseract 离线识别图片中的英文文本。
  Future<String> recognizeText(
      String filePath,
      ) async {
    final File file = File(filePath);

    if (!await file.exists()) {
      throw FileSystemException(
        'OCR image does not exist.',
        filePath,
      );
    }

    return _tikaBridge.extractImageText(filePath);
  }
}