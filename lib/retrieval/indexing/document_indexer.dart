import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'package:local_retrieval_system/embedding/embedding_engine.dart';
import 'package:local_retrieval_system/parsing/file_parser_interface.dart';
import 'package:local_retrieval_system/retrieval/keyword_index/keyword_index.dart';
import 'package:local_retrieval_system/retrieval/models/vector_document.dart';
import 'package:local_retrieval_system/retrieval/vector_store_interface.dart';

/// 文件入库的统一入口。它把一个原始文件（文本或图片）转换成两套并行的索引记录：
/// ```
/// 文件路径
///   ↓
/// 判断类型(文本/图片)
///   ↓
/// 【文本】parse → 清洗 → 分chunk → 每个chunk生成BERT embedding
///   ↓                                    ↓
/// 存入 VectorStore(向量)          存入 KeywordIndex(倒排索引)
///
/// 【图片】读字节 → MobileCLIP embedding
///   ↓                                    ↓
/// 存入 VectorStore(向量)          存入 KeywordIndex(仅metadata,如file_name/caption)
/// ```
/// 现在同时维护两套索引：
///
/// 1. VectorStore
///    - BERT 768D text embeddings
///    - MobileCLIP 512D image embeddings
///
/// 2. KeywordIndex
///    - inverted index
///    - TF
///    - DF
///    - 后续 IDF / Hybrid retrieval 使用
class DocumentIndexer {
  /// 注入四个依赖（文件解析器、embedding引擎、向量库、关键词索引），
  /// 并校验分块参数：chunkWordCount必须>0，chunkOverlapWordCount不能为负且必须小于chunkWordCount（否则重叠会等于或超过chunk本身，逻辑上矛盾）。
  DocumentIndexer({
    required FileParserInterface fileParser,
    required EmbeddingEngine embeddingEngine,
    required VectorStoreInterface vectorStore,
    required KeywordIndex keywordIndex,
    this.chunkWordCount = 90,
    this.chunkOverlapWordCount = 20,
  })  : _fileParser = fileParser,
        _embeddingEngine = embeddingEngine,
        _vectorStore = vectorStore,
        _keywordIndex = keywordIndex {
    if (chunkWordCount <= 0) {
      throw ArgumentError(
        'chunkWordCount must be greater than 0.',
      );
    }

    if (chunkOverlapWordCount < 0) {
      throw ArgumentError(
        'chunkOverlapWordCount cannot be negative.',
      );
    }

    if (chunkOverlapWordCount >= chunkWordCount) {
      throw ArgumentError(
        'chunkOverlapWordCount must be smaller than chunkWordCount.',
      );
    }
  }

  final FileParserInterface _fileParser;
  final EmbeddingEngine _embeddingEngine;
  final VectorStoreInterface _vectorStore;

  /// 独立 keyword inverted index。
  final KeywordIndex _keywordIndex;

  /// 一个chunk的最大值，目前设定为90
  final int chunkWordCount;
  /// 上一个chunk和下一个chunk之前的重叠值，目前设定为20
  final int chunkOverlapWordCount;

  static const Set<String> _imageExtensions = <String>{
    '.jpg',
    '.jpeg',
    '.png',
    '.bmp',
    '.webp',
  };

  // ===========================================================================
  // Index one file
  // ===========================================================================

  /// 索引单个文件的总入口。先检查VectorStore已初始化、文件存在，
  /// 再根据扩展名（.jpg/.jpeg/.png/.bmp/.webp视为图片）分流到 _indexImage 或 _indexTextDocument。异常会被捕获并转成失败结果，而不是抛出。
  /// - 输入：
  /// ```
  /// indexFile('/docs/report.pdf')
  /// ```
  /// - 输出：(成功）
  /// ```
  /// IndexingResult.success(filePath: '/docs/report.pdf', indexedRecordCount: 5)
  /// ```
  /// - 输出：(失败）
  /// ```
  /// IndexingResult.failure(filePath: '/docs/x.pdf', message: 'File does not exist.')
  /// ```
  Future<IndexingResult> indexFile(
      String filePath,
      ) async {
    _ensureVectorStoreReady();

    final File file = File(filePath);

    if (!await file.exists()) {
      return IndexingResult.failure(
        filePath: filePath,
        message: 'File does not exist.',
      );
    }

    try {
      final String extension =
      p.extension(filePath).toLowerCase();

      if (_imageExtensions.contains(extension)) {
        return await _indexImage(file);
      }

      return await _indexTextDocument(file);
    } catch (e) {
      return IndexingResult.failure(
        filePath: filePath,
        message: e.toString(),
      );
    }
  }

  // ===========================================================================
  // Batch indexing
  // ===========================================================================

  /// 批量索引，串行调用 indexFile，收集每个文件的结果。
  /// - 输入：
  /// ```
  /// indexFiles(['/a.txt', '/b.png', '/missing.txt'])
  /// ```
  /// - 输出：
  /// ```
  /// [IndexingResult.success(...), IndexingResult.success(...), IndexingResult.failure(...)]
  Future<List<IndexingResult>> indexFiles(
      List<String> filePaths,
      ) async {
    _ensureVectorStoreReady();

    final List<IndexingResult> results =
    <IndexingResult>[];

    for (final String filePath in filePaths) {
      final IndexingResult result =
      await indexFile(filePath);

      results.add(result);
    }

    return results;
  }

  // ===========================================================================
  // Text document indexing
  // ===========================================================================

  /// 文本文件的完整索引流程：
  /// 1. 用 _fileParser 解析出纯文本
  /// 2. 若解析失败或文本为空 → 返回失败结果
  /// 3. _chunkText 把长文本切成多个chunk（带重叠）
  /// 4. 先删除该文件的旧索引记录（_removeExistingFileRecords），保证重复索引时不会产生重复/陈旧数据
  /// 5. 对每个chunk：生成唯一ID（_buildChunkId）、构造metadata（data_type/file_name/file_extension/chunk_index/chunk_count）、
  /// 调用 _embeddingEngine.generateTextEmbeddingWithMode(chunk, mode: bert) 生成768维BERT向量
  /// 6. 同时构造对应的 VectorDocument 和 KeywordIndexedDocument（注意关键词版本不需要embedding，只需原文+metadata，因为KeywordIndex内部自己会分词）
  /// 7. 分别批量写入 _vectorStore 和 _keywordIndex
  /// - 输入：
  /// ```
  /// 假设 /docs/a.txt 内容为200个词的文本，chunkWordCount=90, chunkOverlapWordCount=20
  /// ```
  /// - 输出：
  /// 产生3个chunk（约90词/块，重叠20词），因此：
  /// ```
  /// IndexingResult.success(filePath: '/docs/a.txt', indexedRecordCount: 3)
  /// 同时：
  /// VectorStore 中新增3条 VectorDocument（id如 docs_a_txt_chunk_0/1/2，各带BERT embedding）
  /// KeywordIndex 中新增3条 KeywordIndexedDocument（同样的id，内容为chunk文本，无embedding）
  Future<IndexingResult> _indexTextDocument(
      File file,
      ) async {
    final String filePath = file.path;

    final parseResult = await _fileParser.parseFile(filePath);

    if (!parseResult.isSuccess) {
      return IndexingResult.failure(
        filePath: filePath,
        message: 'File parsing failed.',
      );
    }

    final String extractedText = parseResult.extractedText.trim();

    if (extractedText.isEmpty) {
      return IndexingResult.failure(
        filePath: filePath,
        message:
        'Parser returned empty text.',
      );
    }

    final List<String> chunks = _chunkText(extractedText);

    if (chunks.isEmpty) {
      return IndexingResult.failure(
        filePath: filePath,
        message:
        'No text chunks were generated.',
      );
    }

    // -------------------------------------------------------------------------
    // Remove old index first
    // -------------------------------------------------------------------------
    //
    // 同一个文件重新 index 时：
    //
    // VectorStore old chunks
    // +
    // KeywordIndex old chunks
    //
    // 都必须删除。
    await _removeExistingFileRecords(
      filePath,
    );

    final List<VectorDocument> vectorDocuments =
    <VectorDocument>[];

    final List<KeywordIndexedDocument>
    keywordDocuments =
    <KeywordIndexedDocument>[];

    // -------------------------------------------------------------------------
    // Generate BERT embedding for every text chunk
    // -------------------------------------------------------------------------

    for (int chunkIndex = 0;
    chunkIndex < chunks.length;
    chunkIndex++) {
      final String chunk =
      chunks[chunkIndex];

      final String documentId =
      _buildChunkId(
        filePath,
        chunkIndex,
      );

      final Map<String, dynamic> metadata =
      <String, dynamic>{
        'data_type': 'text',
        'file_name':
        p.basename(filePath),
        'file_extension':
        p.extension(filePath)
            .toLowerCase(),
        'chunk_index': chunkIndex,
        'chunk_count': chunks.length,
      };

      // -----------------------------------------------------------------------
      // Week 3 - BERT embedding
      // -----------------------------------------------------------------------

      final Float32List embedding =
      await _embeddingEngine
          .generateTextEmbeddingWithMode(
        chunk,
        mode: TextEmbeddingMode.bert,
      );

      // -----------------------------------------------------------------------
      // Vector index document
      // -----------------------------------------------------------------------

      vectorDocuments.add(
        VectorDocument(
          id: documentId,
          sourcePath: filePath,
          content: chunk,
          embedding: embedding,
          embeddingType:
          VectorEmbeddingType.bert,
          metadata: metadata,
        ),
      );

      // -----------------------------------------------------------------------
      // Keyword inverted index document
      // -----------------------------------------------------------------------
      //
      // 注意这里不需要 embedding。
      //
      // KeywordIndex 会自己：
      //
      // tokenize
      // TF
      // DF
      // inverted index
      keywordDocuments.add(
        KeywordIndexedDocument(
          id: documentId,
          sourcePath: filePath,
          content: chunk,
          metadata: metadata,
        ),
      );
    }

    // -------------------------------------------------------------------------
    // Store in VectorStore
    // -------------------------------------------------------------------------

    await _vectorStore.addDocuments(
      vectorDocuments,
    );

    // -------------------------------------------------------------------------
    // Store in KeywordIndex
    // -------------------------------------------------------------------------

    await _keywordIndex.addDocuments(
      keywordDocuments,
    );

    return IndexingResult.success(
      filePath: filePath,
      indexedRecordCount:
      vectorDocuments.length,
    );
  }

  // ===========================================================================
  // Image indexing
  // ===========================================================================

  /// 图片文件索引流程
  /// 1. 读取字节，若为空则失败
  /// 2. 删除旧索引
  /// 3. 用 _embeddingEngine.generateImageEmbedding 生成MobileCLIP 512维向量
  /// 4. 构造metadata（data_type: 'image', file_name, file_extension）
  /// 5. 写入 VectorStore（content: null，因为图片没有文本内容）
  /// 6. 同时写入 KeywordIndex（即使content为null，也会索引metadata如file_name，为未来caption/OCR文本预留扩展空间）
  /// - 输入：
  /// ```
  /// _indexImage(File('/photos/sunset.png'))
  /// ```
  /// - 输出：
  /// ```
  /// IndexingResult.success(filePath: '/photos/sunset.png', indexedRecordCount: 1)
  /// VectorStore新增1条（embeddingType=mobileClip），KeywordIndex新增1条（可通过"sunset"、"png"等关键词命中该图片的file_name）。
  Future<IndexingResult> _indexImage(
      File file,
      ) async {
    final String filePath =
        file.path;

    final Uint8List imageBytes =
    await file.readAsBytes();

    if (imageBytes.isEmpty) {
      return IndexingResult.failure(
        filePath: filePath,
        message: 'Image file is empty.',
      );
    }

    // Remove existing image index.
    await _removeExistingFileRecords(
      filePath,
    );

    // -------------------------------------------------------------------------
    // MobileCLIP image embedding
    // -------------------------------------------------------------------------

    final Float32List embedding =
    await _embeddingEngine
        .generateImageEmbedding(
      imageBytes,
    );

    final String documentId =
    _buildImageId(filePath);

    final Map<String, dynamic> metadata =
    <String, dynamic>{
      'data_type': 'image',
      'file_name':
      p.basename(filePath),
      'file_extension':
      p.extension(filePath)
          .toLowerCase(),
    };

    final VectorDocument vectorDocument =
    VectorDocument(
      id: documentId,
      sourcePath: filePath,
      content: null,
      embedding: embedding,
      embeddingType:
      VectorEmbeddingType.mobileClip,
      metadata: metadata,
    );

    await _vectorStore.addDocument(
      vectorDocument,
    );

    // -------------------------------------------------------------------------
    // Image keyword index
    // -------------------------------------------------------------------------
    //
    // 即使图片没有 content，
    // 仍然把 metadata 加入 KeywordIndex。
    //
    // 这样未来如果 metadata 包含：
    //
    // file_name
    // caption
    // OCR text
    // description
    //
    // KeywordRetriever 仍可以使用。
    await _keywordIndex.addDocument(
      KeywordIndexedDocument(
        id: documentId,
        sourcePath: filePath,
        content: null,
        metadata: metadata,
      ),
    );

    return IndexingResult.success(
      filePath: filePath,
      indexedRecordCount: 1,
    );
  }

  // ===========================================================================
  // Text chunking
  // ===========================================================================

  /// 滑动窗口分块算法。先合并多余空白，按空格切词；若总词数≤chunkWordCount则整体作为一个chunk；
  /// 否则用步长 step = chunkWordCount - chunkOverlapWordCount 滑动截取，保证相邻chunk之间有重叠（防止语义在边界被切断）。
  /// - 输入：
  /// ```
  /// _chunkText(text)，其中text有200个词，chunkWordCount=90, chunkOverlapWordCount=20（step=70）
  /// ```
  /// - 输出：
  /// ```
  /// chunk0: word[0:90]    (90词)
  /// chunk1: word[70:160]  (90词，与chunk0重叠20词)
  /// chunk2: word[140:200] (60词，最后一块可能不足90词)
  /// 返回 ['chunk0文本', 'chunk1文本', 'chunk2文本']（3个元素）
  ///
  /// 若原文本为空 → 返回 []。
  /// 若词数≤chunkWordCount（如50词，≤90）→ 直接返回 [整个文本]（1个元素）。
  List<String> _chunkText(
      String text,
      ) {
    final String cleanedText =
    text
        .replaceAll(
      RegExp(r'\s+'),
      ' ',
    )
        .trim();

    if (cleanedText.isEmpty) {
      return const <String>[];
    }

    final List<String> words =
    cleanedText.split(' ');

    if (words.length <=
        chunkWordCount) {
      return <String>[
        cleanedText,
      ];
    }

    final List<String> chunks = <String>[];

    final int step = chunkWordCount - chunkOverlapWordCount;

    int start = 0;

    while (start < words.length) {
      final int end =
      (start + chunkWordCount <
          words.length)
          ? start + chunkWordCount
          : words.length;

      final String chunk =
      words.sublist(
        start,
        end,
      ).join(' ').trim();

      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      if (end >= words.length) {
        break;
      }

      start += step;
    }

    return chunks;
  }

  // ===========================================================================
  // Remove
  // ===========================================================================

  /// 对外暴露的删除接口，先确保VectorStore已初始化，再调用 _removeExistingFileRecords
  /// - 输入：
  /// ```
  /// removeFile('/docs/a.txt')
  /// ```
  /// - 输出：
  /// ```
  /// 无返回值；VectorStore和KeywordIndex中所有 sourcePath == '/docs/a.txt' 的记录（包括所有chunk）被删除。
  Future<void> removeFile(
      String filePath,
      ) async {
    _ensureVectorStoreReady();

    await _removeExistingFileRecords(
      filePath,
    );
  }

  /// 内部统一删除逻辑，同时清理两套索引，确保两边不会出现数据不一致（比如VectorStore删了但KeywordIndex忘删）。
  /// - 输入：
  /// ```
  /// _removeExistingFileRecords('/docs/a.txt')
  /// ```
  /// - 输出：
  /// ```
  /// _vectorStore.deleteBySourcePath(...) 和 _keywordIndex.removeBySourcePath(...) 都被调用。
  Future<void> _removeExistingFileRecords(
      String filePath,
      ) async {
    await _vectorStore.deleteBySourcePath(
      filePath,
    );

    await _keywordIndex.removeBySourcePath(
      filePath,
    );
  }

  // ===========================================================================
  // Reindex
  // ===========================================================================

  /// 先删除再重新索引，用于文件内容更新后的刷新场景。
  /// - 输入：
  /// ```
  /// reindexFile('/docs/a.txt')（文件内容已修改）
  /// ```
  /// - 输出：
  /// ```
  /// 先清空旧记录，再执行 indexFile，返回新的 IndexingResult。
  Future<IndexingResult> reindexFile(
      String filePath,
      ) async {
    await removeFile(
      filePath,
    );

    return indexFile(
      filePath,
    );
  }

  // ===========================================================================
  // Keyword index access
  // ===========================================================================

  /// 当前 KeywordIndex 中保存的 document/chunk 数量。暴露KeywordIndex当前的文档/chunk总数，方便外部监控索引规模。
  int get keywordDocumentCount => _keywordIndex.documentCount;

  /// 委托给 _keywordIndex.findHighFrequencyWords，找出当前语料库中的动态高频词（未来可接入StopWordPolicy做自适应停用词过滤）
  /// - 输入：
  /// ```
  /// getHighFrequencyWords(threshold: 0.90)
  /// ```
  /// - 输出：
  /// ```
  /// {'the', 'a', 'is', ...}（DF占比≥90%的token集合）
  Set<String> getHighFrequencyWords({
    double threshold = 0.90,
  }) {
    return _keywordIndex
        .findHighFrequencyWords(
      threshold: threshold,
    );
  }

  // ===========================================================================
  // Validation
  // ===========================================================================

  /// 守卫方法，VectorStore未初始化时抛 StateError，防止在未initialize()前误用。
  void _ensureVectorStoreReady() {
    if (!_vectorStore.isInitialized) {
      throw StateError(
        'VectorStore is not initialized. '
            'Call initialize() before indexing files.',
      );
    }
  }

  // ===========================================================================
  // IDs
  // ===========================================================================

  /// 负责“生成全局唯一且稳定（Deterministic）的数据库主键 ID”的工具方法。
  /// 把文件路径转换成可作为ID使用的字符串，经过_normalizePathForId后再拼接后缀chunk
  /// - 输入：
  /// ```
  /// _buildChunkId('E:/docs/合同.pdf', 0)
  /// ```
  /// - 输出：
  /// ```
  /// 'e_docs_pdf_chunk_0'
  /// //为长文档切出来的第 1 个文本块生成专属唯一主键 ID
  /// - 输入：
  /// ```
  /// _buildChunkId('E:/docs/合同.pdf', 1)
  /// ```
  /// - 输出：
  /// ```
  /// 'e_docs_pdf_chunk_1'
  /// // 为长文档切出来的第 2 个文本块生成专属唯一主键 ID
  String _buildChunkId(
      String filePath,
      int chunkIndex,
      ) {
    final String normalized =
    _normalizePathForId(
      filePath,
    );

    return '${normalized}_chunk_$chunkIndex';
  }

  /// 负责“生成全局唯一且稳定（Deterministic）的数据库主键 ID”的工具方法。
  /// 把文件路径转换成可作为ID使用的字符串，经过_normalizePathForId后再拼接后缀image。
  /// - 输入：
  /// ```
  /// _buildImageId('E:/photos/Sunset.png')
  /// ```
  /// - 输出：
  /// 'e_photos_sunset_png_image'
  /// // 为图片文件生成专属唯一主键 ID
  String _buildImageId(
      String filePath,
      ) {
    final String normalized =
    _normalizePathForId(
      filePath,
    );

    return '${normalized}_image';
  }

  /// 把非字母数字字符替换成下划线，合并连续下划线，去首尾下划线，转小写
  String _normalizePathForId(
      String path,
      ) {
    return path
        .replaceAll(
      RegExp(
        r'[^a-zA-Z0-9]+',
      ),
      '_',
    )
        .replaceAll(
      RegExp(r'_+'),
      '_',
    )
        .replaceAll(
      RegExp(r'^_|_$'),
      '',
    )
        .toLowerCase();
  }
}

/// 一个文件 indexing 完成后的结果。不可变结果类，通过工厂方法 .success() / .failure() 构造，
/// 携带 filePath、isSuccess、indexedRecordCount、可选的message（失败原因）。用于统一表示单文件索引结果，便于批量场景中收集成功/失败列表。
class IndexingResult {
  const IndexingResult._({
    required this.filePath,
    required this.isSuccess,
    required this.indexedRecordCount,
    this.message,
  });

  final String filePath;

  final bool isSuccess;

  final int indexedRecordCount;

  final String? message;

  factory IndexingResult.success({
    required String filePath,
    required int indexedRecordCount,
  }) {
    return IndexingResult._(
      filePath: filePath,
      isSuccess: true,
      indexedRecordCount:
      indexedRecordCount,
    );
  }

  factory IndexingResult.failure({
    required String filePath,
    required String message,
  }) {
    return IndexingResult._(
      filePath: filePath,
      isSuccess: false,
      indexedRecordCount: 0,
      message: message,
    );
  }

  @override
  String toString() {
    return 'IndexingResult('
        'filePath: $filePath, '
        'isSuccess: $isSuccess, '
        'indexedRecordCount: $indexedRecordCount, '
        'message: $message'
        ')';
  }
}