# 第三方许可证原文目录

本目录保存项目直接依赖、随发布包分发的主要第三方软件、模型和数据所适用的许可证或署名原文。组件、版本、来源、不确定性和发布限制的详细说明见项目根目录的 `THIRD_PARTY_NOTICES.md`。

## 共用 Apache 2.0 文本

`Apache-2.0.txt` 适用于已确认或高可信推断采用 Apache License 2.0 的组件，包括：

- Apache Tika 3.3.1；
- Tesseract OCR 主程序；
- Google Research BERT 代码、官方预训练模型和词表；
- TensorFlow Lite；
- `tflite_flutter`。

其中 Tika 的署名还必须结合 `Apache-Tika-NOTICE.txt` 保留。

## 组件专用文件

- `Flutter-BSD-3-Clause.txt`：Flutter SDK；
- `pdfrx-MIT.txt`：pdfrx；
- `Dart-http-BSD-3-Clause.txt`、`Dart-path-BSD-3-Clause.txt`、`Dart-ffi-BSD-3-Clause.txt`：Dart 组件；
- `archive-MIT.txt`、`image-MIT.txt`、`file_picker-MIT.txt`、`cupertino_icons-MIT.txt`：直接运行时依赖；
- `ChromaDB-Dart-Client-MIT.txt`：当前使用的 Dart ChromaDB 客户端；
- `OpenAI-CLIP-MIT.txt`：OpenAI CLIP 代码和 BPE 资源的可能上游许可证；
- `Apple-MobileCLIP-Code-MIT.txt`：Apple ML-MobileCLIP 软件许可证；
- `Apple-MobileCLIP-Model-License.txt`：Apple 模型权重许可证，包含非商业研究限制；
- `Apple-MobileCLIP-ACKNOWLEDGEMENTS.txt`：ML-MobileCLIP 上游组件声明；
- `Leptonica-BSD-2-Clause.txt`：Leptonica；
- `PDFium-LICENSE.txt`：PDFium；
- `Apache-Tika-jsoup-MIT.txt`：Tika JAR 内的 jsoup 声明。

## 仍待补齐

`Tesseract-Windows-Runtime-NOTICES.txt` 不是许可证替代文本。它记录当前 Windows OCR 发行包缺少来源和 DLL 许可证集合的问题。找到原始 Tesseract Windows 发行包后，应使用发行包自带的许可证和第三方声明替换或补充该文件。

Flutter 构建生成的完整运行时 NOTICES 也应随最终 Release 发布；本目录不试图替代 Flutter 自动汇总的全部传递依赖许可证。
