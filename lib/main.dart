import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'app/app_backend.dart';
import 'ui/app_settings_controller.dart';
import 'ui/local_retrieval_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 在直接调用 PdfDocument API 前初始化 pdfrx/PDFium。
  pdfrxFlutterInitialize();

  try {
    final retrievalEngine =
    await buildRetrievalEngine();

    runApp(
      LocalRetrievalApp(
        settingsController:
        AppSettingsController(),
        retrievalEngine: retrievalEngine,
      ),
    );
  } catch (error) {
    runApp(
      BackendInitializationErrorApp(
        message: error.toString(),
      ),
    );
  }
}

class BackendInitializationErrorApp
    extends StatelessWidget {
  const BackendInitializationErrorApp({
    required this.message,
    super.key,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Initialization Error',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Colors.red,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '应用初始化失败',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '请确认 ChromaDB 本地服务已经启动，然后重新运行应用。',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    message,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}