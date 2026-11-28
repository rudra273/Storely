import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill_settings.dart';

void main() {
  for (final raw in ['80mm', '58mm']) {
    test(
      // Thermal sizes are first-class paper choices since E12.
      '$raw survives unrelated model edits as a thermal paper size',
      () {
        final original = BillSettings.fromMap({'paper_size': raw});
        expect(original.paperSize, raw);
        final edited = original
            .copyWith(invoiceTitle: 'Custom title')
            .copyWith(footerText: 'Custom footer');
        expect(edited.paperSize, raw);
        expect(edited.toMap()['paper_size'], raw);
        expect(edited.toMap().containsKey('preservedPaperSize'), isFalse);
        for (final explicit in [BillSettings.paperA4, BillSettings.paperA5]) {
          final chosen = edited.copyWith(paperSize: explicit);
          expect(chosen.paperSize, explicit);
          expect(
            chosen.copyWith(termsText: 'Terms').toMap()['paper_size'],
            explicit,
          );
        }
      },
    );
  }

  test(
    'supported and malformed paper values retain the existing fallback policy',
    () {
      for (final supported in [
        BillSettings.paperA4,
        BillSettings.paperA5,
        BillSettings.paper80mm,
        BillSettings.paper58mm,
      ]) {
        final settings = BillSettings.fromMap({'paper_size': supported});
        expect(settings.paperSize, supported);
        expect(
          settings.copyWith(footerText: 'Edited').toMap()['paper_size'],
          supported,
        );
      }
      for (final unknown in [null, '', 'unknown', '80mm ', 80]) {
        final settings = BillSettings.fromMap({'paper_size': unknown});
        expect(settings.paperSize, BillSettings.paperA4);
        expect(
          settings.copyWith(footerText: 'Edited').toMap()['paper_size'],
          BillSettings.paperA4,
        );
      }
    },
  );

  group('persisted paper compatibility', () {
    final db = DatabaseHelper.instance;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      await db.close();
      DatabaseHelper.databaseFileName = 'paper-compatibility.db';
      await deleteDatabase(await DatabaseHelper.databasePath());
      await db.saveBillSettings(BillSettings());
    });
    tearDown(() async {
      await db.close();
      await deleteDatabase(await DatabaseHelper.databasePath());
      DatabaseHelper.databaseFileName = 'storely.db';
    });
    for (final raw in ['80mm', '58mm']) {
      test(
        'guarded title/footer save preserves $raw until an explicit paper choice',
        () async {
          final sql = await db.database;
          await sql.update('bill_settings', {
            'paper_size': raw,
            'sync_dirty': 2,
          });
          final baseline = await db.captureSettingsEditBaseline();
          final loaded = await db.getBillSettings();
          final series = await db.getDefaultInvoiceSeriesSettings();
          expect(loaded.paperSize, raw);
          await db.saveInvoiceSettings(
            loaded.copyWith(
              invoiceTitle: 'Edited title',
              footerText: 'Edited footer',
            ),
            series,
            baseline: baseline,
          );
          final row = (await sql.query('bill_settings')).single;
          expect(row['paper_size'], raw);
          expect(row['invoice_title'], 'Edited title');
          expect(row['footer_text'], 'Edited footer');
          await db.close();
          expect((await db.getBillSettings()).toMap()['paper_size'], raw);
          final nextBaseline = await db.captureSettingsEditBaseline();
          await db.saveInvoiceSettings(
            (await db.getBillSettings()).copyWith(
              paperSize: BillSettings.paperA4,
            ),
            await db.getDefaultInvoiceSeriesSettings(),
            baseline: nextBaseline,
          );
          expect(
            (await (await db.database).query(
              'bill_settings',
            )).single['paper_size'],
            BillSettings.paperA4,
          );
        },
      );
    }
  });
}
