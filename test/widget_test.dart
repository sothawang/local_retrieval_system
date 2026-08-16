import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:local_retrieval_system/retrieval/indexing/document_indexer.dart';
import 'package:local_retrieval_system/retrieval/retrieval_engine_interface.dart';
import 'package:local_retrieval_system/retrieval/retrievers/hybrid_retriever.dart';
import 'package:local_retrieval_system/ui/app_settings_controller.dart';
import 'package:local_retrieval_system/ui/local_retrieval_app.dart';

void main() {
  group(
    'Week 5 UI and accessibility tests',
        () {
      testWidgets(
        'shows the main navigation pages',
            (WidgetTester tester) async {
          await _pumpTestApp(tester);

          expect(
            find.text('本地文件库'),
            findsOneWidget,
          );

          await tester.tap(
            find.byIcon(Icons.search_outlined),
          );
          await tester.pumpAndSettle();

          expect(
            find.text('搜索本地内容'),
            findsOneWidget,
          );

          await tester.tap(
            find.byIcon(
              Icons.settings_outlined,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.text('无障碍设置'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'performs a text search and displays results',
            (WidgetTester tester) async {
          await _pumpTestApp(tester);

          await tester.tap(
            find.byIcon(Icons.search_outlined),
          );
          await tester.pumpAndSettle();

          final Finder searchField =
          find.byType(TextField);

          expect(searchField, findsOneWidget);

          await tester.enterText(
            searchField,
            'accessibility',
          );

          await tester.pump();

          // FilledButton.icon 的真实类型是 FilledButton 的子类，
          // 因此使用 is FilledButton 查找。
          final Finder searchButton =
              find.byWidgetPredicate(
                    (Widget widget) {
                  return widget is FilledButton &&
                      widget.onPressed != null;
                },
                description:
                'enabled search FilledButton',
              );

          expect(
            searchButton,
            findsOneWidget,
          );

          await tester.tap(searchButton);
          await tester.pumpAndSettle();

          expect(
            find.text('1. sample.txt'),
            findsOneWidget,
          );

          expect(
            find.textContaining(
              'Screen readers help people',
            ),
            findsOneWidget,
          );

          expect(
            find.textContaining(
              '搜索完成，共找到 1 条结果',
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'global keyboard shortcuts continue working after mouse navigation',
            (WidgetTester tester) async {
          await _pumpTestApp(tester);

          // 先使用鼠标进入设置页面。
          await tester.tap(
            find.byIcon(
              Icons.settings_outlined,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.text('无障碍设置'),
            findsOneWidget,
          );

          // 鼠标进入文件库。
          await tester.tap(
            find.byIcon(
              Icons.folder_outlined,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.text('本地文件库'),
            findsOneWidget,
          );

          // Alt+2 打开搜索页面。
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.altLeft,
          );
          await tester.sendKeyEvent(
            LogicalKeyboardKey.digit2,
          );
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.altLeft,
          );
          await tester.pumpAndSettle();

          expect(
            find.text('搜索本地内容'),
            findsOneWidget,
          );

          // Alt+3 打开设置。
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.altLeft,
          );
          await tester.sendKeyEvent(
            LogicalKeyboardKey.digit3,
          );
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.altLeft,
          );
          await tester.pumpAndSettle();

          expect(
            find.text('无障碍设置'),
            findsOneWidget,
          );

          // Ctrl+F 返回搜索页面并聚焦输入框。
          await tester.sendKeyDownEvent(
            LogicalKeyboardKey.controlLeft,
          );
          await tester.sendKeyEvent(
            LogicalKeyboardKey.keyF,
          );
          await tester.sendKeyUpEvent(
            LogicalKeyboardKey.controlLeft,
          );
          await tester.pumpAndSettle();

          expect(
            find.text('搜索本地内容'),
            findsOneWidget,
          );

          final TextField searchField =
          tester.widget<TextField>(
            find.byType(TextField),
          );

          expect(
            searchField.focusNode?.hasFocus,
            isTrue,
          );
        },
      );

      testWidgets(
        'provides headings live regions and control semantics',
            (WidgetTester tester) async {
          final SemanticsHandle semantics =
          tester.ensureSemantics();

          try {

          await _pumpTestApp(tester);

          final Finder libraryHeading =
          find.text('本地文件库');

          expect(
            tester.getSemantics(
              libraryHeading,
            ),
            isSemantics(
              label: '本地文件库',
              isHeader: true,
            ),
          );
          } finally {
            semantics.dispose();
          }

          final Finder libraryStatus =
          find.text(
            '当前还没有添加文件。',
          );

          expect(
            tester.getSemantics(
              libraryStatus,
            ),
            isSemantics(
              label: '当前还没有添加文件。',
              isLiveRegion: true,
            ),
          );

          await tester.tap(
            find.byIcon(Icons.search_outlined),
          );
          await tester.pumpAndSettle();

          expect(
            find.bySemanticsLabel(
              RegExp('搜索内容'),
            ),
            findsWidgets,
          );

          final Finder searchStatus =
          find.text(
            '输入查询内容后开始搜索。',
          );

          expect(
            tester.getSemantics(
              searchStatus,
            ),
            isSemantics(
              label:
              '输入查询内容后开始搜索。',
              isLiveRegion: true,
            ),
          );

          await tester.tap(
            find.byIcon(
              Icons.settings_outlined,
            ),
          );
          await tester.pumpAndSettle();

          final Finder scaleControl =
          find.bySemanticsLabel(
            '文字缩放比例',
          );

          expect(
            scaleControl,
            findsOneWidget,
          );

          expect(
            tester.getSemantics(scaleControl),
            isSemantics(
              label: '文字缩放比例',
              value: '100%',
              increasedValue: '125%',
              isSlider: true,
              hasIncreaseAction: true,
              hasDecreaseAction: false,
            ),
          );

          expect(
            find.text('减小文字'),
            findsOneWidget,
          );

          expect(
            find.text('增大文字'),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'supports high contrast and 200 percent text scaling',
            (WidgetTester tester) async {
          final AppSettingsController settings =
          AppSettingsController();

          settings.setHighContrastEnabled(true);
          settings.setTextScaleFactor(2.0);

          await _pumpTestApp(
            tester,
            settingsController: settings,
          );

          final BuildContext context =
          tester.element(
            find.text('本地文件库'),
          );

          expect(
            Theme.of(context).brightness,
            Brightness.dark,
          );

          expect(
            Theme.of(context)
                .colorScheme
                .primary,
            Colors.yellow,
          );

          final double scaledSize =
          MediaQuery.of(context)
              .textScaler
              .scale(10);

          expect(scaledSize, 20.0);

          // 验证 200% 字体下没有布局异常。
          expect(
            tester.takeException(),
            isNull,
          );
        },
      );

      testWidgets(
        'settings controls update accessibility preferences',
            (WidgetTester tester) async {
          final AppSettingsController settings =
          AppSettingsController();

          await _pumpTestApp(
            tester,
            settingsController: settings,
          );

          await tester.tap(
            find.byIcon(
              Icons.settings_outlined,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            settings.highContrastEnabled,
            isFalse,
          );

          await tester.tap(
            find.text('高对比度模式'),
          );
          await tester.pumpAndSettle();

          expect(
            settings.highContrastEnabled,
            isTrue,
          );

          final Finder increaseTextButton =
          find.text('增大文字');

          expect(
            increaseTextButton,
            findsOneWidget,
          );

          await tester.tap(increaseTextButton);
          await tester.pumpAndSettle();

          expect(
            settings.textScaleFactor,
            1.25,
          );

          expect(
            find.text('125%'),
            findsOneWidget,
          );
        },
      );
    },
  );
}

Future<void> _pumpTestApp(
    WidgetTester tester, {
      AppSettingsController?
      settingsController,
    }) async {
  tester.view.physicalSize =
  const Size(1200, 800);

  tester.view.devicePixelRatio = 1.0;

  addTearDown(
    tester.view.resetPhysicalSize,
  );

  addTearDown(
    tester.view.resetDevicePixelRatio,
  );

  // 确保测试结束后 HomeShell 被销毁，
  // 从 HardwareKeyboard 移除全局 handler。
  addTearDown(() async {
    await tester.pumpWidget(
      const SizedBox.shrink(),
    );
  });

  await tester.pumpWidget(
    LocalRetrievalApp(
      settingsController:
      settingsController ??
          AppSettingsController(),
      retrievalEngine:
      _FakeRetrievalEngine(),
    ),
  );

  await tester.pumpAndSettle();
}

class _FakeRetrievalEngine
    implements RetrievalEngineInterface {
  @override
  Future<IndexingResult> indexFile(
      String filePath,
      ) async {
    return IndexingResult.success(
      filePath: filePath,
      indexedRecordCount: 1,
    );
  }

  @override
  Future<List<IndexingResult>> indexFiles(
      List<String> filePaths,
      ) async {
    return filePaths
        .map(
          (String filePath) =>
          IndexingResult.success(
            filePath: filePath,
            indexedRecordCount: 1,
          ),
    )
        .toList(
      growable: false,
    );
  }

  @override
  Future<void> removeFile(
      String filePath,
      ) async {}

  @override
  Future<IndexingResult> reindexFile(
      String filePath,
      ) async {
    return IndexingResult.success(
      filePath: filePath,
      indexedRecordCount: 1,
    );
  }

  @override
  Future<List<HybridSearchResult>>
  searchText({
    required String query,
    int topK = 10,
    Map<String, dynamic>? filters,
  }) async {
    return const <HybridSearchResult>[
      HybridSearchResult(
        id: 'sample_text_1',
        sourcePath:
        'C:/documents/sample.txt',
        content:
        'Screen readers help people access digital content.',
        vectorScore: 0.8,
        normalizedVectorScore: 0.8,
        keywordScore: 0.9,
        normalizedKeywordScore: 0.9,
        finalScore: 0.87,
        foundByVector: true,
        foundByKeyword: true,
        metadata: <String, dynamic>{
          'data_type': 'text',
          'file_name': 'sample.txt',
        },
      ),
    ];
  }

  @override
  Future<List<HybridSearchResult>>
  searchImages({
    required String query,
    int topK = 10,
  }) async {
    return const <HybridSearchResult>[
      HybridSearchResult(
        id: 'sample_image_1',
        sourcePath:
        'C:/images/sample.png',
        vectorScore: 0.85,
        normalizedVectorScore: 0.85,
        keywordScore: 0.7,
        normalizedKeywordScore: 0.7,
        finalScore: 0.805,
        foundByVector: true,
        foundByKeyword: true,
        metadata: <String, dynamic>{
          'data_type': 'image',
          'file_name': 'sample.png',
        },
      ),
    ];
  }
}

