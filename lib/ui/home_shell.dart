import 'package:flutter/material.dart';
import 'package:local_retrieval_system/parsing/tika_bridge.dart';

import 'app_settings_controller.dart';
import 'package:local_retrieval_system/retrieval/retrieval_engine_interface.dart';

import 'library_screen.dart';
import 'search_screen.dart';
import 'package:flutter/services.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    required this.settingsController,
    required this.retrievalEngine,
    super.key,
  });

  final AppSettingsController settingsController;
  final RetrievalEngineInterface retrievalEngine;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final FocusNode _searchFocusNode =
  FocusNode(
    debugLabel: 'Search input',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    HardwareKeyboard.instance.addHandler(
      _handleKeyEvent,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      TikaBridge.terminateTika();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(
      _handleKeyEvent,
    );

    WidgetsBinding.instance.removeObserver(this);
    _searchFocusNode.dispose();
    TikaBridge.terminateTika();

    super.dispose();
  }

  static const List<String> _pageTitles = <String>['文件库', '搜索', '设置'];

  bool _handleKeyEvent(KeyEvent event) {
    // 只处理按下事件，避免松开按键时重复执行。
    if (event is! KeyDownEvent) {
      return false;
    }

    final HardwareKeyboard keyboard =
        HardwareKeyboard.instance;

    if (keyboard.isAltPressed) {
      if (event.logicalKey ==
          LogicalKeyboardKey.digit1) {
        _openPage(0);
        return true;
      }

      if (event.logicalKey ==
          LogicalKeyboardKey.digit2) {
        _openPage(1);
        return true;
      }

      if (event.logicalKey ==
          LogicalKeyboardKey.digit3) {
        _openPage(2);
        return true;
      }
    }

    final bool primaryModifierPressed =
        keyboard.isControlPressed ||
            keyboard.isMetaPressed;

    if (primaryModifierPressed &&
        event.logicalKey ==
            LogicalKeyboardKey.keyF) {
      _openSearchAndFocus();
      return true;
    }

    return false;
  }
  void _openPage(int index) {
    if (index < 0 ||
        index >= _pageTitles.length) {
      return;
    }

    setState(() {
      _selectedIndex = index;
    });
  }

  void _openSearchAndFocus() {
    setState(() {
      _selectedIndex = 1;
    });

    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _selectPage(int index) {
    _openPage(index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = <Widget>[
      LibraryScreen(
        retrievalEngine:
        widget.retrievalEngine,
      ),
      SearchScreen(
        retrievalEngine:
        widget.retrievalEngine,
        searchFocusNode:
        _searchFocusNode,
      ),
      SettingsScreen(
        controller:
        widget.settingsController,
      ),
    ];

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: LayoutBuilder(
        builder: (
            BuildContext context,
            BoxConstraints constraints,
            ) {
          final bool useNavigationRail =
              constraints.maxWidth >= 720;

          final Widget pageStack =
          IndexedStack(
            index: _selectedIndex,
            children: pages,
          );

          return Scaffold(
            appBar: AppBar(
              title: Text(
                _pageTitles[_selectedIndex],
              ),
            ),
            body: useNavigationRail
                ? Row(
              children: <Widget>[
                NavigationRail(
                  selectedIndex:
                  _selectedIndex,
                  onDestinationSelected:
                  _selectPage,
                  labelType:
                  NavigationRailLabelType
                      .all,
                  destinations:
                  const <
                      NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(
                        Icons.folder_outlined,
                      ),
                      selectedIcon: Icon(
                        Icons.folder,
                      ),
                      label: Text('文件库'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(
                        Icons.search_outlined,
                      ),
                      selectedIcon: Icon(
                        Icons.search,
                      ),
                      label: Text('搜索'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(
                        Icons.settings_outlined,
                      ),
                      selectedIcon: Icon(
                        Icons.settings,
                      ),
                      label: Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(
                  width: 1,
                ),
                Expanded(
                  child: pageStack,
                ),
              ],
            )
                : pageStack,
            bottomNavigationBar:
            useNavigationRail
                ? null
                : NavigationBar(
              selectedIndex:
              _selectedIndex,
              onDestinationSelected:
              _selectPage,
              destinations:
              const <
                  NavigationDestination>[
                NavigationDestination(
                  icon: Icon(
                    Icons.folder_outlined,
                  ),
                  selectedIcon: Icon(
                    Icons.folder,
                  ),
                  label: '文件库',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.search_outlined,
                  ),
                  selectedIcon: Icon(
                    Icons.search,
                  ),
                  label: '搜索',
                ),
                NavigationDestination(
                  icon: Icon(
                    Icons.settings_outlined,
                  ),
                  selectedIcon: Icon(
                    Icons.settings,
                  ),
                  label: '设置',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}


class SettingsScreen extends StatelessWidget {
  const SettingsScreen({required this.controller, super.key});

  final AppSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final double currentScale = controller.textScaleFactor;
    final bool canIncrease = currentScale < 2.0;
    final bool canDecrease = currentScale > 1.0;

    final String currentValue =
        '${(currentScale * 100).round()}%';

    final String? increasedValue = canIncrease
        ? '${(((currentScale + 0.25).clamp(1.0, 2.0)) * 100).round()}%'
        : null;

    final String? decreasedValue = canDecrease
        ? '${(((currentScale - 0.25).clamp(1.0, 2.0)) * 100).round()}%'
        : null;

    void increaseTextSize() {
      controller.setTextScaleFactor(
        (currentScale + 0.25)
            .clamp(1.0, 2.0)
            .toDouble(),
      );
    }

    void decreaseTextSize() {
      controller.setTextScaleFactor(
        (currentScale - 0.25)
            .clamp(1.0, 2.0)
            .toDouble(),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        Semantics(
          header: true,
          child: Text(
            '无障碍设置',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('高对比度模式'),
          subtitle: const Text(
            '使用黑色背景、白色文字和黄色重点颜色。',
          ),
          secondary: const Icon(Icons.contrast),
          value: controller.highContrastEnabled,
          onChanged: controller.setHighContrastEnabled,
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: const Text('文字大小'),
          subtitle: Text(currentValue),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Semantics(
                container: true,
                excludeSemantics: true,
                slider: true,
                label: '文字缩放比例',
                value: currentValue,
                increasedValue: increasedValue,
                decreasedValue: decreasedValue,
                onIncrease:
                canIncrease ? increaseTextSize : null,
                onDecrease:
                canDecrease ? decreaseTextSize : null,
                child: LinearProgressIndicator(
                  value: currentScale - 1.0,
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 8,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed:
                    canDecrease ? decreaseTextSize : null,
                    icon: const Icon(Icons.remove),
                    label: const Text('减小文字'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                    canIncrease ? increaseTextSize : null,
                    icon: const Icon(Icons.add),
                    label: const Text('增大文字'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.lock_outline),
          title: Text('离线隐私'),
          subtitle: Text(
            '文件解析、索引和搜索都在本地设备上完成。',
          ),
        ),
      ],
    );
  }
}

