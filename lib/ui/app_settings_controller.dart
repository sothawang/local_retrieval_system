import 'package:flutter/foundation.dart';

/// 这是一个依赖/服务
/// 应用外观与无障碍（Accessibility）相关状态的集中管理与响应式通知。
class AppSettingsController extends ChangeNotifier {
  /// 记录是否开启高对比度模式，默认 false
  bool _highContrastEnabled = false;
  /// 记录文字缩放比例，默认 1.0（即 100%）
  double _textScaleFactor = 1.0;

  bool get highContrastEnabled => _highContrastEnabled;

  double get textScaleFactor => _textScaleFactor;

  void setHighContrastEnabled(bool enabled) {
    if (_highContrastEnabled == enabled) {
      return;
    }

    _highContrastEnabled = enabled;
    notifyListeners();
  }

  void setTextScaleFactor(double value) {
    final double normalizedValue =
    value.clamp(1.0, 2.0).toDouble();

    if (_textScaleFactor == normalizedValue) {
      return;
    }

    _textScaleFactor = normalizedValue;
    notifyListeners();
  }
}