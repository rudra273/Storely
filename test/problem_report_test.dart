import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/services/app_log.dart';
import 'package:storely/services/problem_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (_) async => {
            'appName': 'Storely',
            'packageName': 'com.rudra.storely',
            'version': '2.0.0',
            'buildNumber': '6',
          },
        );
  });

  setUp(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    AppLog.clear();
  });

  test('report has app, counts and errors but no customer details', () async {
    await db.insertBill(
      Bill(
        customerName: 'Asha Sharma',
        customerPhone: '9876543210',
        totalAmount: 450,
        itemCount: 0,
      ),
      const [],
    );
    AppLog.error('Billing', StateError('printer offline'));

    final report = await ProblemReport.build(userNote: 'Print fails');
    expect(report, contains('App: 2.0.0 (6)'));
    expect(report, contains('bills: 1'));
    expect(report, contains('Print fails'));
    expect(report, contains('printer offline'));
    expect(report, isNot(contains('Asha')));
    expect(report, isNot(contains('9876543210')));
    expect(report, isNot(contains('450')));
  });
}
