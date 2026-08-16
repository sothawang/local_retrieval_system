# 第三方软件、模型与数据声明

## 1. 文档说明

本项目包含或依赖第三方软件、原生运行库、机器学习模型、词表和数据文件。本文件根据当前项目的 `pubspec.lock`、本地包缓存、内置 JAR 声明、文件特征以及公开的上游项目资料整理。

本文件用于项目审计和署名说明，不替代各第三方组件的完整许可证原文。正式分发时，应同时提供项目根目录中的 `LICENSE`、`NOTICE`，以及各第三方组件要求保留的完整许可证和 NOTICE 文本。

信息状态含义：

- **已确认**：可从当前文件、包缓存或上游官方仓库直接确认；
- **高可信推断**：文件特征与上游资源高度一致，但当前项目没有保存原始下载记录；
- **待核实**：无法从当前文件确认准确版本、构建来源或许可证组合。

本文件不是法律意见。若项目用于商业发布、对外销售或大规模公开分发，应由版权人或合规人员复核。

## 2. 项目自身许可证

项目自身代码拟采用 Apache License 2.0。项目根目录提供 Apache License 2.0 英文原文。

项目自身采用 Apache License 2.0，并不表示本文件所列的所有第三方组件、模型或数据也采用 Apache License 2.0。第三方内容继续受各自许可证约束。

## 3. 重要发布限制

### 3.1 MobileCLIP 模型权重

当前项目包含：

```text
assets/mobileclip_model/mobileclip_image.tflite
assets/mobileclip_model/mobileclip_text.tflite
```

根据文件名称、模型用途、512 维共享空间和配套 CLIP BPE 词表，高可信推断这两个 TFLite 文件由 Apple ML-MobileCLIP 模型或其衍生模型转换而来。

Apple 官方仓库对代码使用 MIT License，但官方预训练模型权重使用单独的 **Apple Machine Learning Research Model License Agreement**。该模型许可证将使用和再分发限制在非商业科学研究和学术开发用途，不允许商业利用、商业产品开发或商业服务使用。

因此：

- 在没有找到这两个 TFLite 文件的原始下载地址、转换记录或独立授权前，不应宣称模型权重采用 MIT 或 Apache 2.0；
- 如果它们确实由 Apple 官方模型权重转换，应在发布包中附带 Apple 的 `LICENSE_MODELS` 全文；
- 项目可作为非商业研究或课程项目使用，但不能仅凭项目的 Apache 2.0 `LICENSE` 将这些模型权重用于商业发布；
- 如果模型由项目成员自行训练，或来自另一个允许商业使用的来源，应使用实际来源和许可证替换本节。

上游参考：

- [Apple ML-MobileCLIP 官方仓库](https://github.com/apple/ml-mobileclip)
- [ML-MobileCLIP 软件许可证](https://github.com/apple/ml-mobileclip/blob/main/LICENSE)
- [ML-MobileCLIP 模型权重许可证](https://github.com/apple/ml-mobileclip/blob/main/LICENSE_MODELS)
- [ML-MobileCLIP 第三方声明](https://github.com/apple/ml-mobileclip/blob/main/ACKNOWLEDGEMENTS)

状态：**高可信推断，发布前必须核实**。

## 4. Flutter 和 Dart 运行时依赖

以下版本来自当前 `pubspec.lock` 和本地包缓存。

### 4.1 直接运行时依赖

| 组件 | 锁定版本 | 用途 | 许可证 | 状态 | 上游来源 |
|---|---:|---|---|---|---|
| Flutter SDK | 当前本机 SDK | UI、桌面运行时和无障碍框架 | BSD-3-Clause | 已确认 | [Flutter](https://github.com/flutter/flutter) |
| `pdfrx` | 2.4.7 | PDFium Flutter 封装和 PDF 文本提取 | MIT | 已确认 | [pdfrx](https://pub.dev/packages/pdfrx) |
| `http` | 1.6.0 | 本机 Tika HTTP 通信 | BSD-3-Clause | 已确认 | [http](https://pub.dev/packages/http) |
| `archive` | 4.0.9 | 压缩文件处理能力 | MIT | 已确认 | [archive](https://pub.dev/packages/archive) |
| `image` | 4.9.1 | 图片解码、缩放和尺寸读取 | MIT | 已确认 | [image](https://pub.dev/packages/image) |
| `path` | 1.9.1 | 跨平台路径处理 | BSD-3-Clause | 已确认 | [path](https://pub.dev/packages/path) |
| `ffi` | 2.2.0 | Dart 原生接口支持 | BSD-3-Clause | 已确认 | [ffi](https://pub.dev/packages/ffi) |
| `tflite_flutter` | 0.12.1 | TensorFlow Lite 推理 | Apache-2.0 | 已确认 | [tflite_flutter](https://pub.dev/packages/tflite_flutter) |
| `chromadb` | 1.4.1 | ChromaDB Dart HTTP 客户端 | MIT | 已确认 | [chromadb](https://pub.dev/packages/chromadb) |
| `file_picker` | 11.0.3 | 原生文件选择窗口 | MIT | 已确认 | [file_picker](https://pub.dev/packages/file_picker) |
| `cupertino_icons` | 1.0.9 | Cupertino 图标资源 | MIT | 已确认 | [cupertino_icons](https://pub.dev/packages/cupertino_icons) |

### 4.2 主要间接运行时依赖

当前依赖解析还包含下列主要间接组件。其精确版本以 `pubspec.lock` 为准，许可证原文来自对应 pub.dev 包或 Flutter SDK：

| 许可证 | 主要组件 |
|---|---|
| BSD-3-Clause 或 Dart/Flutter BSD 类许可证 | `args`、`async`、`characters`、`collection`、`cross_file`、`crypto`、`ffi`、`flutter_plugin_android_lifecycle`、`hooks`、`http_parser`、`jni`、`jni_flutter`、`jni_util`、`logging`、`meta`、`objective_c`、`package_config`、`path_provider` 系列、`platform`、`plugin_platform_interface`、`source_span`、`typed_data`、`url_launcher` 系列、`vector_math`、`web`、`win32` 等 |
| MIT | `pdfium_dart`、`pdfium_flutter`、`pdfrx_engine`、`petitparser`、`posix`、`synchronized`、`xml` 等 |
| Apache-2.0 | `material_color_utilities`、`quiver`、`rxdart` 以及部分 SDK 组件 |

Flutter 构建通常会生成运行时第三方许可证资源，但正式发布前仍应检查 Release 包内是否存在并可读取对应 NOTICES 资源。不能只依赖本文件的摘要替代许可证原文。

### 4.3 开发和测试依赖

以下组件主要用于开发或测试，通常不作为应用功能代码直接分发，但源码发布时仍应保留其许可证信息：

| 组件 | 锁定版本 | 许可证 | 状态 |
|---|---:|---|---|
| `flutter_test` | Flutter SDK | Flutter BSD-3-Clause | 已确认 |
| `mocktail` | 1.0.5 | MIT | 已确认 |
| `flutter_lints` | 6.0.0 | BSD-3-Clause | 已确认 |

## 5. PDFium

`pdfrx` 依赖 PDFium 原生库。`pdfrx` Dart/Flutter 包自身采用 MIT License；PDFium 使用 BSD 风格许可证，并包含多个可能具有独立声明的第三方组件。

正式发布时应保留 `pdfrx`、`pdfium_dart`、`pdfium_flutter` 和实际打包 PDFium 二进制随附的许可证/第三方声明。

上游参考：

- [pdfrx 官方仓库](https://github.com/espresso3389/pdfrx)
- [PDFium 官方许可证](https://pdfium.googlesource.com/pdfium/+/refs/heads/main/LICENSE)

状态：`pdfrx` 许可证 **已确认**；实际 PDFium 构建所含全部第三方组件 **待发布包复核**。

## 6. TensorFlow Lite

项目通过 `tflite_flutter` 和 Windows TensorFlow Lite C 动态库运行模型。

| 组件 | 用途 | 许可证 | 状态 | 上游来源 |
|---|---|---|---|---|
| `tflite_flutter` 0.12.1 | Dart/Flutter TFLite 接口 | Apache-2.0 | 已确认 | [pub.dev](https://pub.dev/packages/tflite_flutter) |
| TensorFlow Lite C runtime | 原生模型推理 | Apache-2.0 | 高可信推断 | [TensorFlow](https://github.com/tensorflow/tensorflow) |

项目根目录的 Apache 2.0 文本可满足相同许可证文本的提供要求，但仍应保留 TensorFlow/TFLite 自身的版权和 NOTICE 信息。

## 7. Apache Tika Server

项目直接分发：

```text
lib/document_parsing_tool/tika_service/tika-server-standard-3.3.1.jar
lib/document_parsing_tool/tika_service/tika-config.xml
```

| 组件 | 版本 | 用途 | 许可证 | 状态 | 上游来源 |
|---|---:|---|---|---|---|
| Apache Tika standard server | 3.3.1 | DOCX 解析和 Tesseract OCR 调度 | Apache-2.0 | 已确认 | [Apache Tika](https://tika.apache.org/3.3.1/) |
| jsoup | JAR 内置版本 | HTML 解析依赖 | MIT | 已从 JAR 内许可证确认 | [jsoup](https://jsoup.org/) |

当前 JAR 内包含以下 NOTICE：

```text
Apache Tika standard server
Copyright 2007-2026 The Apache Software Foundation

This product includes software developed at
The Apache Software Foundation (http://www.apache.org/).
```

该内容应保留在项目 `NOTICE`、第三方声明或最终发布包的可读位置。Tika JAR 还包含其他传递依赖；正式分发时应保留 JAR 内的 `LICENSE`、`META-INF/LICENSE`、`META-INF/NOTICE` 和其他第三方许可证条目。

状态：**已确认**。

## 8. Tesseract OCR 和 Windows 原生运行库

项目直接分发 `lib/document_parsing_tool/tesseract/` 下的 Tesseract 可执行文件、英文/方向识别数据和大量 DLL。

### 8.1 Tesseract 主程序

| 组件 | 版本 | 用途 | 许可证 | 状态 | 上游来源 |
|---|---|---|---|---|---|
| Tesseract OCR | 无法从当前 EXE 读取准确版本 | 英文 OCR | Apache-2.0 | 主项目许可证已确认，当前二进制版本待核实 | [tesseract-ocr/tesseract](https://github.com/tesseract-ocr/tesseract) |
| Leptonica | 当前 DLL 名为 `libleptonica-6.dll` | Tesseract 图像处理依赖 | BSD-2-Clause 类许可证 | 高可信推断 | [Leptonica](http://www.leptonica.org/) |
| `eng.traineddata` | 未记录具体 tessdata 分支/版本 | 英文识别数据 | Apache-2.0 | 高可信推断 | [tesseract-ocr/tessdata](https://github.com/tesseract-ocr/tessdata) |
| `osd.traineddata` | 未记录具体 tessdata 分支/版本 | 页面方向和脚本识别 | Apache-2.0 | 高可信推断 | [tesseract-ocr/tessdata](https://github.com/tesseract-ocr/tessdata) |

### 8.2 随附 DLL

当前目录还包括 ICU、OpenSSL、Cairo、Pango、GLib、FreeType、Fontconfig、HarfBuzz、libjpeg、libpng、libtiff、libwebp、OpenJPEG、zlib、zstd、brotli、libarchive、liblzma、libbz2、libdeflate、libffi、libiconv、libintl、libdatrie、libthai、Graphite2、FriBidi、pixman、GCC/MinGW 运行库等组件。

这些组件并非全部采用 Apache 2.0，可能分别使用 MIT、BSD、ISC、LGPL、OpenSSL/Apache 或其他许可证。当前 Tesseract 目录没有保存发行包名称、下载地址、版本清单或随附许可证，因此无法逐个准确确认。

正式公开发布前应：

1. 找到实际 Windows Tesseract 发行包的下载来源；
2. 恢复该发行包自带的 `LICENSE`、`COPYING`、`README` 或第三方声明；
3. 将 DLL 对应许可证随发布包分发；
4. 若无法恢复来源，改用来源清楚并带完整许可证的 Tesseract Windows 发行包。

状态：Tesseract 主项目许可证 **已确认**；当前 Windows 二进制发行来源和 DLL 许可证集合 **待核实**。

## 9. BERT 模型与词表

项目包含：

```text
assets/bert_model/bert.tflite
assets/bert_model/vocab.txt
```

当前 `vocab.txt` 共 30,522 行，以 `[PAD]` 和 `[unused0]` 等 token 开头，与 Google BERT Base Uncased WordPiece 词表特征一致。模型输出维度为 768，文件大小也与 BERT Base 级别的 TFLite 转换模型相符。

Google Research BERT 官方代码、预训练模型和词表使用 Apache License 2.0。TFLite 格式转换通常不改变原始模型权重的许可证义务。

| 文件 | SHA-256 | 推断来源 | 许可证 | 状态 |
|---|---|---|---|---|
| `bert.tflite` | `04F52A3611E0F3407B4F9112D9EA5A7A7CC697B2BEB33709E0C1BFD454E5BDE9` | Google BERT Base 或其 TFLite 转换版本 | Apache-2.0 | 高可信推断 |
| `vocab.txt` | `07ECED375CEC144D27C900241F3E339478DEC958F92FDDBC551F295C992038A3` | Google BERT Base Uncased 30,522 token 词表 | Apache-2.0 | 高可信推断 |

上游参考：[Google Research BERT](https://github.com/google-research/bert)

如果模型经过额外微调，应同时记录微调数据集、训练者和模型衍生许可。

## 10. MobileCLIP 和 CLIP BPE 资源

### 10.1 TFLite 模型

| 文件 | SHA-256 | 推断来源 | 许可证 | 状态 |
|---|---|---|---|---|
| `mobileclip_image.tflite` | `5CC68D20FCABAC7E621AD1627BA8E45F7B252D373F294B7F0EF3E746E65FE96A` | Apple ML-MobileCLIP 图片编码器或衍生转换 | Apple Machine Learning Research Model License Agreement | 高可信推断，必须核实 |
| `mobileclip_text.tflite` | `256F1AC06D8350330F034A6567917CC3B2B0289185DF4D6C8BD84AFCA10BA12B` | Apple ML-MobileCLIP 文本编码器或衍生转换 | Apple Machine Learning Research Model License Agreement | 高可信推断，必须核实 |

如果以上推断成立，分发时必须附带 Apple 模型许可证，并使用要求的归属说明：

```text
Apple Machine Learning Research Model is licensed under the
Apple Machine Learning Research Model License Agreement.
```

如 TFLite 转换改变了模型结构或产生模型衍生物，还应明确说明转换和修改。

### 10.2 CLIP BPE 词表

项目中的 `bpe_simple_vocab_16e6.txt` 共约 262,145 行，并带有 `#version: 0.2` 标记，与 OpenAI CLIP 使用的 BPE merges 资源一致。

| 文件 | SHA-256 | 推断来源 | 许可证 | 状态 |
|---|---|---|---|---|
| `bpe_simple_vocab_16e6.txt` | `67603CFDA2E032AD77B5F8808AF37789D590DB664B26DF8705D2BF8B3C553FC8` | OpenAI CLIP BPE vocabulary/merges | MIT | 高可信推断 |

上游参考：

- [OpenAI CLIP](https://github.com/openai/CLIP)
- [OpenAI CLIP MIT License](https://github.com/openai/CLIP/blob/main/LICENSE)

Apple ML-MobileCLIP 还包含 OpenCLIP、FastViT、timm 等组件的独立声明。如果模型确实来源于 Apple，应将 Apple 官方 `ACKNOWLEDGEMENTS` 一并保存和分发。

## 11. 英文停用词表

项目包含：

```text
assets/retrieval/stopwords_en.json
```

该列表与 NLTK/Snowball 常见英文停用词集合高度相似，包括缩写和否定形式，但项目没有保存来源说明。NLTK 的 stopwords corpus 本身汇集了 Snowball、SMART 等多个来源，不能仅根据 NLTK 源码的 Apache 2.0 许可证推定所有语料内容均为 Apache 2.0。

建议暂时记录为：

| 组件 | 用途 | 可能来源 | 许可证 | 状态 |
|---|---|---|---|---|
| `stopwords_en.json` | 英文关键词过滤 | NLTK/Snowball 风格列表，可能经项目整理 | 待确认；若为项目成员独立整理则随项目 Apache-2.0 | 待核实 |

参考：[NLTK data stopwords 索引](https://github.com/nltk/nltk_data/blob/gh-pages/index.xml)

## 12. ChromaDB 服务

项目通过 Dart `chromadb` 客户端连接用户另行启动的 ChromaDB 服务。当前发布包没有直接包含 ChromaDB 服务端。

需要区分：

- 当前使用的 Dart 包 `chromadb` 1.4.1：MIT License；
- 用户单独安装和运行的 ChromaDB 服务：适用其自身版本对应的许可证和部署条款；
- 因服务端未随项目发布，通常不需要把服务端二进制许可证作为项目内置组件处理，但用户手册应说明它是外部运行依赖。

上游参考：[Chroma](https://github.com/chroma-core/chroma)

状态：Dart 客户端 **已确认**；外部服务版本由用户环境决定。

## 13. 当前合规状态汇总

| 类别 | 状态 | 说明 |
|---|---|---|
| 项目 Apache 2.0 文本 | 已提供 | 根目录已有完整官方文本 |
| Flutter/Dart 直接依赖 | 基本确认 | 已从本地包缓存确认主要许可证 |
| Flutter/Dart 间接依赖 | 部分确认 | 应保留 Flutter 生成的完整 NOTICES 资源 |
| Apache Tika | 已确认 | Apache-2.0，JAR NOTICE 已提取并记录 |
| Tika 内传递依赖 | 部分确认 | 已发现 jsoup MIT，其他依赖应保留 JAR 内声明 |
| Tesseract 主程序 | 许可证确认、版本未知 | Apache-2.0 |
| Tesseract Windows DLL | 待核实 | 缺少原始发行包和许可证集合 |
| BERT 模型/词表 | 高可信推断 | 很可能为 Google BERT Apache-2.0 |
| MobileCLIP 模型 | 高风险、待核实 | 很可能受 Apple 非商业研究模型许可证限制 |
| CLIP BPE 词表 | 高可信推断 | 很可能来自 OpenAI CLIP，MIT |
| 英文停用词表 | 待核实 | 与 NLTK/Snowball 列表相似，来源未记录 |

## 14. 发布包必须保留的材料

正式分发时，建议发布目录至少包含：

```text
LICENSE
NOTICE
THIRD_PARTY_NOTICES.md
licenses/
├── Apache-2.0.txt
├── BSD-2-Clause.txt
├── BSD-3-Clause.txt
├── MIT.txt
├── Apple-ML-Research-Model-License.txt
├── ML-MobileCLIP-ACKNOWLEDGEMENTS.txt
├── Tika-NOTICE.txt
├── Tesseract-and-runtime-notices.txt
└── PDFium-third-party-notices.txt
```

如果最终确认 MobileCLIP 模型并非来源于 Apple，应删除不适用的 Apple 文件并替换为真实模型许可证。

## 15. 发布前待办事项

1. 将项目文件名统一为标准的 `LICENSE` 和 `NOTICE`；
2. 在 `NOTICE` 中保留 Tika 的 Apache Software Foundation 署名；
3. 确认两个 MobileCLIP TFLite 文件的原始来源；
4. 若来源是 Apple 官方权重，附带完整 `LICENSE_MODELS`，并明确项目仅限许可允许的研究用途；
5. 确认 BERT TFLite 转换来源和是否经过微调；
6. 找回 Windows Tesseract 发行包下载页面和原始许可证目录；
7. 收集 Tesseract 随附 DLL 的许可证；
8. 确认 `stopwords_en.json` 是独立整理还是来自 NLTK/Snowball；
9. 检查 Windows Release 中 Flutter 生成的 NOTICES 资源；
10. 将本文件及完整许可证目录复制到最终 Windows Release；
11. 每次升级 `pubspec.lock`、模型、Tika、Tesseract 或 DLL 后重新审计本文件。

