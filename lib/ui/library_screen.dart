import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path_util;

import 'package:local_retrieval_system/retrieval/indexing/document_indexer.dart';
import 'package:local_retrieval_system/retrieval/retrieval_engine_interface.dart';

enum LibraryFileStatus {
  indexing,
  indexed,
  failed,
}

class LibraryFileItem {
  const LibraryFileItem({
    required this.path,
    required this.name,
    required this.status,
    this.indexedRecordCount = 0,
    this.message,
  });

  final String path;
  final String name;
  final LibraryFileStatus status;
  final int indexedRecordCount;
  final String? message;

  LibraryFileItem copyWith({
    LibraryFileStatus? status,
    int? indexedRecordCount,
    String? message,
  }) {
    return LibraryFileItem(
      path: path,
      name: name,
      status: status ?? this.status,
      indexedRecordCount:
      indexedRecordCount ??
          this.indexedRecordCount,
      message: message,
    );
  }
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    required this.retrievalEngine,
    super.key,
  });

  final RetrievalEngineInterface retrievalEngine;

  @override
  State<LibraryScreen> createState() =>
      _LibraryScreenState();
}

class _LibraryScreenState
    extends State<LibraryScreen> {
  late final _LibraryController _controller;

  @override
  void initState() {
    super.initState();

    _controller = _LibraryController(
      retrievalEngine: widget.retrievalEngine,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (
            BuildContext context,
            Widget? child,
            ) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment:
              CrossAxisAlignment.stretch,
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    '本地文件库',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '添加本地文件并建立离线搜索索引。',
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _controller.isBusy
                        ? null
                        : () {
                      _controller
                          .pickAndIndexFiles();
                    },
                    icon: const Icon(
                      Icons.add,
                    ),
                    label: const Text('添加文件'),
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _controller.statusMessage,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                Expanded(
                  child: _controller.files.isEmpty
                      ? const _EmptyLibraryView()
                      : ListView.separated(
                    itemCount:
                    _controller.files.length,
                    separatorBuilder: (
                        BuildContext context,
                        int index,
                        ) {
                      return const SizedBox(
                        height: 8,
                      );
                    },
                    itemBuilder: (
                        BuildContext context,
                        int index,
                        ) {
                      final LibraryFileItem item =
                      _controller.files[index];

                      return _LibraryFileCard(
                        item: item,
                        enabled:
                        !_controller.isBusy,
                        onReindex: () {
                          _controller.reindexFile(
                            item,
                          );
                        },
                        onDelete: () {
                          _confirmDelete(
                            context,
                            item,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context,
      LibraryFileItem item,
      ) async {
    final bool? confirmed =
    await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('删除文件索引'),
          content: Text(
            '确定要从索引中删除“${item.name}”吗？\n\n'
                '原始文件不会被删除。',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(false);
              },
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext)
                    .pop(true);
              },
              child: const Text('删除索引'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _controller.removeFile(item);
    }
  }
}

class _LibraryController extends ChangeNotifier {
  _LibraryController({
    required RetrievalEngineInterface
    retrievalEngine,
  }) : _retrievalEngine = retrievalEngine;

  final RetrievalEngineInterface
  _retrievalEngine;

  final List<LibraryFileItem> _files =
  <LibraryFileItem>[];

  bool _isBusy = false;

  String _statusMessage =
      '当前还没有添加文件。';

  List<LibraryFileItem> get files =>
      List<LibraryFileItem>.unmodifiable(
        _files,
      );

  bool get isBusy => _isBusy;

  String get statusMessage =>
      _statusMessage;

  Future<void> pickAndIndexFiles() async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _statusMessage = '正在打开文件选择窗口。';
    notifyListeners();

    try {
      final FilePickerResult? result =
      await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: <String>[
          'txt',
          'pdf',
          'docx',
          'png',
          'jpg',
          'jpeg',
          'bmp',
          'webp',
        ],
      );

      if (result == null) {
        _statusMessage = '已取消选择文件。';
        return;
      }

      final List<String> selectedPaths =
      result.files
          .map(
            (PlatformFile file) =>
        file.path,
      )
          .whereType<String>()
          .toList(
        growable: false,
      );

      if (selectedPaths.isEmpty) {
        _statusMessage =
        '没有获得可用的本地文件路径。';
        return;
      }

      int successCount = 0;
      int failureCount = 0;

      for (final String filePath
      in selectedPaths) {
        final int existingIndex =
        _files.indexWhere(
              (LibraryFileItem item) =>
          item.path == filePath,
        );

        final LibraryFileItem indexingItem =
        LibraryFileItem(
          path: filePath,
          name: path_util.basename(filePath),
          status:
          LibraryFileStatus.indexing,
        );

        if (existingIndex >= 0) {
          _files[existingIndex] =
              indexingItem;
        } else {
          _files.add(indexingItem);
        }

        _statusMessage =
        '正在索引 ${indexingItem.name}';
        notifyListeners();

        final IndexingResult indexResult =
        await _retrievalEngine.indexFile(
          filePath,
        );

        final int itemIndex =
        _files.indexWhere(
              (LibraryFileItem item) =>
          item.path == filePath,
        );

        if (indexResult.isSuccess) {
          successCount++;

          _files[itemIndex] =
              indexingItem.copyWith(
                status:
                LibraryFileStatus.indexed,
                indexedRecordCount:
                indexResult.indexedRecordCount,
                message: null,
              );
        } else {
          failureCount++;

          _files[itemIndex] =
              indexingItem.copyWith(
                status:
                LibraryFileStatus.failed,
                message: indexResult.message ??
                    '索引失败',
              );
        }

        notifyListeners();
      }

      _statusMessage =
      '索引完成：成功 $successCount 个，失败 $failureCount 个。';
    } catch (error) {
      _statusMessage =
      '选择或索引文件时发生错误：$error';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> reindexFile(
      LibraryFileItem item,
      ) async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _statusMessage =
    '正在重新索引 ${item.name}';
    _updateItem(
      item.copyWith(
        status: LibraryFileStatus.indexing,
        message: null,
      ),
    );
    notifyListeners();

    try {
      final IndexingResult result =
      await _retrievalEngine.reindexFile(
        item.path,
      );

      if (result.isSuccess) {
        _updateItem(
          item.copyWith(
            status:
            LibraryFileStatus.indexed,
            indexedRecordCount:
            result.indexedRecordCount,
            message: null,
          ),
        );

        _statusMessage =
        '${item.name} 已重新索引。';
      } else {
        _updateItem(
          item.copyWith(
            status:
            LibraryFileStatus.failed,
            message:
            result.message ?? '重新索引失败',
          ),
        );

        _statusMessage =
        '${item.name} 重新索引失败。';
      }
    } catch (error) {
      _updateItem(
        item.copyWith(
          status:
          LibraryFileStatus.failed,
          message: error.toString(),
        ),
      );

      _statusMessage =
      '${item.name} 重新索引失败。';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<void> removeFile(
      LibraryFileItem item,
      ) async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    _statusMessage =
    '正在删除 ${item.name} 的索引。';
    notifyListeners();

    try {
      await _retrievalEngine.removeFile(
        item.path,
      );

      _files.removeWhere(
            (LibraryFileItem existingItem) =>
        existingItem.path == item.path,
      );

      _statusMessage =
      '${item.name} 的索引已删除，原始文件未被删除。';
    } catch (error) {
      _statusMessage =
      '删除 ${item.name} 的索引失败：$error';
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void _updateItem(
      LibraryFileItem updatedItem,
      ) {
    final int index = _files.indexWhere(
          (LibraryFileItem item) =>
      item.path == updatedItem.path,
    );

    if (index >= 0) {
      _files[index] = updatedItem;
    }
  }
}

class _LibraryFileCard extends StatelessWidget {
  const _LibraryFileCard({
    required this.item,
    required this.enabled,
    required this.onReindex,
    required this.onDelete,
  });

  final LibraryFileItem item;
  final bool enabled;
  final VoidCallback onReindex;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(
          _statusIcon,
          color: _statusColor(context),
        ),
        title: Text(item.name),
        subtitle: Text(
          '${_statusText}\n${item.path}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          tooltip: '管理 ${item.name}',
          enabled: enabled,
          onSelected: (String action) {
            switch (action) {
              case 'reindex':
                onReindex();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (
              BuildContext context,
              ) {
            return const <
                PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'reindex',
                child: Text('重新索引'),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('删除索引'),
              ),
            ];
          },
        ),
      ),
    );
  }

  IconData get _statusIcon {
    switch (item.status) {
      case LibraryFileStatus.indexing:
        return Icons.hourglass_top;
      case LibraryFileStatus.indexed:
        return Icons.check_circle;
      case LibraryFileStatus.failed:
        return Icons.error;
    }
  }

  Color _statusColor(
      BuildContext context,
      ) {
    switch (item.status) {
      case LibraryFileStatus.indexing:
        return Theme.of(context)
            .colorScheme
            .primary;
      case LibraryFileStatus.indexed:
        return Colors.green;
      case LibraryFileStatus.failed:
        return Theme.of(context)
            .colorScheme
            .error;
    }
  }

  String get _statusText {
    switch (item.status) {
      case LibraryFileStatus.indexing:
        return '正在索引';
      case LibraryFileStatus.indexed:
        return '索引成功，共 '
            '${item.indexedRecordCount} 条记录';
      case LibraryFileStatus.failed:
        return '索引失败：'
            '${item.message ?? '未知错误'}';
    }
  }
}

class _EmptyLibraryView
    extends StatelessWidget {
  const _EmptyLibraryView();

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
                Icons.folder_open,
                size: 48,
              ),
              SizedBox(height: 16),
              Text('当前还没有添加文件'),
              SizedBox(height: 8),
              Text(
                '选择 TXT、PDF、DOCX 或图片文件开始建立索引。',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}