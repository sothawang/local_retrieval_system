import 'models/batch_progress.dart';
import 'models/parse_result.dart';

abstract interface class FileParserInterface{
  Future<ParseResult> parseFile(String filePath);
  Stream<BatchProgress> parseBatchFiles(List<String> filePaths);
}
