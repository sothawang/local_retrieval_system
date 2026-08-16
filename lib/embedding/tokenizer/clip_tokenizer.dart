import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:local_retrieval_system/embedding/constants/embedding_constants.dart';

/// OpenCLIP-compatible Byte Pair Encoding tokenizer.
///
/// Used by MobileCLIP-S0 text encoder.
///
/// Input:
///   String
///
/// Output:
///   Int32List with shape [77]
///
/// Token layout:
///   [SOT, token1, token2, ..., EOT, PAD, PAD, ...]
//   输入文本 "A cat."
//     ↓ _cleanText()          清洗：转小写、去多余空格
// "a cat."
//     ↓ _tokenPattern 正则     按词/标点切分（不是按空格，是按 Unicode 语言规则）
// ["a", "cat", "."]
//     ↓ 对每个片段做下面3步 ↓
//
// 片段 "cat"
//     ↓ _encodeBytesToUnicode()   UTF-8字节 → 安全Unicode字符（_byteEncoder）
// "cat"（假设没有特殊字符，形式不变）
//     ↓ _applyBpe()                贪心合并（_bpeRanks 指导顺序）
// ["c", "at</w>"]  （举例）
//     ↓ 查 _encoder                token字符串 → 整数ID
// [ID_c, ID_at</w>]
class ClipTokenizer {
  ClipTokenizer._();

  static final ClipTokenizer instance = ClipTokenizer._();

  // 字节值(0-255) → Unicode字符 的映射表（字节级编码基础）
  // 使用 late 是因为它不在构造函数中初始化，而是在 initialize() 中赋值；final 保证只赋值一次。
  // 构建词表前的"字节翻译层"
  // 词表的"地基"
  // BPE 需要在字节级别切分文本（这样才能处理任意语言、emoji、乱码等），但原始字节包含 \x00、\n、\t 等控制字符，
  // 直接作为字符串 key 会导致各种解析问题。所以 OpenCLIP 设计了一个双射映射，把 256 个字节"翻译"成 256 个安全的 Unicode 字符。
  // 它是词表的前 256 个 token 的来源。
  // 没有 _byteEncoder，就无法生成词表的基础部分。同时 encode() 时也需要它来把 UTF-8 字节转为 BPE 可处理的字符串。
  // Example: "low"，UTF-8 字节是 [108, 111, 119]，经过 _byteEncoder 翻译后变成字符串 "low"
  late final Map<int, String> _byteEncoder;

  // Token字符串 → ID 的映射表（编码时用）
  // 最终产物：token → ID（这就是"分词表"）
  // _encoder 在 encode() 的最后一步使用：把合并完的 token 字符串查表转为 ID
  // _encoder["lo"]     → 256     ✅
  // _encoder["w</w>"]  → 某个ID  ✅ （词表构建时 "w</w>" 被加入了_encoder）
  final Map<String, int> _encoder = <String, int>{};

  /// Key format:
  ///   "firstToken secondToken"
  ///
  /// Value:
  ///   merge priority/rank
  // "tokenA tokenB" → 合并优先级 的映射表（BPE 合并时用）
  // 构建词表时的"合并优先级规则"，encode() 时 BPE 合并的依据
  // BPE 的核心算法是贪心合并：给定一个字符序列，反复找到"最应该被合并"的相邻对并替换。
  // "最应该"的判断标准就是 rank。没有这个表，BPE 就不知道该怎么合并。
  // _bpeRanks 在 encode() 的中间步骤使用：指导 BPE 如何合并
  // bpe_simple_vocab_16e6.txt 的每一行 "a b"
  //         │
  //         ├─→ _bpeRanks["a b"] = rank    （记录合并规则）
  //         │
  //         └─→ _encoder["ab"] = nextId     （记录合并结果作为新 token）
  // 文件第1行: "l o"
  //   → _bpeRanks["l o"] = 0        ← 记录规则：l和o可以合并，优先级最高
  //   → _encoder["lo"] = 256+0      ← 记录产物："lo"这个词的ID
  //
  // 文件第2行: "lo w"
  //   → _bpeRanks["lo w"] = 1       ← 记录规则：lo和w可以合并
  //   → _encoder["low"] = 256+1     ← 记录产物："low"这个词的ID
  final Map<String, int> _bpeRanks = <String, int>{};

  // 正则token → BPE结果列表 的缓存（性能优化关键）
  // encode() 时的"运行时加速缓存"，与词表内容无关，纯性能优化
  // 一个 Map<String, List<String>>，key 是正则分词后的原始 token（如 "playing"），
  // value 是该 token 经过 BPE 合并后的结果列表（如 ["play", "ing</w>"]）。
  // BPE 合并是一个 O(n²) 的循环操作。但在自然语言中，大量词汇会反复出现（"the", "is", "a", "to"...），
  // 每次都重新跑一遍 BPE 是巨大的浪费。缓存使得第二次及以后遇到相同 token 时 O(1) 返回。
  final Map<String, List<String>> _bpeCache = <String, List<String>>{};


  // 因为 Dart 不支持异步构造函数，必须通过手动调用 initialize() 完成异步加载，这个标志位防止在未就绪时调用 encode()。
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  int get vocabSize => _encoder.length;

  // Loads and constructs the OpenCLIP vocabulary.
  //
  // The vocabulary asset must be the decompressed text file:
  // assets/mobileclip_model/bpe_simple_vocab_16e6.txt
  // vocabPath: 分词表路径，也可以自己传入
  Future<void> initialize({
    String? vocabPath,
  }) async {
    if (_isInitialized) {
      return;
    }

    final String path = vocabPath ?? EmbeddingConstants.mobileClipVocabPath;

    // loadString方法有下面特性
    // 1. 底层调用了二进制加载，但会自动将读取到的ByteData按照UTF-8字符编码直接转换解码为String。
    // 2. 返回类型为 Future<String>，必须使用 await 接收。由于读取磁盘/打包资源涉及 I/O 操作，
    // 异步处理可以避免在加载大文件时阻塞 Flutter 的 UI 主线程造成卡顿。
    // 3. 首次加载某个 path 的资源后，Flutter 的 AssetBundle 会将解析后的字符串保存在内存缓存中。
    // 如果后续再次调用加载同一个路径，会直接从内存返回，效率极高。
    // 4. 只能读取在 pubspec.yaml 的 assets:
    // 列表中预先声明并随 App 编译打包进包体（APK/IPA）的静态文件，无法在运行期写入或修改。
    final String vocabContent = await rootBundle.loadString(path);

    // 构建字节映射表
    _byteEncoder = _bytesToUnicode();
    // 把一份纯文本的词表文件，转换成两张可供算法直接查询的哈希表（_encoder 和 _bpeRanks），
    // 没有这一步，整个 tokenizer 完全无法工作。
    _buildVocabulary(vocabContent);
    _isInitialized = true;
  }

  // Converts text into MobileCLIP/OpenCLIP token IDs.
  // 把一段任意的文本字符串，最终变成一个固定长度为77的整数数组，直接喂给 CLIP 模型。
  // text: 位置参数，必填，要编码的文本
  // maxSequenceLength：命名参数，截断长度77，可以在constants里输入不同截断长度
  // 返回值Int32List：Dart 的定长整数数组类型，专门用来跟 TFLite/ONNX 这类推理引擎对接（比普通 List<int> 内存更紧凑、效率更高）
  // 输入："A cat."
  // 输出：[49406, 320, 68, 891, 55, 49407, 0, 0, ..., 0]
  Int32List encode(
      String text, {
        int maxSequenceLength = EmbeddingConstants.mobileClipMaxSequence,
      }) {

    // 如果没调用过 initialize()（词表还没加载），直接报错，防止用空的 _encoder、_byteEncoder 去查表导致更诡异的崩溃
    if (!_isInitialized) {
      throw StateError(
        'ClipTokenizer is not initialized. '
            'Call ClipTokenizer.instance.initialize() first.',
      );
    }

    // maxSequenceLength 至少要是 2
    // 因为下面要留 1 位给 SOT（Start Of Text，句子开始标记）、
    // 1 位给 EOT（End Of Text，句子结束标记），如果连2都不到，连这两个特殊符号都放不下
    if (maxSequenceLength < 2) {
      throw ArgumentError.value(
        maxSequenceLength,
        'maxSequenceLength',
        'Sequence length must be at least 2.',
      );
    }

    // 对输入文本进行清理
    final String cleanedText = _cleanText(text);

    // 中间缓冲区，用于收集当前文本经过分词、BPE 合并、查表后得到的所有 token ID，在添加 SOT/EOT 特殊标记和填充之前。
    final List<int> contentTokenIds = <int>[];

    if (cleanedText.isNotEmpty) {
      // 返回的是一个 Iterable<RegExpMatch>，即一个惰性求值的正则匹配结果集合。
      // Iterable的作用：
      // 惰性求值：不会一次性把所有匹配结果存入内存，而是每次迭代时才计算下一个匹配
      // 节省内存：对于长文本（如 Wikipedia 文章），避免分配一个大列表
      // 代码中用 for (final match in matches) 逐个消费，正好适配惰性语义
      // 每一个 RegExpMatch 对象代表正则表达式在文本中成功匹配到的一个片段:
      // 1. match.group(0) 匹配到的完整字符串（整个正则命中的内容）
      // 2. match.start 匹配片段在原字符串中的起始索引
      // 3. match.end 匹配片段在原字符串中的结束索引（不含）
      // 4. match.groupCount 捕获组数量（此正则无捕获组，始终为 0）
      // 输入："<start_of_text>It's 100% fast!<end_of_text>"
      // 输出：["<start_of_text>", "It", "'s", "1", "0", "0", "%", "fast", "!", "<end_of_text>"]
      final Iterable<RegExpMatch> matches = _tokenPattern.allMatches(cleanedText);

      for (final RegExpMatch match in matches) {
        // group(0)返回的是"fast"
        final String? matchedText = match.group(0);

        if (matchedText == null || matchedText.isEmpty) {
          continue;
        }

        // 这一步对纯 ASCII 是恒等操作，但对非 ASCII 是必要的字节级翻译。
        // 它的存在不是为了服务 "hello"，而是为了确保 "café"、"你好"、"€100"
        // 以及所有可能的 Unicode 输入都能被正确编码为 BPE 工作空间中的字符串，并与 Python 训练端保持逐字节对齐
        // 将原始单个字符转换成符合mobileclip训练数据排布格式的新map中的对应字符内容
        // "hello" -> "hello"
        // "café" -> "cafÃ©"
        // "你好" -> "ä¸Ġå¥½"
        final String byteEncodedToken = _encodeBytesToUnicode(matchedText);

        // 合并可合并的内容
        // 输入: "unlocked"
        // 输出: ["un", "lock", "ed</w>"]
        final List<String> bpeTokens = _applyBpe(byteEncodedToken);

        // 获取输入内容中每个小分类的对应ID
        for (final String token in bpeTokens) {
          final int? tokenId = _encoder[token];
          // 这是一个理论上不应该触发、但用来兜底的安全检查
          // ——因为词表的256个基础字节token保证了任何字符串最终一定能拆解到"查得到"的粒度，
          // 所以正常情况下这个 throw 永远不会执行，除非词表本身构建错了。
          if (tokenId == null) {
            throw StateError(
              'Token "$token" does not exist in the '
                  'OpenCLIP vocabulary.',
            );
          }
          contentTokenIds.add(tokenId);
        }
      }
    }

    // 截断（防止超长）
    // maxSequenceLength - 2：总长度77，减去SOT和EOT各占1位，剩下75位才是真正能放文本内容的空间
    final int maxContentTokens = maxSequenceLength - 2;
    final List<int> truncatedTokenIds =
    contentTokenIds.length > maxContentTokens
        ? contentTokenIds.sublist(0, maxContentTokens)
        : contentTokenIds;

    // 拼装最终数组
    // 下标:   0      1     2    3     4      5    6   ... 76
    // 内容: [49406, 320,  68, 891, 49407,   0,   0,  ...  0]
    //        └SOT┘  └── 内容 ──┘  └EOT┘   └── PAD(自动补0) ──┘
    // Int32List(maxSequenceLength) 创建时会自动全部填 0（Dart 定长数值数组的默认行为），
    // 所以代码里根本不需要手写"填充PAD"的循环——那些没被赋值的位置天然就是 0，
    // 而 0 恰好就是 CLIP 里 PAD（padding）token 的ID，代码最后那行注释也点明了这一点。
    final Int32List output = Int32List(maxSequenceLength);
    output[0] = EmbeddingConstants.clipSotTokenId;
    for (int i = 0; i < truncatedTokenIds.length; i++) {
      output[i + 1] = truncatedTokenIds[i];
    }
    // EOT 的位置是动态计算的：truncatedTokenIds.length + 1，
    // 因为不同句子长度不同，EOT该放在第几位是不固定的，必须根据实际内容长度算出来紧跟在内容后面。
    output[truncatedTokenIds.length + 1] = EmbeddingConstants.clipEotTokenId;

    return output;
  }

  /// Produces the exact interpreter input shape:
  ///
  /// [1, 77]
  // 因为 TFLite/ONNX 这类推理引擎的输入通常要求带上 batch 维度
  // （哪怕只推理一条文本，也要写成"batch size = 1"的形式）。
  // 模型期望的输入张量形状是 [1, 77]（1个样本 × 77个token），而不是单纯的一维 [77]。
  // 这是模型接口层的适配，不涉及 tokenizer 算法本身。
  List<List<int>> encodeForInterpreter(
      String text, {
        int maxSequenceLength =
            EmbeddingConstants.mobileClipMaxSequence,
      }) {
    // 拿到长度77的 Int32List
    final Int32List tokenIds = encode(
      text,
      maxSequenceLength: maxSequenceLength,
    );

    return <List<int>>[
      tokenIds.toList(growable: false),
    ];
  }

  // 从文本文件"重建"出完整词表
  // buildVocabulary是把纯文本词表文件，转换成两张真正驱动分词算法的哈希表（_encoder 负责"最终查ID"，_bpeRanks 负责"合并优先级"）
  // clear() 清空三张表
  //    ↓
  // 重新填充 _encoder / _bpeRanks
  //    ↓
  // _validateVocabulary() 检查是否正确
  //    ↓
  // 正确 → _isInitialized = true
  // 错误 → throw，中断
  void _buildVocabulary(String vocabContent) {
    // Map 的赋值是"有就覆盖，没有就新增"，不会自动清空旧数据。
    // 如果两次构建出的词表内容不完全一样（比如换了一份词表文件），旧词表里有但新词表里没有的 key，
    // 会残留在 _encoder 里，造成一个"新旧词表混杂"的脏状态——比如某个 token 明明在新词表里已经不存在了，
    // 但因为没被清空，查询时依然能查到一个过时的、错误的 ID。
    _encoder.clear();
    _bpeRanks.clear();
    // 如果换了一份新词表（_bpeRanks 变了），但 _bpeCache 里还留着用旧 _bpeRanks 算出来的旧结果，
    // 那么 _applyBpe 会直接命中缓存，返回一个基于旧规则算出的错误结果，而完全不会走新的合并逻辑
    _bpeCache.clear();

    // 把txt文件内容按照row的格式进行分开放入List中
    // u n
    // l o
    // c k
    // ['u n', 'l o', 'c k']
    final List<String> allLines = const LineSplitter().convert(vocabContent);
    if (allLines.isEmpty) {
      throw const FormatException(
        'MobileCLIP BPE vocabulary file is empty.',
      );
    }

    /*
     * OpenCLIP Python implementation:
     *
     * merges = gzip.open(bpe_path)
     *     .read()
     *     .decode("utf-8")
     *     .split('\n')
     *
     * merges = merges[1:49152-256-2+1]
     *
     * This produces exactly 48,894 merge rules.
     */
    final List<List<String>> merges = <List<String>>[];
    // 因为第一行是版本号，所以跳过从第二行开始
    for (int i = 1; i < allLines.length; i++) {
      // 只取前 48,894 条规则
      // 词表文件里虽然有 26万多行，但只有前 48,894 条会被真正用作合并规则，后面的行会被忽略（break 掉）。
      if (merges.length >= EmbeddingConstants.clipMergeCount) {
        break;
      }

      final String line = allLines[i].trim();
      // # 被用作注释符号或元数据/版本标记。所以跳过
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      // 把每一行的内容按照空格分开
      // u n
      // ['u', 'n']
      final List<String> parts = line.split(RegExp(r'\s+'));
      // BPE（字节对编码）的物理本质是二元合并（Binary Merge），
      // 即一次只能且必须合并 2 个符号（A + B -> AB）。
      if (parts.length != 2) {
        continue;
      }
      // 把['u', 'n']作为一个整体传入merges中
      merges.add(<String>[
        parts[0],
        parts[1],
      ]);
    }

    if (merges.length != EmbeddingConstants.clipMergeCount) {
      throw FormatException(
        'Invalid OpenCLIP BPE vocabulary. '
            'Expected ${EmbeddingConstants.clipMergeCount} '
            'merge rules, but found ${merges.length}.',
      );
    }

    /*
     * Official vocabulary construction:
     *
     * vocab = list(bytes_to_unicode().values()) // 256
     * vocab += [v + '</w>' for v in vocab] // 256
     * vocab += [''.join(merge) for merge in merges] // 48894
     * vocab += ['<start_of_text>', '<end_of_text>'] // 2
     */
    // 256（基础字节）+ 256（词尾版）+ 48894（合并规则产生的新token）+ 2（SOT/EOT）= 49408
    // vocabulary[0..255]     = byteVocabulary           ← 这段代码的第一部分
    // vocabulary[256..511]   = byteVocabulary + '</w>'  ← 这段代码的第二部分
    // vocabulary[512..49405] = 合并产生的子词            ← 后续循环追加
    // vocabulary[49406]      = '<|startoftext|>'         ← 后续追加
    // vocabulary[49407]      = '<|endoftext|>'           ← 后续追加
    // 必须保持 OpenCLIP bytes_to_unicode() 的插入顺序。
    // 不能按照 byte key 0..255 重新排序，否则 token ID 会发生偏移。
    // 将 _byteEncoder 映射表中的所有 value（Unicode 字符）按插入顺序提取为一个不可变列表，作为词表的前 256 个基础 token。
    final List<String> byteVocabulary = _byteEncoder.values.toList(growable: false,);

    final List<String> vocabulary = <String>[
      // 第0~255项，256个基础字节字符
      // ...: 把byteVocabulary这个List里的元素拿出一个一个放入vocabulary这个List中
      ...byteVocabulary,
      // 第256~511项，256个"词尾版"，也就是0-255的内容加上</w>的词尾版
      ...byteVocabulary.map((String token) => '$token</w>',),
    ];

    for (int rank = 0; rank < merges.length; rank++) {
      // 拿出每一个类似['u', 'n']的个体中的u和n
      final String first = merges[rank][0];
      final String second = merges[rank][1];

      final String pairKey = _pairKey(
        first,
        second,
      );
      // 记录"合并顺序"（用于_applyBpe）
      // 越上优先级越高
      _bpeRanks[pairKey] = rank;

      // Do not deduplicate. The vocabulary order must exactly match
      // the official OpenCLIP tokenizer.
      // 合并产生的新token，加入词表
      vocabulary.add('$first$second');
    }
    vocabulary.add(EmbeddingConstants.clipSotToken,);
    vocabulary.add(EmbeddingConstants.clipEotToken,);

    // vocabulary 是一个有序列表，_encoder 只是把"第几个位置"记录成"这个token对应的ID"。
    // _encoder["字节字符0"]       = 0
    // _encoder["字节字符1"]       = 1
    // ...
    // _encoder["字节字符255"]     = 255
    // _encoder["字节字符0</w>"]   = 256
    // ...
    // _encoder["字节字符255</w>"] = 511
    // _encoder["合并规则第0条产生的token"] = 512
    // ...
    // _encoder["<start_of_text>"]  = 49406
    // _encoder["<end_of_text>"]    = 49407
    for (int i = 0; i < vocabulary.length; i++) {
      _encoder[vocabulary[i]] = i;
    }

    _validateVocabulary();
  }

  // 构建完词表后，立刻检查结果是否符合预期，而不是等到后面调用 encode() 时才在某个随机地方出错
  void _validateVocabulary() {
    if (_encoder.length !=
        EmbeddingConstants.clipVocabSize) {
      throw StateError(
        'Invalid CLIP vocabulary size. '
            'Expected ${EmbeddingConstants.clipVocabSize}, '
            'but generated ${_encoder.length}.',
      );
    }

    final int? sotId = _encoder[EmbeddingConstants.clipSotToken];
    final int? eotId = _encoder[EmbeddingConstants.clipEotToken];

    if (sotId != EmbeddingConstants.clipSotTokenId) {
      throw StateError(
        'Invalid CLIP SOT token ID. '
            'Expected ${EmbeddingConstants.clipSotTokenId}, '
            'but generated $sotId.',
      );
    }
    if (eotId != EmbeddingConstants.clipEotTokenId) {
      throw StateError(
        'Invalid CLIP EOT token ID. '
            'Expected ${EmbeddingConstants.clipEotTokenId}, '
            'but generated $eotId.',
      );
    }
  }

  // 实现了 OpenCLIP 的 bytes_to_unicode() 函数，
  // 其核心作用是：建立一个从 0~255 每个字节值到唯一 Unicode 字符的双射映射。
  // CLIP 模型训练时，Python 端的 tokenizer 就用了完全相同的 bytes_to_unicode() 函数。
  // --模型学到的 embedding 是基于这套特定映射的。
  // 构建了一张"字节→安全字符"的翻译表，使得 BPE 能在字符串空间中操作字节级信息，
  // --同时避免控制字符带来的各种问题。它是整个 CLIP tokenizer 正确性的地基。
  // 新码点从 256 开始递增，确保不与任何已有 Latin-1 码点冲突，
  // 且分配顺序由 byte 从小到大遍历决定，保证了确定性（每次运行结果相同）
  // 在这个函数中最后得到前 188 项：安全字节 → 自身码点（恒等映射）
  // 后 68 项：不安全字节 → 256, 257, 258... 等新码点
  Map<int, String> _bytesToUnicode() {
    // 188个可打印的 Unicode 字符，可以直接"自己映射到自己"。
    // 68个被排除的字节，这些字节如果直接作为字符串内容，会导致解析错误、显示异常或语义丢失。
    // 0~31：C0 控制字符（\n, \t, \x00 等）
    // 32: 空格（会被正则分词器当作分隔符）
    // 127: DEL 控制字符
    // 128~160: C1 控制字符 + 不间断空格等
    // 173: 软连字符（不可见字符）
    final List<int> bytes = <int>[
      // 33~126，ASCII 可打印字符
      for (int i = '!'.codeUnitAt(0); i <= '~'.codeUnitAt(0); i++) i,
      // 161~172，Latin-1 补充符号
      for (int i = '¡'.codeUnitAt(0); i <= '¬'.codeUnitAt(0); i++) i,
      // 174~255，Latin-1 扩展字符
      for (int i = '®'.codeUnitAt(0); i <= 'ÿ'.codeUnitAt(0); i++) i,
    ];

    // 复制初始副本，与bytes等长，防止修改原版
    final List<int> codePoints = List<int>.from(bytes);
    int extraCodePoint = 0;
    // 穷举 0~255，找出不在安全列表中的68个字节
    for (int byte = 0; byte < 256; byte++) {
      // 这个字节不在"bytes list"中
      if (!bytes.contains(byte)) {
        bytes.add(byte); // 追加到bytes末尾
        codePoints.add(256 + extraCodePoint); // 分配一个新的Unicode码点
        extraCodePoint++;
      }
    }

    // 构建最终映射表，key 是字节值，value 是对应的 Unicode 字符。
    final Map<int, String> result = <int, String>{};
    for (int i = 0; i < bytes.length; i++) {
      // 将一个字节值映射到一个 Unicode 字符，并存入结果bytes map中。
      result[bytes[i]] = String.fromCharCode(codePoints[i]);
    }
    return result;
  }

  // 将一个分隔出的单词或者字母进行转换
  // 把每个字节一一映射到一个安全的 Unicode 字符上，让 BPE 在"看起来像普通文字"的字符串上操作，
  // 但底层语义仍然是字节级分割。
  //  输入: "hello"
  //
  //  Step 1 - utf8.encode():
  //  [104, 101, 108, 108, 111]
  //
  //  Step 2 - 逐字节查 _byteEncoder:
  //  104 → 'h'    ← 可打印ASCII，自身映射
  //  101 → 'e'
  //  108 → 'l'
  //  108 → 'l'
  //  111 → 'o'
  //
  //  输出: "hello"   ← 与输入相同（纯ASCII时恒等）
  //  输入: "café"
  //
  //  Step 1 - utf8.encode():
  //  [99, 97, 102, 195, 169]
  //  ^^^^  ^^^^
  //  é 的 UTF-8 双字节编码
  //
  //  Step 2 - 逐字节查 _byteEncoder:
  //  99  → 'c'     ← 自身映射
  //  97  → 'a'     ← 自身映射
  //  102 → 'f'     ← 自身映射
  //  195 → 'Ã'     ← 非ASCII字节，映射到 Latin-1 区字符
  //  169 → '©'     ← 同上
  //
  //  输出: "cafÃ©"   ← 5个字符对应原始5个UTF-8字节
  String _encodeBytesToUnicode(String token) {
    // 找出单个token的每一个字母的unicode在UTF-8编码下的十进制的表示结果，然后组成一个list保存起来
    // bytes = [99, 97, 102, 195, 169]
    //            c   a   f    é(195为高字节，169为低字节）
    // é 不是单字节 ASCII，UTF-8 编码为两个字节 [195, 169]。
    final List<int> bytes = utf8.encode(token);

    final StringBuffer output = StringBuffer();

    for (final int byte in bytes) {
      // _byteEncoder 是一个 256 项的双射映射（0~255 ↔ 256个唯一Unicode字符），在 _bytesToUnicode() 中构建
      // 获取byte在byteEncoder这个新map中对应的String字符
      final String? encodedCharacter = _byteEncoder[byte];

      if (encodedCharacter == null) {
        throw StateError(
          'No Unicode mapping exists for byte $byte.',
        );
      }

      output.write(encodedCharacter);
    }
    return output.toString();
  }

  // 对一个正则分词后的 token 执行 Byte-Pair Encoding (BPE) 合并。
  // 它将一个字符序列逐步合并为子词（subword）列表，使模型能处理未登录词并控制词表大小。
  // 输入： "cafÃ©"
  // 输出：如果词表中包含完整词元-["cafÃ©</w>"]
  //      如果词表未收录完整单词，只收录了子词-["caf", "Ã©</w>"]
  List<String> _applyBpe(String token) {
    // BPE 合并是 O(n²) 操作，但自然语言中大量 token 重复出现（如 "the", "is", "a"）
    // 首次计算后将结果存入 _bpeCache，后续相同 token O(1) 直接返回
    // 这是端侧推理性能的关键优化点
    final List<String>? cached = _bpeCache[token];
    if (cached != null) {
      return cached;
    }

    // 初始化字符列表 + 添加 </w> 标记
    // token: "Dart🎯"
    // characters: ['D', 'a', 'r', 't', '🎯']
    final List<String> characters =
    // 返回该字符串所有字符的 Unicode 码点（Code Points，整型数值 int 的 Iterable）。
    // 与普通按 16 位 UTF-16 单元拆分不同，runes 能正确识别占用多个字节的 Unicode 字符（例如 Emoji 或罕见字）。
    // 按完整 Unicode 码点拆分，能够准确保留每个独立字符（包括 Emoji 和复合符号）的完整性。
    // token.split('')：按 UTF-16 code units 拆分。
    // --对于 Emoji（如 🎯 或 👨‍👩‍👧）这类由代理对（Surrogate Pair）构成的字符，会被拆分成乱码片段。
    token.runes
        // String.fromCharCode: String 类的一个静态构造方法，接收一个 Unicode 整数码点，
        // --并将其转换回对应的单字符 String
        // 对 runes 序列中的每个 Unicode 整数码点，调用 String.fromCharCode 方法，
        // --将 Iterable<int> 映射为 Iterable<String>。
        .map(String.fromCharCode)
        // 将映射后的 Iterable 转化为一个 List<String>。
        // growable: true 表示创建的列表是可变的（可以继续使用 .add()、.remove() 等增删元素）。
        .toList(growable: true);

    if (characters.isEmpty) {
      return const <String>[];
    }
    // </w> 标记：附加在最后一个字符上，表示"单词结尾"
    // 例："playing" → ['p', 'l', 'a', 'y', 'i', 'n', 'g</w>']
    // 作用：让模型区分词中 "ing" 和词尾 "ing</w>"
    // ${characters.last}: 获取列表中的最后一个元素，然后将它的值转为字符串插入进来。
    characters[characters.length - 1] = '${characters.last}</w>';

    List<String> word = characters;
    // 收集所有相邻 token 对，格式为 "tokenA tokenB"
    // {'p l', 'l a', 'a y', 'y i', 'i n', 'n g</w>'}
    Set<String> pairs = _getPairs(word);

    // 如果只有一个字符（pairs 为空），无需合并，直接缓存返回
    if (pairs.isEmpty) {
      final List<String> result =
      List<String>.unmodifiable(word);

      _bpeCache[token] = result;
      return result;
    }

    // BPE 贪心合并主循环
    // 每轮执行三步：找最优对 → 全局替换 → 更新相邻对。
    while (true) {
      String? bestPair;
      int? bestRank;

      // 找 rank 最小的可合并对
      // 遍历当前所有相邻对，在 _bpeRanks 中查找优先级
      for (final String pair in pairs) {
        final int? rank = _bpeRanks[pair];
        // 该对在_bpeRanks词表中不存在，不可合并，开始下一对
        if (rank == null) {
          continue;
        }
        // 如果是循环中遇到的第一个有效字符对（此时 bestRank 还没被赋值），无条件把它暂定为当前“最佳”。
        // 寻找更小的 Rank：如果当前字符对的 rank 比之前记录的最小值还要小，说明它的合并优先级更高。
        if (bestRank == null || rank < bestRank) {
          bestRank = rank;
          bestPair = pair;
        }
      }
      // 没有可合并的对，退出while循环
      if (bestPair == null) {
        break;
      }

      // 解析最优对的左右部分
      final int separatorIndex = bestPair.indexOf(' ');
      if (separatorIndex <= 0) {
        break;
      }
      final String first = bestPair.substring(0, separatorIndex);
      final String second = bestPair.substring(separatorIndex + 1);

      // 全局替换：将 word 中所有相邻的 (first, second) 合并
      final List<String> newWord = <String>[];
      int index = 0;
      while (index < word.length) {
        // 从index开始找到下一个 first 第一次出现的位置
        final int nextFirstIndex = word.indexOf(first, index);
        // 如果没找到，那么把剩下不可能合并的内容全部加入到newWord list中然后退出循环
        if (nextFirstIndex == -1) {
          newWord.addAll(
            word.sublist(index),
          );
          break;
        }
        // 成功找到最优对的first元素，然后把从index开始到最优对first前的内容全部放入newWord
        if (nextFirstIndex > index) {
          newWord.addAll(
            word.sublist(index, nextFirstIndex),
          );
        }
        // 从发现的first开始寻找
        index = nextFirstIndex;
        // 检查 first 后面是否紧跟 second
        if (index < word.length - 1 &&
            word[index] == first &&
            word[index + 1] == second) {
          newWord.add('$first$second');
          index += 2;
        } else {
          newWord.add(word[index]);
          index++;
        }
      }
      // 最后确认下来的结果
      word = newWord;

      // 只剩一个token，无法再合并
      if (word.length == 1) {
        break;
      }
      // 重新收集相邻对，进入下一轮
      // 重新收集相邻对，就是为了让这些“新产生组合”参与下一轮检查，看看它们能否继续被进一步合并。
      pairs = _getPairs(word);
    }

    // List.unmodifiable() 创建不可变副本，防止外部修改污染缓存
    final List<String> result = List<String>.unmodifiable(word);
    _bpeCache[token] = result;
    return result;
  }

  // 提取字符串列表中所有相邻元素构成的组合（相邻对/Bigram），并去重后以集合（Set）的形式返回。
  // 输入: ['p', 'l', 'a', 'y', 'i', 'n', 'g</w>']
  // 输出： {'p l', 'l a', 'a y', 'y i', 'i n', 'n g</w>'}
  Set<String> _getPairs(List<String> word) {
    final Set<String> pairs = <String>{};

    // 如果列表长度小于 2（只有 0 或 1 个字符），无法构成任何“字符对”，直接返回空集合 pairs
    if (word.length < 2) {
      return pairs;
    }
    String previous = word.first;

    // 从第 2 个元素（索引 1）开始向后遍历到列表末尾。
    for (int i = 1; i < word.length; i++) {
      final String current = word[i];

      pairs.add(
        _pairKey(previous, current),
      );

      previous = current;
    }
    return pairs;
  }

  String _pairKey(
      String first,
      String second,
      ) {
    return '$first $second';
  }

  // 将用户输入的任意原始文本，转换为与 CLIP 模型训练时完全一致的标准化格式。
  String _cleanText(String text) {
    String cleaned = text;

    // 移除 Unicode无法识别导致的替换字符
    // \uFFFD（显示为 ``）是 UTF-8 解码失败时的占位符，代表"此处有无法识别的字节"
    // 它没有任何语义价值，且在训练数据中已被清除
    // 直接删除而非替换为空格，因为它可能出现在词中间（如 "ca\uFFFDt" → "cat"）
    cleaned = cleaned.replaceAll('\uFFFD', '');

    // HTML 实体解码，将文本中被 HTML 转义的字符还原为原始字符
    // CLIP 的训练数据（COCO Captions、Natural Questions 等）大量来自网页爬取。这些文本在存储/传输时经常被 HTML 转义。
    // Example: 原始网页内容 | 爬取后存储的文本 | 人类可读含义
    // Tom & Jerry | Tom &amp; Jerry | Tom 和 Jerry
    // <div> | &lt;div&gt; | HTML标签
    //  He said "hi" | He said &quot;hi&quot; | 他说"hi"
    // 精确匹配训练预处理：OpenCLIP 官方实现就是这 6 个固定替换，不多不少。使用通用库可能会额外解码 &copy;、&euro; 等训练时未处理的实体，反而造成不一致。
    // 性能：6 次简单字符串替换远快于正则解析完整 HTML 实体。
    // 安全性：避免通用解码器处理恶意构造的实体字符串。
    cleaned = cleaned
        // &amp; 放第一个是因为 &amp; 本身是"&"本身的转义，如果不先还原它，其他以 & 开头的实体就无法被正确匹配。
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');

    // 空白归一化与大小写统一
    cleaned = cleaned
        // 去掉前后多余的换行、空格、制表符
        .trim()
        // CLIP 词表是全小写的，大写 token 不存在于 _encoder 中
        .toLowerCase()
        // 将 \n, \t, 多空格等统一为单空格，确保正则分词结果一致
        .replaceAll(RegExp(r'\s+'), ' ');

    return cleaned;
  }

  // 用正则表达式提取出要的内容
  // 模型学到的语义是 "do" + "n't" = "不做"，而不是 "don" + "'t" 或其他切分方式。如果端侧不按同样方式切分，token 序列就对不上。
  // 's
  // is / has / 所有格
  // "cat's" → ["cat", "'s"]

  // 't
  // not
  // "don't" → ["do", "n", "'t"]

  // 're
  // are
  // "they're" → ["they", "'re"]

  // 've
  // have
  // "I've" → ["i", "'ve"]

  // 'm
  // am
  // "I'm" → ["i", "'m"]

  // 'll
  // will
  // "we'll" → ["we", "'ll"]

  // 'd
  // would / had
  // "he'd" → ["he", "'d"]

  // \p{L} 匹配任何语言的字母：拉丁、中文、日文、韩文、阿拉伯文、西里尔文等
  // 示例："hello" → ["hello"]，"你好世界" → ["你好世界"]，"café" → ["café"]
  // CLIP 是多语言模型，词表中包含大量非拉丁字符。用 [a-zA-Z] 会导致中文等被拆成单字符甚至被标点规则错误捕获。

  // \p{N} — 单个数字
  // "2024" → ["2", "0", "2", "4"]（四个独立 token）
  // 这是 OpenCLIP 的设计选择：让 BPE 在数字级别自由组合，使模型能泛化到未见过的数字组合（如年份、电话号码）

  // [^\s\p{L}\p{N}]+ — 连续标点/符号组
  // 示例："!!!" → ["!!!"]，"...," → ["...,"]，"<3" → ["<3"]
  // 标点组合（如 "!!!", "...") 往往有独立的语用含义，而数字的每一位在数值上独立，拆开更有利于 BPE 学习组合规律。
  static final RegExp _tokenPattern = RegExp(
    r"<start_of_text>|<end_of_text>|'s|'t|'re|'ve|'m|'ll|'d|\p{L}+|\p{N}|[^\s\p{L}\p{N}]+",
    caseSensitive: false,
    unicode: true,
  );
}