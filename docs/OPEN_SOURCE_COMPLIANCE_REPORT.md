# 离线无障碍多模态本地内容检索系统开源合规报告

## 1. 报告目的

本报告对当前项目使用和分发的开源软件、原生运行库、机器学习模型、词表与数据文件进行合规整理，说明：

- 项目自身许可证状态；
- 第三方组件及其主要许可证；
- 已经准备的合规材料；
- 源码分发与 Windows 二进制分发的适用条件；
- 当前仍存在的许可证和来源风险；
- 发布时需要执行的操作。

本报告依据当前项目文件和公开上游资料编写，不构成法律意见。项目用于商业发布、销售、企业产品或对公众大规模分发前，应由版权人或具备相应权限的人员再次审核。

## 2. 审计范围

本次审计覆盖：

- 项目根目录的许可证和第三方声明材料；
- `pubspec.yaml` 与 `pubspec.lock` 中的 Flutter/Dart 依赖；
- `assets/` 中的 BERT、MobileCLIP、词表和英文停用词；
- `lib/document_parsing_tool/` 中的 Apache Tika 与 Windows Tesseract；
- PDFium 和 TensorFlow Lite 原生运行组件；
- Windows Release 中由 Flutter 生成的第三方 NOTICES；
- 当前 Windows 构建脚本实际打包的外部资源。

以下内容不在本次详细验证范围内：

- 用户另行安装的 Java 运行时；
- 用户另行启动的 ChromaDB 服务端具体版本；
- 操作系统自身提供的系统 DLL 和字体；
- 用户自行选择并索引的本地文档或图片的版权；
- `NOTICE` 文件内容调整，按当前交付范围不再处理。

## 3. 审计方法

审计采用以下信息来源：

1. 当前项目的锁定依赖版本；
2. 本机 Flutter SDK 和 pub.dev 包缓存中的许可证原文；
3. Tika JAR 内的 `LICENSE`、`META-INF/NOTICE` 和第三方许可证；
4. TFLite 模型、词表和数据文件的文件特征与 SHA-256；
5. Apple、OpenAI、Google、Apache、Tesseract、PDFium 等上游官方仓库；
6. Windows Release 目录中的实际文件；
7. 现有 `THIRD_PARTY_NOTICES.md` 和 `licenses/` 目录。

当文件来源无法直接证明时，本报告使用“高可信推断”或“待核实”，不把推断写成已确认事实。

## 4. 合规结论摘要

### 4.1 总体结论

当前项目已经具备较完整的开源合规文档基础：

- 项目根目录存在完整 Apache License 2.0 文本；
- 已建立第三方组件清单；
- 已建立 `licenses/` 目录；
- 已保存主要直接依赖、Tika、PDFium、Leptonica、OpenAI CLIP 和 Apple MobileCLIP 的许可证或署名原文；
- Windows Flutter Release 已包含 `data/flutter_assets/NOTICES.Z`；
- 已明确记录不能确认的 Tesseract Windows DLL 来源问题。

但当前完整项目不能被简单描述为“所有内容均采用 Apache 2.0”。项目自身代码可以采用 Apache 2.0，第三方软件、模型和数据继续适用各自许可证。

### 4.2 关键限制

当前最重要的限制是 MobileCLIP 模型权重。

如果项目中的两个 MobileCLIP TFLite 文件由 Apple 官方预训练权重转换而来，它们适用 Apple Machine Learning Research Model License Agreement。该许可证仅允许非商业科学研究和学术开发，不允许商业利用、商业产品开发或商业服务使用。

因此，在模型来源没有被证明为其他可商业使用来源前：

- 本项目适合作为课程、研究、实验和非商业演示项目；
- 不应把包含这些模型的完整项目或发布包宣传为不受限制的商业 Apache 2.0 产品；
- 分发模型时必须附带 Apple 模型许可证和要求的归属说明；
- 商业使用前应更换为许可证允许商业分发的模型，或取得额外授权。

## 5. 项目自身许可证

项目根目录提供完整 Apache License 2.0 文本。Apache 2.0 允许在满足条件的情况下使用、修改和分发源码或二进制形式，并包含专利授权与免责声明。

项目自身采用 Apache 2.0 的前提是：许可证由项目代码的实际版权人或得到版权人授权的主体提供。如果项目代码属于学校、实习单位、雇主或多人团队，应先确认许可权归属。

Apache 2.0 仅覆盖版权人有权许可的项目代码和材料，不会自动覆盖：

- Apple MobileCLIP 模型权重；
- OpenAI CLIP 资源；
- Flutter/Dart 包；
- Tika、Tesseract、PDFium 和各原生 DLL；
- 用户导入的本地文件。

官方参考：

- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)
- [Apache 许可证使用 FAQ](https://www.apache.org/foundation/license-faq.html)

## 6. 已准备的合规材料

### 6.1 根目录文件

当前根目录包含：

```text
LICENSE
NOTICE
THIRD_PARTY_NOTICES.md
OPEN_SOURCE_COMPLIANCE_REPORT.md
licenses/
```

其中：

- `LICENSE`：项目使用的 Apache 2.0 完整英文文本；
- `NOTICE`：项目现有声明文件，本报告不对其内容提出进一步处理要求；
- `THIRD_PARTY_NOTICES.md`：组件、版本、用途、许可证、来源与不确定性清单；
- `OPEN_SOURCE_COMPLIANCE_REPORT.md`：本报告；
- `licenses/`：主要第三方许可证和署名原文。

### 6.2 licenses 目录

当前 `licenses/` 包含 24 个非空文件，主要包括：

- Apache License 2.0；
- Flutter BSD-3-Clause；
- Dart `http`、`path`、`ffi` 的 BSD 类许可证；
- `pdfrx`、`archive`、`image`、`chromadb` Dart client、`file_picker` 和 `cupertino_icons` 的 MIT 许可证；
- `tflite_flutter` Apache 2.0；
- Apache Tika NOTICE；
- Tika JAR 内 jsoup MIT 许可证；
- PDFium 许可证；
- Leptonica BSD-2-Clause 类许可证；
- OpenAI CLIP MIT 许可证；
- Apple ML-MobileCLIP 软件 MIT 许可证；
- Apple 模型权重许可证；
- Apple ML-MobileCLIP ACKNOWLEDGEMENTS；
- Tesseract Windows Runtime 来源待核实说明；
- 开发与测试依赖的主要许可证。

`licenses/README.md` 提供组件与许可证文件之间的映射说明。

### 6.3 Flutter 自动许可证资源

当前 Windows Release 中已经存在：

```text
data/flutter_assets/NOTICES.Z
```

该文件用于汇总 Flutter 和 Dart 依赖的许可证信息，应保留在发布包中，不应在精简发布目录时删除。

## 7. 第三方组件合规状态

### 7.1 Flutter 和 Dart 直接依赖

| 组件 | 锁定版本 | 许可证 | 合规状态 |
|---|---:|---|---|
| Flutter SDK | 当前本机 SDK | BSD-3-Clause | 已保存许可证，Release 含 NOTICES |
| `pdfrx` | 2.4.7 | MIT | 已保存许可证 |
| `http` | 1.6.0 | BSD-3-Clause | 已保存许可证 |
| `archive` | 4.0.9 | MIT | 已保存许可证 |
| `image` | 4.9.1 | MIT | 已保存许可证 |
| `path` | 1.9.1 | BSD-3-Clause | 已保存许可证 |
| `ffi` | 2.2.0 | BSD-3-Clause | 已保存许可证 |
| `tflite_flutter` | 0.12.1 | Apache-2.0 | 已保存许可证 |
| `chromadb` Dart client | 1.4.1 | MIT | 已保存许可证 |
| `file_picker` | 11.0.3 | MIT | 已保存许可证 |
| `cupertino_icons` | 1.0.9 | MIT | 已保存许可证 |

评价：直接 Flutter/Dart 依赖的许可证基础材料已经具备。传递依赖继续依靠 Flutter 的 NOTICES 汇总，并应随每次依赖升级重新生成和检查。

### 7.2 开发和测试依赖

| 组件 | 锁定版本 | 许可证 | 合规状态 |
|---|---:|---|---|
| `flutter_test` | Flutter SDK | BSD-3-Clause | 由 Flutter SDK 许可证覆盖 |
| `mocktail` | 1.0.5 | MIT | 已保存许可证 |
| `flutter_lints` | 6.0.0 | BSD-3-Clause | 已保存许可证 |

开发依赖一般不会进入最终应用运行时，但源码仓库包含其配置和引用，因此保留许可证信息是合理做法。

### 7.3 Apache Tika

项目直接分发 Apache Tika Server 3.3.1 JAR 和配置文件，用于 DOCX 解析以及 Tesseract OCR 调度。

已完成：

- 保存 Apache License 2.0；
- 从 JAR 中提取并保存 Apache Tika NOTICE；
- 保存 JAR 内 jsoup 的 MIT 许可证；
- 在第三方声明中记录 Tika 的版本、用途和来源；
- Windows 构建脚本会将 Tika JAR 和配置复制到 Release。

状态：**基本满足当前分发所需的许可证和署名保留要求**。

发布时仍应保留 JAR 自身的 `META-INF` 许可证内容，不应重新打包并删除这些条目。

### 7.4 Tesseract 和 Leptonica

Tesseract 主项目采用 Apache 2.0，Leptonica 采用 BSD-2-Clause 类许可证。两者对应的主要许可证文本已经保存。

当前问题是 Windows Tesseract 目录包含大量 DLL，但项目没有保存原始发行包名称、版本、下载地址和完整第三方声明。涉及的组件包括 ICU、OpenSSL、Cairo、Pango、GLib、FreeType、HarfBuzz、图像编解码库、压缩库和 MinGW 运行库等。

这些 DLL 不会因为和 Tesseract 一起分发就自动变为 Apache 2.0。

当前处理：

- `licenses/Tesseract-Windows-Runtime-NOTICES.txt` 已明确记录来源缺失；
- 没有把未知 DLL 错误声明为 Apache 2.0；
- 已保存可确认的 Tesseract 和 Leptonica许可证信息。

状态：**适合内部课程或研究交付；公开二进制发布前仍建议恢复原始发行包许可证集合或更换为来源清楚的发行包**。

### 7.5 PDFium

项目通过 `pdfrx`、`pdfium_dart` 和 `pdfium_flutter` 使用 PDFium。相关 Dart 包采用 MIT，PDFium 使用 BSD 风格许可证，并包含其他第三方许可内容。

已完成：

- 保存 `pdfrx` MIT 许可证；
- 保存 PDFium 官方许可证文本；
- 在第三方声明中说明 PDFium 的间接原生依赖关系。

状态：**主要许可证材料已准备**。发布时还应保留实际 PDFium 二进制随包产生的完整第三方 NOTICES。

### 7.6 TensorFlow Lite

项目通过 `tflite_flutter` 和 TensorFlow Lite C 动态库运行本地模型。TensorFlow/TensorFlow Lite 和 `tflite_flutter` 主要采用 Apache 2.0。

已完成：

- 保存 Apache 2.0 完整文本；
- 保存 `tflite_flutter` 包内许可证；
- 在第三方清单中记录原生 TensorFlow Lite runtime。

状态：**基本满足当前许可证文本保留要求**。

## 8. 模型和数据合规状态

### 8.1 BERT

当前 BERT 词表包含 30,522 个 token，与 Google BERT Base Uncased 的词表特征一致；模型为 768 维输出，也与 BERT Base 结构相符。

Google Research BERT 官方代码、预训练模型和词表采用 Apache 2.0。本项目已经保存 Apache 2.0 文本并记录模型文件哈希。

状态：**高可信推断为 Apache 2.0，可用于当前项目；仍建议保留原始下载或转换记录**。

如果该模型经过第三方微调，微调数据集和衍生模型可能产生额外条件，需要补充实际来源。

### 8.2 MobileCLIP

项目包含 MobileCLIP 图片和文本 TFLite 编码器。文件命名、输入输出、共享向量空间和 CLIP BPE 词表与 Apple ML-MobileCLIP 高度一致。

Apple 官方仓库区分：

- 软件代码：MIT License；
- 官方模型权重：Apple Machine Learning Research Model License Agreement；
- 上游组件：另见 Apple ACKNOWLEDGEMENTS。

项目已经保存这三类原文。

Apple 模型许可证的主要限制：

- 仅允许非商业科学研究和学术开发；
- 不包括商业利用、商业产品开发或商业服务；
- 再分发应附带模型许可证；
- 应提供规定的 Apple 模型归属说明；
- 模型衍生物应明确说明修改。

状态：**许可证文件已准备，但用途受到重要限制；完整项目不能仅依据 Apache 2.0 进行不受限制的商业分发**。

如果能够证明当前 TFLite 文件来自其他许可证来源或为独立训练模型，应更新第三方清单和本报告。

### 8.3 OpenAI CLIP BPE 词表

`bpe_simple_vocab_16e6.txt` 的文件结构与 OpenAI CLIP BPE merges 一致。OpenAI CLIP 代码采用 MIT License。

项目已经保存 OpenAI CLIP MIT 原文和相关版权声明。

状态：**高可信推断，主要署名和许可证材料已准备**。

### 8.4 英文停用词表

`stopwords_en.json` 与 NLTK/Snowball 常见英文停用词集合相似，但当前项目没有保存该文件的创建或下载记录。NLTK stopwords corpus 汇集多个来源，不能仅根据 NLTK 代码许可证推断语料内容许可证。

状态：**待核实，风险较低但仍应记录来源**。

如果该列表由项目成员独立整理，应在项目文档中声明为项目自有数据并随项目许可证提供；如果从某个语料库复制，应保存对应语料许可证和来源。

## 9. 外部运行服务

### 9.1 ChromaDB

项目内置的是 MIT 许可证的 Dart `chromadb` 客户端。ChromaDB 服务端由用户单独安装和运行，不包含在当前 Windows Release 中。

因此：

- Dart 客户端许可证已经纳入项目；
- 服务端具体版本和许可证由用户安装环境决定；
- 当前发布包无需假装分发 ChromaDB 服务端；
- 用户安装手册应继续说明 ChromaDB 是外部本机依赖。

### 9.2 Java

Java 用于启动 Tika JAR，由用户单独安装。项目没有分发 JDK/JRE，因此不在当前发布包第三方二进制清单中。

如果未来把 Java runtime 一起打包，应重新审计所选择 JDK/JRE 发行版的许可证和附带文件。

## 10. 许可证义务对照

| 许可证或条件 | 当前主要组件 | 主要义务 | 当前状态 |
|---|---|---|---|
| Apache-2.0 | 项目代码、Tika、Tesseract、BERT、TFLite | 提供许可证、保留适用声明、标记对上游文件的修改 | 主要文本已提供 |
| MIT | pdfrx、archive、image、Chroma Dart client、file_picker、CLIP 等 | 保留版权声明和完整许可文本 | 主要原文已保存 |
| BSD-3-Clause/BSD 类 | Flutter、Dart 包、PDFium | 源码或二进制分发时保留版权、条件和免责声明 | 主要原文及 Flutter NOTICES 已存在 |
| BSD-2-Clause 类 | Leptonica | 保留版权、条件和免责声明 | 原文已保存 |
| Apple 模型研究许可证 | 可能的 MobileCLIP 模型权重 | 仅限研究、附带许可证和归属、说明模型修改 | 原文已保存，但限制项目用途 |
| 未确认的原生 DLL 许可证 | Windows Tesseract runtime | 依据各 DLL 的实际许可证保留材料 | 待恢复原始发行包信息 |

## 11. 分发场景评估

### 11.1 仅分发项目自有源码

如果分发内容不包含第三方模型、JAR、Tesseract、DLL 或其他第三方二进制，仅分发项目成员拥有版权的代码：

状态：**在确认代码版权归属后，可按照 Apache 2.0 分发**。

仍应保留：

- `LICENSE`；
- 源码所引用第三方包的说明；
- `pubspec.yaml` 和 `pubspec.lock`；
- `THIRD_PARTY_NOTICES.md`。

### 11.2 分发完整源码仓库

当前完整仓库包含 TFLite 模型、Tika JAR 和 Windows Tesseract runtime，不再是单纯的项目源码。

状态：**适合非商业研究、课程和学术开发场景，并应附带全部许可证材料；不适合作为无条件商业 Apache 2.0 仓库宣传**。

原因：

- MobileCLIP 权重很可能受非商业研究许可证限制；
- Tesseract Windows DLL 的完整来源尚未恢复；
- 部分模型和数据的原始下载记录缺失。

### 11.3 分发 Windows Release

Windows Release 包含程序、Flutter 运行时、模型、Tika、Tesseract 和原生 DLL。

状态：**可用于受控的非商业课程/研究交付；公开或商业二进制发布仍有条件**。

发布前至少应：

1. 保留 `data/flutter_assets/NOTICES.Z`；
2. 把根目录 `LICENSE`、`NOTICE`、`THIRD_PARTY_NOTICES.md`、本报告和 `licenses/` 复制到 Release；
3. 明确 MobileCLIP 模型的非商业研究限制；
4. 不宣称 Apple 模型权重受 Apache 2.0 覆盖；
5. 尽可能恢复 Tesseract Windows 发行包的完整许可证集合；
6. 保留 Tika JAR 内的 META-INF 许可证文件。

## 12. 发布目录要求

建议最终 Windows Release 结构至少包含：

```text
Release/
├── local_retrieval_system.exe
├── LICENSE
├── NOTICE
├── THIRD_PARTY_NOTICES.md
├── OPEN_SOURCE_COMPLIANCE_REPORT.md
├── licenses/
├── data/
│   └── flutter_assets/
│       └── NOTICES.Z
├── tika_service/
├── tesseract/
└── 其他运行库和插件 DLL
```

当前 Flutter Release 已有 `NOTICES.Z`，但根目录的合规文件和 `licenses/` 尚未自动复制到 Release。可以在最终交付时手动复制，或者以后在 Windows 构建脚本中增加安装步骤。

## 13. 不应作出的声明

在当前状态下，不应使用以下说法：

- “发布包中的所有内容均为 Apache 2.0”；
- “MobileCLIP 模型可以自由商业使用”；
- “所有 Tesseract DLL 均为 Apache 2.0”；
- “模型来源已经完全验证”；
- “Apache Software Foundation 或 Apple 为本项目背书”；
- “删除第三方许可证文件不会影响使用和分发”。

可以使用更准确的表述：

> 项目自有代码采用 Apache License 2.0。项目包含适用独立许可证的第三方软件和模型，具体信息见 THIRD_PARTY_NOTICES.md 和 licenses 目录。当前内置 MobileCLIP 模型按可能适用的 Apple 模型许可证仅用于非商业研究和学术开发。

## 14. 风险分级

| 风险 | 等级 | 影响 | 当前控制措施 |
|---|---|---|---|
| MobileCLIP 模型权重可能仅限非商业研究 | 高 | 阻止不受限制的商业发布 | 已保存模型许可证并明确限制 |
| Windows Tesseract DLL 来源不完整 | 高 | 无法证明所有 DLL 的再分发条件 | 已明确标记，建议替换或恢复来源 |
| BERT TFLite 转换来源未保存 | 中 | 无法完全证明模型谱系 | 已记录哈希和高可信来源推断 |
| 停用词表来源未保存 | 中低 | 数据文件署名和许可不明确 | 已在第三方清单标记待核实 |
| 合规材料未自动复制到 Release | 中 | 二进制交付可能缺少可读许可证 | 已建立文件目录，发布时需复制 |
| 依赖升级后许可证变化 | 中 | 旧报告可能失效 | 每次更新锁文件后重新审计 |
| ChromaDB/Java 由用户另行安装 | 低 | 用户环境许可证版本不统一 | 手册中明确为外部依赖 |

