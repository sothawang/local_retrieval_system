# 离线无障碍多模态本地内容检索系统用户安装与操作手册

## 1. 手册说明

本手册适用于当前版本的离线无障碍多模态本地内容检索系统，介绍安装准备、程序启动、文件索引、文本搜索、图片搜索、无障碍操作和常见故障处理。

当前 Windows 版本的运行支持最完整。macOS 和 Linux 的代码基础已经保留，但发布包仍需要用户自行准备 Tesseract、Java 和 Tika 文件。

## 2. 主要功能

本程序可以：

- 添加本地 TXT、PDF、DOCX 和图片文件；
- 为文件建立本地搜索索引；
- 使用语义和关键词混合方式搜索文本文档；
- 使用英文描述搜索本地图片；
- 重新建立或删除某个文件的索引；
- 开启高对比度显示；
- 将应用文字放大到 200%；
- 使用键盘快捷键和屏幕阅读器操作。

程序不会把用户选择的文件上传到云端。文件解析、模型推理和搜索均在本机完成。程序会连接本机运行的 ChromaDB 和 Apache Tika 服务。

## 3. 支持的文件类型

| 文件类型 | 扩展名 | 当前用途 |
|---|---|---|
| 纯文本 | `.txt` | 提取文字并建立文本索引 |
| PDF | `.pdf` | 提取 PDF 中已有的文本层并建立文本索引 |
| Word 文档 | `.docx` | 通过本机 Apache Tika 提取文字并建立文本索引 |
| 图片 | `.jpg`、`.jpeg`、`.png`、`.bmp`、`.webp` | 建立 MobileCLIP 图片向量索引 |

注意：

- 扫描版 PDF 如果没有文本层，当前 PDF 解析不会自动对页面做 OCR；
- 后端已经具备 JPG/PNG 英文 OCR 能力，但当前图片入库流程没有把 OCR 文字加入搜索索引；
- 图片搜索目前主要依据 MobileCLIP 视觉语义和文件名，而不是图片中的 OCR 文字；
- 当前关键词分词、停用词和 OCR 语言均以英文为主，建议使用英文查询获得更稳定的结果。

## 4. Windows 安装

### 4.1 系统要求

建议准备：

- 64 位 Windows；
- 足够空间存放程序、模型、Tesseract 和本地索引；
- Java 11 或更高版本；
- 本地 ChromaDB 服务；
- 对待索引文件的读取权限。

Windows 发布包已经包含：

- Flutter 程序及资源；
- BERT 和 MobileCLIP 模型；
- Apache Tika Server JAR 和配置文件；
- Windows Tesseract OCR；
- Tesseract 英文训练数据。

Windows 用户不需要单独下载 Tika 或 Tesseract，但仍需要安装 Java，并单独启动 ChromaDB。

### 4.2 解压程序

1. 将发布压缩包完整解压到一个固定目录；
2. 不要只复制 EXE 文件；
3. 保留 EXE 同级的 `data`、`tika_service`、`tesseract`、DLL 和其他发布文件；
4. 建议使用普通英文或数字路径，避免将程序放入需要管理员写入权限的系统目录。

正确的 Windows 发布目录应大致包含：

```text
程序目录/
├── local_retrieval_system.exe
├── flutter_windows.dll
├── data/
├── tika_service/
│   ├── tika-server-standard-3.3.1.jar
│   └── tika-config.xml
├── tesseract/
│   ├── tesseract.exe
│   ├── tessdata/
│   │   └── eng.traineddata
│   └── 其他 Tesseract DLL
└── 其他运行库和插件 DLL
```

### 4.3 安装并检查 Java

安装 Java 11 或更高版本，并确保 `java` 命令已经加入系统 `PATH`。

在 PowerShell 中检查：

```powershell
java -version
```

如果可以看到 Java 版本信息，说明程序能够尝试启动 Tika。若提示找不到命令，请重新安装 Java 或修正系统环境变量，然后重新打开 PowerShell。

### 4.4 安装 ChromaDB

程序使用的 Chroma 客户端默认连接：

```text
http://localhost:8000
```

可以选择 Python 或 Docker 方式运行 ChromaDB。

#### 方式一：Python

先安装 Python，然后在 PowerShell 中执行：

```powershell
py -m pip install chromadb
```

如果系统使用 `python` 命令，也可以执行：

```powershell
python -m pip install chromadb
```

创建一个用于保存向量数据的目录，然后启动服务：

```powershell
chroma run --path .\chroma_data
```

Chroma 默认监听 `localhost:8000`。运行程序期间不要关闭这个 PowerShell 窗口。

如果系统提示找不到 `chroma` 命令，可以关闭并重新打开 PowerShell，或者使用 Python 安装目录中的 Chroma 可执行文件。

#### 方式二：Docker

如果已安装 Docker Desktop，可以执行：

```powershell
docker run --name local-retrieval-chroma -v chroma-data:/data -p 8000:8000 chromadb/chroma
```

以后再次启动同一个容器时使用：

```powershell
docker start -a local-retrieval-chroma
```

不要同时启动多个占用 8000 端口的 Chroma 服务。

### 4.5 检查 ChromaDB

保持 Chroma 运行，在另一个 PowerShell 窗口中执行：

```powershell
Invoke-RestMethod http://localhost:8000/api/v2/heartbeat
```

如果返回心跳数据，说明服务可以访问。如果连接失败，请先解决 ChromaDB 或 8000 端口问题，再启动本程序。

### 4.6 启动程序

1. 先启动 ChromaDB；
2. 双击 `local_retrieval_system.exe`；
3. 等待模型和数据库 collection 初始化；
4. 程序显示“文件库”页面后即可开始使用。

首次启动可能比后续启动慢，因为程序需要加载三个本地 TFLite 模型。第一次添加 DOCX 文件时，还需要启动本机 Tika Java 服务，可能出现额外等待。

如果程序直接显示“应用初始化失败”，优先检查 ChromaDB 是否正在 `localhost:8000` 运行。

## 5. 从源码运行

本节面向开发或演示环境。普通发布包用户可以跳过。

### 5.1 准备环境

需要安装：

- Flutter SDK；
- Dart SDK，由 Flutter 提供；
- Windows 桌面开发环境和 Visual Studio C++ 工具；
- Java 11 或更高版本；
- ChromaDB；
- 项目依赖的模型与资源文件。

检查 Flutter 环境：

```powershell
flutter doctor
```

在项目根目录安装 Dart/Flutter 依赖：

```powershell
flutter pub get
```

### 5.2 启动开发版本

先在一个独立终端启动 Chroma：

```powershell
chroma run --path .\chroma_data
```

然后在项目根目录运行：

```powershell
flutter run -d windows
```

### 5.3 构建 Windows 发布版

```powershell
flutter build windows --release
```

构建产物通常位于：

```text
build/windows/x64/runner/Release/
```

分发时必须复制整个 `Release` 目录，不能只发送 EXE。

Windows 构建脚本会检查并复制 Tika 和 Tesseract。若缺少以下文件，构建会失败：

- `lib/document_parsing_tool/tika_service/tika-server-standard-3.3.1.jar`；
- `lib/document_parsing_tool/tika_service/tika-config.xml`；
- `lib/document_parsing_tool/tesseract/tesseract.exe`；
- `lib/document_parsing_tool/tesseract/tessdata/eng.traineddata`。

## 6. macOS 和 Linux 安装说明

当前版本以 Windows 发布流程为主。macOS 和 Linux 用户除 Flutter 程序外，还需要自行准备外部运行环境。

### 6.1 必需组件

- Java 11 或更高版本；
- ChromaDB，监听 `localhost:8000`；
- Tesseract OCR；
- Tesseract 英文语言数据；
- Apache Tika Server 3.3.1 JAR；
- `tika-config.xml`；
- 对应平台可用的 Flutter、TFLite 和桌面插件运行库。

### 6.2 Tesseract

Tesseract 必须能通过系统 `PATH` 直接执行：

```bash
tesseract --version
```

同时需要确认英文语言数据可用：

```bash
tesseract --list-langs
```

输出列表中应包含 `eng`。

### 6.3 Tika 文件位置

发布应用时，需要在可执行文件同级创建 `tika_service` 目录：

```text
应用可执行文件所在目录/
└── tika_service/
    ├── tika-server-standard-3.3.1.jar
    └── tika-config.xml
```

源码开发运行时，程序也会检查：

```text
lib/document_parsing_tool/tika_service/
```

### 6.4 ChromaDB

Chroma 启动方法与 Windows 相同，必须保持默认地址和端口：

```bash
chroma run --path ./chroma_data
```

如果使用自定义端口，当前应用代码不会自动读取该端口，因而无法连接。

### 6.5 平台限制

macOS 和 Linux 尚未配置与 Windows 等价的 Tika/Tesseract 自动打包步骤。安装完成后应实际验证 TXT、PDF、DOCX、图片索引、文本搜索、图片搜索和平台屏幕阅读器，而不能仅以成功编译作为功能完成依据。

## 7. 首次使用

### 7.1 页面说明

程序有三个主要页面：

- **文件库**：选择、索引、重新索引和删除文件索引；
- **搜索**：搜索文本或图片；
- **设置**：调整高对比度和文字大小。

宽窗口使用左侧导航栏，窄窗口使用底部导航栏。

### 7.2 建议的首次操作顺序

1. 确认 ChromaDB 正在运行；
2. 启动程序；
3. 在“文件库”中先添加一个内容明确的英文 TXT 文件；
4. 等待出现“索引成功”；
5. 打开“搜索”页面；
6. 选择“文本文档”；
7. 输入文件中出现的英文关键词并搜索；
8. 确认结果显示文件名和来源路径；
9. 再根据需要添加 PDF、DOCX 或图片。

先用简单 TXT 文件验证，可以更容易区分程序、ChromaDB、Java、PDF 和 OCR 环境问题。

## 8. 文件库操作

### 8.1 添加文件

1. 打开“文件库”；
2. 选择“添加文件”；
3. 在系统文件选择窗口中选择一个或多个支持的文件；
4. 选择“打开”；
5. 等待索引完成。

索引期间页面会显示状态信息。每个文件可能处于：

- 正在索引；
- 索引成功；
- 索引失败。

文本文件可能被分成多条记录，因此“共 N 条记录”不一定等于文件数量。一张图片通常建立一条记录。

### 8.2 批量添加

文件选择窗口允许一次选择多个文件。程序当前按顺序处理文件。大文件、长 PDF、DOCX 或大量图片会增加等待时间。

批量处理完成后会显示成功和失败数量。某一个文件失败不会阻止其他文件继续索引。

### 8.3 重新索引

原始文件内容发生变化后：

1. 在文件卡片右侧打开管理菜单；
2. 选择“重新索引”；
3. 等待状态更新。

程序会删除该路径已有的向量和关键词记录，然后读取当前文件内容并重新建立索引。

如果原始文件已经移动、删除或失去读取权限，重新索引会失败。

### 8.4 删除索引

1. 打开文件卡片的管理菜单；
2. 选择“删除索引”；
3. 阅读确认对话框；
4. 选择“删除索引”。

该操作只删除搜索索引，不删除硬盘上的原始文件。

### 8.5 重复添加

同一路径的文件再次索引时，程序会先清理旧索引，以避免同一文件的旧记录与新记录并存。

## 9. 搜索操作

### 9.1 搜索文本文档

1. 打开“搜索”页面；
2. 在“搜索内容”输入框中输入英文查询；
3. 在“搜索类型”中选择“文本文档”；
4. 选择“搜索”，或在输入框中按 Enter；
5. 查看搜索结果。

文本搜索同时使用：

- BERT 语义相似度；
- 英文关键词匹配；
- 混合排序。

因此可以输入原文关键词，也可以输入意思相近的英文表达。

### 9.2 搜索图片

1. 先在文件库中添加图片；
2. 打开“搜索”页面；
3. 输入英文图片描述，例如 `a red car`；
4. 将搜索类型切换为“图片”；
5. 选择“搜索”。

图片结果基于 MobileCLIP 视觉语义和文件名关键词。当前结果卡片显示文件名、路径、相关度和匹配方式，但不显示图片缩略图。

### 9.3 理解搜索结果

每条结果包含：

- 排名；
- 文件名；
- 原始文件路径；
- 文本摘要或图片说明；
- 相关度百分比；
- “文本文档”或“图片”标签；
- 匹配来源。

匹配来源可能是：

- **语义 + 关键词**：两种检索方式均找到了该结果；
- **语义匹配**：主要由向量语义检索找到；
- **关键词匹配**：主要由关键词倒排索引找到。

相关度是当前候选集合内归一化后的混合分数，适合比较同一次搜索中的结果顺序，不应解释为绝对准确率。

### 9.4 清除搜索

选择“清除”可移除查询和结果，并将焦点返回搜索输入框。搜索框右侧的清除图标也可以清空输入内容。

### 9.5 没有结果时

依次检查：

1. 文件是否显示“索引成功”；
2. 是否选择了正确的搜索类型；
3. 查询是否为英文；
4. ChromaDB 是否仍在运行；
5. 应用是否在索引后被重新启动；
6. PDF 是否实际上只有扫描图片而没有文本层。

## 10. 设置操作

### 10.1 高对比度模式

1. 打开“设置”；
2. 切换“高对比度模式”。

开启后，应用使用黑色背景、白色文字、黄色重点颜色和青色辅助颜色。

### 10.2 调整文字大小

文字缩放范围为 100% 至 200%，每次改变 25%。

- 选择“增大文字”放大；
- 选择“减小文字”缩小；
- 屏幕阅读器可将“文字缩放比例”识别为滑块语义，并执行增加或减少动作。

达到 100% 或 200% 后，对应按钮会停用。

设置只保存在当前应用运行状态中。关闭并重新打开程序后，会恢复默认的普通主题和 100% 文字大小。

## 11. 键盘操作

### 11.1 全局快捷键

| 快捷键 | 操作 |
|---|---|
| Alt + 1 | 打开文件库 |
| Alt + 2 | 打开搜索页面 |
| Alt + 3 | 打开设置页面 |
| Ctrl + F | 打开搜索页面并聚焦输入框 |
| Command + F | macOS 上打开搜索页面并聚焦输入框 |

### 11.2 常用键盘操作

| 按键 | 操作 |
|---|---|
| Tab | 移动到下一个可操作控件 |
| Shift + Tab | 移动到上一个可操作控件 |
| Enter | 激活按钮、提交搜索或确认菜单项 |
| Space | 激活当前按钮或切换开关 |
| 方向键 | 在下拉列表、菜单或部分导航控件中移动 |
| Esc | 关闭部分对话框、菜单或文件选择窗口 |

快捷键由应用级硬件键盘监听处理，因此在使用鼠标点击文件库、搜索或设置后仍应有效。

## 12. 屏幕阅读器操作

### 12.1 Windows NVDA

1. 启动 NVDA；
2. 启动本程序；
3. 使用 Tab 和 Shift + Tab 遍历控件；
4. 使用 Enter 或 Space 激活控件；
5. 使用 Alt + 1、Alt + 2、Alt + 3 切换页面；
6. 使用 Ctrl + F 直接进入搜索框。

程序为以下内容提供了辅助技术信息：

- 页面和区域标题；
- 搜索输入框标签和提示；
- 文件索引状态；
- 搜索进行中、完成和失败状态；
- 搜索结果相关度；
- 文字缩放比例及增加、减少动作。

如果 NVDA 只朗读输入框提示而不朗读按钮或导航文字：

1. 确认使用的是当前构建版本；
2. 完全关闭旧 EXE 后重新构建或重新启动；
3. 重启 NVDA；
4. 使用 Tab 将键盘焦点移动到控件，不要只依赖鼠标悬停；
5. 检查 Windows 辅助功能和 NVDA 是否可以读取其他 Flutter 控件。

### 12.2 其他平台

macOS 可使用 VoiceOver，Linux 可使用 Orca。当前项目已经采用标准 Material 控件、标题语义、实时区域和有序焦点遍历，但仍需要在对应平台构建后单独验证。

## 13. 数据、隐私与保留规则

### 13.1 本地处理

程序读取用户主动选择的本地文件，并在本机执行：

- 文本提取；
- 图片向量生成；
- TFLite 模型推理；
- 关键词索引；
- 搜索和排序。

Tika 使用 `127.0.0.1:9998`，Chroma 使用 `localhost:8000`。这两个地址均指向当前计算机。

### 13.2 原始文件

删除索引不会删除原始文件。程序也不会移动或改写用户选择的原始文件。

如果原始文件被移动或删除，已有索引不会自动更新。文件变化后需要使用“重新索引”。

### 13.3 Chroma 向量数据

Chroma 数据保存在启动 Chroma 时指定的 `--path` 目录或 Docker volume 中。不要随意删除该目录或容器 volume，否则已保存向量会丢失。

### 13.4 关键词索引和文件列表

关键词索引和文件库页面列表只保存在当前应用进程内。关闭应用后：

- Chroma 向量可以继续保存在 Chroma 数据目录；
- 文件库页面不会自动恢复原来的文件列表；
- 关键词索引不会自动从 Chroma 恢复；
- 重新添加原文件可重建完整的向量和关键词索引。

因此，当前版本建议在每次重新启动应用后重新添加需要搜索的文件，以保证混合检索状态完整。

## 14. 正确关闭程序

建议按以下顺序关闭：

1. 完成正在进行的索引或搜索；
2. 正常关闭 Flutter 应用窗口；
3. 程序会尝试终止由它启动的 Tika 进程；
4. 如不再使用，在 Chroma 终端按 Ctrl + C 停止服务，或停止 Docker 容器。

应用不会自动停止由用户单独启动的 ChromaDB。

如果强制结束程序，Tika 进程可能来不及正常清理。再次运行前可在任务管理器中检查是否存在残留的 Java/Tika 进程或被占用的 9998 端口。

## 15. 常见问题与故障排查

### 15.1 启动时显示“应用初始化失败”

可能原因：

- ChromaDB 没有启动；
- Chroma 没有监听 8000 端口；
- 8000 端口被其他程序占用；
- Chroma 版本或 API 与客户端不兼容；
- 模型或 Flutter 资源缺失；
- TFLite 原生运行库缺失。

处理方法：

1. 关闭应用；
2. 启动 Chroma：`chroma run --path .\chroma_data`；
3. 使用 heartbeat 地址检查服务；
4. 确认发布目录完整；
5. 重新启动应用并查看错误页中的具体异常。

### 15.2 DOCX 索引失败

检查：

```powershell
java -version
```

然后确认：

- `tika_service` 目录与 EXE 同级；
- JAR 和配置文件都存在；
- 9998 端口没有被其他程序占用；
- DOCX 文件未损坏且有读取权限。

第一次 DOCX 解析需要等待 Tika 启动。程序最多等待约 30 秒；低性能设备可能需要更长，但当前超时固定为 30 秒。

### 15.3 图片索引失败

检查：

- 文件扩展名是否受支持；
- 图片是否损坏或为空；
- 图片是否过大；
- MobileCLIP 模型文件是否完整；
- TFLite 原生库是否存在。

普通图片向量索引不需要 OCR 成功。当前 UI 的图片索引主要由 MobileCLIP 完成。

### 15.4 OCR 失败

当前 UI 没有单独的 OCR 按钮，但如果开发或解析测试调用 OCR，可检查：

- Java 是否可用；
- Tika 是否能够启动；
- Windows 发布目录中是否存在完整 `tesseract` 目录；
- `tessdata/eng.traineddata` 是否存在；
- 图片是否为 JPG、JPEG 或 PNG；
- 9998 端口是否可用。

### 15.5 PDF 索引成功但搜不到文字

可能原因：

- PDF 是扫描图片，没有真实文本层；
- PDF 的字体编码异常；
- PDF 被加密或禁止提取；
- 提取出的文本为空；
- 查询语言与当前英文检索配置不匹配。

当前版本不会自动对扫描版 PDF 页面执行 OCR。可先使用能够生成文本层的 OCR 工具处理 PDF，再重新索引。

### 15.6 搜索结果为空

检查：

- 是否至少有一个文件索引成功；
- 文本查询是否选择了“文本文档”；
- 图片查询是否选择了“图片”；
- ChromaDB 是否仍在运行；
- 查询框是否为空；
- 应用是否刚刚重启但尚未重新添加文件。

### 15.7 搜索速度较慢

可能原因：

- 首次模型推理；
- 文件或索引数量增加；
- 设备 CPU 性能较低；
- ChromaDB 正在写入或处理其他查询；
- 查询同时进行向量和关键词两路召回；
- TFLite 推理并发受到限制。

等待当前索引完成后再搜索，并避免同时运行多个测试或 Chroma 实例。

### 15.8 文件库重启后为空

这是当前实现的正常行为。文件库列表和关键词索引没有持久化。重新添加原文件即可重建当前运行所需的完整索引。

### 15.9 删除索引后原始文件还存在

这是预期行为。“删除索引”只删除搜索数据，不会删除原始文件。

### 15.10 9998 端口被占用

在 Windows PowerShell 中检查：

```powershell
Get-NetTCPConnection -LocalPort 9998 -ErrorAction SilentlyContinue
```

如果已有 Tika 服务正常运行，程序会复用它。如果是其他程序占用端口，需要先关闭占用程序，再重试 DOCX 或 OCR 操作。

### 15.11 8000 端口被占用

检查：

```powershell
Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue
```

程序当前固定连接 `localhost:8000`。如该端口被其他服务占用，应停止冲突服务并在 8000 端口启动 ChromaDB。

### 15.12 Windows 防火墙提示

Tika 和 Chroma 只需要本机回环通信。若 Windows 防火墙弹出提示，不需要为公共网络开放服务。应优先保持服务仅供本机使用。

## 16. 推荐使用方法

- 先启动 ChromaDB，再启动应用；
- 首次使用先用小型英文 TXT 文件验证；
- 等待文件显示索引成功后再搜索；
- 文本检索优先使用简短、明确的英文查询；
- 图片检索使用可描述画面内容的英文短语；
- 修改原始文件后使用“重新索引”；
- 需要完整混合检索时，在应用重启后重新添加文件；
- 不要拆散 Windows 发布目录；
- 不要同时启动多个 Chroma 或 Tika 实例；
- 定期备份 Chroma 的数据目录，但不要在服务运行中随意移动或删除数据库文件。

## 17. 官方环境参考

- [Chroma CLI 安装](https://docs.trychroma.com/cli/install)
- [运行本地 Chroma Server](https://docs.trychroma.com/docs/cli/run)
- [Chroma Docker 部署](https://docs.trychroma.com/deployment/docker)
- [Apache Tika 3.3.1 入门文档](https://tika.apache.org/3.3.1/gettingstarted.html)
- [Apache Tika 下载页面](https://tika.apache.org/download)
