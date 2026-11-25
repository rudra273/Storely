import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/screens/notifications_screen.dart';
import 'package:storely/screens/reports_screens.dart';
import 'package:storely/services/cloud_service.dart';
import 'package:storely/theme/app_theme.dart';
import '../test/support/notification_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Needs action opens the matching aggregate window and guarded device sheets',
    (tester) async {
      final db = DatabaseHelper.instance;
      final cloud = CloudService.instance;
      final originalState = cloud.state.value;
      await db.close();
      final originalName = DatabaseHelper.databaseFileName;
      DatabaseHelper.databaseFileName = 'notification-device-validation.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      SharedPreferences.setMockInitialValues({});
      Finder key(String kind) => find.byKey(ValueKey('needs-action-$kind'));
      Future<void> wait(Finder finder) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
      }

      Future<void> tap(Finder finder) async {
        await wait(finder);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> back() async {
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
      }

      try {
        await seedNotificationFixture();
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            home: const NotificationsScreen(),
          ),
        );
        await wait(key('overdueDues'));
        expect(find.textContaining('354.75'), findsOneWidget);
        await tap(key('overdueDues'));
        await wait(find.text('Age 31'));
        expect(find.text('Overdue dues'), findsOneWidget);
        expect(find.text('Age 30'), findsNothing);
        expect(find.text('Foreign Customer'), findsNothing);
        await back();
        await tap(key('expiring'));
        await wait(find.text('Expiry 7'));
        expect(find.text('Expiry 8'), findsNothing);
        expect(
          tester
              .widget<ExpiringStockScreen>(find.byType(ExpiringStockScreen))
              .initialDays,
          7,
        );
        await back();
        await tap(key('backup'));
        await wait(find.text('Backup & restore'));
        expect(find.byKey(const ValueKey('backup-now')), findsOneWidget);
        await back();
        await db.setCloudSyncState('preference_owner', 'alert-owner');
        cloud.state.value = const CloudState(
          config: CloudConfig.api('https://test.invalid'),
          user: CloudUser(id: 'alert-owner', email: 'alert@test.invalid'),
          membership: CloudMembership.member,
          shopRole: 'owner',
          error: 'Isolated sync warning',
        );
        await tester.pump();
        await tap(key('syncProblem'));
        await wait(find.text('Cloud sync'));
        cloud.state.value = cloud.state.value.copyWith(shopRole: 'staff');
        await tester.pumpAndSettle();
        expect(find.text('Cloud sync'), findsNothing);
        expect(
          find.text('Workspace changed. Reopen Needs action.'),
          findsOneWidget,
        );
        await back();
        await wait(find.text('Some changes could not sync'));
        expect(key('overdueDues'), findsNothing);
        expect(key('expiring'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        cloud.state.value = originalState;
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = originalName;
      }
    },
  );
}
