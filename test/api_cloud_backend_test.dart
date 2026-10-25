import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/cloud/api_cloud_backend.dart';
import 'package:storely/services/cloud/cloud_backend.dart';
import 'package:storely/services/cloud_service.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response failure(int status, String code, String message) => json({
  'error': {'code': code, 'message': message},
}, status);

const tokens = {'access_token': 'a', 'refresh_token': 'r', 'expires_in': 900};
const me = {'id': 'u1', 'email': 'a@b.com', 'email_verified': true};

class Harness {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final routes = <String, http.Response Function(http.Request)>{};
  late final ApiCloudBackend backend;
  late final ApiClient api;

  Harness({MemoryTokenStore? store}) {
    api = ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      httpClient: MockClient((request) async {
        final key = '${request.method} ${request.url.path}';
        calls.add(key);
        bodies[key] = request.body.isEmpty ? null : jsonDecode(request.body);
        final route = routes[key];
        return route == null
            ? failure(404, 'x', 'no route $key')
            : route(request);
      }),
      tokens: store ?? MemoryTokenStore(),
    );
    backend = ApiCloudBackend(api);
  }
}

void main() {
  group('signing in', () {
    test('a normal sign-in returns the person', () async {
      final h = Harness()
        ..routes['POST /v1/auth/login'] = ((_) => json(tokens))
        ..routes['GET /v1/me'] = ((_) => json(me));
      final user = await h.backend.signIn('a@b.com', 'pw');
      expect(user.email, 'a@b.com');
      expect(h.backend.currentUser?.id, 'u1');
    });

    test(
      'two-factor: the password step throws, the code step finishes',
      () async {
        final h = Harness()
          ..routes['POST /v1/auth/login'] = ((_) =>
              json({'mfa_required': true, 'mfa_token': 'chal'}))
          ..routes['POST /v1/auth/mfa/verify'] = ((_) => json(tokens))
          ..routes['GET /v1/me'] = ((_) => json(me));
        await expectLater(
          h.backend.signIn('a@b.com', 'pw'),
          throwsA(isA<CloudMfaRequired>()),
        );
        expect(h.backend.currentUser, isNull);

        final user = await h.backend.completeMfa('123456');
        expect(user.email, 'a@b.com');
        expect(h.bodies['POST /v1/auth/mfa/verify'], {
          'mfa_token': 'chal',
          'code': '123456',
        });
      },
    );

    test(
      'a code without a password step first is a clear error, not a request',
      () async {
        final h = Harness();
        await expectLater(h.backend.completeMfa('123456'), throwsStateError);
        expect(h.calls, isEmpty);
      },
    );

    test(
      'an unconfirmed address asks for the email code instead of failing',
      () async {
        final h = Harness()
          ..routes['POST /v1/auth/login'] = ((_) => failure(
            403,
            'email_not_verified',
            'Verify your email address first.',
          ));
        await expectLater(
          h.backend.signIn(' a@b.com ', 'pw'),
          throwsA(
            isA<CloudEmailNotVerified>().having(
              (e) => e.email,
              'email',
              'a@b.com',
            ),
          ),
        );
      },
    );

    test('wrong credentials surface the server message untouched', () async {
      final h = Harness()
        ..routes['POST /v1/auth/login'] = ((_) => failure(
          401,
          'invalid_credentials',
          'Email or password is incorrect.',
        ));
      await expectLater(
        h.backend.signIn('a@b.com', 'nope'),
        throwsA(
          predicate((e) => e.toString() == 'Email or password is incorrect.'),
        ),
      );
    });
  });

  group('account', () {
    test('sign-up asks for an emailed code and signs nobody in', () async {
      final h = Harness()
        ..routes['POST /v1/auth/signup'] = ((_) =>
            json({'status': 'verification_sent'}, 202));
      final result = await h.backend.signUp('a@b.com', 'a-long-passphrase-123');
      expect(result.outcome, SignUpOutcome.emailCodeSent);
      expect(result.user, isNull);
      expect(h.backend.supportsEmailCodes, isTrue);
    });

    test(
      'verify, resend, forgot and reset hit the right endpoints with the right bodies',
      () async {
        final h = Harness()
          ..routes['POST /v1/auth/verify-email'] = ((_) =>
              json({'status': 'verified'}))
          ..routes['POST /v1/auth/resend-verification'] = ((_) =>
              json({'status': 'verification_sent'}, 202))
          ..routes['POST /v1/auth/password/forgot'] = ((_) =>
              json({'status': 'reset_code_sent'}, 202))
          ..routes['POST /v1/auth/password/reset'] = ((_) =>
              json({'status': 'password_reset'}));
        await h.backend.verifyEmail('a@b.com', '123456');
        await h.backend.resendVerificationCode('a@b.com');
        await h.backend.forgotPassword('a@b.com');
        await h.backend.resetPassword(
          'a@b.com',
          '654321',
          'new-passphrase-456',
        );
        expect(h.bodies['POST /v1/auth/verify-email'], {
          'email': 'a@b.com',
          'code': '123456',
        });
        expect(h.bodies['POST /v1/auth/password/reset'], {
          'email': 'a@b.com',
          'code': '654321',
          'new_password': 'new-passphrase-456',
        });
      },
    );
  });

  group('shops and members', () {
    Harness signedIn() => Harness()
      ..routes['POST /v1/auth/login'] = ((_) => json(tokens))
      ..routes['GET /v1/me'] = ((_) => json(me));

    test('membership is "has any shop"', () async {
      final yes = signedIn()
        ..routes['GET /v1/shops'] = ((_) => json([
          {'shop_id': 's'},
        ]));
      await yes.backend.signIn('a@b.com', 'pw');
      expect(await yes.backend.hasShopMembership(), isTrue);
      final no = signedIn()..routes['GET /v1/shops'] = ((_) => json([]));
      await no.backend.signIn('a@b.com', 'pw');
      expect(await no.backend.hasShopMembership(), isFalse);
    });

    test('registering a shop keeps the phone\'s own shop id', () async {
      final h = signedIn()
        ..routes['POST /v1/shops'] = ((_) =>
            json({'shop_id': 'phone-id', 'status': 'created'}, 201));
      await h.backend.signIn('a@b.com', 'pw');
      await h.backend.registerShop(
        const ShopRegistration(
          shopId: 'phone-id',
          name: 'Sharma Kirana',
          gstin: '27AAAAA0000A1Z5',
        ),
      );
      expect(h.bodies['POST /v1/shops'], containsPair('shop_id', 'phone-id'));
      expect(h.bodies['POST /v1/shops'], containsPair('name', 'Sharma Kirana'));
    });

    test('the role is null (not an error) when it cannot be read', () async {
      final h = signedIn()
        ..routes['GET /v1/shops/s1/role'] = ((_) =>
            failure(500, 'internal_error', 'x'));
      await h.backend.signIn('a@b.com', 'pw');
      expect(await h.backend.fetchRole('s1'), isNull);
      h.routes['GET /v1/shops/s1/role'] = ((_) => json({'role': 'admin'}));
      expect(await h.backend.fetchRole('s1'), 'admin');
    });

    test('members and invites are mapped for the existing screens', () async {
      final h = signedIn()
        ..routes['GET /v1/shops/s1/members'] = ((_) => json([
          {
            'user_id': 'u1',
            'email': 'owner@x.in',
            'full_name': null,
            'role': 'owner',
            'created_at': '2026-10-01T00:00:00Z',
          },
          {
            'user_id': 'u2',
            'email': 'staff@x.in',
            'full_name': 'Ravi',
            'role': 'staff',
            'created_at': '2026-10-02T00:00:00Z',
          },
        ]))
        ..routes['GET /v1/shops/s1/invites'] = ((_) => json([
          {
            'id': 'i1',
            'email': 'new@x.in',
            'role': 'staff',
            'created_at': '2026-10-03T00:00:00Z',
          },
        ]));
      await h.backend.signIn('a@b.com', 'pw');
      final members = await h.backend.listMembers('s1');
      expect(members.map((m) => (m.email, m.role, m.isOwner)), [
        ('owner@x.in', 'owner', true),
        ('staff@x.in', 'staff', false),
      ]);
      expect(members.first.joinedAt, DateTime.utc(2026, 10, 1));
      final invites = await h.backend.listPendingInvites('s1');
      expect(invites.single.id, 'i1');
      expect(invites.single.email, 'new@x.in');
    });

    test(
      'invite, change role, remove and revoke use the right methods and paths',
      () async {
        final h = signedIn()
          ..routes['POST /v1/shops/s1/invites'] = ((_) =>
              json({'id': 'i1'}, 201))
          ..routes['PATCH /v1/shops/s1/members/u2'] = ((_) =>
              json({'status': 'updated'}))
          ..routes['DELETE /v1/shops/s1/members/u2'] = ((_) =>
              http.Response('', 204))
          ..routes['DELETE /v1/shops/s1/invites/i1'] = ((_) =>
              http.Response('', 204));
        await h.backend.signIn('a@b.com', 'pw');
        await h.backend.inviteMember('s1', 'new@x.in', 'staff');
        await h.backend.changeMemberRole('s1', 'u2', 'admin');
        await h.backend.removeMember('s1', 'u2');
        await h.backend.revokeInvite('s1', 'i1');
        expect(h.bodies['POST /v1/shops/s1/invites'], {
          'email': 'new@x.in',
          'role': 'staff',
        });
        expect(h.bodies['PATCH /v1/shops/s1/members/u2'], {'role': 'admin'});
        expect(h.calls.where((c) => c.startsWith('DELETE')), hasLength(2));
      },
    );

    test('a refused action (not allowed) shows the server\'s reason', () async {
      final h = signedIn()
        ..routes['POST /v1/shops/s1/invites'] = ((_) =>
            failure(403, 'forbidden', 'Only the owner can invite an admin.'));
      await h.backend.signIn('a@b.com', 'pw');
      await expectLater(
        h.backend.inviteMember('s1', 'x@y.in', 'admin'),
        throwsA(
          predicate(
            (e) => e.toString() == 'Only the owner can invite an admin.',
          ),
        ),
      );
    });
  });

  group('the cloud settings', () {
    test('the Storely API address must be https and needs no key', () {
      expect(const CloudConfig.api('https://api.example.com').isValid, isTrue);
      expect(const CloudConfig.api('http://api.example.com').isValid, isFalse);
      expect(const CloudConfig.api('https://').isValid, isFalse);
    });

    test('an own-Supabase setup still needs a key', () {
      expect(
        const CloudConfig(url: 'https://x.supabase.co', anonKey: 'k').isValid,
        isTrue,
      );
      expect(
        const CloudConfig(url: 'https://x.supabase.co', anonKey: ' ').isValid,
        isFalse,
      );
    });

    test(
      'both Storely options count as "Storely Cloud", an own Supabase does not',
      () {
        expect(CloudBackendMode.storelyApi.isStorelyCloud, isTrue);
        expect(CloudBackendMode.storelyHosted.isStorelyCloud, isTrue);
        expect(CloudBackendMode.ownSupabase.isStorelyCloud, isFalse);
      },
    );
  });

  test(
    'with no signal at launch the last known person stays signed in',
    () async {
      final store = MemoryTokenStore()..token = 'saved-refresh';
      final h = Harness(store: store);
      expect(await h.api.hasStoredSession(), isTrue);
      h.api.adoptUser(const ApiUser(id: 'u1', email: 'a@b.com'));
      expect(h.backend.currentUser?.email, 'a@b.com');
      expect(store.token, 'saved-refresh'); // nothing was thrown away
    },
  );
}
