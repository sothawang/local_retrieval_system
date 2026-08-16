import 'package:path/path.dart' as p;

import 'stop_word_config.dart';

/// 根据输入的文件路径或文件名，自动判断该文件属于“代码/工程文件领域（code）”还是“通用文本领域（general）”。
/// 当前文件是什么类型
class DomainDetector {
  const DomainDetector();

  /// 代码扩展名匹配，如果文件名没命中特例，继续提取后缀 p.extension(sourcePath).toLowerCase()，匹配包含 30+ 种主流编程语言及配置后缀
  static const Set<String> _codeExtensions =
  <String>{
    '.dart',
    '.py',
    '.js',
    '.ts',
    '.java',
    '.kt',
    '.kts',
    '.swift',
    '.cpp',
    '.cc',
    '.cxx',
    '.c',
    '.h',
    '.hpp',
    '.cs',
    '.go',
    '.rs',
    '.php',
    '.rb',
    '.scala',
    '.sh',
    '.bash',
    '.ps1',
    '.sql',
    '.html',
    '.css',
    '.scss',
    '.xml',
    '.json',
    '.yaml',
    '.yml',
    '.toml',
    '.ini',
    '.gradle',
  };

  /// 特例文件名规则，关键工程代码配置文件。
  /// 有些关键的工程代码配置文件，其扩展名看起来像普通文本（比如 .txt），如果仅仅根据扩展名判定就会误判
  static const Set<String> _codeFileNames =
  <String>{
    'pubspec.yaml',
    'package.json',
    'tsconfig.json',
    'dockerfile',
    'makefile',
    'cmakelists.txt',
    'requirements.txt',
  };

  /// 双重校验机制（特例规则 + 扩展名规则），告诉调用者这是code还是general
  // 输入：文件绝对路径或相对路径（如 "lib/main.dart" 或 "C:/docs/requirements.txt"）。
  // 输出：返回枚举 RetrievalDomain.code 或 RetrievalDomain.general。
  RetrievalDomain detectFromPath(
      String? sourcePath,
      ) {
    if (sourcePath == null || sourcePath.trim().isEmpty) {
      return RetrievalDomain.general;
    }

    final String fileName = p.basename(sourcePath).toLowerCase();

    // 判断是不是特例
    if (_codeFileNames.contains(fileName)) {
      return RetrievalDomain.code;
    }

    // 获取后缀，转小写，然后判断是不是代码文件
    final String extension = p.extension(sourcePath).toLowerCase();
    if (_codeExtensions.contains(extension)) {
      return RetrievalDomain.code;
    }

    // 如果既不是特例也不是代码文件，就返回为普通文件
    return RetrievalDomain.general;
  }

  /// 判断是否是文件代码
  // 输入：文件路径。
  // 输出：快捷布尔值（true 代表是代码文件，false 代表普通文件）。
  bool isCodeFile(
      String? sourcePath,
      ) {
    return detectFromPath(sourcePath) == RetrievalDomain.code;
  }
}