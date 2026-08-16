import 'package:local_retrieval_system/retrieval/indexing/document_indexer.dart';
import 'package:local_retrieval_system/retrieval/retrieval_engine_interface.dart';
import 'package:local_retrieval_system/retrieval/retrievers/hybrid_retriever.dart';
import 'package:local_retrieval_system/retrieval/vector_store_interface.dart';

import 'models/vector_document.dart';

/// Week 4 - Retrieval Engine
///
/// 整个 Retrieval Layer 的统一门面。这个类本身不包含任何检索算法逻辑（那些都在 HybridRetriever/KeywordRetriever/VectorRetriever 里），
/// 它的价值在于：统一入口 + 统一的初始化状态管理 + 统一的参数校验，让上层代码不需要关心索引、向量检索、关键词检索、混合排序这些内部组件是怎么协作的，
/// 只需要调用 RetrievalEngine 的方法即可。
/// ```
/// Architecture:
///
/// UI / Application Layer
/// 上层调用 RetrievalEngine
///    │
///    ├── initialize()                  → 初始化 VectorStore
///    │
///    ├── 索引类方法（对接 DocumentIndexer）
///    │     indexFile / indexFiles
///    │     removeFile / reindexFile
///    │
///    ├── 检索类方法（对接 HybridRetriever）
///    │     searchText / searchTextDocuments
///    │     searchImages / searchMultimodal
///    │        每个都是：_ensureInitialized() → _validateSearchInput() → 转调 HybridRetriever 对应方法
///    │
///    ├── 数据库管理（对接 VectorStore）
///    │     getTextIndexCount / getMobileClipIndexCount
///    │     clearTextIndex / clearMobileClipIndex
///    │
///    └── dispose()                     → 释放 VectorStore 资源
// 接收三个核心依赖——DocumentIndexer（负责把文件解析、embedding、写入向量库）、
// HybridRetriever（负责混合检索）、VectorStoreInterface（底层向量数据库，比如 Chroma），
// 保存成私有字段。这是典型的依赖注入写法，RetrievalEngine 本身不关心这三者内部怎么实现，只负责编排调用它们。
class RetrievalEngine implements RetrievalEngineInterface {
  RetrievalEngine({
    required DocumentIndexer documentIndexer,
    required HybridRetriever hybridRetriever,
    // 面向接口设计，如果之后采用Qdrant等其他数据库可以不修改retrieval engine代码
    required VectorStoreInterface vectorStore,
  })  : _documentIndexer = documentIndexer,
        _hybridRetriever = hybridRetriever,
        _vectorStore = vectorStore;

  final DocumentIndexer _documentIndexer;

  final HybridRetriever _hybridRetriever;

  final VectorStoreInterface _vectorStore;

  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // ===========================================================================
  // Initialize
  // ===========================================================================

  /// 初始化 Retrieval Layer。核心是确保底层 VectorStore 已经初始化好（比如建好 Chroma 的 BERT collection 和 MobileCLIP collection）
  ///
  /// 当前最主要的初始化工作是：
  ///```
  ///           Chroma VectorStore
  ///                 ↓
  /// BERT collection + MobileCLIP collection
  /// - 输入：无参数（内部检查 _isInitialized 和 _vectorStore.isInitialized）
  ///
  /// - 情况 1 — 第一次调用，vectorStore 还没初始化：
  /// - 输出：await 完成后，_vectorStore 被初始化，_isInitialized 变为 true
  ///
  /// - 情况 2 — 已经初始化过：
  /// - 输出：直接 return，什么都不做
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    if (!_vectorStore.isInitialized) {
      await _vectorStore.initialize();
    }

    _isInitialized = true;
  }

  // ===========================================================================
  // Indexing
  // ===========================================================================

  /// 给单个文件建索引（先确保引擎已初始化，再转调 _documentIndexer.indexFile）。这是 RetrievalEngineInterface 接口方法的实现
  /// - 输入：
  /// ```
  /// filePath = "/docs/accessibility_guide.md"
  /// ```
  /// - 输出：
  /// ```
  ///   IndexingResult(filePath: "/docs/accessibility_guide.md", isSuccess: true, indexedRecordCount: 12)
  @override
  Future<IndexingResult> indexFile(
      String filePath,
      ) async {
    _ensureInitialized();

    return _documentIndexer.indexFile(
      filePath,
    );
  }

  /// 批量给多个文件建索引。先确保已初始化，如果传入空列表直接返回空结果（避免不必要的调用），否则转调 _documentIndexer.indexFiles
  /// - 输入：
  /// ```
  /// filePaths = ["/docs/a.md", "/docs/b.md"]
  /// ```
  /// - 输出：
  /// ```
  ///   [
  ///     IndexingResult(filePath: "/docs/a.md", isSuccess: true, ...),
  ///     IndexingResult(filePath: "/docs/b.md", isSuccess: true, ...),
  ///   ]
  ///   ```
  /// - 输入：
  /// ```
  /// filePaths = []
  /// ```
  /// - 输出：
  /// ```
  /// []   // 提前返回，不调用 _documentIndexer
  @override
  Future<List<IndexingResult>> indexFiles(
      List<String> filePaths,
      ) async {
    _ensureInitialized();

    if (filePaths.isEmpty) {
      return const <IndexingResult>[];
    }

    return _documentIndexer.indexFiles(
      filePaths,
    );
  }

  /// 从索引里删除某个文件对应的数据。先确保初始化，再校验 filePath 非空（空字符串或全是空白会抛异常），最后转调 _documentIndexer.removeFile
  /// - 输入：
  /// ```
  /// filePath = "/docs/old_file.md"
  /// ```
  /// - 输出：无返回值，该文件从向量库里被移除
  ///
  /// - 输入：
  /// ```
  /// filePath = "   "
  /// ```
  /// - 输出：
  /// ```
  /// 抛出 ArgumentError('filePath cannot be empty.')
  @override
  Future<void> removeFile(
      String filePath,
      ) async {
    _ensureInitialized();

    if (filePath.trim().isEmpty) {
      throw ArgumentError(
        'filePath cannot be empty.',
      );
    }

    await _documentIndexer.removeFile(
      filePath,
    );
  }

  /// 对已索引过的文件重新建索引（比如文件内容更新后需要刷新向量数据）。逻辑和 indexFile 类似，但多了 filePath 非空校验，转调 _documentIndexer.reindexFile
  /// - 输入：
  /// ```
  /// filePath = "/docs/accessibility_guide.md"
  /// ```
  /// - 输出：
  /// ```
  ///   IndexingResult(filePath: "/docs/accessibility_guide.md", isSuccess: true, indexedRecordCount: 14)
  ///   // 假设文件内容变多了，chunk 数量从 12 变成 14
  /// ```
  /// - 输入：
  /// ```
  /// filePath = ""
  /// ```
  /// - 输出：
  /// ```
  /// 抛出 ArgumentError('filePath cannot be empty.')
  @override
  Future<IndexingResult> reindexFile(
      String filePath,
      ) async {
    _ensureInitialized();

    if (filePath.trim().isEmpty) {
      throw ArgumentError(
        'filePath cannot be empty.',
      );
    }

    return _documentIndexer.reindexFile(
      filePath,
    );
  }

  // ===========================================================================
  // Text retrieval
  // ===========================================================================

  /// 文本 Hybrid Retrieval。普通文本混合检索的对外入口。
  /// 确保已初始化 → 校验查询参数 → 转调 _hybridRetriever.searchText。是对 HybridRetriever.searchText 的一层"加了保护"的转发。
  /// - 输入：
  /// ```
  /// query = "how to enable screen reader", topK = 5
  /// ```
  /// - 输出：
  /// ```
  ///   [
  ///     HybridSearchResult(id: "guide3", finalScore: 0.92, ...),
  ///     ... 共 5 条
  ///   ]
  ///   ```
  ///```
  /// Pipeline:
  ///
  /// String Query
  ///      ↓
  ///     BERT
  ///      ↓
  /// VectorRetriever
  ///      ↓
  /// semantic candidates
  ///      ↓
  /// KeywordRetriever
  ///      ↓
  /// weighted lexical score
  ///      ↓
  /// HybridRetriever
  ///      ↓
  ///    Top-K
  @override
  Future<List<HybridSearchResult>> searchText({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    _ensureInitialized();

    _validateSearchInput(
      query,
      topK,
    );

    return _hybridRetriever.searchText(
      query: query,
      topK: topK,
      filters: filters,
    );
  }

  /// 文本文件专用检索。只搜文本类型文档的检索入口（自动限定 data_type = text，具体过滤逻辑在更底层实现）。
  /// 同样是"确保初始化 + 校验参数 + 转调"的模式，转调 _hybridRetriever.searchTextDocuments
  /// - 输入：
  /// ```
  /// query = "installation steps", topK = 3
  /// ```
  /// - 输出：
  /// ```
  ///   [
  ///     HybridSearchResult(id: "manual_1", finalScore: 0.81, ...),
  ///     HybridSearchResult(id: "manual_2", finalScore: 0.65, ...),
  ///     HybridSearchResult(id: "manual_3", finalScore: 0.52, ...),
  ///   ]
  Future<List<HybridSearchResult>> searchTextDocuments({
    required String query,
    int topK = 10,
  }) async {
    _ensureInitialized();

    _validateSearchInput(
      query,
      topK,
    );

    return _hybridRetriever
        .searchTextDocuments(
      query: query,
      topK: topK,
    );
  }

  // ===========================================================================
  // Multimodal retrieval
  // ===========================================================================

  /// Text -> Image retrieval。
  /// 文字搜图片的检索入口，基于 MobileCLIP 的文本编码器把 query 转成向量去匹配图片 collection。
  /// 同样是"确保初始化 + 校验 + 转调 _hybridRetriever.searchImages"。
  /// - 输入：
  /// ```
  /// query = "a red bicycle on the street", topK = 4
  ///```
  /// - 输出：
  /// ```
  ///   [
  ///     HybridSearchResult(id: "img_88", finalScore: 0.77, ...),
  ///     ... 共 4 条
  ///   ]
  ///   ```
  /// - 流程：
  ///```
  /// Query String
  ///      ↓
  /// MobileCLIP Text Encoder
  ///      ↓
  ///     512D
  ///      ↓
  /// MobileCLIP collection
  ///      ↓
  /// image candidates
  ///      ↓
  /// Hybrid ranking
  @override
  Future<List<HybridSearchResult>> searchImages({
    required String query,
    int topK = 10,
  }) async {
    _ensureInitialized();

    _validateSearchInput(
      query,
      topK,
    );

    return _hybridRetriever.searchImages(
      query: query,
      topK: topK,
    );
  }

  /// 通用的 MobileCLIP 多模态检索入口，比 searchImages 更灵活——
  /// 可以通过 filters 参数控制搜索范围（比如限定 data_type = image，
  /// 或者未来支持的其他 MobileCLIP 数据类型）。转调 _hybridRetriever.searchMultimodal
  /// - 输入：
  /// ```
  ///   query = "sunset landscape"
  ///   filters = {"data_type": "image"}
  ///   topK = 6
  /// ```
  /// - 输出：
  /// ```
  ///   [
  ///     HybridSearchResult(id: "photo_12", finalScore: 0.85, ...),
  ///     ... 共 6 条
  ///   ]
  Future<List<HybridSearchResult>> searchMultimodal({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    _ensureInitialized();

    _validateSearchInput(
      query,
      topK,
    );

    return _hybridRetriever
        .searchMultimodal(
      query: query,
      topK: topK,
      filters: filters,
    );
  }

  // ===========================================================================
  // Database management
  // ===========================================================================

  /// 查询当前 BERT（文本）collection 里已经索引了多少条数据。确保初始化后转调 _vectorStore.count(VectorEmbeddingType.bert)
  /// - 输入：无参数
  /// - 输出：
  /// ```
  /// 1523   // 表示当前文本索引里有 1523 条向量数据
  Future<int> getTextIndexCount() async {
    _ensureInitialized();

    return _vectorStore.count(
      VectorEmbeddingType.bert,
    );
  }

  /// 查询当前 MobileCLIP（多模态/图片）collection 里已经索引了多少条数据。确保初始化后转调VectorEmbeddingType.mobileClip
  /// - 输入：无参数
  /// - 输出：
  /// ```
  /// 342   // 表示图片索引里有 342 条向量数据
  Future<int> getMobileClipIndexCount() async {
    _ensureInitialized();

    return _vectorStore.count(
      VectorEmbeddingType.mobileClip,
    );
  }

  /// 清空整个文本（BERT）索引库，转调 _vectorStore.clear(VectorEmbeddingType.bert)
  /// - 输入：无参数
  /// - 输出：无返回值，BERT collection 里的所有数据被删除
  Future<void> clearTextIndex() async {
    _ensureInitialized();

    await _vectorStore.clear(
      VectorEmbeddingType.bert,
    );
  }

  /// 清空 MobileCLIP（图片/多模态）索引库，转调_vectorStore.clear(VectorEmbeddingType.mobileClip)
  /// - 输入：无参数
  /// - 输出：无返回值，MobileCLIP collection 里的所有数据被删除
  Future<void> clearMobileClipIndex() async {
    _ensureInitialized();

    await _vectorStore.clear(
      VectorEmbeddingType.mobileClip,
    );
  }

  // ===========================================================================
  // Dispose
  // ===========================================================================

  /// 释放整个检索引擎持有的资源（比如关闭数据库连接）。如果还没初始化过，直接返回（没必要释放没建立的资源）；
  /// 否则调用 _vectorStore.dispose()，并把 _isInitialized 重置为 false（意味着之后如果要再用，得重新调用 initialize()）
  /// - 输入：无参数（假设 _isInitialized 当前是 true）
  /// - 输出：无返回值，_vectorStore 资源被释放，_isInitialized 变为 false
  ///
  /// - 输入：无参数（假设从未调用过 initialize()，_isInitialized 是 false）
  /// - 输出：直接 return，不做任何事
  Future<void> dispose() async {
    if (!_isInitialized) {
      return;
    }

    await _vectorStore.dispose();

    _isInitialized = false;
  }

  // ===========================================================================
  // Validation
  // ===========================================================================

  /// 前置守卫方法，检查 _isInitialized 是否为 true，如果引擎还没初始化就直接抛 StateError。
  /// 几乎每一个公开方法（索引类、检索类、数据库管理类）开头都会先调用这个方法，防止在引擎未就绪时执行任何操作。
  /// - 输入：无参数（假设未初始化）
  /// - 输出：
  /// ```
  /// 抛出 StateError('RetrievalEngine is not initialized. Call initialize() first.')
  /// ```
  /// - 输入：无参数（假设已初始化）
  /// - 输出：无返回值，正常往下执行
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'RetrievalEngine is not initialized. '
            'Call initialize() first.',
      );
    }
  }

  /// 校验检索类方法（searchText、searchTextDocuments、searchImages、searchMultimodal）传入的 query 和 topK 是否合法
  /// ——query trim 后不能为空，topK 必须大于 0。和 HybridRetriever._validateQuery 逻辑几乎一样，
  /// 属于在门面层再做一次同样的输入校验（双重保险，即使上层没走 RetrievalEngine 而是绕过去也不会漏检查——不过这里是同一条调用链，
  /// 算是"提前拦截，快速失败"，可以在还没触发底层昂贵的向量检索调用之前就报错）。
  /// - 输入：
  /// ```
  /// query = "", topK = 5
  /// ```
  /// - 输出：
  /// ```
  /// 抛出 ArgumentError('Search query cannot be empty.')
  /// ```
  /// - 输入：
  /// ```
  /// query = "hello", topK = -1
  /// ```
  /// - 输出：
  /// ```
  /// 抛出 ArgumentError.value(-1, 'topK', 'topK must be greater than 0.')
  /// ```
  /// - 输入：
  /// ```
  /// query = "hello world", topK = 10
  /// ```
  /// - 输出：无返回值，正常通过
  void _validateSearchInput(
      String query,
      int topK,
      ) {
    if (query.trim().isEmpty) {
      throw ArgumentError(
        'Search query cannot be empty.',
      );
    }

    if (topK <= 0) {
      throw ArgumentError.value(
        topK,
        'topK',
        'topK must be greater than 0.',
      );
    }
  }
}