import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';

/// What a backup file contains, read before restoring it.
class BackupInfo {
  final String shopName;
  final DateTime createdAt;
  final int products;
  final int bills;
  final int customers;

  const BackupInfo({
    required this.shopName,
    required this.createdAt,
    required this.products,
    required this.bills,
    required this.customers,
  });

  Map<String, Object> toJson() => {
    'format': BackupService.format,
    'shop_name': shopName,
    'created_at': createdAt.toIso8601String(),
    'products': products,
    'bills': bills,
    'customers': customers,
  };

  factory BackupInfo.fromJson(Map<String, dynamic> json) => BackupInfo(
    shopName: json['shop_name'] as String? ?? 'Shop',
    createdAt: DateTime.parse(json['created_at'] as String),
    products: json['products'] as int? ?? 0,
    bills: json['bills'] as int? ?? 0,
    customers: json['customers'] as int? ?? 0,
  );
}

class BackupException implements Exception {
  final String message;
  const BackupException(this.message);
  @override
  String toString() => message;
}

/// One-file backup of all shop data: a zip holding a consistent copy of the
/// SQLite database plus a small manifest. Restoring replaces this phone's
/// data, after keeping a copy of what was there.
class BackupService {
  static const format = 'storely-backup-1';
  static const _dbEntry = 'storely.db';
  static const _manifestEntry = 'manifest.json';
  static const _lastBackupKey = 'last_backup_at';

  static Future<DateTime?> lastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastBackupKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<int> _count(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM $table WHERE deleted_at IS NULL',
    );
    return (rows.first['n'] as num).toInt();
  }

  /// Builds the backup zip in a temp folder and returns its path.
  static Future<File> createBackupFile({Directory? workDir}) async {
    final helper = DatabaseHelper.instance;
    final db = await helper.database;
    final tmp = workDir ?? await getTemporaryDirectory();
    final snapshot = File(p.join(tmp.path, 'storely_snapshot.db'));
    if (snapshot.existsSync()) snapshot.deleteSync();
    // A consistent copy even while the app is writing.
    await db.execute('VACUUM INTO ?', [snapshot.path]);

    final shop = await helper.getShopProfile();
    final info = BackupInfo(
      shopName: shop?.name ?? 'Shop',
      createdAt: DateTime.now(),
      products: await _count(db, 'products'),
      bills: await _count(db, 'bills'),
      customers: await _count(db, 'customers'),
    );
    final dbBytes = await snapshot.readAsBytes();
    final manifest = utf8.encode(jsonEncode(info.toJson()));
    final archive = Archive()
      ..addFile(ArchiveFile(_dbEntry, dbBytes.length, dbBytes))
      ..addFile(ArchiveFile(_manifestEntry, manifest.length, manifest));
    final zipped = ZipEncoder().encode(archive)!;
    snapshot.deleteSync();

    final safeName = info.shopName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp = DateFormat('yyyy-MM-dd_HHmm').format(info.createdAt);
    final file = File(
      p.join(
        tmp.path,
        'Storely-backup-${safeName.isEmpty ? 'shop' : safeName}-$stamp.zip',
      ),
    );
    await file.writeAsBytes(zipped);
    return file;
  }

  /// Creates a backup and opens the share sheet (Drive, WhatsApp, Files...).
  static Future<void> shareBackup() async {
    final file = await createBackupFile();
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/zip')],
        subject: 'Storely backup',
      ),
    );
    if (result.status != ShareResultStatus.dismissed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastBackupKey, DateTime.now().toIso8601String());
    }
  }

  /// Reads and checks a backup file. Throws [BackupException] when it is
  /// not a Storely backup or is damaged.
  static Future<(BackupInfo, List<int>)> readBackup(
    List<int> bytes, {
    Directory? workDir,
  }) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const BackupException('This is not a Storely backup file.');
    }
    final manifest = archive.findFile(_manifestEntry);
    final dbFile = archive.findFile(_dbEntry);
    if (manifest == null || dbFile == null) {
      throw const BackupException('This is not a Storely backup file.');
    }
    final json =
        jsonDecode(utf8.decode(manifest.content as List<int>))
            as Map<String, dynamic>;
    if (json['format'] != format) {
      throw const BackupException(
        'This backup was made by a newer Storely. Update the app first.',
      );
    }
    final dbBytes = dbFile.content as List<int>;
    // Check the database opens and looks like Storely's before using it.
    final tmp = workDir ?? await getTemporaryDirectory();
    final probe = File(p.join(tmp.path, 'storely_restore_probe.db'));
    await probe.writeAsBytes(dbBytes, flush: true);
    try {
      final db = await openDatabase(probe.path, readOnly: true);
      try {
        final check = await db.rawQuery('PRAGMA integrity_check');
        if (check.first.values.first != 'ok') {
          throw const BackupException('This backup file is damaged.');
        }
        await db.rawQuery('SELECT COUNT(*) FROM shops');
        await db.rawQuery('SELECT COUNT(*) FROM bills');
      } finally {
        await db.close();
      }
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('This backup file is damaged.');
    } finally {
      if (probe.existsSync()) probe.deleteSync();
    }
    return (BackupInfo.fromJson(json), dbBytes);
  }

  /// Replaces this phone's data with [dbBytes]. The current database is
  /// first copied to the app's documents folder (pre-restore copy).
  static Future<void> restore(List<int> dbBytes, {Directory? keepDir}) async {
    final helper = DatabaseHelper.instance;
    final path = await DatabaseHelper.databasePath();
    final docs = keepDir ?? await getApplicationDocumentsDirectory();
    final current = File(path);
    if (current.existsSync()) {
      final db = await helper.database;
      final keep = File(p.join(docs.path, 'storely_before_restore.db'));
      if (keep.existsSync()) keep.deleteSync();
      await db.execute('VACUUM INTO ?', [keep.path]);
    }
    await helper.close();
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File('$path$suffix');
      if (f.existsSync()) f.deleteSync();
    }
    await File(path).writeAsBytes(dbBytes, flush: true);
    // Reopen: runs any migrations an older backup needs.
    await helper.database;
    notifyDatabaseChanged();
  }
}
