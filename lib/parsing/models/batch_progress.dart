import 'parse_result.dart';

/// 批量文件解析进度模型
class BatchProgress {
  final int totalCount;           // 本批次待处理的文件总数
  final int processedCount;       // 当前已完成解析的文件数量
  final String currentFilePath;   // 当前正在解析的文件路径
  final ParseResult latestResult; // 当前刚解析完成的单个文件结果

  BatchProgress({
    required this.totalCount,
    required this.processedCount,
    required this.currentFilePath,
    required this.latestResult,
  });
}