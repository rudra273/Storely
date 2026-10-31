import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/config/cloud_defaults.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/http_client_factory.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:uuid/uuid.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/screens/premium_request_screen.dart';
import 'package:storely/services/cloud/premium_request_service.dart';
import 'package:storely/services/cloud_service.dart';
import 'package:storely/theme/app_theme.dart';
import 'support/full_shop_fixture.dart';

const run = String.fromEnvironment('PREMIUM_DEVICE_RUN');
const webDevice = bool.fromEnvironment('PREMIUM_WEB_DEVICE');
const mail = String.fromEnvironment('STORELY_MAIL_URL');
const password = 'Correct-Horse-Battery-Staple-42';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'premium activation → all-table clean restore → two-device/web round trip',
    (tester) async {
      expect(run, isNotEmpty);
      final prefs = await SharedPreferences.getInstance();
      final originalPrefs = {
        for (final key in prefs.getKeys()) key: prefs.get(key),
      };
      const secure = FlutterSecureStorage();
      final oldRefresh = await secure.read(key: 'storely_api_refresh_token');
      final oldRequest = await secure.read(key: 'storely_premium_request');
      final oldFile = DatabaseHelper.databaseFileName;
      final service = CloudService.instance;
      await DatabaseHelper.instance.close();
      DatabaseHelper.databaseFileName = 'premium_emulator_$run.db';
      await prefs.remove('storely_cloud_backend_mode');
      await prefs.remove('storely_api_last_user');
      await secure.delete(key: 'storely_api_refresh_token');
      await secure.delete(key: 'storely_premium_request');
      try {
        final db = DatabaseHelper.instance;
        await db.saveShopProfile(
          ShopProfile(
            name: 'Emulator Premium $run',
            phone: '+919123456789',
            address: 'Local profile address',
          ),
        );
        await db.insertProduct(
          Product(
            name: 'Offline Rice',
            mrp: 0,
            purchasePrice: 100,
            quantity: 10,
          ),
        );
        await service.initialize();
        await populateFullShop();
        final shopId = await db.currentShopId();
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            home: const PremiumRequestScreen(),
          ),
        );
        await tester.pumpAndSettle();
        Map<String, dynamic>? draft;
        if (!webDevice) {
          await tester.enterText(
            find.byType(TextFormField).at(0),
            'Emulator Owner',
          );
          await tester.enterText(
            find.byType(TextFormField).at(1),
            '+919876543210',
          );
          await tester.tap(find.byType(CheckboxListTile).first);
          await tester.pump();
          await tester.ensureVisible(find.text('Send premium request'));
          await tester.tap(find.text('Send premium request'));
          // Native networking and Keystore calls must complete before asserting UI state.
          for (var i = 0; i < 100; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            draft = await PremiumRequestService.instance.load();
            if (draft?['response'] != null &&
                find.text('Request: pending').evaluate().isNotEmpty) {
              break;
            }
          }
          expect(draft!['response']['status'], 'pending');
          expect(find.text('Request: pending'), findsOneWidget);
          expect(service.state.value.isConfigured, isFalse);
          expect(
            await db.getCloudSyncState('last_successful_cloud_sync_at'),
            isNull,
          );
        }
        await service.useStorelyCloud();
        final email = 'premium-$run@example.com';
        await service.signUp(email, password, syncAfterAuth: false);
        String? code;
        for (var i = 0; i < 60; i++) {
          final search =
              jsonDecode(
                    (await http.get(
                      Uri.parse('$mail/api/v1/search?query=to:$email'),
                    )).body,
                  )
                  as Map;
          final messages = search['messages'] as List;
          if (messages.isNotEmpty) {
            final message =
                jsonDecode(
                      (await http.get(
                        Uri.parse(
                          '$mail/api/v1/message/${messages.first['ID']}',
                        ),
                      )).body,
                    )
                    as Map;
            code = RegExp(
              r'\b(\d{6})\b',
            ).firstMatch(message['Text'] as String)?.group(1);
            if (code != null) break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        expect(code, isNotNull);
        await service.verifyEmail(email, code!);
        await service.signIn(email, password, syncAfterAuth: false);
        if (webDevice) {
          final api = ApiClient(
            baseUrl: Uri.parse(CloudDefaults.apiUrl),
            httpClient: createApiHttpClient(),
            tokens: MemoryTokenStore(),
          );
          try {
            await api.login(email, password);
            await api.postJson('/v1/me/premium-requests', {
              'id': const Uuid().v4(),
              'request_kind': 'existing_android',
              'shop_id': shopId,
              'shop_name': 'Emulator Premium $run',
              'contact_name': 'Web Emulator Owner',
              'phone': '+919876543210',
              'contact_consent': true,
            });
          } finally {
            api.dispose();
          }
          await tester.pumpWidget(const MaterialApp(home: SizedBox()));
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            MaterialApp(
              theme: StorelyTheme.light(),
              home: const PremiumRequestScreen(),
            ),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Find my web request'));
          await tester.tap(find.text('Find my web request'));
          for (var i = 0; i < 100; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await tester.pump();
            draft = await PremiumRequestService.instance.load();
            if (draft?['channel'] == 'web') break;
          }
          expect(draft?['channel'], 'web');
          expect(
            (draft!['body'] as Map).containsKey('receipt_secret'),
            isFalse,
          );
        }
        for (var i = 0; i < 60; i++) {
          if (webDevice) {
            await service.findWebPremiumRequest();
            draft = await PremiumRequestService.instance.load();
          } else {
            draft = await PremiumRequestService.instance.refresh();
          }
          if (draft!['response']['status'] == 'approved') break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        expect(draft!['response']['status'], 'approved');
        // Signing in and approval still do not authorize a business upload.
        await service.syncNow();
        expect(
          await db.getCloudSyncState('last_successful_cloud_sync_at'),
          isNull,
        );
        // Render the actual approved/consent screen and activate using its button.
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            home: const PremiumRequestScreen(),
          ),
        );
        await tester.pumpAndSettle();
        final checkbox = find.widgetWithText(
          CheckboxListTile,
          'Create a local backup and upload my existing business data.',
        );
        await tester.scrollUntilVisible(
          checkbox,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(checkbox);
        await tester.pump();
        await tester.ensureVisible(find.text('Back up and activate premium'));
        await tester.tap(find.text('Back up and activate premium'));
        for (var i = 0; i < 200; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
          if (service.state.value.lastSyncedAt != null) break;
        }
        expect(service.state.value.error, isNull);
        expect(service.state.value.lastSyncedAt, isNotNull);
        draft = await PremiumRequestService.instance.load();
        expect(draft!['response']['status'], 'activated');
        expect(await File(draft['backup_path'] as String).exists(), isTrue);
        expect((draft['body'] as Map)['local_shop_id'], shopId);
        expect(await db.cloudDirtyRows('products'), isEmpty);
        expect(await db.getSyncConflicts(), isEmpty);
        expect((await db.getShopProfile())!.phone, '+919123456789');
        expect((await db.getShopProfile())!.address, 'Local profile address');
        expect(
          (await db.getAllProducts()).any((p) => p.name == 'Offline Rice'),
          isTrue,
        );
        // A repeat activation/claim must not duplicate the uploaded product.
        await service.activatePremium();
        expect(
          (await db.getAllProducts())
              .where((p) => p.name == 'Offline Rice')
              .length,
          1,
        );
        await verifyCleanRestore(run, email, password);
        await tester.pumpAndSettle();
        await binding.convertFlutterSurfaceToImage();
        await tester.pump();
        final bytes = await binding.takeScreenshot('premium-activated');
        // Ask Android to create its scoped external directory; hardcoding
        // Android/data fails on a fresh installation under scoped storage.
        final output = await getExternalStorageDirectory();
        expect(output, isNotNull);
        await File('${output!.path}/premium-activated.png').writeAsBytes(bytes);
      } finally {
        await service.clearConfig();
        await DatabaseHelper.instance.close();
        DatabaseHelper.databaseFileName = oldFile;
        for (final key in prefs.getKeys()) {
          await prefs.remove(key);
        }
        for (final entry in originalPrefs.entries) {
          final value = entry.value;
          if (value is String) await prefs.setString(entry.key, value);
          if (value is bool) await prefs.setBool(entry.key, value);
          if (value is int) await prefs.setInt(entry.key, value);
          if (value is double) await prefs.setDouble(entry.key, value);
          if (value is List<String>) {
            await prefs.setStringList(entry.key, value);
          }
        }
        for (final entry in {
          'storely_api_refresh_token': oldRefresh,
          'storely_premium_request': oldRequest,
        }.entries) {
          if (entry.value == null) {
            await secure.delete(key: entry.key);
          } else {
            await secure.write(key: entry.key, value: entry.value);
          }
        }
      }
    },
  );
}
