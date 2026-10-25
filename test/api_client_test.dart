import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/token_store.dart';

/// A scripted server: routes by "METHOD /path", records every request.
class Script {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final headers = <String, Map<String, String>>{};
  final handlers = <String, http.Response Function(http.Request)>{};

  http.Client get client => MockClient((request) async => respond(request));

  http.Response respond(http.Request request) {
    final key = '${request.method} ${request.url.path}';
    calls.add(key);
    headers[key] = request.headers;
    bodies[key] = request.body.isEmpty ? null : jsonDecode(request.body);
    final handler = handlers[key];
    if (handler == null) {
      return http.Response('{"error":{"code":"x","message":"no route"}}', 404);
    }
    return handler(request);
  }

  int count(String key) => calls.where((c) => c == key).length;
}

http.Response json(
  Object body, [
  int status = 200,
  Map<String, String>? headers,
]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json', ...?headers},
);

http.Response failure(int status, String code, String message) => json({
  'error': {'code': code, 'message': message},
}, status);

const meJson = {
  'id': 'u1',
  'email': 'a@b.com',
  'full_name': null,
  'email_verified': true,
};

ApiClient build(
  Script script,
  MemoryTokenStore tokens, {
  DateTime Function()? now,
}) => ApiClient(
  baseUrl: Uri.parse('https://api.test'),
  httpClient: script.client,
  tokens: tokens,
  now: now,
);

void main() {
  test('refuses to talk over plain http', () {
    expect(
      () => ApiClient(
        baseUrl: Uri.parse('http://api.test'),
        httpClient: Script().client,
        tokens: MemoryTokenStore(),
      ),
      throwsArgumentError,
    );
  });

  test(
    'login keeps the refresh token in the store and the access token in memory',
    () async {
      final script = Script()
        ..handlers['POST /v1/auth/login'] = ((_) => json({
          'access_token': 'acc',
          'refresh_token': 'ref1',
          'expires_in': 900,
        }))
        ..handlers['GET /v1/me'] = ((_) => json(meJson));
      final tokens = MemoryTokenStore();
      final api = build(script, tokens);

      final result = await api.login(' a@b.com ', 'pw');

      expect(result.needsMfa, isFalse);
      expect(api.user?.email, 'a@b.com');
      expect(tokens.token, 'ref1');
      expect(
        script.bodies['POST /v1/auth/login'],
        containsPair('client', 'mobile'),
      );
      expect(
        script.bodies['POST /v1/auth/login'],
        containsPair('email', 'a@b.com'),
      ); // trimmed
      expect(script.headers['GET /v1/me']!['authorization'], 'Bearer acc');
      expect(script.headers['GET /v1/me']!['user-agent'], 'StorelyApp');
    },
  );

  test('a second factor is asked for, then completes the sign-in', () async {
    final script = Script()
      ..handlers['POST /v1/auth/login'] = ((_) =>
          json({'mfa_required': true, 'mfa_token': 'chal', 'expires_in': 300}))
      ..handlers['POST /v1/auth/mfa/verify'] = ((_) => json({
        'access_token': 'acc',
        'refresh_token': 'ref',
        'expires_in': 900,
      }))
      ..handlers['GET /v1/me'] = ((_) => json(meJson));
    final tokens = MemoryTokenStore();
    final api = build(script, tokens);

    final first = await api.login('a@b.com', 'pw');
    expect(first.needsMfa, isTrue);
    expect(api.user, isNull);
    expect(tokens.token, isNull); // nothing stored until the code is accepted

    final user = await api.completeMfa(first.mfaToken!, ' 123456 ');
    expect(user.email, 'a@b.com');
    expect(script.bodies['POST /v1/auth/mfa/verify'], {
      'mfa_token': 'chal',
      'code': '123456',
    });
    expect(tokens.token, 'ref');
  });

  test('errors carry the server message, code and wait time', () async {
    final script = Script()
      ..handlers['POST /v1/auth/login'] = ((_) => http.Response(
        jsonEncode({
          'error': {'code': 'rate_limited', 'message': 'Too many attempts.'},
        }),
        429,
        headers: {'retry-after': '30'},
      ));
    final api = build(script, MemoryTokenStore());

    await expectLater(
      api.login('a@b.com', 'pw'),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 429)
            .having((e) => e.code, 'code', 'rate_limited')
            .having((e) => e.message, 'message', 'Too many attempts.')
            .having(
              (e) => e.retryAfter,
              'retryAfter',
              const Duration(seconds: 30),
            ),
      ),
    );
  });

  test(
    'a non-JSON error page becomes a generic message, not a crash',
    () async {
      final script = Script()
        ..handlers['POST /v1/auth/login'] = ((_) =>
            http.Response('<html>502</html>', 502));
      final api = build(script, MemoryTokenStore());
      await expectLater(
        api.login('a@b.com', 'pw'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 502)),
      );
    },
  );

  test(
    'an expired access token is refreshed once, even for concurrent requests',
    () async {
      var clock = DateTime.utc(2026, 1, 1);
      var refreshes = 0;
      final script = Script()
        ..handlers['POST /v1/auth/login'] = ((_) => json({
          'access_token': 'acc1',
          'refresh_token': 'ref1',
          'expires_in': 60,
        }))
        ..handlers['POST /v1/auth/refresh'] = ((_) {
          refreshes++;
          return json({
            'access_token': 'acc2',
            'refresh_token': 'ref2',
            'expires_in': 900,
          });
        })
        ..handlers['GET /v1/me'] = ((_) => json(meJson))
        ..handlers['GET /v1/ping'] = ((_) => json({'ok': true}));
      final tokens = MemoryTokenStore();
      final api = build(script, tokens, now: () => clock);
      await api.login('a@b.com', 'pw');

      clock = clock.add(const Duration(minutes: 5)); // acc1 is now stale
      await Future.wait([
        api.getJson('/v1/ping'),
        api.getJson('/v1/ping'),
        api.getJson('/v1/ping'),
      ]);

      expect(refreshes, 1);
      expect(tokens.token, 'ref2');
      expect(script.headers['GET /v1/ping']!['authorization'], 'Bearer acc2');
    },
  );

  test('a 401 triggers one refresh and one retry', () async {
    var pings = 0;
    final script = Script()
      ..handlers['POST /v1/auth/login'] = ((_) => json({
        'access_token': 'acc1',
        'refresh_token': 'ref1',
        'expires_in': 900,
      }))
      ..handlers['POST /v1/auth/refresh'] = ((_) => json({
        'access_token': 'acc2',
        'refresh_token': 'ref2',
        'expires_in': 900,
      }))
      ..handlers['GET /v1/me'] = ((_) => json(meJson))
      ..handlers['GET /v1/ping'] = ((request) {
        pings++;
        return request.headers['authorization'] == 'Bearer acc2'
            ? json({'ok': true})
            : failure(401, 'invalid_token', 'Sign in again.');
      });
    final api = build(script, MemoryTokenStore());
    await api.login('a@b.com', 'pw');

    expect(await api.getJson('/v1/ping'), {'ok': true});
    expect(pings, 2);
    expect(script.count('POST /v1/auth/refresh'), 1);
  });

  test(
    'when the server ends the session, the stored token is wiped and the user is signed out',
    () async {
      final script = Script()
        ..handlers['POST /v1/auth/login'] = ((_) => json({
          'access_token': 'acc1',
          'refresh_token': 'ref1',
          'expires_in': 900,
        }))
        ..handlers['GET /v1/me'] = ((_) => json(meJson))
        ..handlers['GET /v1/ping'] = ((_) =>
            failure(401, 'invalid_token', 'Sign in again.'))
        ..handlers['POST /v1/auth/refresh'] = ((_) =>
            failure(401, 'invalid_token', 'Sign in again.'));
      final tokens = MemoryTokenStore();
      final api = build(script, tokens);
      await api.login('a@b.com', 'pw');
      final events = <ApiUser?>[];
      api.userChanges.listen(events.add);

      await expectLater(api.getJson('/v1/ping'), throwsA(isA<ApiException>()));
      await Future<void>.delayed(Duration.zero);

      expect(tokens.token, isNull);
      expect(api.user, isNull);
      expect(events, [null]);
    },
  );

  test('a network failure while refreshing keeps the session', () async {
    var offline = false;
    final script = Script()
      ..handlers['POST /v1/auth/login'] = ((_) => json({
        'access_token': 'acc1',
        'refresh_token': 'ref1',
        'expires_in': 900,
      }))
      ..handlers['GET /v1/me'] = ((_) => json(meJson));
    final client = MockClient((request) async {
      if (offline) throw http.ClientException('no network');
      return script.respond(request);
    });
    final tokens = MemoryTokenStore();
    final api = ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      httpClient: client,
      tokens: tokens,
      now: () => DateTime.utc(2030),
    );
    await api.login('a@b.com', 'pw');
    offline = true;

    await expectLater(
      api.getJson('/v1/ping'),
      throwsA(isA<http.ClientException>()),
    );
    expect(tokens.token, 'ref1'); // still signed in once the network is back
    expect(api.user, isNotNull);
  });

  test('a saved session is restored on the next launch', () async {
    final script = Script()
      ..handlers['POST /v1/auth/refresh'] = ((_) => json({
        'access_token': 'acc',
        'refresh_token': 'ref-new',
        'expires_in': 900,
      }))
      ..handlers['GET /v1/me'] = ((_) => json(meJson));
    final tokens = MemoryTokenStore()..token = 'ref-old';
    final api = build(script, tokens);

    final user = await api.restoreSession();

    expect(user?.email, 'a@b.com');
    expect(script.bodies['POST /v1/auth/refresh'], {
      'refresh_token': 'ref-old',
    });
    expect(tokens.token, 'ref-new'); // rotated
  });

  test(
    'with no saved session there is nothing to restore and no request is made',
    () async {
      final script = Script();
      final api = build(script, MemoryTokenStore());
      expect(await api.restoreSession(), isNull);
      expect(script.calls, isEmpty);
    },
  );

  test(
    'a revoked saved session restores to signed out and clears the token',
    () async {
      final script = Script()
        ..handlers['POST /v1/auth/refresh'] = ((_) =>
            failure(401, 'invalid_token', 'Sign in again.'));
      final tokens = MemoryTokenStore()..token = 'ref-old';
      final api = build(script, tokens);

      expect(await api.restoreSession(), isNull);
      expect(tokens.token, isNull);
    },
  );

  test('logging out works offline and always forgets the session', () async {
    final script = Script()
      ..handlers['POST /v1/auth/login'] = ((_) => json({
        'access_token': 'acc',
        'refresh_token': 'ref',
        'expires_in': 900,
      }))
      ..handlers['GET /v1/me'] = ((_) => json(meJson));
    final tokens = MemoryTokenStore();
    final api = ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/auth/logout') {
          throw http.ClientException('offline');
        }
        return script.respond(request);
      }),
      tokens: tokens,
    );
    await api.login('a@b.com', 'pw');

    await api.logout();

    expect(tokens.token, isNull);
    expect(api.user, isNull);
  });

  test('the password is only ever sent to the API, never kept', () async {
    final script = Script()
      ..handlers['POST /v1/auth/signup'] = ((_) =>
          json({'status': 'verification_sent'}, 202));
    final tokens = MemoryTokenStore();
    final api = build(script, tokens);

    await api.signUp('a@b.com', 'secret-pw', fullName: 'Asha');

    expect(script.bodies['POST /v1/auth/signup'], {
      'email': 'a@b.com',
      'password': 'secret-pw',
      'full_name': 'Asha',
    });
    expect(tokens.token, isNull);
  });
}
