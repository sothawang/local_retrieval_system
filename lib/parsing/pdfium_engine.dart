import 'package:pdfrx/pdfrx.dart';

class PdfiumEngine {

  /// 使用 PDFium 引擎获取 PDF 的总页数
  Future<int> getPageCount(String filePath) async {
    final document = await PdfDocument.openFile(filePath);
    try {
      return document.pages.length;
    } finally {
      // 无论是否发生异常，确保物理句柄被关闭，释放物理文件锁
      await document.dispose();
    }
  }
  /// 使用 PDFium 引擎循环遍历提取 PDF 内部的所有纯文本
  Future<String> extractAllText(String filePath) async {
    final document = await PdfDocument.openFile(filePath);
    try {
      final buffer = StringBuffer();
      for (int i = 0; i < document.pages.length; i++) {
        final page = document.pages[i];
        final pageText = await page.loadText();
        // 规避 pageText 为 null 时的强转崩溃，使用安全调用
        if (pageText != null) {
          buffer.writeln(pageText.fullText);
        }
      }
      return buffer.toString();
    } finally {
      // 无论循环期间发生什么灾难性错误，确保关闭 PDFium 句柄并释放物理文件锁
      await document.dispose();
    }
  }
}