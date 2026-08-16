import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// 按需启动本地 Apache Tika，并通过 HTTP 提取 DOCX 文本。
/// - 流程：
/// ```
/// 第一次解析 DOCX
///     ↓
/// 检查 http://127.0.0.1:9998/version
///     ↓
/// ┌───────────────┬────────────────┐
/// │ 返回 200       │ 无法连接        │
/// │ 直接复用 Tika  │ 自动启动 JAR    │
/// └───────────────┴────────────────┘
///                          ↓
///                   最多等待 30 秒
///                          ↓
///                   PUT /tika 解析文件
class TikaBridge {
  static const String _tikaUrl = 'http://127.0.0.1:9998/tika';
  // Tika Server 3.3.1 实际没有可用的 /ping 接口，因此发起get请求会返回404
  // /version 会返回200作为启动成功的证明。并且可作为轻量健康检查。
  // GET /ping      → 404 Not Found
  // GET /tika      → 200
  // GET /version   → 200，返回 Apache Tika 3.3.1
  static const String _healthUrl = 'http://127.0.0.1:9998/version';
  static const String _jarFileName = 'tika-server-standard-3.3.1.jar';
  static const String _configFileName = 'tika-config.xml';

  /// 持有并管理由当前应用拉起的 Tika Java 后台子进程
  static Process? _process;
  /// 防止多个文件同时解析时，重复发起多次启动 Tika 的操作。
  static Future<void>? _starting;

  /// 第一次解析时自动启动 Tika；后续解析复用同一个本地服务。
  /// 核心对外解析接口。用于读取指定路径的 DOCX 文件二进制数据，
  /// 发送 PUT 请求给本地 Apache Tika 服务的 /tika 端点提取纯文本内容。在发起请求前会自动确保 Tika 服务已就绪，
  /// 并在收到解析成功的 HTTP 200 响应后将结果以 UTF-8 格式解码返回。
  Future<String> extractDocxText(String filePath) async {
    await ensureTikaServiceReady();

    final response = await http
        .put(
          Uri.parse(_tikaUrl),
          headers: const <String, String>{
            // text/plain：告诉 Tika 服务端：“文档解析完成后，只要提炼出的纯文本内容，不需要带任何 HTML 标签、XML 标记或多余的排版格式。”
            // charset=UTF-8：明确要求返回的文本必须使用 UTF-8 字符编码，防止文档中的中文、特殊标点或多语言字符在传输过程中变成乱码。
            'Accept': 'text/plain; charset=UTF-8',
            'Content-Type':
                // 这是国际标准的 MIME 类型（媒体类型），专门代表 .docx 格式的 Microsoft Word 文档。
                // 告诉 Tika 服务端：“我现在在请求体（Body）里传给你的这堆二进制数据，是一份 DOCX 文档，请直接使用 DOCX 专用的解析引擎来解构它。
                'application/vnd.openxmlformats-officedocument.'
                'wordprocessingml.document',
          },
          body: await File(filePath).readAsBytes(),
        )
        .timeout(const Duration(seconds: 60));

    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'Tika 解析失败（HTTP ${response.statusCode}）：${response.body}',
      );
    }
    // Tika 处理完文档后，是通过网络将数据以**一连串原始数字（字节流，List<int>）**的形式发回给 Flutter 的。
    // 相比 response.body（可能会被某些默认设置误判编码），response.bodyBytes 拿到的是最纯粹、完全未被二次污染的原始字节流。
    // utf8.decode(...) —— 解码还原为字符串，对照 UTF-8 的字符编码字典，把那些二进制字节（比如 0xE4 0xBD 0xA0）翻译还原成对应的文字（比如中文“你”）。
    // 设置为 allowMalformed: true（容错模式）： 即使遇到了损坏或非标准的字节，它也不会抛出异常打断程序，而是会自动把坏掉的那个字节替换为占位符（``），然后继续顺畅地把后面所有正常内容完整解码出来。
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }

  /// 使用本地 Tika + Tesseract 提取 JPG/PNG 图片中的英文文本。
  Future<String> extractImageText(String filePath) async {
    final File imageFile = File(filePath);

    if (!await imageFile.exists()) {
      throw FileSystemException(
        'OCR 图片不存在。',
        filePath,
      );
    }

    final String extension = p.extension(filePath).toLowerCase();

    final String contentType;
    if (extension == '.png') {
      contentType = 'image/png';
    } else if (extension == '.jpg' || extension == '.jpeg') {
      contentType = 'image/jpeg';
    } else {
      throw UnsupportedError(
        'Tika OCR 只支持 JPG、JPEG 和 PNG：$filePath',
      );
    }

    await ensureTikaServiceReady();

    final http.Response response = await http
        .put(
      Uri.parse(_tikaUrl),
      headers: <String, String>{
        'Accept': 'text/plain; charset=UTF-8',
        'Content-Type': contentType,
        'X-Tika-OCRLanguage': 'eng',
        'X-Tika-OCRPageSegMode': '3',
        'X-Tika-OCRskipOcr': 'false',
      },
      body: await imageFile.readAsBytes(),
    )
        .timeout(const Duration(seconds: 120));

    if (response.statusCode != HttpStatus.ok) {
      throw Exception(
        'Tika OCR 失败（HTTP ${response.statusCode}）：'
            '${response.body}',
      );
    }

    return utf8
        .decode(
      response.bodyBytes,
      allowMalformed: true,
    )
        .trim();
  }


  /// 确保 Tika 可用。多个同时到达的请求只会触发一次启动。
  /// Tika 服务就绪守护方法。负责检查本地 Tika 服务是否可用，若未启动则触发自动拉起流程。
  /// 内部通过并发锁（_starting）机制进行防护，确保即使有多个文件解析请求同时发起，
  /// 也只会触发一次 Tika 服务的启动，避免多实例重复启动和端口冲突。
  Future<void> ensureTikaServiceReady() async {
    // 在做任何繁重操作之前，先向本地 http://127.0.0.1:9998/version 发一个轻量 GET 请求。
    // 如果 Tika 已经正常运行了（比如之前解析过文件，或者用户本地已启动），则直接 return 结束，整个函数耗时仅需几毫秒。
    if (await _isReady()) {
      return;
    }

    // 如果第一步检测到服务没好，但 _starting != null，说明前面已经有另一个请求正在拉起 Java 进程了（处于 0~3 秒的启动中途）。
    // 此时当前请求不需要重新走一遍启动流程，而是直接把那个正在进行的任务（existingStart）返回并一起等待。
    final existingStart = _starting;
    // 如果不是null表示tika程序正在运行
    if (existingStart != null) {
      return existingStart;
    }

    // _startAndWait()：调用底层方法去执行 java -jar 命令并开始轮询端口（注意这里没有加 await，为了立刻拿到任务句柄）。
    final start = _startAndWait();
    // _starting = start;：把这个启动任务的凭据存入全局静态变量，相当于在门上挂了个牌子：“Tika 正在启动中，后面的请排队”。
    _starting = start;
    try {
      // 正式停下来等待 Java 进程就绪。如果启动失败，这里会抛出异常。
      await start;
    } finally {
      // 校验当前全局锁中的任务是否依然是自己发起的这一个（避免多线程环境下的误清理），
      // 然后安全地把 _starting 重新重置为 null，释放锁，确保下次还能正常重新启动。
      if (identical(_starting, start)) {
        _starting = null;
      }
    }
  }

  /// Tika 进程启动与轮询等待方法（私有）。负责将 Tika 的 JAR 包准备到系统临时目录，
  /// 调用系统的 java -jar 命令在后台异步拉起子进程（监听 127.0.0.1:9998）；
  /// 启动后会以 250ms 为间隔轮询健康检查接口（最长等待 30 秒），直到服务可用或检测到进程异常退出并抛出对应错误日志。
  Future<void> _startAndWait() async {
    final String jarPath = await _resolveJarPath();

    final String configPath = p.join(
      File(jarPath).parent.path,
      _configFileName,
    );

    if (!await File(configPath).exists()) {
      throw Exception(
        '找不到 Tika OCR 配置文件：$configPath',
      );
    }
    final String? tesseractDirectory =
    await _resolveTesseractDirectory();

    final Map<String, String> processEnvironment =
    Map<String, String>.from(Platform.environment);

    if (tesseractDirectory != null) {
      final String currentPath =
          processEnvironment['PATH'] ?? '';

      final String pathSeparator =
      Platform.isWindows ? ';' : ':';

      processEnvironment['PATH'] = currentPath.isEmpty
          ? tesseractDirectory
          : '$tesseractDirectory$pathSeparator$currentPath';

      processEnvironment['TESSDATA_PREFIX'] = p.join(
        tesseractDirectory,
        'tessdata',
      );
    }
    // 准备一个内存字符串缓冲区，用于实时收集 Java 进程可能打印的错误日志（stderr），方便报错时给用户提供详细的排查信息。
    final errorOutput = StringBuffer();

    final Process process;
    try {
      // 在终端后台执行 java -jar <jarPath> --host 127.0.0.1 --port 9998。
      // runInShell: false: 直接由操作系统原生创建进程，不经过额外的 cmd/bash 壳层，提升性能且避免信号传递丢失。
      process = await Process.start(
        'java',
        <String>[
          '-jar',
          jarPath,
          '--config',
          configPath,
          '--noFork',
          '--host',
          '127.0.0.1',
          '--port',
          '9998',
        ],
        runInShell: false,
        environment: processEnvironment,
      );
    } on ProcessException catch (error) {
      // 如果用户的电脑上根本没有安装 Java，或者系统环境变量没有配置 java 命令，底层会抛出 ProcessException，这里会精准捕获并抛出清晰友好的错误提示。
      throw Exception('无法启动 Tika，请确认已安装 Java 运行时：$error');
    }

    // 将句柄赋给全局变量，方便后续退出或超时时调用 kill()。
    _process = process;
    // 操作系统为子进程分配的输出缓冲区是有限的，如果不去读取（消费）它，
    // 缓冲区一旦被 Java 的启动日志填满，整个 Java 进程就会被操作系统挂起（卡死死锁）。因此必须挂一个空监听来持续排空它。
    process.stdout.listen((_) {});
    process.stderr.transform(utf8.decoder).listen(errorOutput.write);

    int? exitCode;
    // 在后台非阻塞监听该进程的退出事件。一旦 Java 进程意外挂掉了，立即记录它的退出码 exitCode，并将 _process 重置为 null。
    unawaited(
      process.exitCode.then((int code) {
        exitCode = code;
        if (identical(_process, process)) {
          _process = null;
        }
      }),
    );

    // 循环轮询健康状态（每 250 毫秒一次）
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isReady()) {
        return; // 只要返回 200，说明 Tika 已经完全启动好了
      }
      if (exitCode != null) {
        // 如果还没就绪但进程已经退出了，说明启动报错崩溃了
        // 比如端口被占用或内存不足
        throw Exception(
          'Tika 启动失败（退出码 $exitCode）。${errorOutput.toString().trim()}',
        );
      }
      // 每隔 250 毫秒向 http://127.0.0.1:9998/version 发一次 GET 探测
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    // 如果 30 秒过去了 Tika 既没响应也没报错，说明它处于卡死状态。
    // 此时主动调用 process.kill() 强行干掉这个无响应的僵尸进程，清空全局引用，并抛出超时异常。
    process.kill();
    if (identical(_process, process)) {
      _process = null;
    }
    throw Exception(
      'Tika 启动超时；请检查 Java 环境，或确认 9998 端口未被其他程序占用。'
      '${errorOutput.toString().trim()}',
    );
  }

  /// 轻量健康检查探针（私有）。向本地 Tika 服务的 /version 接口发送超时时间为 500ms 的 GET 请求；
  /// 若能在限定时间内收到 HTTP 200 状态码则判定 Tika 服务处于存活且就绪状态，出现网络异常或超时则返回 false。
  Future<bool> _isReady() async {
    try {
      final response = await http
          .get(Uri.parse(_healthUrl))
          .timeout(const Duration(milliseconds: 500));
      return response.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  /// 查找当前平台使用的 Tesseract 目录。
  ///
  /// Windows 优先使用发布包内置版本，其次使用开发目录，
  /// 最后回退到系统安装目录。
  ///
  /// macOS 和 Linux 使用系统 PATH 中安装的 Tesseract。
  Future<String?> _resolveTesseractDirectory() async {
    if (!Platform.isWindows) {
      return null;
    }

    final String executableDirectory =
        File(Platform.resolvedExecutable).parent.path;

    final List<String> candidates = <String>[
      // Windows 正式发布目录。
      p.join(
        executableDirectory,
        'tesseract',
      ),

      // Flutter 开发和测试目录。
      p.join(
        Directory.current.path,
        'lib',
        'document_parsing_tool',
        'tesseract',
      ),

      // 本机安装目录，仅作为开发回退。
      r'C:\Program Files\Tesseract-OCR',
    ];

    for (final String directory in candidates) {
      final String executablePath = p.join(
        directory,
        'tesseract.exe',
      );

      final String languageDataPath = p.join(
        directory,
        'tessdata',
        'eng.traineddata',
      );

      if (await File(executablePath).exists() &&
          await File(languageDataPath).exists()) {
        return directory;
      }
    }

    throw Exception(
      '找不到 Windows Tesseract OCR。'
          '请确认发布目录或项目目录中包含 '
          'tesseract.exe 和 tessdata/eng.traineddata。',
    );
  }

  /// Tika JAR 物理路径智能解析方法（私有）。负责根据当前运行环境自适应查找 Tika JAR 包的实际存储路径：
  /// 在打包发布后优先从可执行文件（.exe）同级的 tika_service 安装目录中查找；
  /// 在 flutter test 或日常开发调试时自动回退到源码项目工程目录（lib/document_parsing_tool/tika_service）中查找；
  /// 若两个环境路径均未命中则抛出带有排查路径信息的明确异常。相比临时目录拷贝方式，该方法直接复用本地物理文件，消除了额外的磁盘 I/O 开销。
  Future<String> _resolveJarPath() async {
    final executableDirectory =
        File(Platform.resolvedExecutable).parent.path;

    final installedJarPath = p.join(
      executableDirectory,
      'tika_service',
      _jarFileName,
    );

    if (await File(installedJarPath).exists()) {
      return installedJarPath;
    }

    final developmentJarPath = p.join(
      Directory.current.path,
      'lib',
      'document_parsing_tool',
      'tika_service',
      _jarFileName,
    );

    if (await File(developmentJarPath).exists()) {
      return developmentJarPath;
    }

    throw Exception(
      '找不到 Apache Tika JAR。'
          '安装路径：$installedJarPath；'
          '开发路径：$developmentJarPath',
    );
  }

  /// 进程清理与资源释放静态方法。
  /// 用于在应用退出或需要强制重置服务时，
  /// 向当前应用所拉起的 Tika 后台子进程发送终止信号（kill）并重置进程句柄；
  /// 此方法只会关闭由本应用创建的 Tika 进程，不会误杀用户此前手动独立启动的外部服务。
  static void terminateTika() {
    _process?.kill();
    _process = null;
  }
}
