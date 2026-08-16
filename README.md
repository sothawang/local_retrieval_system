# 离线无障碍多模态本地内容检索系统 (Offline Accessible Multimodal Local Content Retrieval System)

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![WCAG 2.1 AA](https://img.shields.io/badge/Accessibility-WCAG_2.1_AA-success.svg)](docs/accessibility_compliance_validation_report_CN.md)

一个 **100% 离线端侧运行**、深度融合 **“高维向量语义 + 内存倒排关键词”双路并行检索** 并全面符合 **WCAG 2.1 AA 级无障碍标准** 的现代化跨平台本地内容检索应用。

---

## 📖 项目简介

在个人电脑中通常存储着海量文档与图片，传统字面搜索无法理解同义语义，而纯 AI 向量搜索又容易模糊代码、专有名词与特定编号。

本项目专为解决这一矛盾而设计：
- **100% 离线安全与隐私保护**：所有文件解析、OCR 识读、深度学习向量推理与索引检索均在用户本地端侧完成，零网络请求，杜绝隐私泄漏。
- **双模型多模态支持**：
  - **BERT-base TFLite (768 维)**：用于高精度文本-文本（Text-to-Text）深层语义检索。
  - **MobileCLIP TFLite (512 维)**：基于视觉-语言共享空间，支持通过自然语言输入进行“以文搜图（Text-to-Image）”。
- **双路并行召回与加权融合**：
  - 向量语义分支（ChromaDB）与字面倒排分支（KeywordIndex 5-Pillar 打分模型）独立并行检索并取并集（UNION）。
  - 经 NQ 真实基准调优采用 **0.3 向量 + 0.7 关键词** 加权融合，兼顾模糊语义理解与代码/编号精准命中。
- **深度无障碍交互体系 (WCAG 2.1 Level AA)**：
  - 全流程支持纯键盘导航与无障碍焦点管理，无键盘陷阱。
  - 全面适配 NVDA (Windows) 与 VoiceOver (macOS) 等屏幕阅读器，支持 LiveRegion 状态实时语音播报。
  - 支持一键切换专用高对比度黑黄主题，以及 100% ~ 200% 全局文字动态无损缩放。
- **多格式本地文件摄取**：支持 `.txt`、`.pdf`、`.docx`、`.jpg`、`.jpeg`、`.png`、`.bmp`、`.webp`。

---

## 🛠️ 前置环境与依赖服务

在启动本应用前，请确保在本地计算机上安装并启动以下公共依赖环境：

### 1. ChromaDB 本地向量数据库（必需）
程序后端默认通过本机回环连接 `http://localhost:8000`。您可选择以下任一方式运行：

#### 方式 A：通过 Python 运行（推荐）
```bash
# 1. 安装 ChromaDB
pip install chromadb

# 2. 指定数据存储目录并启动本地服务（默认监听 8000 端口）
chroma run --path ./chroma_data
```

#### 方式 B：通过 Docker 运行
```bash
# 启动持久化 Chroma 容器
docker run -d --name local-retrieval-chroma -v chroma-data:/data -p 8000:8000 chromadb/chroma
```

> **心跳检查**：保持 Chroma 服务终端运行，在另一个终端执行：
> - **PowerShell (Windows)**: `Invoke-RestMethod http://localhost:8000/api/v2/heartbeat`
> - **Bash (macOS / Linux)**: `curl http://localhost:8000/api/v2/heartbeat`
> 
> 若返回心跳时间戳，说明 ChromaDB 已就绪。

### 2. Java 运行时环境（JRE / JDK 11+）
系统解析 `.docx` 文档及调度 OCR 时，会在本地后台启动 Apache Tika Server。
- 确保系统已安装 Java 11 或更高版本。
- 终端运行 `java -version` 确认 `java` 命令已加入系统环境变量 `PATH`。

---

## 💻 各操作系统配置与安装指南

不同操作系统在外部工具与运行库配置上略有差异，请根据您的操作系统查阅对应说明：

### 🪟 Windows 用户指南

Windows 平台的构建分发最为完整，发布包已内置打包了 Tika 与 Tesseract 运行环境。

#### 1. 所需软件与依赖
1. **Java 11+**：下载并安装 [Oracle JDK](https://www.oracle.com/java/technologies/downloads/) 或 [Eclipse Temurin OpenJDK](https://adoptium.net/)，确保已配置环境变量。
2. **ChromaDB**：按上述指南通过 `chroma run --path .\chroma_data` 启动。

#### 2. 运行发布版
- 下载并解压 Windows Release 压缩包（包含 `local_retrieval_system.exe`、`data/`、`tika_service/`、`tesseract/` 及相关 DLL）。
- **启动步骤**：先启动 ChromaDB，随后双击运行 `local_retrieval_system.exe`。

#### 3. 源码开发与编译构建
若您从源码编译 Windows 客户端：
```powershell
# 1. 获取依赖
flutter pub get

# 2. 确认 blobs 目录下存在 Windows TFLite 原生动态库
# libtensorflowlite_c-win.dll 应放置在 <项目根目录>/blobs/ 下

# 3. 本地调试运行
flutter run -d windows

# 4. 构建 Release 发布包
flutter build windows --release
```

---

### 🍎 macOS 用户指南

macOS 用户需要通过 Homebrew 安装 Tesseract OCR 引擎及语言包。

#### 1. 通过 Homebrew 安装外部依赖
```bash
# 1. 安装 Java
brew install openjdk@17
# 将 java 链接到系统路径（按 brew 提示操作）
sudo ln -sfn $(brew --prefix)/opt/openjdk@17/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-17.jdk

# 2. 安装 Tesseract OCR 引擎及英文语言包
brew install tesseract tesseract-lang

# 验证 Tesseract 与语言包
tesseract --version
tesseract --list-langs  # 列表中必须包含 eng
```

#### 2. 配置 Tika 服务文件
发布或独立运行应用时，请确保在应用可执行文件同级或工程根目录下存在 `tika_service` 文件夹：
```text
tika_service/
├── tika-server-standard-3.3.1.jar
└── tika-config.xml
```

#### 3. 启动与开发运行
```bash
# 1. 终端启动 ChromaDB
chroma run --path ./chroma_data

# 2. 源码运行
flutter run -d macos
```

---

### 🐧 Linux (Ubuntu / Debian / Fedora) 用户指南

Linux 用户需使用系统的包管理器安装 OCR、Java 等环境依赖。

#### 1. 安装系统依赖工具
以 Ubuntu / Debian 为例：
```bash
sudo apt update

# 1. 安装 Java 运行时
sudo apt install default-jre

# 2. 安装 Tesseract OCR 及英文训练数据
sudo apt install tesseract-ocr tesseract-ocr-eng

# 3. 验证安装
java -version
tesseract --list-langs  # 确认输出包含 eng
```

#### 2. 配置 Tika 服务文件与 TFLite 库
- 将 `tika_service/` 放置于二进制文件同级目录下。
- 确保系统具备 Linux 版 TensorFlow Lite C 动态库支持（`libtensorflowlite_c.so`）。

#### 3. 启动与开发运行
```bash
# 1. 启动 ChromaDB
chroma run --path ./chroma_data

# 2. 源码运行
flutter run -d linux
```

---

## 🚀 快速上手与操作指南

```
【 推荐启动顺序 】
1. 启动本地 ChromaDB (端口 8000) ──> 2. 打开 Local Retrieval System 应用程序
```

### 1. 文件库管理 (File Library)
- 点击 **“添加文件”** 按钮（或通过原生对话框多选），选择本地 `.txt`、`.pdf`、`.docx` 文档或图片。
- 系统自动启动后台流水线：解析正文/元数据 $\rightarrow$ 动态切块 $\rightarrow$ 提取向量 $\rightarrow$ 双写至 Chroma 向量库与倒排索引库。
- 支持单文件 **“重新索引”** 与 **“删除索引”**（删除索引不会影响磁盘上的原始文件）。

### 2. 多模态内容搜索 (Search)
- **文本文档搜索**：在搜索栏输入查询词（如 `"system architecture"`），系统执行 BERT 语义 + 关键词五维打分双路并行召回，返回相关度排序结果与文本摘要片段。
- **图片检索（以文搜图）**：切换到“图片”模式，输入自然语言视觉描述（如 `"a red sports car on the road"`），系统通过 MobileCLIP 空间检索匹配的本地图片。

### 3. 系统设置与无障碍调节 (Settings)
- **高对比度模式**：一键开启高对比度主题，文字与背景对比度大幅提升。
- **动态字号缩放**：支持 100% ~ 200% 文字缩放调节，界面自动响应重排。

---

## ⌨️ 全局无障碍快捷键速查

| 快捷键 (Windows/Linux) | 快捷键 (macOS) | 触发功能 |
| :--- | :--- | :--- |
| `Alt + 1` | `Option + 1` | 快速跳转至 **“文件库”** 页面 |
| `Alt + 2` | `Option + 2` | 快速跳转至 **“搜索”** 页面 |
| `Alt + 3` | `Option + 3` | 快速跳转至 **“设置”** 页面 |
| `Ctrl + F` | `Command + F` | 全局快速跳转并聚焦到 **搜索输入框** |
| `Tab` / `Shift + Tab` | `Tab` / `Shift + Tab` | 正向 / 逆向顺畅流转控件焦点 |
| `Enter` / `Space` | `Enter` / `Space` | 激活/触发当前聚焦的按钮或选项 |

---

## 📁 项目关键目录结构

```text
local_retrieval_system/
├── assets/                    # 模型权重与资源文件
│   ├── bert_model/            # BERT TFLite 模型与 WordPiece 词表 (vocab.txt)
│   ├── mobileclip_model/      # MobileCLIP TFLite 图文双模型与 BPE 词表
│   └── retrieval/             # 英文停用词表 (stopwords_en.json)
├── blobs/                     # Windows 原生 TFLite C 动态链接库
├── docs/                      # 架构设计、评测报告、合规审计与操作手册
├── lib/
│   ├── app/                   # 后端组装工厂与依赖编排 (app_backend.dart)
│   ├── embedding/             # BERT / MobileCLIP 嵌入推理引擎与限流队列
│   ├── parsing/               # 文件解析层 (PDFium, Tika 桥接, Tesseract OCR)
│   ├── retrieval/             # 检索核心 (Chroma 存储, KeywordIndex, HybridRetriever)
│   ├── ui/                    # Flutter Material 3 界面与无障碍控制器
│   └── main.dart              # 应用入口
├── test/                      # 单元测试、基准测试与 Widget/Semantics 自动化测试
└── pubspec.yaml               # Flutter 项目依赖配置
```

---

## 📄 开源许可与特别声明 (License & Notices)

1. **项目源码许可**：本项目自主研发的应用程序源代码遵循 [Apache License 2.0](LICENSE) 开源协议。
2. **第三方模型权重限制声明**：
   - 本项目所使用的 MobileCLIP 预训练模型权重遵循 **Apple Machine Learning Research Model License Agreement**。
   - **该模型权重仅限用于非商业科学研究与学术评估**。如需商用分发，请更换为符合商用许可的模型权重。
3. **第三方开源组件**：
   - Apache Tika（Apache 2.0）、Tesseract OCR（Apache 2.0）、PDFium（BSD-3-Clause）、ChromaDB（Apache 2.0）。详细第三方组件清单与许可证请参阅 [docs/THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md) 与 [docs/OPEN_SOURCE_COMPLIANCE_REPORT.md](docs/OPEN_SOURCE_COMPLIANCE_REPORT.md)。
