import 'dart:io';
import 'package:local_retrieval_system/parsing/ocr_engine.dart';
import 'package:local_retrieval_system/parsing/parser_factory.dart';
import 'package:local_retrieval_system/parsing/pdfium_engine.dart';
import 'package:local_retrieval_system/parsing/tika_bridge.dart';
import 'file_parser_interface.dart';
import 'models/parse_result.dart';
import 'models/batch_progress.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

class LocalFileParser implements FileParserInterface {
  @override
  Future<ParseResult> parseFile(String filePath) async {
    try {
      // 1. 基础物理校验：检查文件在本地是否存在
      final file = File(filePath);
      if (!await file.exists()) {
        return ParseResult(
          isSuccess: false,
          fileType: 'UNKNOWN',
          extractedText: '',
          metadata: {},
          errorCode: 'ERR_FILE_NOT_FOUND',
          errorMessage: '本地文件路径不存在或无读取权限',
        );
      }

      // 2. 提取通用系统元数据
      final fileName = p.basename(file.path);
      final fileSize = await file.length();
      final lastModified = (await file.lastModified()).toIso8601String();

      final baseMetadata = {
        'fileName': fileName,
        'filePath': filePath,
        'fileSize': fileSize,
        'lastModified': lastModified,
      };

      // 3. 调用工厂进行格式决策
      final SupportedType type = ParserFactory.getFileType(filePath);

      // 4. 路由分流执行,将 CPU 密集型解析路由移交至后台 Isolate 执行，杜绝阻塞 UI 线程
      switch (type) {
        case SupportedType.txt:
          return await compute(
            _parseTxtIsolate,
            _IsolateParam(filePath, baseMetadata),
          );
        case SupportedType.docx:
          // Tika 是异步文件/HTTP I/O，不需要 compute；保留在主 Isolate
          // 才能可靠管理自动启动的 Java 进程生命周期。
          return await _parseDocx(_IsolateParam(filePath, baseMetadata));
        case SupportedType.pdf:
          return await compute(
            _parsePdfIsolate,
            _IsolateParam(filePath, baseMetadata),
          );
        case SupportedType.image:
          // 注意：因 Google ML Kit 内部原生 SDK 已自带底层异步线程调度，
          // 故保持在当前主上下文调用，但内部图像位图尺寸解码已做安全处理
          return await _parseImageFile(file, baseMetadata);
        case SupportedType.unknown:
          return ParseResult(
            isSuccess: false,
            fileType: 'UNKNOWN',
            extractedText: '',
            metadata: baseMetadata,
            errorCode: 'ERR_UNSUPPORTED_FORMAT',
            errorMessage: '不支持的文件格式类型',
          ); //
      }
    } catch (e) {
      // 捕获不可预期的底层引擎崩溃
      return ParseResult(
        isSuccess: false,
        fileType: 'ERROR',
        extractedText: '',
        metadata: {},
        errorCode: 'ERR_ENGINE_CRASH',
        errorMessage: '底层解析引擎发生严重错误: $e',
      );
    }
  }

  @override
  Stream<BatchProgress> parseBatchFiles(List<String> filePaths) async* {
    final totalCount = filePaths.length;
    int processedCount = 0;

    for (final path in filePaths) {
      ParseResult result;
      try {
        // // 逐个串行调用解析，内部有独立的边界异常隔离
        result = await parseFile(path);
      } catch (e) {
        result = ParseResult(
          isSuccess: false,
          fileType: 'ERROR',
          extractedText: '',
          metadata: {},
          errorCode: 'ERR_ENGINE_CRASH',
          errorMessage: e.toString(),
        );
      }

      processedCount++;
      // 流式产生当前进度事件，不影响 UI 接收实时批处理看板更新
      yield BatchProgress(
        totalCount: totalCount,
        processedCount: processedCount,
        currentFilePath: path,
        latestResult: result,
      );
    }
  }

  /// 本地图片格式（JPG/PNG）的私有解析逻辑
  Future<ParseResult> _parseImageFile(
    File file,
    Map<String, dynamic> meta,
  ) async {
    try {
      final ocrEngine = OcrEngine();

      // 获取图片的物理尺寸（内部已防范大图 OOM 风险）
      final ImageSize size = await ocrEngine.getImageSize(file.path);
      // 执行端侧离线文本识别神经网络（无网络依赖）
      final String text = await ocrEngine.recognizeText(file.path);

      meta['width'] = size.width;
      meta['height'] = size.height;

      return ParseResult(
        isSuccess: true,
        fileType: 'IMAGE',
        extractedText: text,
        metadata: meta,
      );
    } catch (e) {
      return ParseResult(
        isSuccess: false,
        fileType: 'IMAGE',
        extractedText: '',
        metadata: meta,
        errorCode: 'ERR_ENGINE_CRASH',
        errorMessage: '端侧 OCR 视觉识别引擎异常: $e',
      );
    }
  }
}

/// 跨 Isolate 传递的多参数封装模型
class _IsolateParam {
  final String filePath;
  final Map<String, dynamic> metadata;
  _IsolateParam(this.filePath, this.metadata);
}

/// 纯文本后台解析后台任务
Future<ParseResult> _parseTxtIsolate(_IsolateParam param) async {
  // 浅拷贝元数据字典，规避跨 Isolate 的内存共享冲突
  final meta = Map<String, dynamic>.from(param.metadata);
  try {
    final file = File(param.filePath);
    final text = await file.readAsString();
    return ParseResult(
      isSuccess: true,
      fileType: 'TXT',
      extractedText: text,
      metadata: meta,
    );
  } catch (e) {
    return ParseResult(
      isSuccess: false,
      fileType: 'TXT',
      extractedText: '',
      metadata: meta,
      errorCode: 'ERR_ENGINE_CRASH',
      errorMessage: 'TXT 物理磁盘读取失败: $e',
    );
  }
}

/// PDF 物理引擎后台解析任务（高度优化后的安全句柄管理）
Future<ParseResult> _parsePdfIsolate(_IsolateParam param) async {
  final meta = Map<String, dynamic>.from(param.metadata);
  final pdfEngine = PdfiumEngine();
  try {
    // 提取文件特有元数据：PDF页数
    final int pages = await pdfEngine.getPageCount(param.filePath);
    // 循环遍历提取所有非结构化文本内容
    final String text = await pdfEngine.extractAllText(param.filePath);
    meta['pageCount'] = pages;
    return ParseResult(
      isSuccess: true,
      fileType: 'PDF',
      extractedText: text,
      metadata: meta,
    );
  } catch (e) {
    return ParseResult(
      isSuccess: false,
      fileType: 'PDF',
      extractedText: '',
      metadata: meta,
      errorCode: 'ERR_ENGINE_CRASH',
      errorMessage: 'PDFium 底层引擎文本解析崩溃: $e',
    );
  }
}

/// Word 文档端侧桥接后台解析任务
Future<ParseResult> _parseDocx(_IsolateParam param) async {
  final meta = Map<String, dynamic>.from(param.metadata);
  try {
    final tikaBridge = TikaBridge();
    // 通过回环网络将流推送给本地沙盒常驻的 Apache Tika 提取纯文本
    final String text = await tikaBridge.extractDocxText(param.filePath);
    return ParseResult(
      isSuccess: true,
      fileType: 'DOCX',
      extractedText: text,
      metadata: meta,
    );
  } catch (e) {
    return ParseResult(
      isSuccess: false,
      fileType: 'DOCX',
      extractedText: '',
      metadata: meta,
      errorCode: 'ERR_ENGINE_CRASH',
      errorMessage: 'Apache Tika 端侧服务无响应或解析失败: $e',
    );
  }
}
