# 软件维护指南

## 1. 文档目的

本文档用于指导维护人员运行、检查、备份、升级和排查“离线无障碍多模态本地内容检索系统”。维护对象包括 Flutter 桌面客户端、ChromaDB、本地模型、Apache Tika、Tesseract OCR 以及 Windows 发布包。

当前 Windows 桌面版本的运行和打包支持最完整。macOS 和 Linux 保留了工程基础，但 Tika、Tesseract 和 TensorFlow Lite 原生库仍需根据目标平台单独安装、打包和验证。

## 2. 系统组成

| 组件 | 作用 | 主要维护事项 |
| --- | --- | --- |
| Flutter/Dart 客户端 | 界面、文件管理、检索调度和无障碍交互 | Flutter 版本、依赖、测试和发布构建 |
| ChromaDB | 持久化 BERT 与 MobileCLIP 向量 | 8000 端口、数据目录、备份和集合兼容性 |
| Apache Tika Server 3.3.1 | DOCX 文本提取和 OCR 调度 | Java、9998 端口、JAR 和配置文件 |
| Tesseract OCR | 识别 JPG/PNG 中的英文文字 | 可执行文件、依赖 DLL 和 `eng.traineddata` |
| PDFium（`pdfrx`） | PDF 文本提取 | 插件版本和目标平台原生文件 |
| BERT TFLite | 生成 768 维文本向量 | 模型与词表必须匹配 |
| MobileCLIP TFLite | 生成 512 维图文向量 | 图文模型、BPE 词表和许可证 |
| 内存关键词索引 | 关键词召回与混合排序 | 应用重启后不会自动恢复 |

当前混合检索权重为向量 `0.3`、关键词 `0.7`。调整模型、分词、停用词、评分逻辑或混合权重后，应重新建立索引并执行检索测试。

## 3. 关键目录

```text
local_retrieval_system/
├── assets/
│   ├── bert_model/                 # BERT 模型和词表
│   ├── mobileclip_model/           # MobileCLIP 模型和 BPE 词表
│   └── retrieval/                  # 英文停用词表
├── blobs/                          # Windows TensorFlow Lite DLL
├── docs/                           # 项目文档
├── lib/
│   ├── document_parsing_tool/
│   │   ├── tika_service/           # Tika JAR 和配置
│   │   └── tesseract/              # Windows Tesseract 运行时
│   ├── embedding/                  # 模型加载和向量生成
│   ├── parsing/                    # 文件解析与 OCR
│   ├── retrieval/                  # 索引和混合检索
│   └── ui/                         # 界面和无障碍实现
├── licenses/                       # 第三方许可证原文
├── test/                           # 自动化测试与测试资源
├── windows/                        # Windows 构建配置
├── pubspec.yaml                    # 直接依赖和资源声明
└── pubspec.lock                    # 实际锁定的依赖版本
```

Windows Release 应包含：

```text
build/windows/x64/runner/Release/
├── local_retrieval_system.exe
├── blobs/libtensorflowlite_c-win.dll
├── data/flutter_assets/
├── tika_service/
│   ├── tika-server-standard-3.3.1.jar
│   └── tika-config.xml
└── tesseract/
    ├── tesseract.exe
    ├── tessdata/eng.traineddata
    └── 运行所需 DLL
```

## 4. 日常启动和关闭

### 4.1 启动前检查

开发环境可在项目根目录执行：

```powershell
flutter --version
flutter doctor -v
java -version
chroma --help
```

发布版用户不需要安装 Flutter，但必须能够运行 Java 和 ChromaDB。Windows 发布包已包含 Tika 和 Tesseract。

### 4.2 启动 ChromaDB

客户端启动前必须先运行 ChromaDB。维护人员应固定使用同一个数据目录，避免误连到新的空数据库。

```powershell
chroma run --path "E:\path\to\chroma_data"
```

ChromaDB 默认监听 `localhost:8000`。使用以下命令进行健康检查：

```powershell
Invoke-RestMethod http://localhost:8000/api/v2/heartbeat
```

如果提示找不到 `chroma` 命令，可安装或修复 Python 包：

```powershell
py -m pip install chromadb
```

没有 `py` 启动器时使用：

```powershell
python -m pip install chromadb
```

安装后应关闭并重新打开 PowerShell。

### 4.3 启动客户端

开发环境：

```powershell
flutter pub get
flutter run -d windows
```

发布环境：先启动 ChromaDB，再运行 Release 目录中的 `local_retrieval_system.exe`。

客户端会连接或创建两个集合：

- `bert_text_embeddings`：768 维文本向量；
- `mobileclip_embeddings`：512 维图片向量。

### 4.4 Tika 的启动方式

Tika 不需要提前手动启动。首次处理 DOCX 或图片 OCR 时，程序会：

1. 检查 `http://127.0.0.1:9998/version`；
2. 服务存在时直接复用；
3. 服务不存在时通过 Java 自动启动本地 Tika；
4. 最多等待约 30 秒，成功后继续解析。

程序自动启动的 Tika 会在应用正常退出时尝试关闭；外部独立启动的 Tika 不由客户端结束。

### 4.5 正常关闭

1. 等待正在进行的索引任务结束；
2. 正常关闭客户端，使其释放模型、连接和自身启动的 Tika；
3. 回到 ChromaDB 终端按 `Ctrl+C`；
4. 确认终端返回命令提示符后，再备份或移动数据库目录。

不要在索引写入期间强制结束 ChromaDB，也不要在服务运行时移动其数据目录。

## 5. 数据和索引维护

### 5.1 持久化范围

ChromaDB 数据目录会持久化两个向量集合。当前文件库列表和关键词倒排索引位于应用内存中，不会随 ChromaDB 一起完整恢复。因此：

- 重启后，ChromaDB 中的向量仍可能存在；
- 文件库界面和关键词索引不会自动从 ChromaDB 重建；
- 为保证混合检索状态一致，重启后建议重新选择并索引需要使用的原始文件；
- 必须保留原始文件，不能将 ChromaDB 视为原文件备份。

### 5.2 单文件维护

文件内容发生变化后，应在文件库中执行“重新索引”。原文件移动或重命名后，旧记录仍保存旧路径，应删除旧索引，再从新路径添加文件。

“删除索引”仅删除检索记录，不删除磁盘上的原文件。操作前应核对文件名和完整路径。

### 5.3 实际支持格式

当前解析入口识别：

- `.txt`；
- `.pdf`；
- `.docx`；
- `.jpg`；
- `.png`。

OCR 桥接可以处理 `.jpeg`，但当前文件类型识别入口尚未把 `.jpeg` 映射到图片分支。增加新格式时，应同时修改并检查解析工厂、解析引擎、文件选择器、测试和用户文档。

### 5.4 备份 ChromaDB

以下操作前建议备份：

- 升级 ChromaDB；
- 修改模型、集合名称或向量维度；
- 大批量重新索引；
- 发布新版本；
- 迁移计算机或清理磁盘。

安全备份步骤：

1. 关闭客户端；
2. 使用 `Ctrl+C` 停止 ChromaDB；
3. 确认 8000 端口不再监听；
4. 复制整个 `chroma_data` 目录；
5. 记录应用、ChromaDB、模型版本和集合名称；
6. 重新启动服务并执行一个已知查询。

不要只复制数据目录中的某一个数据库文件。

### 5.5 恢复 ChromaDB

1. 关闭客户端和 ChromaDB；
2. 保留当前异常目录，不要覆盖唯一副本；
3. 将完整备份复制到新的恢复目录；
4. 使用恢复目录启动 ChromaDB；
5. 启动客户端并验证两个集合；
6. 重新索引原始文件，以恢复当前会话的文件库和关键词索引；
7. 验证文本搜索和图片搜索。

如果模型、维度或集合结构已经改变，不应强行复用旧索引，应使用新数据目录重新索引。

## 6. Apache Tika 维护

### 6.1 必需文件

开发目录：

```text
lib/document_parsing_tool/tika_service/
├── tika-server-standard-3.3.1.jar
└── tika-config.xml
```

发布目录必须在 EXE 同级包含相同的 `tika_service/` 文件夹。

### 6.2 健康检查

```powershell
Invoke-RestMethod http://127.0.0.1:9998/version
```

预期返回 Tika 版本。当前项目不使用 `/ping` 作为健康检查地址。

### 6.3 端口冲突

```powershell
Get-NetTCPConnection -LocalPort 9998 -ErrorAction SilentlyContinue
```

如果端口被占用，使用返回的进程 ID 查明进程：

```powershell
Get-Process -Id <进程ID>
```

不要直接结束所有 Java 进程。只有确认是本项目遗留的 Tika 后，才可结束对应进程。如果需要更换端口，必须同步修改服务启动参数、健康检查和请求地址。

### 6.4 升级 Tika

升级时必须同步：

1. 替换 JAR；
2. 检查 `tika-config.xml`；
3. 更新代码中的 JAR 文件名；
4. 更新 `windows/CMakeLists.txt`；
5. 测试 DOCX、JPG 和 PNG；
6. 验证 Tesseract 仍能被 Tika 调用；
7. 更新许可证和第三方声明；
8. 重新生成并检查 Windows Release。

## 7. Tesseract OCR 维护

### 7.1 Windows 查找顺序

程序依次查找：

1. 发布版 EXE 同级的 `tesseract/`；
2. `lib/document_parsing_tool/tesseract/`；
3. `C:\Program Files\Tesseract-OCR`。

有效目录至少需要：

```text
tesseract/
├── tesseract.exe
├── tessdata/eng.traineddata
└── 运行所需 DLL
```

程序启动 Tika 时会将该目录加入子进程的 `PATH`，并将 `TESSDATA_PREFIX` 指向 `tessdata`。当前只配置英文 `eng` OCR。

### 7.2 手动检查

在 Tesseract 目录中执行：

```powershell
.\tesseract.exe --version
.\tesseract.exe --list-langs
```

语言列表必须包含 `eng`。之后还应通过应用导入一张文字清晰的英文图片，并确认识别文字可以被搜索。

### 7.3 macOS 和 Linux

这两个平台使用系统 `PATH` 中的 Tesseract：

```bash
tesseract --version
tesseract --list-langs
```

语言列表应包含 `eng`。相应平台还需独立处理 Tika 文件和 TensorFlow Lite 原生库的打包。

### 7.4 升级注意事项

替换 Windows Tesseract 时应使用来源清楚、包含许可证和依赖说明的完整发行包。不要只替换 `tesseract.exe` 而保留不匹配的旧 DLL。升级后必须验证 Tesseract 自检、Tika 启动、JPG/PNG OCR、搜索、Debug/Release 构建和许可证材料。

## 8. 模型与检索配置维护

### 8.1 BERT

BERT 文件位于 `assets/bert_model/`。模型输出必须为 768 维，并与 `vocab.txt` 和分词逻辑兼容。

替换模型或词表后，旧的 `bert_text_embeddings` 不再保证兼容，应使用新数据目录或重建相应集合，并重新索引原文件。

### 8.2 MobileCLIP

MobileCLIP 文件位于 `assets/mobileclip_model/`。文本模型、图片模型和 BPE 词表必须属于兼容的一组，输出必须为 512 维。

替换任何一个 MobileCLIP 文件后，应重建 `mobileclip_embeddings`。当前模型权重可能受 Apple 非商业研究许可限制，替换模型时必须检查模型权重许可证，而不只是代码许可证。

### 8.3 停用词与混合权重

英文停用词位于 `assets/retrieval/stopwords_en.json`。修改停用词、关键词评分或混合权重后，应重新索引并运行：

```powershell
flutter test test/retrieval/retrieval_engine_test.dart
flutter test test/retrieval/retrieval_benchmark_test.dart
flutter test test/retrieval/hybrid_weight_tuning_test.dart
```

评估时应同时查看 Recall@1、Recall@5、Recall@10、MRR 和查询延迟，并记录采用新配置的原因。

## 9. Flutter 依赖维护

### 9.1 升级前

```powershell
flutter doctor -v
flutter pub outdated
```

升级前应保存 `pubspec.yaml` 和 `pubspec.lock`。一次只升级一组相关依赖，避免未测试的批量主版本升级。

### 9.2 升级后

```powershell
flutter pub get
flutter analyze
flutter test
flutter build windows --release
```

涉及 `tflite_flutter`、`pdfrx`、`file_picker` 或其他桌面插件时，必须实际运行 Release，因为原生 DLL、插件注册和 CMake 问题不一定会在 Widget 测试中出现。

### 9.3 TensorFlow Lite DLL

源码目录应存在：

```text
blobs/libtensorflowlite_c-win.dll
```

构建后应存在：

```text
build/windows/x64/runner/Release/blobs/libtensorflowlite_c-win.dll
```

替换 DLL 时应确认它是 x64，并与当前 `tflite_flutter` 和模型格式兼容。

## 10. 测试和质量检查

每次发布前至少执行：

```powershell
flutter analyze
flutter test
flutter build windows --release
```

自动化检查通过后，应使用 Release 包完成以下人工回归：

1. 启动 ChromaDB 并打开客户端；
2. 导入 TXT、PDF、DOCX、PNG 和 JPG；
3. 验证索引、重新索引和删除索引；
4. 验证关键词搜索和语义搜索；
5. 验证英文图片 OCR 和图片语义检索；
6. 验证 `Alt+1/2/3`、`Ctrl+F`、Tab 和 Shift+Tab；
7. 验证高对比度和 100%～200% 文字缩放；
8. 使用 NVDA 验证输入框、按钮、标题、状态和结果朗读；
9. 正常退出并确认应用启动的 Tika 被清理；
10. 重启后确认数据库连接和索引行为符合第 5.1 节。

macOS 或 Linux 相关改动必须在真实目标平台验证，不能使用 Windows 结果代替。

## 11. Windows 构建与发布

### 11.1 构建命令

```powershell
flutter clean
flutter pub get
flutter build windows --release
```

日常小修改无需每次执行 `flutter clean`；遇到原生插件、CMake、生成文件或缓存异常时再执行。

### 11.2 发布包检查

不能只分发 EXE。应整体分发 `build/windows/x64/runner/Release/`，并确认：

- Flutter DLL、插件 DLL 和 `data/` 完整；
- `blobs/libtensorflowlite_c-win.dll` 存在；
- `tika_service/` 中 JAR 和配置存在；
- `tesseract/` 中 EXE、英文数据和依赖 DLL 存在；
- 模型和词表位于 `data/flutter_assets/assets/`；
- `data/flutter_assets/NOTICES.Z` 存在；
- 交付包附带 `LICENSE`、第三方声明、合规报告和 `licenses/`。

发布前应在没有 Flutter 开发环境的干净 Windows 测试机上完成一次全流程验证。

### 11.3 版本记录

每次发布至少记录：

- 应用版本；
- Flutter 和 Dart 版本；
- `pubspec.lock`；
- ChromaDB、Java、Tika 和 Tesseract 版本；
- BERT 和 MobileCLIP 文件来源或校验值；
- 自动化与人工测试结果；
- 已知问题、数据迁移和回滚方法。

## 12. 常见故障排查

### 12.1 无法连接 ChromaDB

```powershell
Invoke-RestMethod http://localhost:8000/api/v2/heartbeat
Get-NetTCPConnection -LocalPort 8000 -ErrorAction SilentlyContinue
```

确认 ChromaDB 正在运行、数据目录正确且 8000 未被其他服务占用。若升级后发生 API 或数据格式不兼容，应恢复原版本和备份，或者使用新目录重新索引。

### 12.2 Tika 启动失败或超时

```powershell
java -version
Invoke-RestMethod http://127.0.0.1:9998/version
Get-NetTCPConnection -LocalPort 9998 -ErrorAction SilentlyContinue
```

同时确认 JAR 和配置文件位于正确位置。Java 不可用、9998 被占用、文件缺失或损坏、安全软件阻止 Java 子进程，都可能导致失败。

### 12.3 DOCX 无法解析

1. 确认 Tika 健康检查成功；
2. 确认文件是 `.docx` 而不是旧式 `.doc`；
3. 确认文件未损坏、未加密且具备读取权限；
4. 使用已知正常的小型 DOCX 复测；
5. 所有文件失败时检查 Tika，仅单文件失败时优先检查文件本身。

### 12.4 图片 OCR 没有文字

1. 当前只配置英文 OCR；
2. 使用 JPG 或 PNG，保证文字清晰、方向正确、对比度足够；
3. 确认 `eng.traineddata` 存在；
4. 执行 Tesseract `--version` 和 `--list-langs`；
5. 确认 Tika 正常；
6. 在应用中重新索引图片；
7. 注意 `.jpeg` 当前尚未由解析入口正式识别。

### 12.5 搜索没有结果或结果不一致

1. 确认文件索引成功；
2. 确认 ChromaDB 使用建立索引时的数据目录；
3. 应用重启后重新添加原文件，恢复内存关键词索引；
4. 先使用文件中明确存在的英文词进行基线检查；
5. 分别检查文本和图片搜索模式；
6. 模型或维度变化后重建向量集合；
7. 停用词或权重变化后重新执行测试。

### 12.6 Windows 构建失败

```powershell
flutter doctor -v
flutter clean
flutter pub get
flutter build windows --release -v
```

重点检查 Visual Studio Desktop development with C++、Windows SDK、原生插件、TFLite DLL、Tika 文件和 Tesseract 文件。CMake 会在关键 Tika/Tesseract 文件缺失时主动停止构建。

### 12.7 Release 能启动但模型加载失败

确认整个 Release 目录均被复制，而不是只复制 EXE，并检查：

- `data/flutter_assets/assets/bert_model/`；
- `data/flutter_assets/assets/mobileclip_model/`；
- `blobs/libtensorflowlite_c-win.dll`；
- DLL 架构是否为 x64；
- 安全软件是否隔离了 DLL。

### 12.8 NVDA 异常或控件不朗读

1. 使用最新 Release 复测；
2. 检查是否重新引入冲突或重复的 `Semantics`；
3. 检查自定义控件的标签、值和操作；
4. 运行 `test/widget_test.dart`；
5. 使用真实 NVDA 验证键盘焦点和朗读；
6. 查阅 `docs/nvda_windows_axtree_issue_report_CN.md`。

## 13. 安全、隐私与合规

- ChromaDB 和 Tika 应仅通过本机回环地址访问；
- 不要将 8000 或 9998 端口开放到公共网络；
- `chroma_data` 可能包含文本片段、本地路径和向量，应按敏感本地数据保护；
- 备份目录应使用与原文件相同或更严格的访问控制；
- 分享日志和截图前应隐藏私人文件路径；
- 删除索引不会删除原文件，删除原文件也不会自动清理旧索引；
- 对外分发前应检查第三方许可证和模型用途限制；
- MobileCLIP 模型权重目前可能仅允许非商业研究和学术使用；
- 替换 Tesseract Windows 运行时后，应保存发行来源和完整许可证。

## 14. 升级和回滚

### 14.1 升级前

1. 记录当前可用版本和运行环境；
2. 停止客户端、Tika 和 ChromaDB；
3. 备份完整 ChromaDB 数据目录；
4. 保存当前 Release、`pubspec.lock`、模型和外部工具；
5. 阅读依赖变更和许可证变化；
6. 判断是否必须重建索引。

### 14.2 升级后

1. 执行静态分析、自动化测试和 Release 构建；
2. 优先用新的测试数据目录验证，不覆盖唯一数据；
3. 完成第 10 节的人工回归；
4. 复核无障碍与开源合规材料；
5. 确认备份可以恢复后再移除旧版本。

### 14.3 回滚原则

回滚必须同时考虑应用、依赖、模型和索引格式。恢复旧客户端时，应配套恢复旧模型、外部组件和相应 ChromaDB 备份。不要用旧客户端写入已被不兼容新版本升级的数据目录。

## 15. 定期维护清单

### 每次运行或演示前

- [ ] Java 可用；
- [ ] ChromaDB 使用正确目录并通过心跳检查；
- [ ] 8000 和 9998 端口没有冲突；
- [ ] Windows Release 目录完整；
- [ ] 使用已知查询完成快速搜索检查；
- [ ] 需要 OCR 时先用示例图片预检。

### 每次代码或依赖变化后

- [ ] 执行 `flutter analyze`；
- [ ] 执行 `flutter test`；
- [ ] 构建 Windows Release；
- [ ] 验证 TXT、PDF、DOCX、JPG 和 PNG；
- [ ] 验证文本和图片检索；
- [ ] 验证键盘、文字缩放和 NVDA；
- [ ] 检查模型、DLL、Tika 和 Tesseract 的打包结果。

### 每次发布前

- [ ] 备份 ChromaDB；
- [ ] 记录版本与测试结果；
- [ ] 在干净测试机验证完整 Release；
- [ ] 附带许可证和第三方声明；
- [ ] 明确 MobileCLIP 的用途限制；
- [ ] 记录已知问题和回滚步骤。

## 16. 相关文档

- `docs/TECHNICAL_DOCUMENTATION.md`：系统架构与技术实现；
- `docs/USER_MANUAL.md`：安装与用户操作；
- `docs/accessibility_user_guide_CN.md`：无障碍功能使用；
- `docs/nvda_windows_axtree_issue_report_CN.md`：Windows NVDA 问题记录；
- `docs/THIRD_PARTY_NOTICES.md`：第三方组件清单；
- `docs/OPEN_SOURCE_COMPLIANCE_REPORT.md`：开源合规结论；
- `licenses/`：第三方许可证原文。

维护人员应先在测试环境验证任何更新，再用于正式演示或发布。涉及模型、向量维度、Tika、Tesseract、ChromaDB 数据格式或原生 DLL 的变化，应视为高风险维护，并准备完整备份和回滚方案。
