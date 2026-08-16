# 无障碍合规性验证报告

## 离线可访问多模态本地内容检索系统 (Offline Accessible Multimodal Local Content Retrieval System)

| 项目 | 详细信息 |
|---|---|
| 项目阶段 | 第 5 周 - 跨平台 UI 开发与无障碍支持 |
| 验证目标 | Flutter Windows 桌面端应用程序 |
| Flutter 版本 | 3.44.4 stable |
| 目标标准 | 符合 WCAG 2.1 Level AA 标准要求 |

## 1. 目的

本报告记录了对“离线可访问多模态本地内容检索系统”的 Flutter 用户界面所执行的无障碍合规性验证工作。

本次验证重点关注：

- 屏幕阅读器（Screen Reader）兼容性
- 纯键盘无障碍导航（Keyboard-only navigation）
- 无障碍名称（Accessible names）、角色（Roles）、状态值（Values）及状态消息通知
- 高对比度（High-contrast）视觉呈现
- 支持最高 200% 的动态文本缩放（Dynamic text scaling）
- 焦点流转顺序与全局快捷键（Focus order & Shortcuts）
- 与无障碍相关的 Widget 测试与语义（Semantics）自动化测试

本报告陈述了本系统与相关 WCAG 2.1 AA 条款的符合性，不作为正式的第三方商业无障碍认证证书。

## 2. 测试的应用模块

测试覆盖了以下核心模块与界面：

1. 文件库页面（File Library screen）
2. 搜索页面（Search screen）
3. 设置页面（Settings screen）
4. 搜索结果展示（Search result display）
5. 文件索引与管理控件（File indexing & management controls）
6. 高对比度与字号缩放控件（High-contrast & text-scaling controls）

验证中涵盖了以下交互方式：

- 鼠标操作
- 纯键盘操作
- NVDA 屏幕阅读器
- Flutter Widget 单元/集成测试
- Flutter Semantics 语义树测试

## 3. 测试环境

| 项目 | 配置说明 |
|---|---|
| 操作系统 | Microsoft Windows |
| 应用开发框架 | Flutter 3.44.4 stable |
| 屏幕阅读器 | NVDA |
| 输入交互方式 | 鼠标与物理键盘 |
| 自动化测试框架 | `flutter_test` |
| 核心测试文件 | `test/widget_test.dart` |
| 文字缩放范围 | 100% 至 200% |
| 高对比度模式 | 应用内置的高对比度深色主题 |

## 4. 自动化无障碍测试

为了使测试快速、可确定且不依赖外部资源，Flutter Widget 与 Semantics 语义测试在执行时采用轻量 Mock 检索引擎，未加载真实的大语言模型/向量嵌入模型、向量数据库或原生文件选择器。

自动化测试验证了以下内容：

- 文件库、搜索与设置页面之间的导航流转
- 文本检索与结果列表渲染展示
- 全局键盘快捷键的触发与响应
- 搜索输入框的焦点自动捕获行为
- 各页面的语义标题层级（Semantic page headings）
- 实时区域（Live-region）状态变动广播消息
- 交互控件的无障碍标签与名称
- 文字缩放控件的无障碍名称、角色、取值及操作动作
- 高对比度主题的动态切换激活
- 文本放大至 200% 时的布局自适应
- 各类设置项的交互行为
- 测试完成后语义句柄（Semantics handles）的正确销毁与清理

### 4.1 自动化测试结果

**测试结论：全部通过 (Passed)**

在完成无障碍兼容性修复后，`test/widget_test.dart` 中的所有自动化测试用例均成功通过。

## 5. 键盘无障碍测试结果

| 测试项 | 预期行为 | 结果 |
|---|---|---|
| `Alt+1` | 快速打开“文件库”页面 | 通过 (Passed) |
| `Alt+2` | 快速打开“搜索”页面 | 通过 (Passed) |
| `Alt+3` | 快速打开“设置”页面 | 通过 (Passed) |
| `Ctrl+F` | 打开“搜索”页面并自动聚焦到搜索框 | 通过 (Passed) |
| `Tab` | 焦点沿交互控件顺序向前移动 | 通过 (Passed) |
| `Shift+Tab` | 焦点沿交互控件逆向回退移动 | 通过 (Passed) |
| `Enter` 或 `Space` | 激活并触发当前处于焦点的控件 | 通过 (Passed) |
| 搜索提交 | 纯键盘操作触发检索，无需鼠标介入 | 通过 (Passed) |
| 高对比度设置 | 使用纯键盘切换开关状态 | 通过 (Passed) |
| 文字缩放调节 | 通过键盘按钮增大或减小字号 | 通过 (Passed) |
| 焦点陷阱检测 (Keyboard trap) | 焦点均能正常移入和移出所有测试控件，无死锁陷阱 | 通过 (Passed) |

本应用均采用组合键修饰符（Modifier-based shortcuts），有效避免了与日常普通文本输入的按键冲突风险。

## 6. 屏幕阅读器验证

使用 NVDA 对 Windows 桌面端构建版本进行了实际朗读与无障碍交互测试。

重点检查了以下内容的朗读表现：

- 页面层级标题
- 导航目标项
- 搜索输入框及占位提示
- 搜索执行按钮及操作
- 检索状态动态更新播报
- 搜索结果列表项内容
- 高对比度模式切换开关
- 文字大小调节组件
- 文件管理与索引操作控件

### 6.1 屏幕阅读器测试结论

**测试结论：完成兼容性修复后全部通过 (Passed after compatibility fix)**

在移除原生 Flutter `Slider` 控件并换用无障碍重构方案后，NVDA 能够清晰、稳定且连贯地朗读应用中的所有静态内容和交互式控件。

最终重构的文字缩放控件向无障碍辅助技术暴露了：

- 标签名称：`文字缩放比例`
- 当前读数：如 `100%`、`125%` 等
- 增加值动作（Increase action）
- 减小值动作（Decrease action）
- 独立的键盘无障碍操作按钮：`减小文字` 与 `增大文字`

搜索及文件库的状态变更信息均配置了实时区域（Live-region）语义，保证重要状态变化能够第一时间被辅助技术捕捉并主动朗读给用户。

## 7. Windows AXTree 兼容性问题与修复

在进行 NVDA 联调测试初期，Windows 构建版本曾触发过类似如下的错误日志：

```text
Failed to update ui::AXTree
N will not be in the tree and is not the new root
```

发生该问题时，NVDA 仅能朗读部分静态文字，而无法稳定识别和朗读可交互的 UI 组件。

经排查，该问题源于 Flutter Windows 引擎已知的无障碍树更新缺陷（涉及原生 `Slider`、`OverlayPortal` 与 Windows 无障碍 UI 树同步冲突）。

原生的 Slider 滑块控件被替换为如下组合架构：

- 语义化滑块表示（Semantic slider representation）
- 用于直观视觉呈现的 `LinearProgressIndicator` 进度条
- 明确的“增大文字”和“减小文字”按钮
- 显式声明的当前值、增加后取值与减小后取值的语义属性

完成替换重构后：

- 测试全流程中不再产生 AXTree 报错
- NVDA 能够完全正常且准确地朗读应用控件
- 纯键盘操控体验保持完整顺畅
- 文字缩放功能保持支持 100% 至 200%（以 25% 为步进调节）

相关 Flutter 官方 Issue 追踪：

- [Windows ListView and Tooltip AXTree issue](https://github.com/flutter/flutter/issues/182444)
- [Windows Slider orphan semantics node issue](https://github.com/flutter/flutter/issues/190357)

技术专项排查文档中对此问题进行了更为详尽的记录。

## 8. 视觉无障碍测试结果

### 8.1 高对比度模式

应用内置了专用的高对比度模式，具备以下视觉特征：

- 纯黑高对比度背景
- 纯白高清晰度前景色文字
- 亮黄色重点强调色与聚焦指示
- 轮廓鲜明的交互控件
- 视觉辨识度极高的选中导航状态

**测试结论：在测试的 Windows 界面下测试通过 (Passed)**

### 8.2 动态文字缩放

应用支持以下字号比例切换：

- 100%（标准）
- 125%
- 150%
- 175%
- 200%（最大）

自动化测试与视觉测试确认，在 200% 缩放下，应用在预设窗口尺寸内渲染正常，未发生任何组件溢出（Overflow）或 Flutter 布局异常（Layout exception）。

**测试结论：测试通过 (Passed)**

### 8.3 状态信息无障碍呈现

搜索进度与文件索引状态消息均直接以可视文本展示，并同步暴露给无障碍实时区域（Live-region）。

因此，系统的状态传达完全不单一依赖颜色区分，保证色觉障碍用户能无障碍获取状态。

**测试结论：测试通过 (Passed)**

## 9. WCAG 2.1 AA 标准符合性对照表

| WCAG 准则条款 | 核心标准要求 | 系统实现方式与验证依据 | 状态 |
|---|---|---|---|
| 1.1.1 非文本内容 (Non-text Content) | 所有非文本控件必须提供等效文本替代 | 交互图标均配备文字标签或语义控件名称 | 符合 (Aligned) |
| 1.3.1 信息与层级关系 (Info and Relationships) | 界面结构与关系必须能够被程序化识别 | 提供明确的语义标题、控件角色、标签和实时通知区域 | 符合 (Aligned) |
| 1.4.1 颜色使用 (Use of Colour) | 颜色不得作为传达信息的唯一视觉手段 | 状态与选中指示均结合了文字说明、专用图标或控件状态 | 符合 (Aligned) |
| 1.4.3 对比度 (Contrast) | 文本必须具备充足的视觉对比度 | 标准主题与专用高对比度主题均通过了视觉检查 | 部分验证 (Partially verified) |
| 1.4.4 调整文本大小 (Resize Text) | 文本必须支持无损放大至 200% | 系统内置支持 100% 至 200% 的动态缩放，布局不崩坏 | 符合 (Aligned) |
| 1.4.11 非文本对比度 (Non-text Contrast) | 控件与焦点指示器必须保持清晰可见 | 在标准与高对比度模式下均对控件可见性进行了校验 | 部分验证 (Partially verified) |
| 2.1.1 键盘操作 (Keyboard) | 所有交互功能必须可通过键盘完成 | 覆盖 Tab 导航、激活按键、快捷键与字号调节按钮测试 | 符合 (Aligned) |
| 2.1.2 无键盘陷阱 (No Keyboard Trap) | 键盘焦点不得被任何组件困住 | 验证了所有控件的正向与反向焦点流转移出机制 | 符合 (Aligned) |
| 2.1.4 单字符快捷键 (Character Key Shortcuts) | 单字符快捷键必须可控或避免使用 | 应用快捷键均采用 Alt 或 Ctrl 组合修饰键 | 符合 (Aligned) |
| 2.4.3 焦点顺序 (Focus Order) | 键盘焦点流转顺序必须符合逻辑 | 键盘遍历完全遵循界面的视觉呈现顺序流转 | 符合 (Aligned) |
| 2.4.6 标题与标签 (Headings and Labels) | 标题与标签必须准确描述其目的 | 各页面与控件均采用清晰明确的中文描述标签 | 符合 (Aligned) |
| 2.4.7 焦点可见 (Focus Visible) | 键盘聚焦位置必须有清晰的视觉提示 | Flutter Material 控件均提供可见的外轮廓焦点反馈 | 符合 (Aligned) |
| 3.2.1 获得焦点时 (On Focus) | 仅获得焦点不得意外触发状态变更 | 仅聚焦到控件不会自动触发页面跳转或提交行为 | 符合 (Aligned) |
| 3.3.2 标签或说明 (Labels or Instructions) | 用户输入处需提供标签或明确提示 | 搜索输入框配备语义标签与示例输入指引 | 符合 (Aligned) |
| 4.1.2 名称、角色与值 (Name, Role, Value) | 控件必须向辅助技术暴露完整的无障碍信息 | 通过 Flutter Semantics 测试与 NVDA 实测核实 | 符合 (Aligned) |
| 4.1.3 状态消息 (Status Messages) | 状态变动必须可被辅助技术自动感知 | 搜索与文件库状态通知均接入了 Live-region 机制 | 符合 (Aligned) |

## 10. 评估工具适用性与局限性说明

Google Accessibility Scanner 主要专用于 Android 原生生态，而 WAVE 则主要通过浏览器 DOM 结构评估 Web 网页内容。

本报告的验证目标为 Flutter Windows 原生桌面构建版本，因此：

- 采用 NVDA 进行 Windows 桌面屏幕阅读器实测
- 采用 Flutter Semantics 自动化测试进行程序化无障碍验证
- 采用 Flutter Widget 测试进行组件交互流程验证
- 未对 Windows 可执行文件运行 Google Accessibility Scanner
- 未运行 WAVE（因本次验证目标非 Flutter Web 网页端部署）

若未来版本发布 Android 或 Web 端构建，应补充针对特定平台的专项测试：

- Android 平台使用 Accessibility Scanner 与 TalkBack
- Web 平台使用 WAVE 及主流浏览器无障碍检测插件
- macOS / iOS 平台使用 VoiceOver

## 11. 遗留风险与注意事项

当前仍存在以下局限性与注意事项：

1. Flutter Windows 无障碍支持深度依赖于 Flutter 引擎与 Windows UI Automation 底层桥接层。
2. 使用了 Overlay 浮层的部分原生 Flutter 控件可能在特定平台上存在潜在无障碍缺陷。
3. 色彩对比度尚未通过专业硬件色彩分析仪进行逐像素精确比值测定。
4. 本次验证是在既有的 Windows 测试环境下完成的，尚未覆盖所有可能的 Windows OS 补丁分支。
5. 不同版本 NVDA 与不同 Windows 系统的组合表现可能存在微小差异。

## 12. 最终评估结论

在项目范围内，所测试的 Windows Flutter 版本被评定为**符合 WCAG 2.1 Level AA 标准要求 (WCAG 2.1 AA aligned)**。

系统完整具备：

- 全流程纯键盘可访问导航
- 全局无障碍快捷键
- NVDA 屏幕阅读器完整支持
- 清晰的语义化标题与控件
- 实时状态变更语音播报（Live-region）
- 专用高对比度深色模式
- 最高 200% 的动态文本放大支持
- 完善的 Widget 与 Semantics 自动化测试覆盖

针对测试中发现的 Windows AXTree 语义树兼容性问题已成功完成专项重构与修复，修复后 NVDA 朗读与操作表现稳定顺畅。

