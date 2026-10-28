import 'dart:async';

import '../api/api_client.dart';
import '../api/api_sync_backend.dart';
import '../sync/sync_backend.dart';
import 'cloud_backend.dart';

/// [CloudBackend] for the Storely API.
class ApiCloudBackend implements CloudBackend {
  ApiCloudBackend(
    this.api, {
    this.deviceLabel = 'Storely app',
    Future<String> Function()? preferredShopId,
  }) : sync = ApiSyncBackend(api, preferredShopId: preferredShopId);

  final ApiClient api;
  final String deviceLabel;

  @override
  final SyncBackend sync;

  String? _mfaToken;

  static CloudUser? _asCloud(ApiUser? user) =>
      user == null ? null : CloudUser(id: user.id, email: user.email);

  @override
  CloudUser? get currentUser => _asCloud(api.user);

  @override
  Stream<CloudUser?> get userChanges => api.userChanges.map(_asCloud);

  @override
  bool get supportsEmailCodes => true;

  @override
  Future<CloudUser> signIn(String email, String password) async {
    try {
      final result = await api.login(email, password, deviceLabel: deviceLabel);
      if (result.needsMfa) {
        _mfaToken = result.mfaToken;
        throw const CloudMfaRequired();
      }
      _mfaToken = null;
      return _asCloud(result.user)!;
    } on ApiException catch (error) {
      if (error.code == 'email_not_verified') {
        throw CloudEmailNotVerified(email.trim());
      }
      rethrow;
    }
  }

  @override
  Future<CloudUser> completeMfa(String code) async {
    final token = _mfaToken;
    if (token == null) {
      throw StateError('Sign in with your password first.');
    }
    final user = await api.completeMfa(token, code);
    _mfaToken = null;
    return _asCloud(user)!;
  }

  @override
  Future<SignUpResult> signUp(String email, String password) async {
    await api.signUp(email, password);
    return const SignUpResult(SignUpOutcome.emailCodeSent);
  }

  @override
  Future<void> verifyEmail(String email, String code) =>
      api.verifyEmail(email, code);

  @override
  Future<void> resendVerificationCode(String email) =>
      api.resendVerification(email);

  @override
  Future<void> forgotPassword(String email) => api.forgotPassword(email);

  @override
  Future<void> resetPassword(String email, String code, String newPassword) =>
      api.resetPassword(email, code, newPassword);

  @override
  Future<void> signOut() => api.logout();

  @override
  Future<bool> hasShopMembership() async {
    final shops = (await api.getJson('/v1/shops'))['value'];
    return shops is List && shops.isNotEmpty;
  }

  @override
  Future<void> registerShop(ShopRegistration shop) async {
    await api.postJson('/v1/shops', {
      'name': shop.name,
      'shop_id': shop.shopId,
      'phone': shop.phone,
      'email': shop.email,
      'gstin': shop.gstin,
      'address': shop.address,
    });
  }

  @override
  Future<String?> fetchRole(String shopId) async {
    try {
      return (await api.getJson('/v1/shops/$shopId/role'))['role']?.toString();
    } on Object {
      return null; // the role is a convenience; sync must not fail over it
    }
  }

  @override
  Future<void> inviteMember(String shopId, String email, String role) async {
    await api.postJson('/v1/shops/$shopId/invites', {
      'email': email,
      'role': role,
    });
  }

  @override
  Future<List<ShopMember>> listMembers(String shopId) async {
    final rows = (await api.getJson('/v1/shops/$shopId/members'))['value'];
    return [
      for (final row in rows as List)
        ShopMember.fromApi(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<List<ShopInvite>> listPendingInvites(String shopId) async {
    final rows = (await api.getJson('/v1/shops/$shopId/invites'))['value'];
    return [
      for (final row in rows as List)
        ShopInvite.fromMap(Map<String, dynamic>.from(row as Map)),
    ];
  }

  @override
  Future<void> changeMemberRole(
    String shopId,
    String userId,
    String role,
  ) async {
    await api.patchJson('/v1/shops/$shopId/members/$userId', {'role': role});
  }

  @override
  Future<void> removeMember(String shopId, String userId) async {
    await api.deleteJson('/v1/shops/$shopId/members/$userId');
  }

  @override
  Future<void> revokeInvite(String shopId, String inviteId) async {
    await api.deleteJson('/v1/shops/$shopId/invites/$inviteId');
  }

  @override
  Future<void> dispose() async => api.dispose();
}
