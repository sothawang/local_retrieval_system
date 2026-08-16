import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

// 替换为你的实际包名
import 'package:local_retrieval_system/parsing/local_file_parser.dart';
import 'package:local_retrieval_system/parsing/parser_factory.dart';
import 'package:local_retrieval_system/parsing/tika_bridge.dart';
import 'package:local_retrieval_system/parsing/models/batch_progress.dart';

void main() {
  // 定义测试资源目录（相对于项目根目录运行命令时的相对路径）
  const String testResPath = 'test/test_resources';

  late LocalFileParser parser;

  setUpAll(() {
    // 确保测试资源目录存在，否则手动创建防崩溃（防范环境未准备好的情况）
    final dir = Directory(testResPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  });

  tearDownAll(() {
    // 测试套件执行完毕后，确保关闭后台 Java 进程，防止僵尸进程占用 9998 端口
    TikaBridge.terminateTika();
  });

  setUp(() {
    parser = LocalFileParser();
  });

  group('ParserFactory 单元测试', () {
    test('应该正确映射支持的文件后缀到 SupportedType 枚举', () {
      expect(ParserFactory.getFileType('document.txt'), SupportedType.txt);
      expect(
        ParserFactory.getFileType('document.TXT'),
        SupportedType.txt,
      ); // 测试大小写不敏感
      expect(ParserFactory.getFileType('report.pdf'), SupportedType.pdf);
      expect(ParserFactory.getFileType('data.docx'), SupportedType.docx);
      expect(ParserFactory.getFileType('photo.jpg'), SupportedType.image);
      expect(ParserFactory.getFileType('screenshot.png'), SupportedType.image);
      expect(ParserFactory.getFileType('unknown.mp4'), SupportedType.unknown);
    });
  });

  group('LocalFileParser - 边界与异常测试', () {
    test('读取不存在的文件应该返回 ERR_FILE_NOT_FOUND', () async {
      final result = await parser.parseFile('$testResPath/not_exist_file.txt');

      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'ERR_FILE_NOT_FOUND');
      expect(result.errorMessage, contains('不存在或无读取权限'));
    });

    test('解析未知格式应该返回 ERR_UNSUPPORTED_FORMAT', () async {
      // 临时创建一个未知格式的文件用于测试
      final fakeFile = File('$testResPath/temp.xyz')
        ..writeAsStringSync('fake content');

      final result = await parser.parseFile(fakeFile.path);

      expect(result.isSuccess, isFalse);
      expect(result.errorCode, 'ERR_UNSUPPORTED_FORMAT');

      // 清理临时文件
      fakeFile.deleteSync();
    });
  });

  group('LocalFileParser - 核心格式功能测试', () {
    // 注意：因 Google ML Kit 和 PDFium 包含 C++/平台底层代码，在纯桌面/命令行的 flutter_test 环境中
    // 极有可能会抛出 MissingPluginException 或直接由于原生库未加载而触发 Catch 块。
    // 这里的测试目的在于“证明 Dart 层的路由调度逻辑与数据装配逻辑正常运转”，我们验证其执行分支。

    test('解析纯文本 (TXT) 功能测试', () async {
      final txtPath = '$testResPath/sample.txt';
      final file = File(txtPath);

      // 强行写入确定的测试内容，避免受到外部已存在空文件的干扰
      file.writeAsStringSync('测试文本内容：Hello World');

      final result = await parser.parseFile(txtPath);

      expect(result.isSuccess, isTrue);
      expect(result.fileType, 'TXT');
      expect(result.extractedText, contains('Hello World'));
      expect(result.metadata['fileName'], 'sample.txt');
      expect(result.metadata.containsKey('fileSize'), isTrue);
    });

    test('解析 PDF 分支调度测试', () async {
      final pdfPath = '$testResPath/sample.pdf';
      if (!File(pdfPath).existsSync()) {
        File(pdfPath).writeAsBytesSync([0, 1, 2]);
      }

      final result = await parser.parseFile(pdfPath);

      // 在脱离宿主设备的 Test 环境中，若原生插件报错会进入 Catch 返回 ERR_ENGINE_CRASH
      // 这依然证明了 switch 路由和 Isolate 包装机制正常工作
      expect(result.fileType, 'PDF');
      if (result.isSuccess) {
        expect(result.metadata.containsKey('pageCount'), isTrue);
      } else {
        expect(result.errorCode, 'ERR_ENGINE_CRASH');
      }
    });

    test('TikaBridge 应从本地 JAR 自动启动并通过健康检查', () async {
      // 确保初始端口是干净的
      TikaBridge.terminateTika();
      await Future.delayed(const Duration(milliseconds: 500));

      // 明确验证 asset 中的 JAR 可以准备、启动并通过健康检查。
      await TikaBridge().ensureTikaServiceReady();
    });

    test('解析 Image (OCR) 分支调度测试', () async {
      final imgPath = '$testResPath/sample.png';
      if (!File(imgPath).existsSync()) {
        File(imgPath).writeAsBytesSync([0, 1, 2]);
      }

      final result = await parser.parseFile(imgPath);

      expect(result.fileType, 'IMAGE');
      // MLKit 在单元测试中大概率没有环境支持
      if (!result.isSuccess) {
        expect(result.errorCode, 'ERR_ENGINE_CRASH');
      } else {
        expect(result.metadata.containsKey('width'), isTrue);
      }
    });

    test('parseBatchFiles 遇到无效文件时应正确返回错误结果且不中断流', () async {
      // 传入一个完全非法的路径
      final stream = parser.parseBatchFiles([
        '/invalid/path/triggered/crash.pdf',
      ]);

      await for (final progress in stream) {
        expect(progress.latestResult.isSuccess, isFalse);

        // 因为 parseFile 内部已经处理了不存在的文件并返回了 UNKNOWN
        // 这里应断言真实的返回值，而非 ERROR
        expect(progress.latestResult.fileType, 'UNKNOWN');
        expect(progress.latestResult.errorCode, 'ERR_FILE_NOT_FOUND');
      }
    });
  });

  group('LocalFileParser - 批处理(Batch)流测试', () {
    test('parseBatchFiles 应该按顺序发送 Stream 事件并统计进度', () async {
      final paths = [
        '$testResPath/sample.txt',
        '$testResPath/not_exist_file.pdf',
        '$testResPath/sample.png',
      ];

      // 为确保上述路径文件在物理上存在(至少 TXT 和 PNG 存在)
      if (!File(paths[0]).existsSync()) File(paths[0]).writeAsStringSync('1');
      if (!File(paths[2]).existsSync()) File(paths[2]).writeAsBytesSync([0]);

      final stream = parser.parseBatchFiles(paths);
      final events = <BatchProgress>[];

      await for (final progress in stream) {
        events.add(progress);
      }

      // 验证事件数量与传入文件数量一致
      expect(events.length, 3);

      // 验证最终进度的合法性
      final finalEvent = events.last;
      expect(finalEvent.totalCount, 3);
      expect(finalEvent.processedCount, 3);
      expect(finalEvent.currentFilePath, paths.last);

      // 验证中间事件状态
      expect(events[0].processedCount, 1);
      expect(events[1].processedCount, 2);
      expect(events[1].latestResult.isSuccess, isFalse); // 第二个文件是假的路径，预期失败
    });
  });
}
