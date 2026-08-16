/// 单文件解析结果模型
class ParseResult {
  final bool isSuccess;         // 标记该文件是否解析成功
  final String fileType;        // 文件格式 (TXT, PDF, DOCX, JPG, PNG)
  final String extractedText;   // 提取出的纯文本或 OCR 文字
  final Map<String, dynamic> metadata; // 结构化元数据键值对
  final String? errorCode;      // 错误代码 (如 ERR_FILE_NOT_FOUND)
  final String? errorMessage;   // 错误信息

  ParseResult({
    required this.isSuccess,
    required this.fileType,
    required this.extractedText,
    required this.metadata,
    this.errorCode,
    this.errorMessage,
  });
}