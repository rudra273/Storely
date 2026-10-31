// The real CloudService on a real (emulated) Android phone, talking to the real
// Storely API over TLS: Keystore storage, the network security rules, the on-device
// SQLite, sign-up with an emailed code, registering a shop, and a first sync.
//
// Run with `make test-device` in the storelyapi repo (boots nothing by itself:
// start the emulator first). Needs a debug build, which trusts the development CA.
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/http_client_factory.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/cloud_service.dart';

const _mail = String.fromEnvironment('STORELY_MAIL_URL');
const _password = 'Correct-Horse-Battery-Staple-42';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<String> emailCode(String email) async {
    for (var i = 0; i < 50; i++) {
      final search = await http.get(
        Uri.parse('$_mail/api/v1/search?query=to:$email'),
      );
      final messages = (jsonDecode(search.body)['messages'] as List?) ?? [];
      if (messages.isNotEmpty) {
        final message = await http.get(
          Uri.parse('$_mail/api/v1/message/${messages.first['ID']}'),
        );
        final match = RegExp(
          r'\b(\d{6})\b',
        ).firstMatch(jsonDecode(message.body)['Text'] as String);
        if (match != null) return match.group(1)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw StateError('no email for $email');
  }

  testWidgets('sign up, confirm, sign in, register a shop and sync', (
    tester,
  ) async {
    final email =
        'phone-${Random.secure().nextInt(1 << 30).toRadixString(16)}@example.com';
    final service = CloudService.instance;
    await service.initialize();

    // Storely Cloud resolves to the API (the debug build defines STORELY_API_URL and STORELY_CLOUD_PREVIEW=true).
    await service.useStorelyCloud();
    expect(service.state.value.mode, CloudBackendMode.storelyApi);
    expect(service.state.value.config!.isValid, isTrue);
    expect(service.supportsEmailCodes, isTrue);

    // A shop that already has stock on the phone before it ever goes online.
    await DatabaseHelper.instance.insertProduct(
      Product(name: 'Device Rice', mrp: 0, purchasePrice: 100, quantity: 10),
    );

    // Create the account; the app asks for the emailed code.
    final outcome = await service.signUp(
      email,
      _password,
      syncAfterAuth: false,
    );
    expect(outcome, SignUpOutcome.emailCodeSent);
    expect(service.state.value.isSignedIn, isFalse);

    // Signing in before confirming asks for the code instead of failing.
    await expectLater(
      service.signIn(email, _password, syncAfterAuth: false),
      throwsA(isA<CloudEmailNotVerified>()),
    );

    // A wrong code is refused with the server's own sentence.
    await expectLater(
      service.verifyEmail(email, '000000'),
      throwsA(predicate((e) => e.toString().contains('wrong or has expired'))),
    );
    await service.verifyEmail(email, await emailCode(email));

    // Wrong password, then the right one.
    await expectLater(
      service.signIn(email, 'Not-The-Password-123', syncAfterAuth: false),
      throwsA(predicate((e) => e.toString().contains('incorrect'))),
    );
    await service.signIn(email, _password, syncAfterAuth: false);
    expect(service.state.value.user?.email, email);
    expect(await service.currentUserHasShopMembership(), isFalse);

    // Register the shop and upload the product the phone already had.
    await service.registerShop();
    if (service.state.value.firstSyncChoicePending) {
      await service.chooseFirstSync(FirstSyncMode.uploadExisting);
    }
    await service.syncNow(reason: 'on-device test');
    final after = service.state.value;
    expect(after.error, isNull, reason: after.error);
    expect(after.membership, CloudMembership.member);
    expect(after.shopRole, 'owner');
    expect(after.lastSyncedAt, isNotNull);
    expect(await DatabaseHelper.instance.pendingSyncCounts(), isEmpty);

    // Signing out leaves nobody signed in.
    await service.signOut();
    expect(service.state.value.isSignedIn, isFalse);
  });

  testWidgets('the refresh token survives in the Android Keystore', (
    tester,
  ) async {
    final email =
        'keystore-${Random.secure().nextInt(1 << 30).toRadixString(16)}@example.com';
    const apiUrl = String.fromEnvironment('STORELY_API_URL');
    ApiClient newClient() => ApiClient(
      baseUrl: Uri.parse(apiUrl),
      httpClient: createApiHttpClient(),
      tokens: SecureTokenStore(),
    );

    final first = newClient();
    await first.signUp(email, _password);
    await first.verifyEmail(email, await emailCode(email));
    await first.login(email, _password);

    // A brand-new client (as after the app is killed and reopened) finds the
    // saved session in secure storage and is signed in without a password.
    final reopened = newClient();
    expect(await reopened.hasStoredSession(), isTrue);
    final user = await reopened.restoreSession();
    expect(user?.email, email);

    await reopened.logout();
    expect(await newClient().hasStoredSession(), isFalse);
  });

  testWidgets('without the development CA the phone refuses the local server', (
    tester,
  ) async {
    // A plain client uses only the phone's trusted authorities. Our development
    // CA is not among them, so this must fail the TLS handshake. It is also what a
    // release build does, whatever is passed in.
    await expectLater(
      http.Client().get(
        Uri.parse('${const String.fromEnvironment('STORELY_API_URL')}/health'),
      ),
      throwsA(
        predicate(
          (e) =>
              e.toString().toLowerCase().contains('certificate') ||
              e.toString().contains('Handshake'),
        ),
      ),
    );
  });

  testWidgets('the app refuses to be pointed at plain http', (tester) async {
    expect(
      () => ApiClient(
        baseUrl: Uri.parse('http://10.0.2.2'),
        httpClient: createApiHttpClient(),
        tokens: MemoryTokenStore(),
      ),
      throwsArgumentError,
    );
  });
}
