import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../config/cloud_defaults.dart';
import '../api/api_client.dart';
import '../api/http_client_factory.dart';
import '../api/token_store.dart';

abstract class PremiumReceiptStore {
  Future<String?> read();
  Future<void> write(String value);
}

class SecurePremiumReceiptStore implements PremiumReceiptStore {
  static const _key = 'storely_premium_request';
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

/// Explicit contact requests only; no network activity on construction/load.
/// The draft, secret and idempotency ID are durable BEFORE the first HTTP call.
class PremiumRequestService {
  PremiumRequestService({required this.api, required this.store});
  static PremiumRequestService? _instance;
  static PremiumRequestService get instance =>
      _instance ??= PremiumRequestService(
        api: ApiClient(
          baseUrl: Uri.parse(CloudDefaults.apiUrl),
          httpClient: createApiHttpClient(),
          tokens: MemoryTokenStore(),
        ),
        store: SecurePremiumReceiptStore(),
      );

  final ApiClient api;
  final PremiumReceiptStore store;
  Future<Map<String, dynamic>?> load() async {
    final raw = await store.read();
    if (raw == null) return null;
    final draft = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    if (draft['api_origin'] != api.baseUrl.toString()) {
      throw StateError(
        'This request belongs to a different Storely service. Contact support before reconnecting.',
      );
    }
    return draft;
  }

  Future<void> _save(Map<String, dynamic> data) =>
      store.write(jsonEncode(data));

  Future<Map<String, dynamic>> submit({
    required String shopId,
    required String shopName,
    required String contactName,
    required String phone,
  }) async {
    var draft = await load();
    if (draft == null || (draft['response'] as Map?)?['status'] == 'rejected') {
      final random = Random.secure();
      draft = {
        'api_origin': api.baseUrl.toString(),
        'body': {
          'id': const Uuid().v4(),
          'receipt_secret': base64UrlEncode(
            List<int>.generate(32, (_) => random.nextInt(256)),
          ).replaceAll('=', ''),
          'local_shop_id': shopId,
          'shop_name': shopName.trim(),
          'contact_name': contactName.trim(),
          'phone': phone.trim(),
          'contact_consent': true,
        },
      };
      await _save(draft);
    }
    if (draft['channel'] == 'web') {
      throw StateError(
        'This request was submitted on the web. Sign in to refresh it.',
      );
    }
    final body = Map<String, dynamic>.from(draft['body'] as Map);
    if (body['local_shop_id'] != shopId) {
      throw StateError(
        'The saved request belongs to a different local shop. Contact support.',
      );
    }
    final response = await api.postJson(
      '/v1/premium-requests',
      body,
      auth: false,
    );
    draft['response'] = response;
    await _save(draft);
    return draft;
  }

  Future<Map<String, dynamic>> refresh() async {
    final draft = await load();
    if (draft == null) throw StateError('Submit a premium request first.');
    if (draft['channel'] == 'web') {
      throw StateError(
        'Sign in with the requesting account to refresh a web request.',
      );
    }
    final body = draft['body'] as Map;
    final response = await api.postJson(
      '/v1/premium-requests/${body['id']}/status',
      {'receipt_secret': body['receipt_secret']},
      auth: false,
    );
    draft['response'] = response;
    await _save(draft);
    return draft;
  }

  Future<void> importWebRequest(
    Map<String, dynamic> response, {
    required String shopId,
    required String userId,
  }) async {
    if (response['channel'] != 'web' ||
        response['request_kind'] != 'existing_android' ||
        response['local_shop_id'] != shopId ||
        response['id'] is! String) {
      throw StateError('This web request does not match this Android shop.');
    }
    final previous = await load();
    if (previous != null &&
        (previous['response'] as Map?)?['status'] != 'rejected' &&
        (previous['body'] as Map)['id'] != response['id']) {
      throw StateError(
        'A different request is saved on this phone. Contact support.',
      );
    }
    await _save({
      if (previous != null && (previous['body'] as Map)['id'] == response['id'])
        ...previous,
      'api_origin': api.baseUrl.toString(),
      'channel': 'web',
      'requested_user': userId,
      'body': {
        'id': response['id'],
        'local_shop_id': shopId,
        'shop_name': response['shop_name'],
      },
      'response': response,
    });
  }

  Future<void> authorizeUpload(
    Map<String, dynamic> response,
    String userId,
    String backupPath,
  ) async {
    final draft = (await load())!;
    draft['response'] = response;
    draft['upload_user'] = userId;
    draft['backup_path'] = backupPath;
    draft['upload_consented_at'] = DateTime.now().toUtc().toIso8601String();
    await _save(draft);
  }
}
