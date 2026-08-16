# 类型化数据（Typed Data）
* Uint8List：存储原始二进制数据（如图片、音频、文件流）。
  * 读取 .tflite 模型文件到内存中时，模型文件的二进制流就是 Uint8List。
  * 使用 PDFium 或 Flutter 的图片解码器读取图片或 PDF 页面时，得到的像素数据（RGBA）会直接存储在 Uint8List 中。
* Float32List：
  * 模型输入/输出（特征向量）：MobileCLIP 和 BERT 模型的输入图像通常需要进行归一化（像素值除以 255 并减去均值），转换后的数值是浮点数，必须存入 Float32List 送入 TFLite 推理。
  * 向量检索：模型输出的 Embedding（特征向量） 是一串浮点数，Chroma DB 和本地向量计算（计算余弦相似度）时，使用 Float32List 进行浮点数矩阵运算速度最快，能完美利用 CPU 的 SIMD 硬件加速。
* Int32List：
  * 硬件加速的最优解：现代 GPU 和 TPU 等加速硬件的底层架构对 32 位整数和 32 位浮点数（float32）的计算支持最为完善。使用 int32 可以确保在进行张量运算、内存寻址和掩码（Mask）操作时，获得最高的吞吐量和计算效率。
  * 寻址空间充足：BERT 的词表大小通常在 3万 到 10万 之间。int32 的最大值约为 21 亿，完全足以覆盖词表索引、序列长度等需求；而 int16（最大值 65535）可能在某些超大词表或长序列场景下溢出。
  * 避免过度浪费：虽然 int64 绝对安全，但对于仅仅是作为“索引”和“掩码”的数据来说，64 位显得过于庞大。使用 int64 不仅会白白增加内存占用（显存消耗翻倍），还会降低缓存命中率，拖慢整体推理速度。 
# Core Tech Stack
1. Document Parsing (文档解析): PDFium + Apache Tika
   * 具体作用： 这是数据进入系统的第一道关卡。本地原始文件（如 PDF、DOCX、JPG、PNG 等）是无法被大模型或数据库直接读取的 。
     * PDFium: 专门用于高效渲染和提取 PDF 文件中的文本与图像数据 。
     * Apache Tika： 充当“数字文件翻译官”，负责检测和提取各类文档（如 Word、TXT、HTML 等）的元数据和结构化文本内容 。
       * 元数据：文档的特征、属性或上下文的信息。系统会把这些元数据和后面生成的“语义向量”一起存入 Chroma DB 。当你在搜索框输入“查找 2026 年 5 月创建的关于预算的 PDF”时，系统就能利用元数据中的“时间”和“格式”标签，精准过滤掉非 PDF 或其他年份的文件 。
       * 结构化文本内容： 指的是去除了样式干扰、保留了排版逻辑和层次结构的纯文本正文。这些结构化文本会被切分成大小适中的“文本块（Chunks）”，经由分词器（Tokenizer）转换为数字编号后，然后送给 BERT 模型去计算语义特征向量 。保留了结构排版的数据，能让 BERT 更准确地捕捉到上下文的语义，从而大幅提升搜索的准确度 。

2. ML Inference (机器学习推理框架): TensorFlow Lite
   * 具体作用： 这是系统底层的算力引擎（硬件加速器）。
     * 由于系统要求“完全离线”且“在端侧（设备本地）运行” ，传统的云端大模型引擎无法使用。TensorFlow Lite 作为轻量化的端侧推理框架，负责在用户的本地 CPU/GPU/NPU 上高效运行优化后的 AI 模型，确保在不耗尽设备内存和电量的情况下完成计算 。
       * 端测(end-side)：用户端，指的是本地用户端。 
   * 下面是三个库在深度学习领域中(***在本项目中未使用***)
     * torch (PyTorch) —— 深度学习核心框架，底层矩阵运算工具。本质上是无数个矩阵在做极其庞大的数学加减乘除计算
       * 提供张量（Tensor）数据结构： 张量就是“超级多维数组”。PyTorch 负责把你的文本、图像全部打包成这种专门为数学计算优化过的数据块。
       * 硬件加速与算力调度： PyTorch 负责直接去压榨你电脑的硬件潜力。它能用 C++ 级别的速度驱动你的 CPU 进行高速计算；如果你有英伟达显卡，它还能一键把计算任务分发给 GPU (CUDA)。如果没有 PyTorch，你就得自己用 C 语言去写几万行底层的矩阵乘法和内存管理代码。 
     * torchvision —— PyTorch 的计算机视觉扩展包，它包含了常用的图像数据集、预训练的经典视觉模型（如 ResNet、VGG），以及极度重要的图像预处理工具。
     * transformers —— 预训练模型，无需自己去写 BERT 的几百行网络架构，直接通过 transformers 库就能在 Python 中把原始的 BERT 权重和分词器（Tokenizer）完整载入进来。
       * 一键模型封装： 它把世界上几乎所有著名的开源大模型（BERT, GPT, RoBERTa, LLaMA 等）的复杂网络结构，全部用高级代码封装好了。你只需要写一行 BertModel.from_pretrained()，它就自动帮你把 BERT 的 1.1 亿个神经元管道结构在 PyTorch 里搭建完成了。
       * 分词器（Tokenizer）： 计算机是不认得汉字和英文单词的，它只认得数字。Transformers 库里自带了配套的 Tokenizer。比如你输入 "Hello"，它负责把这个单词切开，去查谷歌官方的字典，将其变成计算机认的数字代号（比如 [7592]）。 
       * 胶水层： 它负责把 “文本” $\rightarrow$ “分词器转换” $\rightarrow$ “拉取本地权重文件” $\rightarrow$ “送入 PyTorch 进行矩阵计算” $\rightarrow$ “输出向量” 这整条长长的工业流水线，用极其简单的几行 Python API 粘合在一起。
     ```
     [上游：模型加载与解析]
     文本生态：transformers ──> 负责加载原始的 BERT 权重
     图像生态：torch + torchvision ──> 负责加载原始的 MobileCLIP 结构与图像预处理逻辑
          │
          ▼（在 Python 虚拟环境中提取出模型的数学权重）
     [中游：跨框架转换桥梁]
     通过工具（如 ONNX 或 TFLite Converter）进行算子转换
          │
          ▼（将 PyTorch/HuggingFace 模型重构并压缩）
     [下游：TensorFlow 落地执行]
     TensorFlow (Python 端) ──> 接收权重，生成优化后的 .tflite 文件
     TensorFlow Lite (Flutter 端) ──> 最终部署到 Windows，实现离线语义检索！
     ```

3. Multimodal Models (多模态模型): BERT + MobileCLIP
   * 具体作用： 这是系统的大脑，运行在 TensorFlow Lite 引擎之上，负责理解内容的含义（语义生成）。BERT和MobileCLIP这两个模型本身已经由开发者训练好了，但是由于从0开始训练需要极大算力和数据，所以利用TensorFlow lite优化这两个模型让其能够放入到低性能设备中，然后在系统运行时，通过 TensorFlow Lite（端侧推理框架） 作为引擎，去加载转换好的 .tflite 模型。
   * 当你克隆（Clone）或下载了 BERT 和 MobileCLIP 的官方 GitHub 仓库时，你下载的全部是 源代码（Python/C++ 文件）。这些代码定义了：
     * 神经网络的骨架结构（例如有多少层 Transformer，注意力机制怎么计算）。
     * 数据前处理和后处理的管道逻辑。
     * 但是，这些代码里的参数全都是随机初始化的数学变量。它就像一辆刚由工程师画好设计图纸、但在产线上还没有注入任何燃油和组装核心芯片的空壳车。它现在没有任何“知识”，无法识别任何文本或图片。
   * models/ 文件夹的资产主要分为两类：
     * 预训练权重文件（Pre-trained Weights / Checkpoints）
       * 这些文件里存放的是神经网络中几亿个矩阵微调后的精确数字（权重与偏置）。只有把这些数字加载到官方仓库的代码骨架中，模型才具备真正的“语义理解能力”。
     * 分词器词表（Tokenizer Vocabulary / vocab.txt）
       * 计算机是看不懂人类的中文或英文单词的，它只能处理数字向量。作用：以 BERT 为例，它必须配有一个 vocab.txt 静态文件（包含几万个常用词或词根的对照表）。分词器代码会读取这个文件，把你的输入文本（如 "invoice"）转换成数字编号（如 [4821]），然后再送给模型。没有这个词表，连第一步的文本输入都无法完成。
  * BERT： 负责处理文本 。它将提取出来的文章、句子转换为包含深度语义信息的“向量（Embedding）” 。768维度
    * Integrate BERT-base model for text embedding (集成 BERT 模型用于文本向量化)
      * 输入前处理与 Tokenizer 架构：
        * 在`bert_tokenizer.dart`中实现了完整的纯 Dart WordPiece 分词逻辑（包含 [CLS]、[SEP]、[PAD] 特殊 Token 拼接及词表匹配）。
        * 在`bert_input.dart`中将文本构造为符合标准 BERT 规范的 input_ids、input_mask (attention_mask) 和 segment_ids (token_type_ids) 三组张量输入。
      * 句向量提取 (Sentence Embedding)：
        * 在`text_embedding_service.dart`中，模型运行后准确提取了 Output index 1 (poolerOutput)，即代表整句浓缩语义的 768 维 Dense Vector。
    * Converted for TensorFlow Lite offline CPU inference (转为 TFLite 并用于离线 CPU 推理)
      * 离线模型加载：
        * 模型文件置于本地资源 assets/models/bert.tflite，不依赖任何网络请求，实现 100% 端侧离线运行。
      * TFLite CPU 推理引擎集成：
        * 在`model_manager.dart`中使用 tflite_flutter 绑定 TensorFlow Lite 本地 C++ 底层库（Interpreter.fromAsset），在端侧 CPU 上直接执行矩阵推演 (interpreter.runForMultipleInputs)。
    * Optimize (多维度的性能与推理优化)
      * CPU 多线程并行优化：
        * 在`model_manager.dart`中显式配置了 InterpreterOptions()..threads = EmbeddingConstants.maxConcurrentInference，激活 CPU 多线程并行加速计算。
      * 序列长度剪裁优化 (Sequence Length Optimization)：
        * 在`embedding_constants.dart`中将最长序列限制为 maxSequence = 128。相较于 BERT 原始的 512 长度，由于 Self-Attention 复杂度为 $O(n^2)$，所以序列长度缩短后，计算复杂度显著降低，推理速度显著提升。
      * 高效 TypedData 内存优化：
        * 在`text_embedding_service.dart`中使用连续内存的 Float32List 代替 Dart 原生离散对象数组 List<double>，降低了指针与对象头开销，提高了 CPU L1/L2 Cache 命中率。
      * 单例模式与原生内存生命周期管理：
        * 使用 TFLiteModelManager单例在内存中持久复用模型权重，避免重复加载，同时提供了手动释放原生 C++ 内存 (close()) 的机制，防止内存泄漏。
      * 异步推理队列 (Inference Queue)：
        * 在`inference_queue.dart`中实现了任务队列与防抖，防止密集并发文本推理造成 CPU 过载或 UI 卡顿。
    ```
    在convert_bert_to_tflite.py脚本内部流程
    搭建骨架 -> 填充权重 -> 追踪生成静态图 -> 打包成 SavedModel -> TFLite 读取并压缩。
    ```
    1. 下载下面四个文件
      * config.json：原始模型结构配置，已融合进 bert.tflite
        * 网络结构定义（即 config.json 中记录的层数、隐藏层维度、注意力头数等超参数）
      * model.safetensors：原始 PyTorch 权重，已融合进 bert.tflite
        * 模型权重参数（即 model.safetensors / pytorch_model.bin 中几百MB的神经网络参数）
        * Flutter 运行时载入： Flutter 中的tflite_flutter库在调用 Interpreter.fromAsset('assets/bert_model/bert.tflite') 时，只需读取 bert.tflite 这一个文件，就可以在内存中直接恢复完整的计算图并进行神经网络推理。原始的 config.json 和 model.safetensors 已经完成了它们的历史使命。
      * tokenizer.json：Hugging Face 库配置，BertTokenizer已实现其功能
      * tokenizer_config.json：Hugging Face 库配置，BertTokenizer已实现其功能
      * vocab.txt：分词字典，文本预处理：提供`BertTokenizer`查询映射
        * BERT 模型本身只认识整数张量（如 [101, 7592, 2088, 102]），无法直接理解文本字符串。vocab.txt 是 WordPiece 分词字典，记录了文本 Token 到整数 ID 的对应关系。
    2. 使用convert_bert_to_tflite.py把Hugging face里PyTorch格式转换为Tensorflow keras模型，然后导出保存为SavedModel格式，然后使用convert转换成tflite格式。
          * 在pytorch格式转换成tensorflow keras模型的时候，执行`TFBertModel.from_pretrained()`时，TensorFlow 会在内存中按照 BERT 的架构，实例化所有的层（Embedding, Attention, Dense 等）。此时，一个抽象的计算图骨架已经在内存中诞生了。`from_pt=True`触发时，PyTorch 的权重被加载并赋值给这个骨架。此时，计算图有了具体的数值，但它依然是动态的（Eager Mode）。TensorFlow 会根据你提供的输入签名，真正执行一次前向传播（Trace）。在这个过程中，TensorFlow 会记录下所有的张量操作，从而生成一个完整的、静态的、可优化的计算图（Graph）
          * 将内存中追踪到的静态计算图导出，保存为 Protocol Buffer 格式的文件（即 saved_model.pb）。将内存中加载好的 TensorFlow 权重，保存为二进制检查点文件（放在 variables/ 目录下）。记录模型的“API 接口”（输入输出张量的名称、形状、数据类型），让外部程序知道如何调用这个模型。如果模型有词表等附属文件，也会一并打包。
          * 从keras模型保存为savedmodel格式的这个过程中，剔除了一些无关的文件，比如Keras 模型在内存中可能还包含很多 Python 对象、动态控制流或训练专用的组件。SavedModel 剥离了所有 Python 代码，只保留了纯粹的数学计算图（saved_model.pb）和权重。TFLite Converter 读取这个 .pb 文件后，才能对其进行算子融合、量化等极底层的优化，最终生成 .tflite 文件。
    3. 最后剩下bert.tflite和vocab.txt文件
  --------------------------------------------------
  * MobileCLIP： 负责处理图像（照片、截图）。它是一种轻量级视觉-语言模型，能将图片转化为与文本在同一维度空间相互关联的向量 。通过它，系统能实现“用文字搜图片”或“用图片搜图片” 。512维度
     * Integrate MobileCLIP model for lightweight image embedding (集成 MobileCLIP 模型用于轻量级图像向量化)
       * 模型引入与端侧资源化：
         * 在`pubspec.yaml`中声明引入了轻量级多模态视觉模型`assets/models/mobileclip.tflite`。
       * 图像特征向量提取服务：
         * 在`image_embedding_service.dart`的`generateImageEmbedding(Uint8List imageBytes)`方法中，通过 TFLite 解释器直接运行模型，提取出包含图像语义信息的 512 维 Dense Vector（Float32List(512)）。
     * Optimized for end-side execution (针对端侧/移动端执行的优化)，针对 MobileCLIP 模型在端侧设备上的运行，代码在预处理、内存分配、计算调度等多个层面上实施了优化：
       * 轻量化预处理与维度统一 (ImagePreprocessor)：
         * 在`image_preprocessor.dart`中：
           * 自动解码与等比降采样：将输入的原始图片字节（PNG/JPG等）自动解码并强缩放为 224×224 尺寸 (img.copyResize)，显著降低大幅面原图输入给神经网络带来的内存和计算压力。
           * RGB 归一化：将 [0, 255] 像素值归一化至 [0.0, 1.0] 浮点数，适配 TFLite 模型的标准输入要求。
           * 张量塑造：构建符合端侧模型 Batch 要求的标准 [1, 224, 224, 3] 4 维 float32 张量。
       * Dart 堆内存定长分配优化 (growable: false)：
         * 在构造 1×224×224×3 张量时，代码全流程指定了 growable: false。相比可变长列表，定长 List 在 Dart VM 内部有专门的连续内存优化，消除了动态扩容时的内存分配与垃圾回收 (GC) 抖动。
       * CPU 多线程加速与离线运行 (TFLiteModelManager)：
         * 在`model_manager.dart`中，给 MobileCLIP 模型同样开启了 InterpreterOptions()..threads = EmbeddingConstants.maxConcurrentInference，激活多核 CPU 线程并行加速推理。
         * 依赖底层的 C++ TFLite Native 动态库，无需网络依赖，100% 本地离线高效推演。
       * 连续内存输出 (Float32List)：
         * 模型输出使用 TypedData Float32List.fromList(...) 包装，提供连续的内存存储，大幅提升 CPU 缓存（L1/L2 Cache）命中率，同时减少 Dart 对象的指针头开销。
       * 非阻塞异步推理队列 (InferenceQueue)：
         * 将包括图像向量化在内的耗时计算解耦至`inference_queue.dart`异步队列中管理，避免在批量扫描/解析大批图片时造成 Flutter UI 界面卡顿。
      * 在`mobileclip_export_tflite.py`文件中采用多步中间件转换管线（Multi-stage Pipeline）方法去转换
    $$\text{PyTorch} \longrightarrow \text{ONNX} \longrightarrow \text{TensorFlow (SavedModel)} \longrightarrow \text{TFLite (Float32)}$$
      * 由于`Pytorch/ONNX`采用的`数据维度排布标准`和`TensorFlow / TFLite`不一样，所以使用`onnx2tf`工具库将NCHW标准转换成NHWC标准。
        * PyTorch / ONNX 严格遵循 NCHW 标准（Batch 数量, 通道数 Channels, 高度 Height, 宽度 Width）。例如，一张彩色图像在内存中是先排满所有红色像素，再排绿色，最后排蓝色。
        * TensorFlow / TFLite 默认且原生推荐 NHWC 标准（Batch 数量, 高度 Height, 宽度 Width, 通道数 Channels）。在内存中，它是将每一个像素点的红、绿、蓝三个通道紧挨着排列。 
      * 步骤 1：模块剥离与静态图追踪 (PyTorch $\rightarrow$ ONNX)（实现了lighting image embedding）
        * 加载`mobileclip_s0`完整模型后，根据导出目标精确定位并剥离出对应的子模块。PyTorch 模型是多个子模块堆叠而成的，脚本通过 model.image_encoder 或 model.text_encoder 将其作为独立的模型对象（代码中为 encoder 变量）提取出来，使其只包含单一模态的网络层和权重，从而实现 lighting embedding。随后传入对应形状的虚拟张量（Dummy Tensor），利用 torch.onnx.export 追踪前向传播路径：
          * Image Encoder：传入$1 \times 3 \times 224 \times 224$ 的浮点张量，固化端侧固定分辨率输入，省去动态转换开销。
          * Text Encoder：传入$1 \times 77$ 的 int32 张量（而非默认的 int64），从源头减少后续 ArgMax/Gather 相关算子的类型分歧。
        * GELU → Tanh 近似替换（双编码器通用）：将所有精确 GELU 激活函数替换为 tanh 近似版本。精确 GELU 在 ONNX 中会产生 Erf 算子，转换为 TFLite 时会退化为 FlexErf。由于本项目 Flutter TFLite 运行时仅链接轻量级内置算子解释器，加载含 Flex 算子的模型会直接抛出 Interpreter.allocateTensors 致命崩溃。替换后算子全部落在 Tanh、Mul、Add 等原生内置算子集中，确保零依赖运行。
        * ArgMax dtype 净化（Text Encoder 专属）：MobileCLIP 文本编码器通过 text.argmax(dim=-1) 提取 EOT token 表示，该操作在 int64 张量上执行时，追踪到 ONNX 后易生成类型不干净的 ArgMax 节点，进而在 onnx2tf 转换时退化为 FlexArgMax / FlexGatherNd。脚本采用双重保险策略：
          * 全局 Monkey Patch torch.argmax 与 torch.Tensor.argmax，在调用前将整型输入显式 cast 为 int32；
          * 对 mobileclip 包源码中形如 .argmax(dim=-1) 的 EOT 索引写法进行正则替换，从源头保证 ONNX 图中 ArgMax 节点输入类型干净规范。
        * 按需抽离：本地设备处理图片检索时只需视觉编码器，处理文本查询时只需文本编码器。按模态剥离可极大瘦身单模型体积，适配端侧存储限制。 
      * 步骤 2：ONNX 算子集协商与图优化
        * onnx2tf 离线与安全补丁：新版 onnx2tf 转换时默认发起网络请求下载 MS-COCO 验证集图片做逐层校验，在离线/受限环境下会下载回 HTML 错误页，导致 np.load() 解析时抛出 _pickle.UnpicklingError。通过 patch_onnx2tf_source_code() 动态入侵其内部源码：
          * 修复 numpy allow_pickle=False 限制，避免加载含 Pickle 对象的本地缓存时直接崩溃；
          * 在下载函数头部注入 return np.random.rand(...)，斩断联网逻辑，使离线环境瞬间返回本地模拟矩阵。
        * 算子集版本：导出时指定 opset_version=17。新版 PyTorch 导出器在低 opset 下容易出现追踪降级失败，opset 17 配合前置的 GELU→tanh 替换及 ArgMax int32 净化，能在保证导出成功率的同时确保算子落在 TFLite Builtin 支持范围内。
        * ONNX 图校验（分模态差异化）：导出后立即加载 ONNX 图进行预检：
          * 通用检查：扫描是否存在残留 Erf 节点，确认 GELU 替换生效；
          * Text Encoder 专属检查：额外扫描 Arange、Trilu、NonZero、Where、TopK 等高风险算子，并逐个打印 ArgMax 节点的输入类型声明，提前暴露可能导致 Flex 退化的隐患。
        * 图优化策略：完全依赖 torch.onnx.export 内置的 do_constant_folding=True 常量折叠及 onnx2tf 转换过程中的自动图简化，未引入额外第三方优化库，保持离线环境纯净。
      * 步骤 3：跨框架转译与全量转换 (ONNX $\rightarrow$ TensorFlow)
        * onnx2tf 工具在解析 ONNX 模型的权重（Weights）和偏置（Bias）时，会先把它们从 ONNX 张量格式读取出来，转化为内存中的 numpy 矩阵，然后通过 numpy 进行维度重组和排列（比如从 PyTorch/ONNX 常用的 NCHW 格式调整为 TensorFlow 喜欢的 NHWC 格式），最后再写入 TensorFlow 的计算图中。
        * 转换参数策略：启动 onnx2tf 时，优先注入 --disable_flex_ops 参数强制禁止 Flex 算子退化，并内置版本检测与回退机制；刻意避免使用 -cotof 等可能触发联网校验的参数，确保全流程离线可用。图优化完全依赖 PyTorch 导出时的 do_constant_folding=True 常量折叠及 onnx2tf 内置简化能力，未引入额外第三方库。
        * 利用 onnx2tf 核心工具，将 ONNX 的符号计算图无损地翻译为 TensorFlow 的数据流图，并在本地生成一个标准的 SavedModel 文件夹。
        * 因为 TensorFlow 模型和 PyTorch 模型在底层的数据排布（NCHW 与 NHWC）和算子实现上存在根本差异。onnx2tf 扮演了“翻译官”的角色，为最后一步生成 TFLite 铺平了道路。
      * 步骤 4：全精度编译与 Builtin 算子校验 (TensorFlow → TFLite Float32)
        * 借助 TensorFlow 编译器将 SavedModel 转化为离线端侧专用的 .tflite 文件，保持 float32 全精度，不进行任何量化。
        * 为什么选 float32 而非 float16：本项目核心目标是 WCAG 2.1 AA 无障碍合规 + 离线 CPU 推理。MobileCLIP-S0 本身仅 ~30MB (FP32)，体积已满足端侧要求；FP16 在纯 CPU 上可能回退到 FP32 计算反而更慢，且精度损失可能导致语义检索排序偏差，影响视障用户的搜索准确性。float32 是精度、兼容性、性能的最佳平衡点。
        * Builtin 算子强制校验：转换完成后，脚本自动加载生成的 .tflite 文件，历所有算子并扫描是否存在`Flex`前缀或`CUSTOM`类型的算子。如果发现任何非原生算子（如 FlexErf、FlexArgMax 或未注册的 CUSTOM 算子），脚本会立即终止并拒绝保存模型，防止含不兼容算子的模型流入生产环境导致移动端崩溃。只有 100% Builtin 算子的模型才会被写入对应的`saved_model_image/`或`saved_model_text/`目录
        * 安全文件搬运：由于 onnx2tf 某些版本的 -o 参数解析存在 bug（可能输出到异常命名的文件夹如 b/），脚本内置了 move_tflite_to_target() 兜底机制，自动搜索并将 .tflite 文件搬运到标准输出目录，同时清理残留的异常文件夹。搬运后的文件统一重命名为 mobileclip_image.tflite / mobileclip_text.tflite，确保下游 Flutter 集成时路径可预测。
      * 最后生成负责图片模型的`mobileclip_image.tflite` 和负责文本模型的 `mobileclip_text.tflite` 两个文件，分别用于图片检索和文本检索和用文字搜索图片的功能。然后放入符合mobileclip底层的`bpe_simple_vocab_16e6.txt`分词表搭配`mobileclip_text.tflite`使用。
        * `bpe_simple_vocab_16e6.txt`需要前往`https://github.com/openai/CLIP/tree/main/clip`中找到并下载，mobileclip的官方仓库没有。因为苹果在开发 MobileCLIP 时直接动态加载了 open_clip 库自带的词表，没有在自己的仓库中重复提交 bpe_simple_vocab_16e6.txt 文件。
        * 每个模型有自己对应适配的分词表，在模型内部的一层矩阵有与正确分词表对应的词义映射，如果mobileclip_text用的是bert的vocab.txt的分词表，由于不同分词表的结构不同导致算出的embedding（特征向量）是不同的，就会导致模型内部根据不同分词表生成的embedding找到的词义与正确的词义对不上，产生偏移。此外由于bert的vocab.txt和bpe_simple_vocab_16e6.txt的切词规则与标记格式不匹配（语法规则不同）也会影响embedding结果。
        * `bpe_simple_vocab_16e6.txt`词表的每一行既是一条合并规则，也隐含定义了一个新词条。
        * 算法流程：
          * 第一步：初始状态（_applyBpe 第428-438行）
          ```Dart
          "low" → 按字符拆开 → ['l', 'o', 'w']
          最后一个字符加词尾标记 → ['l', 'o', 'w</w>']
          ```
          * 第二步：找出所有相邻对（_getPairs）
          ```Dart
          pairs = { "l o", "o w</w>" }
          ```
          * 第三步：查 _bpeRanks，找排名最小（优先级最高）的那一对
          ```Dart
          _bpeRanks["l o"]     = 0   ← 排名0，优先级最高！
          _bpeRanks["o w</w>"]  = 未定义（词表里没有这条规则，不能合并）

          → 选中 "l o"
          ```
          * 第四步：执行合并
          ```Dart
          ['l', 'o', 'w</w>']  →  ['lo', 'w</w>']
          ```
          * 第五步：循环，重新找相邻对
          ```Dart
          pairs = { "lo w</w>" }
          _bpeRanks["lo w</w>"] = 1   ← 找到了！继续合并

          → ['lo', 'w</w>']  →  ['low</w>']
          ```
          * 第六步：word.length == 1，停止循环（第522-524行）
          ```Dart
          最终结果: ["low</w>"]
          ```
          * 第七步：查 _encoder，把字符串换成ID（在 encode() 里）
          ```Dart
          _encoder["low</w>"] → 假设是 256+1 = 257
          ```
        ```python
        import open_clip
        # 直接调用 open_clip 的底层分词器
        self.tokenizer = open_clip.get_tokenizer("ViT-B-16")
        ```
   
4. Vector Storage (向量数据库): Chroma DB
   * 具体作用： 这是系统的智能存储与搜索中心 。
     * 传统的数据库只能通过“关键词精确匹配”来搜索。而 Chroma DB 作为本地向量数据库，专门用来存储由 BERT 和 MobileCLIP 生成的“语义向量” 。当用户输入搜索词时，Chroma DB 会在本地进行快速的“数学距离计算”（数学相似度检索），找出意思最相近的内容，从而实现“哪怕没有完全匹配的字，也能看懂意思并搜出来”的语义搜索功能 。
   * 在retrieval层设计了两个向量空间（collections）：`bert_text_embeddings`和`mobileclip_embeddings`。
     * `bert_text_embeddings`是纯文本 - 纯文本检索（如：用文字搜 PDF 段落/文档内容），包括BERT 生成的纯文本向量。
     * `mobileclip_embeddings`跨模态 / 图文检索（如：“以文搜图”、“以图搜文”），包括MobileCLIP 生成的图片向量 + MobileCLIP 生成的文本向量。
       * 其中MobileCLIP 采用的是经典的双塔 CLIP（Contrastive Language-Image Pre-training）架构：
       ```
       [ 文本内容 ] ──> MobileCLIP Text Encoder  ──> [ 512维向量 ] ──┐
                                                                ├─> 投影映射到【同一个 512维共享空间】
       [ 图片内容 ] ──> MobileCLIP Vision Encoder ──> [ 512维向量 ] ──┘
       ```
       * CLIP架构有下面两个特点：
         * 共享语义空间（Shared Embedding Space）： MobileCLIP 的核心优势在于，它的文本编码器（Text Encoder）和图像编码器（Vision Encoder）经过对比学习训练后，把“猫的图片”和“写有‘猫’的文字”映射到了同一个 512 维数学空间中极为接近的位置。
         * “以文搜图”的数学前提： 当用户在搜索框输入“红色跑车”时，Embedding Engine 会调用`TextEmbeddingMode.mobileClip`生成一个 512 维的`mobileclip_text`查询向量。 系统拿着这个 512 维向量去`mobileclip_embeddings`集合里计算余弦相似度，就能直接把之前存入该集合的“红色跑车图片向量（`mobileclip_image`）”匹配出来！
         * 因此如果把 mobileclip_text 和 mobileclip_image 分开保存在两个不同的 Collection 里，它们就无法计算向量距离了，也就无法实现跨模态图文检索功能。
     * 因此在`lib/retrieval/models/vector_document.dart`中的枚举定义：
       * 当使用 BERT 提取文本时 → 标记为`VectorEmbeddingType.bert`→ 存入`bert_text_embeddings`。
       * 当使用 MobileCLIP 提取文本或图片时 → 都标记为`VectorEmbeddingType.mobileClip`→ 存入`mobileclip_embeddings`。
      ```dart
      enum VectorEmbeddingType {
        bert,       // 对应 768维 纯文本空间
        mobileClip, // 对应 512维 图文共享空间（包含 mobileclip_text 和 mobileclip_image）
      }
      ```
   * 在`document_indexer`中的输入句子切分流程。`chunkWordCount`= 90（带标点的空格分隔词）预留了一定的“缓冲膨胀空间”，保证在第二阶段经 BERT Tokenizer 把标点符号和子词拆开后，总 Token 数依然能够安全落入 128 的硬性截断范围之内。
    ```
      [ 原始文本 ]
        │
        ▼
      【第一阶段：DocumentIndexer 粗切分 】
      按空格切出 90 个“粗单词”（包含粘连的标点符号）
        │
        ▼
      【 第二阶段：Week 3 TextPreprocessor / BERT Tokenizer 细切分 】
      标点符号被拆独立 + 复杂词拆子词 + 加上 [CLS] 和 [SEP]
        │
        ▼
      【 最终结果 】
      90 个“粗单词”膨胀后大约转换为 100 ~ 115 个真正的 Tokens
        │
        ▼
      正好 < 128 Token 限制（安全放进 BERT 模型，无信息损失）
    ```
   * 在这一层，我实现了`embedding检索`和`关键字检索`两个检索方式。
     * Embedding 检索（向量语义检索）：
       * 原理：用 BERT 或 MobileCLIP 模型把文本/图片变成高维向量，计算它们在大脑“语义空间”中的距离。
       * 优势：
         * 懂“同义词”和“上下文”：搜 “西红柿” 能查到包含 “番茄” 的文章；搜 “手机无法开机” 能查到 “设备故障重启指南”。
         * 支持多模态（跨模态）：能够实现“用文字搜图片”、“用图片搜图片”。
       * 劣势：
         * 对“精确型号/专名/代码”极度不敏感：如果你搜一个特定订单号 “ORDER_2026_987” 或代码方法名 “onParseCompleted()”，向量模型容易把它当作模糊概念，导致真正包含这个订单号的文档反而排在后面。
         * 会发生“语义失控”：有时候你只想搜某个具体的字，它却自作聪明返回了一堆“意思相近但根本没有这个字”的文档。
     * 关键字检索（Keyword 词法检索）：
       * 原理：基于字面精确匹配（如 TF-IDF、BM25 或词频统计），计算查询词在文章里的出现次数和覆盖率。
       * 优势：
         * 100% 精确匹配：对于产品型号、代码变量名、人名、身份证号、无障碍缩写（如 WCAG），只要文章里有，必能精准命中。
         * 绝对可靠：搜什么就是什么，不会自作聪明去联想同义词。
       * 劣势：
         * 存在“词汇鸿沟（Vocabulary Mismatch）”：如果文章里写的是 “Apple”，你搜 “苹果” 就绝对搜不到。
         * 完全无法支持图片等多模态数据。
   * 在关键字检索功能中，我使用了`停用词表`，`停用词（Stop Words）`指的是语言中出现频率极高，但本身几乎不携带特定主题信息/区分度的词。
     * 在搜索引擎和文本检索中，使用停用词表有以下 4 个极其关键的原因：
       * 消除噪声，提升检索准确率（Precision）:比如`"The contract of Apple"（苹果公司的合同）`系统自动过滤或降权 the 和 of，把 100% 的注意力聚焦在 contract 和 Apple 这两个核心实体词上，搜索准确率大幅提升。
       * 符合信息论原理：“稀有词才包含高信息量”：在信息检索（Information Retrieval）中，有一个基本定律：越稀有的词，区分度越高，信息量越大；越泛滥的词，信息量越低。
       * 极大节省计算资源与存储空间（Performance Optimization）：如果为 the, of, a 等停用词建立倒排索引或计算词频矩阵，索引文件体积会膨胀 30% ~ 50%。过滤或降权停用词，可以大幅减少计算矩阵的大小，节省 CPU 遍历时间与内存占用，提升毫秒级响应速度。
       * 配合领域机制（Domain-Specific Adaptation）：在普通文章中，if 和 for 是停用词；在代码库检索中，for 和 if 则是极具代表性的语法结构。 有了停词表与配置类，系统就能根据不同的搜索场景灵活配置，做到“在普通文档里降权，在代码库里保留”。
   * 在`hybrid_retriever.dart`中，有几个设计点：
     * 双路独立并行召回与候选集并集（Two-Way Parallel Retrieval & UNION）：
       * 系统采用双路独立召回架构，而不是全盘扫描本地大文件库。
       * VectorRetriever 独立去 Chroma 向量库取`topK×5`个语义候选，KeywordRetriever 借助内存倒排索引库（KeywordIndex）O(1)独立秒级取`topK×5`个关键词候选。
       * 两路候选求并集（UNION）生成 70~90 个候选文档池，随后统一进行分数归一化与加权融合。这样既避免了全库遍历的性能衰退，又彻底杜绝了生僻代码、特定型号在向量阶段被漏检的问题。
     * 对Vector Score进行了Min-Max Normalization，因为 KeywordRetriever 算出来的得分在输出时，本身就已经天然保证在标准的[0.0,1.0]绝对区间了。$$KeywordScore=0.60\times Coverage+0.30\times squash(TF)+0.10\times PhraseBonus$$
        * $$Coverage\in[0.0,1.0]$$
        * $$squash(TF)∈[0.0,1.0] （通过 x/(1+x)平滑压缩）$$
        * $$PhraseBonus∈{0.0,1.0}$$
        * 方法最后还执行了 .clamp(0.0, 1.0)。
        * KeywordScore 本身就是一个指标绝对、范围固定的标准得分（有 0 分，也有 1 分），因此不需要重复进行 Min-Max。
     * 在 ChromaVectorStore 中，向量距离转得分使用的是$$Score=\frac{1}{distance+1}$$。 在实际检索中，这批候选集（Top 50）的向量得分可能全部分布在 [0.65,0.85]这个窄小区间里。最差的向量文档依然拥有 0.65 的保底高分。无论怎么操作，这个最差的向量文档仍然会处于较高或者中等水平，这样本来应该被遗弃的低分向量文档，依然有机会被排在前面，导致检索结果质量下降。进行 Min-Max 之后，$$NormalizedVectorScore=\frac{Score-Minimum}{Maximum-Minimum}$$
       * 这样可以将当前批次中最好的向量得分拉伸至 1.0，最差的向量得分压缩至 0.0，充分放大了局部批次内的相对优劣差距。
   * 在`document_indexer.dart`中，用`_normalizePathForId`这个方法把路径中的冒号 :、斜杠 /、反斜杠 \、空格、特殊字符全部替换成了下划线 _，并转成了小写的原因有下面几点：
     * 规避数据库和 REST API 的“非法字符崩溃”：
       * Windows 路径可能长这样：E:\My Documents\2026/08/合同 (第1版).pdf。
       * 路径中包含了冒号 :、反斜杠 \、空格、中文括号 () 等特殊字符。
       * 当 Chroma DB 或 REST 接口把这个 ID 放到 URL 路由或底层哈希索引时，未清洗的特殊字符极易导致 URL 转义错误、解析失败或数据库报错。
       * 清洗后变成纯净的 e_my_documents_2026_08_1_pdf，保证了数据库存储的绝对安全性。
     * 保证 ID 的“确定性与幂等性（Deterministic & Idempotent）”：
       * 反例（如果用随机 UUID）：如果每次建索引都随机生成一个 uuid.v4()，那么你每次重新索引同一个文件，都会产生一堆新的随机 ID，导致数据库里堆满重复垃圾。
       * 正例（基于路径生成）：同一个文件无论今天索引还是明天重新索引，算出来的 ID 永远完全相同，直接天然支持精准覆盖更新与精准删除！
   * Min-Max Normalization 的局限性：
     * 抹杀绝对语义相关性（受制于局部极值）：Min-Max 仅根据当前批次内的最大值和最小值进行放缩。若某文档在向量分支的原始分为 0.5（实际具备不错的语义相关性），但因为同批次中恰好有 0.9 的最高分，导致该文档成为批次最低分（min），被 Min-Max 强行抹杀压成 0.0。
     * 弱化双路同时命中（Found By Both）的互证优势：若某文档 B 既命中了向量又命中了关键词，在现实中往往最具可信度。但若 B 在向量分支排在末尾被压成 0.0，在关键词分支排在榜首被拉到 1.0，其最终融合分只有$$0.7\times0.0+0.3\times1.0=0.30$$，反而大幅落后于仅在单路命中、排在头部的单边文档 A：$$0.7\times1.0+0.3\times0.0=0.70$$
     * 对异常极值（Outliers）敏感：当候选集里出现一篇异常超高分的文档时，其余处于正常区间（如 0.4 ~ 0.6）的优秀文档会被集体压缩至接近 0.0 的极窄区间，导致大面积区分度失真。