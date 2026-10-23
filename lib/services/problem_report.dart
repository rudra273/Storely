import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/support_config.dart';
import '../db/database_helper.dart';
import 'app_log.dart';
import 'cloud_service.dart';
import 'sync_status.dart';

/// Builds a plain-text report for support: app and phone details, record
/// counts, sync state and recent errors. No customer names, phone numbers
/// or amounts are included.
class ProblemReport {
  static Future<String> build({String userNote = ''}) async {
    final buffer = StringBuffer('Storely problem report\n')
      ..writeln('Created: ${DateTime.now().toIso8601String()}');
    try {
      final info = await PackageInfo.fromPlatform();
      buffer.writeln('App: ${info.version} (${info.buildNumber})');
    } catch (_) {
      buffer.writeln('App: unknown version');
    }
    buffer.writeln(
      'Phone: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    if (userNote.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('What happened:')
        ..writeln(userNote.trim());
    }
    try {
      final db = await DatabaseHelper.instance.database;
      buffer
        ..writeln()
        ..writeln('Records:');
      for (final table in [
        'products',
        'bills',
        'customers',
        'stock_movements',
        'expenses',
      ]) {
        final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
        buffer.writeln('  $table: ${rows.first['n']}');
      }
    } catch (error) {
      buffer.writeln('Records: could not read ($error)');
    }
    final cloud = CloudService.instance.state.value;
    buffer
      ..writeln()
      ..writeln(
        'Cloud: ${cloud.isSignedIn ? 'signed in (${cloud.shopRole ?? 'no role'})' : 'not signed in'}',
      )
      ..writeln('Last sync: ${cloud.lastSyncedAt?.toIso8601String() ?? '-'}');
    if (cloud.error != null) buffer.writeln('Sync error: ${cloud.error}');
    final status = SyncStatus.instance;
    buffer.writeln('Waiting to upload: ${status.pendingTotal}');
    for (final c in status.conflicts.take(20)) {
      buffer.writeln('  not synced: ${c.table}: ${c.message}');
    }
    buffer
      ..writeln()
      ..writeln('Recent log (${AppLog.lines.length} lines):');
    for (final line in AppLog.lines.reversed.take(150).toList().reversed) {
      buffer.writeln(line);
    }
    return buffer.toString();
  }

  /// Writes the report to a file and opens the share sheet.
  static Future<void> share({String userNote = ''}) async {
    final text = await build(userNote: userNote);
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .substring(0, 16)
        .replaceAll(':', '');
    final file = File('${dir.path}/storely-report-$stamp.txt');
    await file.writeAsString(text);
    final to = SupportConfig.email.trim();
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/plain')],
        subject: 'Storely problem report',
        text: to.isEmpty
            ? 'Storely problem report attached.'
            : 'Please send to $to. Storely problem report attached.',
      ),
    );
  }
}
