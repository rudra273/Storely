import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/backup_service.dart';

void main() {
  final db = DatabaseHelper.instance;
  late Directory work;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    work = await Directory.systemTemp.createTemp('storely_backup_test');
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    await work.delete(recursive: true);
  });

  test('backup then restore brings the data back', () async {
    await db.insertProduct(Product(name: 'Rice', mrp: 60, quantity: 10));
    await db.insertProduct(Product(name: 'Dal', mrp: 90, quantity: 5));

    final file = await BackupService.createBackupFile(workDir: work);
    final (info, bytes) = await BackupService.readBackup(
      await file.readAsBytes(),
      workDir: work,
    );
    expect(info.products, 2);

    // Data changes after the backup...
    await db.insertProduct(Product(name: 'Sugar', mrp: 45, quantity: 1));
    expect(await db.getAllProducts(), hasLength(3));

    // ...and restore puts the backup's data back, keeping a copy first.
    await BackupService.restore(bytes, keepDir: work);
    final names = (await db.getAllProducts()).map((p) => p.name).toSet();
    expect(names, {'Rice', 'Dal'});
    expect(
      File(p.join(work.path, 'storely_before_restore.db')).existsSync(),
      isTrue,
    );
  });

  test(
    'backup preserves interrupted payment identity and recovers it as unknown',
    () async {
      final sql = await db.database;
      final shop = await db.currentShopId();
      const payload = '{"request_key":"backup-payment","amount":"0.01"}';
      await sql.insert('supplier_payment_queue', {
        'request_key': 'backup-payment',
        'shop_id': shop,
        'supplier_uuid': 'supplier',
        'payload': payload,
        'sync_state': 'pending',
        'created_at': '2026-10-01',
      });
      expect(
        await db.beginSupplierPaymentAttempt('backup-payment', shopId: shop),
        isTrue,
      );
      final file = await BackupService.createBackupFile(workDir: work);
      final (_, bytes) = await BackupService.readBackup(
        await file.readAsBytes(),
        workDir: work,
      );
      await sql.delete('supplier_payment_queue');
      await BackupService.restore(bytes, keepDir: work);
      final restored = (await db.pendingSupplierPayments()).single;
      expect(restored['request_key'], 'backup-payment');
      expect(restored['payload'], payload);
      expect(restored['command_state'], 'unknown');
      expect(restored['attempt_count'], 1);
      expect(restored['last_attempt_at'], isNotNull);
    },
  );

  test('other files are refused', () async {
    expect(
      () => BackupService.readBackup([1, 2, 3, 4], workDir: work),
      throwsA(isA<BackupException>()),
    );
  });
}
