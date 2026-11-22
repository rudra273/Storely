import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/screens/notifications_screen.dart';
import 'package:storely/screens/reports_screens.dart';
import 'package:storely/services/cloud_service.dart';
import 'package:storely/services/needs_action.dart';
import 'package:storely/theme/app_theme.dart';
import 'support/notification_fixture.dart';

void main() {
  final db = DatabaseHelper.instance;
  late CloudState original;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    original = CloudService.instance.state.value;
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'notification-test.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await seedNotificationFixture();
  });
  tearDown(() async {
    CloudService.instance.state.value = original;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  test(
    'overdue alert preserves paise, exact bucket boundary and tenant',
    () async {
      final snapshot = await NeedsAction.loadSnapshot();
      final overdue = snapshot.items.singleWhere(
        (i) => i.kind == NeedsActionKind.overdueDues,
      );
      expect(overdue.title, '3 customers owe for over 30 days');
      expect(overdue.detail, contains('354.75'));
      final rows = overdueAgeingRows(await db.receivablesAgeing());
      expect(
        rows.map((r) => r.customerName),
        containsAll(['Age 31', 'Age 60', 'Age 61']),
      );
      expect(rows.map((r) => r.customerName), isNot(contains('Age 30')));
      expect(rows.every((r) => r.buckets[0] == 0 && r.buckets[1] == 0), isTrue);
      expect(rows.fold<double>(0, (sum, r) => sum + r.total), 354.75);
    },
  );
  test('expiry includes expired and day seven, excludes day eight', () async {
    final rows = await expiringAlertBatches();
    expect(rows.map((r) => r.productName).toSet(), {'Expiry -1', 'Expiry 7'});
  });
  test(
    'workspace guard rejects owner switch and guards stock transaction',
    () async {
      final workspace = await NeedsActionWorkspace.capture();
      final product = (await db.getAllProducts()).first;
      await db.setCloudSyncState('preference_owner', 'other-owner');
      await expectLater(workspace.verify(), throwsStateError);
      expect(
        db.adjustStock(
          product.id!,
          delta: -1,
          reason: StockAdjustmentReason.expired,
          expectedScope: workspace.scope,
        ),
        throwsStateError,
      );
      expect((await db.getProductById(product.id!))!.quantity, 2);
    },
  );
  test(
    'staff business alerts hidden, unresolved signed-in ownership fails closed',
    () async {
      CloudService.instance.state.value = const CloudState(
        config: CloudConfig.api('https://test.invalid'),
        user: CloudUser(id: 'staff', email: 'staff@test.invalid'),
        membership: CloudMembership.member,
        shopRole: 'staff',
      );
      await expectLater(NeedsAction.loadSnapshot(), throwsStateError);
      await db.setCloudSyncState('preference_owner', 'staff');
      final snapshot = await NeedsAction.loadSnapshot();
      expect(
        snapshot.items.where(
          (i) =>
              i.kind == NeedsActionKind.overdueDues ||
              i.kind == NeedsActionKind.expiring,
        ),
        isEmpty,
      );
    },
  );
  Future<void> ready(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  testWidgets(
    'overdue tap opens filtered aggregate and a later account change removes its data',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: StorelyTheme.light(),
          home: const NotificationsScreen(),
        ),
      );
      final alert = find.byKey(const ValueKey('needs-action-overdueDues'));
      await ready(tester, alert);
      await tester.tap(alert);
      await ready(tester, find.text('Overdue dues'));
      await ready(tester, find.text('Age 31'));
      expect(find.text('Age 30'), findsNothing);
      expect(find.text('0-7 days'), findsNothing);
      expect(find.text('8-30 days'), findsNothing);
      expect(find.text('Foreign Customer'), findsNothing);
      final route = tester.widget<ReceivablesScreen>(
        find.byType(ReceivablesScreen),
      );
      expect(route.overdueOnly, isTrue);
      CloudService.instance.state.value = original.copyWith(shopRole: 'staff');
      await tester.pump();
      expect(find.text('Age 31'), findsNothing);
      expect(
        find.text('Workspace changed. Reopen Needs action.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('stale alert tap cannot open another workspace report', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: StorelyTheme.light(),
        home: const NotificationsScreen(),
      ),
    );
    final alert = find.byKey(const ValueKey('needs-action-overdueDues'));
    await ready(tester, alert);
    await tester.runAsync(
      () => db.setCloudSyncState('preference_owner', 'other-owner'),
    );
    await tester.tap(alert);
    await ready(tester, find.textContaining('Workspace changed'));
    expect(find.byType(ReceivablesScreen), findsNothing);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
}
