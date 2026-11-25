import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/settings_search.dart';
import 'package:storely/screens/store_screen.dart';
import 'package:storely/services/cloud_service.dart';
import 'package:storely/theme/app_theme.dart';

void main() {
  final db = DatabaseHelper.instance;
  final cloud = CloudService.instance;
  late CloudState original;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    original = cloud.state.value;
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'settings-search-test.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveShopName('Private Sapphire Shop');
  });
  tearDown(() async {
    cloud.state.value = original;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  test('task aliases use literal case-insensitive labels only', () {
    for (final pair in [
      (' GSTIN ', 'Shop Profile'),
      ('margin', 'Pricing Defaults'),
      ('threshold', 'Low-stock alert'),
      ('footer', 'Bill Settings'),
      ('paper size', 'Bill Settings'),
      ('printer', 'App Settings'),
      ('theme', 'App Settings'),
      ('catalog', 'Categories'),
      ('Data & security', 'App Settings'),
      ('Help & about', 'Privacy policy'),
    ]) {
      expect(matchesSettingsSearch(pair.$1, pair.$2), isTrue);
    }
    expect(matchesSettingsSearch('.*', 'Bill Settings'), isFalse);
    expect(
      matchesSettingsSearch('Private Sapphire Shop', 'Shop Profile'),
      isFalse,
    );
    expect(matchesSettingsSearch('   ', 'Bill Settings'), isTrue);
  });
  Future<void> ready(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 150 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  final search = find.byKey(const ValueKey('store-settings-search'));
  Finder label(String text) =>
      find.byWidgetPredicate((w) => w is Text && w.data == text);
  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: StorelyTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const StoreScreen(),
      ),
    );
    await ready(tester, search);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets(
    'filter never indexes values, aliases open same editor and clearing restores rows',
    (tester) async {
      await mount(tester);
      final before = await tester.runAsync(db.captureSettingsEditBaseline);
      await tester.enterText(search, 'Private Sapphire Shop');
      await tester.pump();
      expect(label('No matching settings'), findsOneWidget);
      expect(label('Private Sapphire Shop'), findsNothing);
      await tester.enterText(search, 'threshold');
      await tester.pump();
      expect(label('Low-stock alert'), findsOneWidget);
      expect(label('Pricing Defaults'), findsNothing);
      expect(label('Billing'), findsNothing);
      await tester.tap(label('Low-stock alert'));
      await ready(tester, label('Needs Attention'));
      await tester.tap(label('Cancel'));
      await tester.pumpAndSettle();
      expect(await tester.runAsync(db.captureSettingsEditBaseline), isNotNull);
      expect(
        (await tester.runAsync(db.captureSettingsEditBaseline))!.toLocalMap(),
        before!.toLocalMap(),
      );
      await tester.enterText(search, '');
      await tester.pump();
      expect(label('Bill Settings'), findsOneWidget);
      expect(label('Pricing Defaults'), findsOneWidget);
      await unmount(tester);
    },
  );
  testWidgets(
    'staff hidden team stays hidden and role transition clears search but sync flags do not',
    (tester) async {
      cloud.state.value = const CloudState(
        config: CloudConfig.api('https://test.invalid'),
        user: CloudUser(id: 'staff', email: 'staff@test.invalid'),
        membership: CloudMembership.member,
        shopRole: 'staff',
      );
      await mount(tester);
      await tester.enterText(search, 'members');
      await tester.pump();
      expect(label('No matching settings'), findsOneWidget);
      expect(label('Team Members'), findsNothing);
      cloud.state.value = cloud.state.value.copyWith(
        phase: CloudSyncPhase.syncing,
      );
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, 'members');
      cloud.state.value = cloud.state.value.copyWith(shopRole: 'owner');
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      await tester.enterText(search, 'members');
      await tester.pump();
      expect(label('Team Members'), findsOneWidget);
      expect(label('Cloud Backup & Sync'), findsNothing);
      await unmount(tester);
    },
  );
  testWidgets(
    'a stale account cannot open a previously matched settings editor',
    (tester) async {
      await mount(tester);
      await tester.enterText(search, 'threshold');
      await tester.pump();
      expect(label('Low-stock alert'), findsOneWidget);
      await tester.runAsync(
        () => db.setCloudSyncState('preference_owner', 'different-owner'),
      );
      await tester.tap(label('Low-stock alert'));
      await ready(tester, label('Shop changed. Search settings again.'));
      expect(label('Needs Attention'), findsNothing);
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      await unmount(tester);
    },
  );
}
