import 'package:flutter/material.dart';

import 'app_settings_controller.dart';
import 'home_shell.dart';
import 'package:local_retrieval_system/retrieval/retrieval_engine_interface.dart';

/// 客户端，使用依赖的类
class LocalRetrievalApp extends StatelessWidget {
  const LocalRetrievalApp({
    required this.settingsController,
    required this.retrievalEngine,
    super.key,
  });

  final AppSettingsController settingsController;
  final RetrievalEngineInterface retrievalEngine;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settingsController,
      builder: (BuildContext context, Widget? child) {
        return MaterialApp(
          title: 'Offline Local Retrieval',
          debugShowCheckedModeBanner: false,
          theme: _buildStandardTheme(),
          darkTheme: _buildHighContrastTheme(),
          themeMode: settingsController.highContrastEnabled
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (
              BuildContext context,
              Widget? child,
              ) {
            final MediaQueryData mediaQuery =
            MediaQuery.of(context);

            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(
                  settingsController.textScaleFactor,
                ),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: HomeShell(
            settingsController: settingsController,
            retrievalEngine: retrievalEngine,
          ),
        );
      },
    );
  }

  ThemeData _buildStandardTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
      visualDensity: VisualDensity.standard,
    );
  }

  ThemeData _buildHighContrastTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.black,
      focusColor: Colors.yellow,
      dividerColor: Colors.white,
      colorScheme: const ColorScheme.dark(
        primary: Colors.yellow,
        onPrimary: Colors.black,
        secondary: Colors.cyanAccent,
        onSecondary: Colors.black,
        surface: Colors.black,
        onSurface: Colors.white,
        error: Colors.redAccent,
        onError: Colors.black,
      ),
    );
  }
}