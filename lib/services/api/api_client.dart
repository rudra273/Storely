import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'token_store.dart';

/// The server refused a request. [message] is safe to show to the user.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final Duration? retryAfter;

  const ApiException(this.status, this.code, this.message, {this.retryAfter});

  bool get isUnauthorized => status == 401;

  @override
  String toString() => message;
}

class ApiUser {
  final String id;
  final String email;
  final String? fullName;
  final bool emailVerified;

  const ApiUser({
    required this.id,
    required this.email,
    this.fullName,
    this.emailVerified = true,
  });

  factory ApiUser.fromJson(Map<String, dynamic> json) => ApiUser(
    id: json['id'].toString(),
    email: json['email'].toString(),
    fullName: json['full_name']?.toString(),
    emailVerified: json['email_verified'] != false,
  );
}

/// Outcome of the password step of signing in: either a session, or the
/// server wants a second-factor code (use [mfaToken] with [ApiClient.completeMfa]).
class LoginResult {
  final ApiUser? user;
  final String? mfaToken;

  const LoginResult.signedIn(ApiUser this.user) : mfaToken = null;
  const LoginResult.needsMfa(String this.mfaToken) : user = null;

  bool get needsMfa => mfaToken != null;
}

/// Talks to the Storely API over HTTPS only.
///
/// - The access token lives in memory; the refresh token in [TokenStore].
/// - A request that finds the access token expired refreshes it once, however
///   many requests are waiting, then retries (so rotating refresh tokens are
///   never used twice by this device).
/// - If the server says the session is over, the stored token is wiped and
///   [userChanges] emits null. A network failure never signs anyone out.
class ApiClient {
  ApiClient({
    required Uri baseUrl,
    required http.Client httpClient,
    required TokenStore tokens,
    this.userAgent = 'StorelyApp',
    this.timeout = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : baseUrl = _requireHttps(baseUrl),
       _http = httpClient,
       _tokens = tokens,
       _now = now ?? DateTime.now;

  final Uri baseUrl;
  final String userAgent;
  final Duration timeout;
  final http.Client _http;
  final TokenStore _tokens;
  final DateTime Function() _now;

  final _userChanges = StreamController<ApiUser?>.broadcast();
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<void>? _refreshing;
  ApiUser? _user;

  ApiUser? get user => _user;
  Stream<ApiUser?> get userChanges => _userChanges.stream;
  bool get hasSession => _user != null;

  static Uri _requireHttps(Uri url) {
    if (url.scheme != 'https' || url.host.isEmpty) {
      throw ArgumentError.value(
        url.toString(),
        'baseUrl',
        'The Storely API must be reached over https',
      );
    }
    return url;
  }

  /// Picks up a session saved by an earlier launch. Returns the user, or null
  /// when there is none (or the server ended it). A network failure keeps the
  /// stored token and rethrows, so the next attempt can still succeed.
  Future<ApiUser?> restoreSession() async {
    if (await _tokens.readRefreshToken() == null) return null;
    try {
      await _refreshOnce();
      await _loadUser();
    } on ApiException catch (error) {
      if (error.isUnauthorized) return null;
      rethrow;
    }
    return _user;
  }

  /// True when an earlier launch left a refresh token behind.
  Future<bool> hasStoredSession() async =>
      await _tokens.readRefreshToken() != null;

  /// Starts out signed in as [user] without asking the server. Used at launch
  /// with no network: the stored refresh token is exchanged on the first request
  /// that needs it, so the person is not shown a sign-in screen in a shop with
  /// no signal.
  void adoptUser(ApiUser user) {
    _user = user;
    _userChanges.add(user);
  }

  // ── sign-in and account ──

  Future<LoginResult> login(
    String email,
    String password, {
    String deviceLabel = 'Android',
  }) async {
    final data = await postJson('/v1/auth/login', {
      'email': email.trim(),
      'password': password,
      'client': 'mobile',
      'device_label': deviceLabel,
    }, auth: false);
    if (data['mfa_required'] == true) {
      return LoginResult.needsMfa(data['mfa_token'].toString());
    }
    return LoginResult.signedIn(await _acceptSession(data));
  }

  Future<ApiUser> completeMfa(String mfaToken, String code) async {
    final data = await postJson('/v1/auth/mfa/verify', {
      'mfa_token': mfaToken,
      'code': code.trim(),
    }, auth: false);
    return _acceptSession(data);
  }

  Future<void> signUp(String email, String password, {String? fullName}) =>
      postJson('/v1/auth/signup', {
        'email': email.trim(),
        'password': password,
        'full_name': ?fullName,
      }, auth: false);

  Future<void> verifyEmail(String email, String code) => postJson(
    '/v1/auth/verify-email',
    {'email': email.trim(), 'code': code.trim()},
    auth: false,
  );

  Future<void> resendVerification(String email) => postJson(
    '/v1/auth/resend-verification',
    {'email': email.trim()},
    auth: false,
  );

  Future<void> forgotPassword(String email) => postJson(
    '/v1/auth/password/forgot',
    {'email': email.trim()},
    auth: false,
  );

  Future<void> resetPassword(String email, String code, String newPassword) =>
      postJson('/v1/auth/password/reset', {
        'email': email.trim(),
        'code': code.trim(),
        'new_password': newPassword,
      }, auth: false);

  /// Ends this device's session on the server (best effort) and forgets it.
  Future<void> logout() async {
    try {
      final refresh = await _tokens.readRefreshToken();
      await postJson('/v1/auth/logout', {
        'refresh_token': ?refresh,
      }, auth: _accessToken != null);
    } on Object {
      // Offline or already ended: signing out locally still has to work.
    } finally {
      await _forgetSession();
    }
  }

  Future<ApiUser> _acceptSession(Map<String, dynamic> data) async {
    _setAccess(
      data['access_token'] as String,
      (data['expires_in'] as num?)?.toInt(),
    );
    final refresh = data['refresh_token'] as String?;
    if (refresh != null) await _tokens.writeRefreshToken(refresh);
    await _loadUser();
    return _user!;
  }

  Future<void> _loadUser() async {
    final me = await getJson('/v1/me');
    _user = ApiUser.fromJson(me);
    _userChanges.add(_user);
  }

  void _setAccess(String token, int? expiresInSeconds) {
    _accessToken = token;
    _accessExpiresAt = expiresInSeconds == null
        ? null
        : _now().add(Duration(seconds: expiresInSeconds));
  }

  Future<void> _forgetSession() async {
    _accessToken = null;
    _accessExpiresAt = null;
    await _tokens.clear();
    if (_user != null) {
      _user = null;
      _userChanges.add(null);
    }
  }

  // ── token refresh ──

  bool get _accessIsStale {
    final expires = _accessExpiresAt;
    return _accessToken == null ||
        (expires != null &&
            _now().isAfter(expires.subtract(const Duration(seconds: 30))));
  }

  Future<void> _refreshOnce() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<void> _doRefresh() async {
    final refresh = await _tokens.readRefreshToken();
    if (refresh == null) {
      throw const ApiException(401, 'invalid_token', 'Sign in again.');
    }
    try {
      final data = await _request('POST', '/v1/auth/refresh', {
        'refresh_token': refresh,
      }, auth: false);
      _setAccess(
        data['access_token'] as String,
        (data['expires_in'] as num?)?.toInt(),
      );
      final next = data['refresh_token'] as String?;
      if (next != null) await _tokens.writeRefreshToken(next);
    } on ApiException catch (error) {
      if (error.isUnauthorized) await _forgetSession();
      rethrow;
    }
  }

  // ── requests ──

  Future<Map<String, dynamic>> getJson(String path) =>
      _authed('GET', path, null);

  Future<Map<String, dynamic>> postJson(
    String path,
    Object? body, {
    bool auth = true,
  }) => auth ? _authed('POST', path, body) : _request('POST', path, body);

  Future<Map<String, dynamic>> patchJson(String path, Object? body) =>
      _authed('PATCH', path, body);

  Future<Map<String, dynamic>> deleteJson(String path, [Object? body]) =>
      _authed('DELETE', path, body);

  Future<Map<String, dynamic>> _authed(
    String method,
    String path,
    Object? body,
  ) async {
    if (_accessIsStale) await _refreshOnce();
    try {
      return await _request(method, path, body, auth: true);
    } on ApiException catch (error) {
      if (!error.isUnauthorized) rethrow;
    }
    // The server rejected the token (e.g. clock drift): refresh once and retry.
    await _refreshOnce();
    return _request(method, path, body, auth: true);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path,
    Object? body, {
    bool auth = false,
  }) async {
    final request = http.Request(method, baseUrl.resolve(path))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json'
      ..headers['user-agent'] = userAgent;
    if (auth && _accessToken != null) {
      request.headers['authorization'] = 'Bearer $_accessToken';
    }
    if (body != null) request.body = jsonEncode(body);

    final streamed = await _http.send(request).timeout(timeout);
    final response = await http.Response.fromStream(streamed).timeout(timeout);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.bodyBytes.isEmpty) return const {};
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      return decoded is Map<String, dynamic> ? decoded : {'value': decoded};
    }
    throw _errorFrom(response);
  }

  ApiException _errorFrom(http.Response response) {
    var code = 'http_${response.statusCode}';
    var message = 'The server could not complete the request.';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final error = decoded is Map ? decoded['error'] : null;
      if (error is Map) {
        code = error['code']?.toString() ?? code;
        message = error['message']?.toString() ?? message;
      }
    } on FormatException {
      // Not JSON (e.g. a proxy error page): keep the generic message.
    }
    final wait = int.tryParse(response.headers['retry-after'] ?? '');
    return ApiException(
      response.statusCode,
      code,
      message,
      retryAfter: wait == null ? null : Duration(seconds: wait),
    );
  }

  void dispose() {
    _http.close();
    _userChanges.close();
  }
}
