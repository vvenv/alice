import 'dart:async';

import 'package:flutter/foundation.dart';

/// Toast 状态。对应 RN 版 src/hooks/useToast.ts。
const Duration _toastDuration = Duration(milliseconds: 2200);

/// 带操作按钮的 toast 停留久一点 —— 用户需要时间点「撤销」。
const Duration _toastActionDuration = Duration(milliseconds: 4000);

class ToastAction {
  const ToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

class ToastState {
  const ToastState({required this.message, this.action});

  final String message;
  final ToastAction? action;
}

class ToastController extends ChangeNotifier {
  ToastState? _toast;
  Timer? _timer;
  bool _disposed = false;

  ToastState? get toast => _toast;

  void show(String message, {ToastAction? action}) {
    _toast = ToastState(message: message, action: action);
    _timer?.cancel();
    _timer = Timer(action != null ? _toastActionDuration : _toastDuration, () {
      _toast = null;
      if (!_disposed) notifyListeners();
    });
    if (!_disposed) notifyListeners();
  }

  void hide() {
    _timer?.cancel();
    _timer = null;
    _toast = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
