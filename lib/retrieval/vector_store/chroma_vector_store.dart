import 'dart:typed_data';

import 'package:chromadb/chromadb.dart';

import '../models/vector_document.dart';
import '../models/vector_search_result.dart';
import '../vector_store_interface.dart';

/// 底层仓库管理员 —— Storage Engine，采用chromaDB存储向量
/// 1. 只专注于纯粹的向量增删改查，不关心向量是怎么来的。
/// 2. 管理 Chroma DB 的底层连接与 Collection（bert_text_embeddings 和 mobileclip_embeddings）。
/// 3. 接收已经生成好的向量（VectorDocument），将其持久化存入本地磁盘。
/// 4. 当收到查询向量（Query Vector）时，在数据库内部执行 K-NN 高维空间相似度搜索，返回最近的前
/// K 个结果。
// ChromaDB implementation of [VectorStoreInterface].
//
// Two independent collections are used:
//
// BERT:
//   768 dimensions
//
// MobileCLIP:
//   512 dimensions
//
// This prevents vectors from different semantic spaces
// from being mixed together.
class ChromaVectorStore implements VectorStoreInterface {
  ChromaVectorStore({
    ChromaClient? client,
    this.bertCollectionName = 'bert_text_embeddings',
    this.mobileClipCollectionName = 'mobileclip_embeddings',
  }) : _client = client ?? ChromaClient();

  // _client 是这个类和 ChromaDB 服务器之间的底层连接管理对象（负责创建/获取/删除 collection、管理网络连接）
  final ChromaClient _client;

  final String bertCollectionName;
  final String mobileClipCollectionName;

  ChromaCollection? _bertCollection;
  ChromaCollection? _mobileClipCollection;

  bool _isInitialized = false;

  @override
  bool get isInitialized => _isInitialized;

  // ===========================================================================
  // Initialize
  // ===========================================================================

  // 初始化两个 collection 的引用。
  // 先检查 _isInitialized，如果已经初始化过就直接返回，避免重复操作（幂等）。
  // 用 getOrCreateCollection 分别拿到/创建 BERT 和 MobileCLIP 的 collection 对象，存入成员变量。
  // 最后把 _isInitialized 置为 true。
  // 这个方法必须在使用其他方法之前调用一次，后面几乎所有方法开头都会调用 _ensureInitialized() 来强制这个前提。
  @override
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    // getOrCreateCollection 是 ChromaDB 客户端提供的一个方法，
    // 语义是"获取一个已存在的集合（collection），如果它不存在就创建一个新的"。
    _bertCollection = await _client.getOrCreateCollection(
      name: bertCollectionName,
      metadata: <String, dynamic>{
        'embedding_type': 'bert',
        'dimension': 768,
      },
    );

    _mobileClipCollection = await _client.getOrCreateCollection(
      name: mobileClipCollectionName,
      metadata: <String, dynamic>{
        'embedding_type': 'mobileclip',
        'dimension': 512,
      },
    );

    _isInitialized = true;
  }

  // ===========================================================================
  // Add single document
  // ===========================================================================

  // 往数据库里插入单条向量文档。
  @override
  Future<void> addDocument(
      VectorDocument document,
      ) async {
    _ensureInitialized();

    _validateDocument(document);

    // 根据记录的嵌入类型进入到对应的collection中
    final ChromaCollection collection =
    _getCollection(
      document.embeddingType,
    );

    // 每一条记录本质上由 4 个部分组成
    await collection.add(
      // 1. 唯一标识
      ids: <String>[
        document.id,
      ],
      // 2. 向量
      embeddings: <List<double>>[
        document.embedding.toList(),
      ],
      // 3. 原文
      documents: <String>[
        document.content ?? '',
      ],
      // 4. 元数据
      metadatas: <Map<String, dynamic>>[
        _buildMetadata(document),
      ],
    );
  }

  // ===========================================================================
  // Add multiple documents
  // ===========================================================================

  @override
  Future<void> addDocuments(
      List<VectorDocument> documents,
      ) async {
    _ensureInitialized();

    if (documents.isEmpty) {
      return;
    }

    final List<VectorDocument> bertDocuments = <VectorDocument>[];
    final List<VectorDocument> mobileClipDocuments = <VectorDocument>[];

    for (final VectorDocument document in documents) {
      _validateDocument(document);

      switch (document.embeddingType) {
        case VectorEmbeddingType.bert:
          bertDocuments.add(document);
          break;

        case VectorEmbeddingType.mobileClip:
          mobileClipDocuments.add(document);
          break;
      }
    }

    // 把刚才List里的内容存进对应collection中
    if (bertDocuments.isNotEmpty) {
      await _addDocumentsToCollection(
        collection: _bertCollection!,
        documents: bertDocuments,
      );
    }

    if (mobileClipDocuments.isNotEmpty) {
      await _addDocumentsToCollection(
        collection: _mobileClipCollection!,
        documents: mobileClipDocuments,
      );
    }
  }

  /// 把一批 VectorDocument 对象批量写入指定的 Chroma collection。
  Future<void> _addDocumentsToCollection({
    required ChromaCollection collection,
    required List<VectorDocument> documents,
  }) async {
    final List<String> ids = <String>[];
    final List<List<double>> embeddings = <List<double>>[];
    final List<String> contents = <String>[];
    final List<Map<String, dynamic>> metadatas = <Map<String, dynamic>>[];

    for (final VectorDocument document in documents) {
      ids.add(document.id);

      embeddings.add(
        document.embedding.toList(),
      );

      contents.add(
        document.content ?? '',
      );

      metadatas.add(
        _buildMetadata(document),
      );
    }

    await collection.add(
      ids: ids,
      embeddings: embeddings,
      documents: contents,
      metadatas: metadatas,
    );
  }

  // ===========================================================================
  // Search
  // ===========================================================================

  // 给定一个查询向量，去 Chroma 里做语义相似度检索，把 Chroma 返回的原始结果转换成业务层的 VectorSearchResult 列表。
  // queryEmbedding: 查询向量本身（比如把用户的搜索文本先转成 embedding，再传进来）
  // embeddingType: 指定去哪个 collection 查（BERT 还是 MobileCLIP，因为两者维度不同、语义空间不同，不能混查）
  // topK：返回最相似的前 K 条，默认 10
  // filters：可选的 metadata 过滤条件（对应 Chroma 的 where 子句，比如只在某个 source_path 下搜）
  @override
  Future<List<VectorSearchResult>> search({
    required Float32List queryEmbedding,
    required VectorEmbeddingType embeddingType,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {

    _ensureInitialized();
    if (topK <= 0) {
      throw ArgumentError.value(
        topK,
        'topK',
        'topK must be greater than 0.',
      );
    }
    _validateQueryEmbedding(
      queryEmbedding,
      embeddingType,
    );

    // 定位 collection 并发起查询
    final ChromaCollection collection = _getCollection(embeddingType);
    final result = await collection.query(
      // Chroma 的 API 设计支持"一次传多个查询向量、批量做多次检索
      // 因此将其转换为<List<List<double>>>
      queryEmbeddings: <List<double>>[
        // 长度为 1 的数组，里面装着这一个查询向量
        queryEmbedding.toList(),
      ],
      nResults: topK,
      where: filters,
    );

    // 如果一条都没查到（比如 collection 是空的，或 filters 太严格），直接返回空列表，避免后面代码对空结构做无意义的处理。
    final List<VectorSearchResult> output = <VectorSearchResult>[];
    if (result.ids.isEmpty) {
      return output;
    }

    // 从"批量结果"里取出"第一个查询"的结果
    // 因为上面 queryEmbeddings 传的是一个只含 1 个向量的数组，
    // 所以 Chroma 返回的 result.ids 结构是 List<List<String>>（外层对应每个查询向量，
    // 内层对应该查询向量的 topK 个命中 id）。这里只有一个查询，所以用 .first 取出这一个查询对应的 id 列表。
    final List<String> ids = result.ids.first;
    final List<String?> documents =
    result.documents?.isNotEmpty == true
        ? result.documents!.first
        // 如果没有数据（null 或空），就用构造一个和 ids 等长、每个元素都是 null 的占位列表。
        : List<String?>.filled(ids.length, null);

    final List<Map<String, dynamic>?> metadatas =
    result.metadatas?.isNotEmpty == true
        ? result.metadatas!.first
        : List<Map<String, dynamic>?>.filled(ids.length, null);

    final List<double?> distances =
    result.distances?.isNotEmpty == true
        ? result.distances!.first
        : List<double?>.filled(ids.length, null);

    // 在上面有通过filled方法填充占位符的操作是因为：
    // -如果 documents 的长度和 ids 不一致，循环时就会数组越界或数据错位。
    // -所以必须保证这四个 List 长度始终等于 ids.length，哪怕原始数据缺失也要用 null 补齐占位。
    // 遍历，把平行数组重新组装成 VectorSearchResult 对象
    for (int i = 0; i < ids.length; i++) {
      // 用 Map<String, dynamic>.from(... ?? {}) 兜底成一个空 Map，
      // 避免后面 metadata['source_path'] 对 null 取值报错。同时 Map.from 是做了一次浅拷贝，
      // 而不是直接引用 Chroma 返回的原始 Map，
      // 这样调用方拿到 VectorSearchResult 后修改它的 metadata，不会意外影响到 Chroma 客户端内部的数据结构。
      final Map<String, dynamic> metadata =
      Map<String, dynamic>.from(
        metadatas[i] ?? <String, dynamic>{},
      );

      final double distance = distances[i] ?? 0.0;

      // 把第 i 条查询命中的原始数据，组装成一个业务层的 VectorSearchResult 对象，加入结果列表。
      output.add(
        VectorSearchResult(
          id: ids[i],
          sourcePath: metadata['source_path'] as String? ?? '',
          content: documents[i],
          score: _distanceToScore(distance),
          metadata: metadata,
        ),
      );
    }

    return output;
  }

  // ===========================================================================
  // Delete by ID
  // ===========================================================================

  // 按单个 id 精确删除不同
  @override
  Future<void> deleteDocument(
      String id,
      ) async {
    _ensureInitialized();

    if (id.trim().isEmpty) {
      throw ArgumentError(
        'Document id cannot be empty.',
      );
    }

    // Because the interface does not specify embedding type,
    // try both collections.
    // wait: 它接收一个 Future 的集合（这里是 List<Future<void>>），
    // 返回一个新的 Future，这个新 Future 会在列表里所有的 Future 都执行完成后才 resolve（完成）。
    await Future.wait(<Future<void>>[
      _bertCollection!.delete(
        ids: <String>[id],
      ),
      _mobileClipCollection!.delete(
        ids: <String>[id],
      ),
    ]);
  }

  // ===========================================================================
  // Delete by source path
  // ===========================================================================

  // 按来源路径（sourcePath）做批量条件删除
  // 一个 sourcePath（原始文件）通常会被拆分成多条 VectorDocument（多个 id），而不是一对一的关系。
  // 一个原始文件（比如一篇很长的 PDF、一篇文章）通常不会被当成一整条记录存进向量库，
  // -而是会被切分成很多个小片段（chunk），每个 chunk 单独生成一个 embedding、单独存成一条 VectorDocument，
  // -拥有各自独立的 id，但它们的 sourcePath 都指向同一个原始文件。
  @override
  Future<void> deleteBySourcePath(
      String sourcePath,
      ) async {
    _ensureInitialized();

    if (sourcePath.trim().isEmpty) {
      throw ArgumentError(
        'sourcePath cannot be empty.',
      );
    }

    // 按 metadata 条件筛出符合条件的所有记录，再把它们全部删掉。
    final Map<String, dynamic> where =
    <String, dynamic>{
      'source_path': sourcePath,
    };

    await Future.wait(<Future<void>>[
      _bertCollection!.delete(
        where: where,
      ),
      _mobileClipCollection!.delete(
        where: where,
      ),
    ]);
  }

  // ===========================================================================
  // Clear one embedding space
  // ===========================================================================

  // 先删除、再 getOrCreate"，用来实现"清空某个向量空间"的效果：
  // 删掉整个 collection（连同所有数据），然后立刻重新创建一个空的、同名同 metadata 的 collection，
  // 这样调用方后续还能继续往里面写入数据，而不需要重新调用 initialize()。
  @override
  Future<void> clear(
      VectorEmbeddingType embeddingType,
      ) async {
    _ensureInitialized();

    switch (embeddingType) {
      case VectorEmbeddingType.bert:
        await _client.deleteCollection(
          name: bertCollectionName,
        );

        _bertCollection = await _client.getOrCreateCollection(
          name: bertCollectionName,
          metadata: <String, dynamic>{
            'embedding_type': 'bert',
            'dimension': 768,
          },
        );

        break;

      case VectorEmbeddingType.mobileClip:
        await _client.deleteCollection(
          name: mobileClipCollectionName,
        );

        _mobileClipCollection = await _client.getOrCreateCollection(
          name: mobileClipCollectionName,
          metadata: <String, dynamic>{
            'embedding_type':
            'mobileclip',
            'dimension': 512,
          },
        );

        break;
    }
  }

  // ===========================================================================
  // Count
  // ===========================================================================

  // 返回的是这个 collection 里当前存储的记录总数
  // 也就是这个 collection 里有多少条 id（等价于有多少条通过 add 插入进去、且没有被 delete 掉的记录）。
  @override
  Future<int> count(
      VectorEmbeddingType embeddingType,
      ) async {
    _ensureInitialized();

    final ChromaCollection collection = _getCollection(
      embeddingType,
    );

    return collection.count();
  }

  // ===========================================================================
  // Dispose
  // ===========================================================================

  @override
  Future<void> dispose() async {
    if (!_isInitialized) {
      return;
    }

    // _client.close() 关闭的是底层的网络连接/HTTP client
    // （ChromaDB 的 Dart 客户端底层大概率是基于 http 包实现的，
    // close() 通常对应释放底层的 HttpClient 连接池资源，比如关闭 socket 连接、释放文件描述符等系统资源）。
    _client.close();

    _bertCollection = null;
    _mobileClipCollection = null;

    _isInitialized = false;
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  /// 根据传入的 embeddingType（枚举值），
  /// 从两个成员变量 _bertCollection / _mobileClipCollection 中选出对应的 ChromaDB collection 并返回，
  /// 是整个类里"路由到正确 collection"的统一入口。
  ChromaCollection _getCollection(
      VectorEmbeddingType embeddingType,
      ) {
    switch (embeddingType) {
      case VectorEmbeddingType.bert:
        final ChromaCollection? collection = _bertCollection;
        if (collection == null) {
          throw StateError(
            'BERT Chroma collection is not initialized.',
          );
        }
        return collection;

      case VectorEmbeddingType.mobileClip:
        final ChromaCollection? collection = _mobileClipCollection;
        if (collection == null) {
          throw StateError(
            'MobileCLIP Chroma collection is not initialized.',
          );
        }

        return collection;
    }
  }

  /// 把一个 VectorDocument 对象转换成 ChromaDB 存储时需要的 `Map<String, dynamic>` 格式的 metadata（元数据）。
  Map<String, dynamic> _buildMetadata(
      VectorDocument document,
      ) {
    return <String, dynamic>{
      ...document.metadata,

      // 下面三个是保留字段，这几个 key 名字是保留给系统用的，不要在业务 metadata 里用同名字段，否则会被覆盖"。
      'source_path': document.sourcePath,

      'embedding_type': document.embeddingType.name,

      'embedding_dimension': document.embedding.length,
    };
  }

  // 确认是否已初始化，如果没有初始化返回报错信息给上层
  void _ensureInitialized() {
    if (!_isInitialized) {
      throw StateError(
        'ChromaVectorStore is not initialized. '
            'Call initialize() first.',
      );
    }
  }

  /// 将文档写入向量数据库之前，确保数据的完整性和合法性。
  void _validateDocument(
      VectorDocument document,
      ) {
    // id 是 ChromaDB 的主键，id 被直接用作 Chroma 的唯一标识符。如果id是empty的话，
    // 多个本来不应该映射的文件统一映射到了一个空白id上。
    // 如果 id 是空白字符串，会导致：
    // 1. 多条文档共享同一个空白 key，互相覆盖
    // 2. 删除操作误删所有空白 id 的文档
    // 3. ChromaDB 服务端可能拒绝写入或产生未定义行为
    if (document.id.trim().isEmpty) {
      throw ArgumentError(
        'VectorDocument id cannot be empty.',
      );
    }

    if (document.sourcePath.trim().isEmpty) {
      throw ArgumentError(
        'VectorDocument sourcePath '
            'cannot be empty.',
      );
    }

    // 获取向量数据库中的记录的类型的“应该维度值”
    final int expectedDimension = _expectedDimension(
      document.embeddingType,
    );

    if (document.embedding.length != expectedDimension) {
      throw ArgumentError(
        'Invalid embedding dimension '
            'for ${document.embeddingType.name}: '
            '${document.embedding.length}. '
            'Expected $expectedDimension.',
      );
    }

    // 判断每一个维度的值是不是有限数字，是不是无效的数学运算结果
    for (int i = 0; i < document.embedding.length; i++) {
      final double value = document.embedding[i];

      if (!value.isFinite || value.isNaN) {
        throw ArgumentError(
          'Invalid embedding value at index $i: $value.',
        );
      }
    }
  }

  /// 检查查询向量的维度是否和自身类型的维度一致，每一个维度的value是否是有限的和是否有数学意义
  void _validateQueryEmbedding(
      Float32List embedding,
      VectorEmbeddingType embeddingType,
      ) {
    final int expectedDimension = _expectedDimension(
      embeddingType,
    );

    if (embedding.length != expectedDimension) {
      throw ArgumentError(
        'Invalid query embedding '
            'dimension for '
            '${embeddingType.name}: '
            '${embedding.length}. '
            'Expected $expectedDimension.',
      );
    }

    for (final double value in embedding) {
      if (!value.isFinite || value.isNaN) {
        throw ArgumentError(
          'Query embedding contains '
              'NaN or Infinity.',
        );
      }
    }
  }

  /// 获取这个向量类型的对应维度
  int _expectedDimension(
      VectorEmbeddingType type,
      ) {
    switch (type) {
      case VectorEmbeddingType.bert:
        return 768;

      case VectorEmbeddingType.mobileClip:
        return 512;
    }
  }

  /// 把 ChromaDB 返回的"距离"（distance）转换成"相似度分数"（score）的转换函数
  // 向量数据库（包括 Chroma）在做相似度检索时，底层计算出来的原始结果通常是"距离"（distance），而不是直接的"相似度"。这两者的语义方向是相反的：
  // distance（距离）：数值越小，代表两个向量越相似（越接近）；数值越大，代表越不相似
  // score/similarity（相似度）：习惯上是数值越大，代表越相似
  // 这种"方向相反"对最终使用者（业务代码、UI 展示）是很不友好的，因为大家的直觉是"分数越高越好、越相关"，
  // 如果直接把 distance 当 score 用，排序和展示逻辑就会反直觉（比如做一个"相关度进度条"，distance 越大条越长，这在语义上是错的）。
  // 所以需要一个转换函数，把"越小越好"的 distance，转换成"越大越好"的 score。
  // 转换公式score = 1 / (1 + distance)
  // 这个函数是严格单调递减的——distance 越大，score 越小；distance 越小，score 越大。这保证了转换前后排序顺序完全不变
  double _distanceToScore(
      double distance,
      ) {
    if (!distance.isFinite || distance < 0.0) {
      return 0.0;
    }

    return 1.0 / (1.0 + distance);
  }
}