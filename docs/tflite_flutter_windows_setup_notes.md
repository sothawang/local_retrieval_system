# tflite_flutter 在 Windows 桌面端的原生库配置流程

## 背景：为什么 pubspec.yaml 里加了依赖还不够

`tflite_flutter` 这个 Dart 包本身只是**接口/绑定层**（通过 Dart FFI 调用底层 C API）。
它不像 Android/iOS 那样，会自动帮你把 TensorFlow Lite 的原生运行时打包进去。

- **Android**：原生 `.so` 库会随 Android 端的 aar 依赖自动下载/打包。
- **iOS**：原生库通过 CocoaPods 自动引入。
- **Windows / Linux / macOS（桌面端）**：官方明确说明"需要手动添加动态库"，因为桌面端没有官方预编译产物随包发布。

所以你在 Windows 上跑起来，必须自己拿到一份 **`libtensorflowlite_c-win.dll`**（本质是 TensorFlow Lite C API 编译出的 `tensorflowlite_c.dll`，改了个名字），放进项目里，并且让 CMake 在打包 exe 的时候把这个 dll 一起拷贝进最终的安装目录。

---

## 完整流程梳理

### 第 1 步：获取 Windows 版的 tflite C 动态库

有两种途径，**你当时大概率用的是第二种（下载现成的）**，因为自己用 Bazel 编译 TensorFlow 在 Windows 上非常繁琐：

**方式 A：自己编译（麻烦，通常不推荐）**
```bash
git clone https://github.com/tensorflow/tensorflow.git
cd tensorflow
git checkout r2.5   # 或其他你需要的版本
bazel build -c opt //tensorflow/lite/c:tensorflowlite_c --define tflite_with_xnnpack=true
```
编译产物在 `bazel-bin/tensorflow/lite/c/tensorflowlite_c.dll`，需要重命名为 `libtensorflowlite_c-win.dll`。

**方式 B：直接下载预编译好的 dll（推荐，也是你大概率做过的）**

社区维护了一个专门发布 Windows 预编译 TFLite C 库的仓库：
- 仓库：`ValYouW/tflite-dist`
- Releases 页面：https://github.com/ValYouW/tflite-dist/releases

下载后会得到类似这样的结构：
```
tflite-dist/
├─ include/tensorflow/lite/c/   （头文件，桌面端 FFI 用不太上，主要给 C++ 项目用）
└─ libs/windows_x86_64/
   ├─ tensorflowlite_c.dll
   └─ tensorflowlite_c.dll.if.lib
```
你需要的就是 `tensorflowlite_c.dll`，把它**重命名**为 `libtensorflowlite_c-win.dll`。

---

### 第 2 步：把 dll 放进项目的 `blobs` 目录

按 Flutter 官方桌面动态库加载规范，在项目**根目录**（和 `lib/`、`windows/` 同级）下：

```
<project_root>/
├─ blobs/
│  └─ libtensorflowlite_c-win.dll   ← 放这里
├─ lib/
├─ windows/
│  └─ CMakeLists.txt   ← 需要修改这个文件
└─ pubspec.yaml
```

---

### 第 3 步：修改 `windows/CMakeLists.txt`

这一步就是让 Flutter 在 `flutter build windows` 时，把 `blobs/` 里的 dll 一并拷贝到最终发布包的 `blobs/` 子目录下（保证运行时能被加载到）。这正是你记得加过的那段：

```cmake
# 打包 tflite_flutter 所需的原生 DLL
if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../blobs/libtensorflowlite_c-win.dll")
  install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/../blobs/libtensorflowlite_c-win.dll"
          DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/blobs"
          COMPONENT Runtime)
endif()
```

> 官方文档里给的是稍微不同的变量名（`${PROJECT_BUILD_DIR}` / `${INSTALL_BUNDLE_DATA_DIR}`），你用的是 `CMAKE_CURRENT_SOURCE_DIR` + `INSTALL_BUNDLE_LIB_DIR`，效果等价，只是变量来源不同（可能是参考了不同版本的文档或社区帖子）。核心逻辑一致：**存在就 install 到 bundle 里的 `blobs/` 子目录**。

---

### 第 4 步：Dart 侧确认能正确加载

`tflite_flutter` 在桌面端默认会去当前可执行文件目录下的 `blobs/` 找动态库，一般不需要额外指定路径，直接：

```dart
import 'package:tflite_flutter/tflite_flutter.dart';

final interpreter = await Interpreter.fromAsset('assets/bert.tflite');
```

如果加载失败（常见报错是找不到 dll 或符号缺失），排查顺序：
1. 确认 `flutter build windows` 之后，`build/windows/x64/runner/Release/blobs/` 下**确实生成了** `libtensorflowlite_c-win.dll`（说明 CMake 那段生效了）。
2. 确认 dll 的位数（x64）和 Flutter Windows 构建目标一致。
3. 确认 dll 版本和你 `tflite_flutter` 包版本（`^0.12.1`）在 API 层面兼容——包版本升级有时会要求更新的 TFLite C API 符号，旧 dll 可能缺函数报错。

---

## 关于你的 BERT 转换脚本和这套流程的衔接

你之前的 `convert_bert_to_tflite.py` 产出的是 `bert.tflite`（模型文件本身），这个和 `libtensorflowlite_c-win.dll`（运行时/推理引擎）是**两个独立但配套的东西**：

| 文件 | 作用 | 存放位置 |
|---|---|---|
| `bert.tflite` | 模型权重 + 计算图，"要跑什么" | `assets/` 目录，随 Flutter 应用打包 |
| `libtensorflowlite_c-win.dll` | TFLite 的 C 推理引擎，"用什么跑" | `blobs/` 目录，由 CMake 安装到发布包 |

两者缺一不可：没有 dll，`Interpreter.fromAsset()` 会在运行时直接加载失败；没有正确转换的 `.tflite`，dll 加载没问题但推理会报输入/算子不支持的错误

---

## 参考链接

- tflite_flutter 官方文档（桌面端动态库添加说明）：https://pub.dev/documentation/tflite_flutter/latest/
- tensorflow/flutter-tflite 官方仓库：https://github.com/tensorflow/flutter-tflite
- Windows 预编译 TFLite C 库下载源：https://github.com/ValYouW/tflite-dist/releases
- Flutter 官方桌面动态库加载指南（Step 1&2）：https://docs.flutter.dev/platform-integration/windows/building
