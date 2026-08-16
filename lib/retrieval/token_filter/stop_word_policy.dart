import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'domain_detector.dart';
import 'stop_word_config.dart';

/// 停用词策略类，是执行词权重计算与决策的大脑，综合config和detector的结果，得到这个词在当前文件里应该拿多少分
class StopWordPolicy {
  StopWordPolicy({
    StopWordConfig config = const StopWordConfig(),
    DomainDetector domainDetector = const DomainDetector(),
  })  : _config = config,
        _domainDetector = domainDetector;

  final StopWordConfig _config;
  final DomainDetector _domainDetector;

  final Set<String> _englishStopWords = <String>{};
  final Set<String> _dynamicHighFrequencyWords = <String>{};

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  StopWordConfig get config => _config;

  /// 初始化停词表
  Future<void> initialize({
    String englishAssetPath =
    'assets/retrieval/stopwords_en.json',
  }) async {
    if (_isInitialized) {
      return;
    }

    _englishStopWords.addAll(await _loadWordList(englishAssetPath));
    _isInitialized = true;
  }

  /// 基于“领域类型”计算 Token 权重的核心方法。
  /// 输入一个词（token），根据一系列规则判断这个词在检索/搜索场景中应该被赋予多大的权重（weight）。
  /// 权重越低，说明这个词越"不重要"（比如 "the"、"a" 这种停用词），
  /// 越容易在检索时被降权或过滤；权重越高，说明这个词越重要，应该被保留并参与匹配计算。
  double getTokenWeight({
    required String token,
    RetrievalDomain domain = RetrievalDomain.general,
  }) {
    final String normalized = _normalizeToken(token);

    if (normalized.isEmpty) {
      return 0.0;
    }

    // 1. Accessibility-safe whitelist
    if (_neverFilterWords.contains(normalized)) {
      return _config.neverFilterWeight;
    }

    // 2. Code-domain important keywords
    if (domain == RetrievalDomain.code &&
        _codeImportantWords.contains(normalized)) {
      return _config.codeImportantWordWeight;
    }

    // 3. Dynamic high-frequency words
    if (_dynamicHighFrequencyWords.contains(normalized)) {
      return _config.dynamicHighFrequencyWeight;
    }

    // 4. Standard English stop words
    if (_englishStopWords.contains(normalized)) {
      return _config.baseStopWordWeight;
    }

    return _config.defaultTokenWeight;
  }

  /// 基于“文件路径”计算 Token 权重的便捷方法。
  /// 自动调用 _domainDetector.detectFromPath(sourcePath) 识别出文件所属领域（如 .dart 文件自动识别为 code 领域），
  /// 随后自动转发调用 getTokenWeight 返回权重。
  double getTokenWeightForFile({
    required String token,
    required String? sourcePath,
  }) {
    final RetrievalDomain domain = _domainDetector.detectFromPath(
      sourcePath,
    );

    return getTokenWeight(
      token: token,
      domain: domain,
    );
  }

  /// 批量更新/覆盖动态高频词库。清空现有动态高频词，并将传入的词列表逐一规范化后写入（自动排除无障碍白名单词）。
  void updateDynamicHighFrequencyWords(
      Iterable<String> words,
      ) {
    _dynamicHighFrequencyWords
      ..clear()
      ..addAll(
        words.map(_normalizeToken)
            .where(
              (String word) => word.isNotEmpty && !_neverFilterWords.contains(word),
        ),
      );
  }

  /// 单条添加动态高频词。将单个单词转换为小写并规范化后加入动态高频词集合中（若该词属于无障碍白名单则自动忽略）
  void addDynamicHighFrequencyWord(
      String word,
      ) {
    final String normalized = _normalizeToken(word);

    if (normalized.isEmpty) {
      return;
    }

    if (_neverFilterWords.contains(normalized)) {
      return;
    }

    _dynamicHighFrequencyWords.add(normalized);
  }

  /// 清空动态高频词库。清空 _dynamicHighFrequencyWords 集合里的所有词。
  void clearDynamicHighFrequencyWords() {
    _dynamicHighFrequencyWords.clear();
  }

  /// 判断一个词是否是动态高频词。检查规范化后的 token 是否存在于动态高频词集合中。
  bool isDynamicHighFrequencyWord(
      String token,
      ) {
    return _dynamicHighFrequencyWords.contains(
      _normalizeToken(token),
    );
  }

  /// 资源加载与解析工具。利用 rootBundle 读取 Asset 资源文件内容。
  /// 同时兼容 JSON 数组格式（如 ["a", "an"]）和 按行分隔文本格式（自动过滤以 # 开头的注释行），
  /// 返回清洗后的 `Set<String>` 集合。
  Future<Set<String>> _loadWordList(
      String assetPath,
      ) async {
    // 加载停词表的内容，按照每行分开
    final String content = await rootBundle.loadString(assetPath);

    final String trimmed = content.trim();

    if (trimmed.isEmpty) {
      return <String>{};
    }

    if (trimmed.startsWith('[')) {
      // 把 trimmed（去除首尾空白后的文件内容字符串）当作 JSON 文本解析，得到的结果赋值给变量 decoded
      // 因为 jsonDecode 无法在编译期知道你传入的 JSON 到底是哪种结构，它的返回类型在 Dart 的类型签名里就被声明为 dynamic
      final dynamic decoded = jsonDecode(trimmed);

      if (decoded is! List<dynamic>) {
        throw FormatException(
          'Stop word asset must contain a JSON array: '
              '$assetPath',
        );
      }

      return decoded
          // 从集合中筛选出类型是 String 的元素，其余类型的元素直接丢弃，
          // 同时把返回结果的静态类型变成 Iterable<String>
          .whereType<String>()
          // 对 Iterable<String> 中的每一个元素应用 _normalizeToken 函数，
          // 把每个原始字符串转换成"标准化"后的字符串，返回一个新的 Iterable<String>
          .map(_normalizeToken)
          .where(
            (String word) => word.isNotEmpty,
      ).toSet();
    }

    // 返回纯文本行格式：适合人工编辑、维护简单的词表，还支持注释掉#注释来给某些词写说明
    return const LineSplitter()
        .convert(content)
        .map((String line) => line.trim())
        .where(
          (String line) => line.isNotEmpty && !line.startsWith('#'),
    ).map(_normalizeToken).where(
          (String word) => word.isNotEmpty,
    ).toSet();
  }

  /// 对token进行首位空白处理，并小写化
  String _normalizeToken(
      String token,
      ) {
    return token
        .trim()
        .toLowerCase();
  }

  /// 不能被过滤掉的单词
  static const Set<String> _neverFilterWords =
  <String>{
    'accessibility',
    'accessible',
    'a11y',
    'wcag',
    'screen-reader',
    'screenreader',
    'voiceover',
    'talkback',
    'tts',
    'text-to-speech',
    'aria',
    'alt',
    'alt-text',
    'contrast',
    'keyboard',
    'focus',
    'caption',
    'captions',
    'subtitle',
    'subtitles',
    'transcript',
  };

  /// 对于代码来说很重要不能被过滤的单词
  static const Set<String> _codeImportantWords =
  <String>{
    'if',
    'else',
    'for',
    'while',
    'switch',
    'case',
    'break',
    'continue',
    'return',
    'null',
    'true',
    'false',
    'import',
    'export',
    'class',
    'interface',
    'abstract',
    'extends',
    'implements',
    'factory',
    'const',
    'final',
    'static',
    'async',
    'await',
    'future',
    'void',
    'int',
    'double',
    'string',
    'bool',
    'list',
    'map',
    'set',
    'try',
    'catch',
    'throw',
    'json',
    'yaml',
    'xml',
    'sql',
  };
}