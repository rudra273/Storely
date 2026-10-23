import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// A small on-phone log of recent errors, attached to problem reports.
/// Keeps the last [maxLines] lines in app storage; never leaves the phone
/// unless the user shares a report.
class AppLog {
  static const maxLines = 300;
  static final List<String> _lines = [];
  static File? _file;

  /// Loads the saved log and starts recording Flutter and Dart errors.
  static Future<void> init() async {
    try {
      final dir = await getApplicationSupportDirectory();
      _file = File('${dir.path}/storely_log.txt');
      if (_file!.existsSync()) {
        _lines.addAll(_file!.readAsLinesSync().takeLast(maxLines));
      }
    } catch (_) {
      // Logging must never stop the app.
    }
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      error('Flutter', details.exception, details.stack);
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (exception, stack) {
      error('Dart', exception, stack);
      return false;
    };
  }

  static void info(String message) => _add('INFO  $message');

  static void error(String where, Object error, [StackTrace? stack]) {
    final frames = stack?.toString().split('\n').take(6).join('\n    ') ?? '';
    _add('ERROR $where: $error${frames.isEmpty ? '' : '\n    $frames'}');
  }

  static List<String> get lines => List.unmodifiable(_lines);

  static void _add(String line) {
    final stamped = '${DateTime.now().toIso8601String()} $line';
    _lines.add(stamped);
    if (_lines.length > maxLines)
      _lines.removeRange(0, _lines.length - maxLines);
    try {
      _file?.writeAsStringSync('${_lines.join('\n')}\n');
    } catch (_) {}
  }

  @visibleForTesting
  static void clear() => _lines.clear();
}

extension<T> on List<T> {
  Iterable<T> takeLast(int n) => length <= n ? this : sublist(length - n);
}
