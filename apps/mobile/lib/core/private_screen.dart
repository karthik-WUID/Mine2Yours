import 'dart:async';

import 'package:flutter/foundation.dart';

import 'audio.dart';

/// Personnel routes prevent Android screenshots/task previews while visible.
class PrivateScreenGuard {
  static int _routes = 0;
  bool _active = false;
  void open() {
    if (_active) return;
    _active = true;
    _routes++;
    _set();
  }

  void close() {
    if (!_active) return;
    _active = false;
    _routes--;
    _set();
  }

  static void _set() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      unawaited(
        AudioService.channel
            .invokeMethod('privateScreen', {'enabled': _routes > 0})
            .then((_) {}, onError: (_) {}),
      );
    }
  }
}
