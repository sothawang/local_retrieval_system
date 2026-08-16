import 'package:flutter/material.dart';
import 'package:path/path.dart' as path_util;

import 'package:local_retrieval_system/retrieval/retrieval_engine_interface.dart';
import 'package:local_retrieval_system/retrieval/retrievers/hybrid_retriever.dart';

enum SearchMode {
  text,
  image,
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    required this.retrievalEngine,
    required this.searchFocusNode,
    super.key,
  });

  final RetrievalEngineInterface retrievalEngine;
  final FocusNode searchFocusNode;

  @override
  State<SearchScreen> createState() =>
      _SearchScreenState();
}

class _SearchScreenState
    extends State<SearchScreen> {
  final TextEditingController _queryController =
  TextEditingController();

  SearchMode _searchMode = SearchMode.text;

  List<HybridSearchResult> _results =
  <HybridSearchResult>[];

  bool _isSearching = false;

  String _statusMessage =
      '输入查询内容后开始搜索。';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (_isSearching) {
      return;
    }

    final String query =
    _queryController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _statusMessage = '请输入搜索内容。';
      });

      widget.searchFocusNode.requestFocus();
      return;
    }

    setState(() {
      _isSearching = true;
      _statusMessage = '正在搜索“$query”。';
      _results = <HybridSearchResult>[];
    });

    try {
      final List<HybridSearchResult> results;

      switch (_searchMode) {
        case SearchMode.text:
          results =
          await widget.retrievalEngine.searchText(
            query: query,
            topK: 10,
            filters: <String, dynamic>{
              'data_type': 'text',
            },
          );
          break;

        case SearchMode.image:
          results =
          await widget.retrievalEngine.searchImages(
            query: query,
            topK: 10,
          );
          break;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _results = results;

        if (results.isEmpty) {
          _statusMessage =
          '没有找到与“$query”相关的结果。';
        } else {
          _statusMessage =
          '搜索完成，共找到 ${results.length} 条结果。';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _statusMessage =
        '搜索失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _clearSearch() {
    _queryController.clear();

    setState(() {
      _results = <HybridSearchResult>[];
      _statusMessage =
      '搜索内容和结果已清除。';
    });

    widget.searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.stretch,
          children: <Widget>[
            Semantics(
              header: true,
              child: Text(
                '搜索本地内容',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _queryController,
              focusNode: widget.searchFocusNode,
              enabled: !_isSearching,
              textInputAction:
              TextInputAction.search,
              onSubmitted: (_) {
                _search();
              },
              decoration: InputDecoration(
                labelText: '搜索内容',
                hintText: '例如：accessibility guide',
                prefixIcon:
                const Icon(Icons.search),
                border:
                const OutlineInputBorder(),
                suffixIcon:
                _queryController.text.isEmpty
                    ? null
                    : IconButton(
                  tooltip: '清除搜索内容',
                  onPressed: _clearSearch,
                  icon: const Icon(
                    Icons.clear,
                  ),
                ),
              ),
              onChanged: (_) {
                setState(() {});
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<SearchMode>(
              initialValue: _searchMode,
              decoration: const InputDecoration(
                labelText: '搜索类型',
                border: OutlineInputBorder(),
              ),
              items:
              const <DropdownMenuItem<SearchMode>>[
                DropdownMenuItem<SearchMode>(
                  value: SearchMode.text,
                  child: Text('文本文档'),
                ),
                DropdownMenuItem<SearchMode>(
                  value: SearchMode.image,
                  child: Text('图片'),
                ),
              ],
              onChanged: _isSearching
                  ? null
                  : (SearchMode? mode) {
                if (mode == null) {
                  return;
                }

                setState(() {
                  _searchMode = mode;
                  _results =
                  <HybridSearchResult>[];
                  _statusMessage =
                  '已切换搜索类型。';
                });
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.icon(
                  onPressed:
                  _isSearching ? null : _search,
                  icon: _isSearching
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                    CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                      : const Icon(Icons.search),
                  label: Text(
                    _isSearching ? '搜索中' : '搜索',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _isSearching
                      ? null
                      : _clearSearch,
                  icon: const Icon(Icons.clear),
                  label: const Text('清除'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(_statusMessage),
            ),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                '搜索结果',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _buildResults(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(
          semanticsLabel: '正在搜索',
        ),
      );
    }

    if (_results.isEmpty) {
      return const _EmptyResultsView();
    }

    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (
          BuildContext context,
          int index,
          ) {
        return const SizedBox(height: 8);
      },
      itemBuilder: (
          BuildContext context,
          int index,
          ) {
        return _SearchResultCard(
          result: _results[index],
          rank: index + 1,
        );
      },
    );
  }
}

class _SearchResultCard
    extends StatelessWidget {
  const _SearchResultCard({
    required this.result,
    required this.rank,
  });

  final HybridSearchResult result;
  final int rank;

  @override
  Widget build(BuildContext context) {
    final String fileName =
    _getFileName(result);

    final String dataType =
        result.metadata['data_type']
        as String? ??
            'unknown';

    final bool isImage =
        dataType == 'image';

    final String summary =
    _buildSummary(result);

    final String percentage =
    (result.finalScore * 100)
        .toStringAsFixed(1);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment:
          CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  isImage
                      ? Icons.image_outlined
                      : Icons.description_outlined,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$rank. $fileName',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium,
                  ),
                ),
                Semantics(
                  label:
                  '相关度 $percentage 百分比',
                  child: Text('$percentage%'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              result.sourcePath,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall,
            ),
            const SizedBox(height: 8),
            Text(summary),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                Chip(
                  label: Text(
                    isImage ? '图片' : '文本文档',
                  ),
                ),
                if (result.foundByBoth)
                  const Chip(
                    label: Text('语义 + 关键词'),
                  )
                else if (result.foundByVector)
                  const Chip(
                    label: Text('语义匹配'),
                  )
                else if (result.foundByKeyword)
                    const Chip(
                      label: Text('关键词匹配'),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _getFileName(
      HybridSearchResult result,
      ) {
    final dynamic metadataFileName =
    result.metadata['file_name'];

    if (metadataFileName is String &&
        metadataFileName.trim().isNotEmpty) {
      return metadataFileName;
    }

    if (result.sourcePath.trim().isNotEmpty) {
      return path_util.basename(
        result.sourcePath,
      );
    }

    return result.id;
  }

  String _buildSummary(
      HybridSearchResult result,
      ) {
    final String? content = result.content;

    if (content == null ||
        content.trim().isEmpty) {
      if (result.metadata['data_type'] ==
          'image') {
        return '匹配的本地图片。';
      }

      return '该结果没有可显示的文本摘要。';
    }

    final String normalizedContent =
    content
        .replaceAll(
      RegExp(r'\s+'),
      ' ',
    )
        .trim();

    const int maximumLength = 240;

    if (normalizedContent.length <=
        maximumLength) {
      return normalizedContent;
    }

    return '${normalizedContent.substring(0, maximumLength)}…';
  }
}

class _EmptyResultsView
    extends StatelessWidget {
  const _EmptyResultsView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.search,
                size: 48,
              ),
              SizedBox(height: 16),
              Text('当前没有搜索结果'),
              SizedBox(height: 8),
              Text(
                '请先在文件库中添加文件，然后输入搜索内容。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
