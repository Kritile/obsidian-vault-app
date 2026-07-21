import 'package:flutter/foundation.dart';

abstract final class AppLog {
  static void debug(String area, String message) => _write('DEBUG', area, message);
  static void info(String area, String message) => _write('INFO ', area, message);
  static void warning(String area, String message) => _write('WARN ', area, message);

  static void error(String area, String message, [Object? error, StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    _write('ERROR', area, '$message${error == null ? '' : ' · $error'}');
    if (stackTrace != null) debugPrintStack(stackTrace: stackTrace, label: '[PavelVault][$area] stack trace');
  }

  static void _write(String level, String area, String message) {
    if (!kDebugMode) return;
    final time = DateTime.now().toIso8601String();
    debugPrint('$time [$level] [PavelVault:$area] $message');
  }
}

