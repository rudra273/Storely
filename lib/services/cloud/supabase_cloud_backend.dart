import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../sync/sync_backend.dart';
import 'cloud_backend.dart';

/// [CloudBackend] for a Supabase project (Storely-hosted or the owner's own).
///
/// This is the app's original cloud code, moved behind the interface unchanged,
/// so existing installs keep working until they move to the Storely API.
class SupabaseCloudBackend implements CloudBackend {
  SupabaseCloudBackend._(this._client) : sync = SupabaseSyncBackend(_client);

  /// Starts (or restarts) the process-wide Supabase client for [url].
  static Future<SupabaseCloudBackend> start(String url, String anonKey) async {
    await Supabase.initialize(url: url, anonKey: anonKey);
    return SupabaseCloudBackend._(Supabase.instance.client);
  }

  final SupabaseClient _client;

  @override
  final SyncBackend sync;

  static CloudUser? _asCloud(User? user) =>
      user == null ? null : CloudUser(id: user.id, email: user.email ?? '');

  @override
  CloudUser? get currentUser => _asCloud(_client.auth.currentUser);

  @override
  Stream<CloudUser?> get userChanges => _client.auth.onAuthStateChange.map(
    (data) => _asCloud(data.session?.user),
  );

  @override
  bool get supportsEmailCodes => false;

  @override
  Future<CloudUser> signIn(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    return _asCloud(response.user ?? _client.auth.currentUser)!;
  }

  @override
  Future<SignUpResult> signUp(String email, String password) async {
    final response = await _client.auth.signUp(
      email: email.trim(),
      password: password,
    );
    return SignUpResult(
      response.session == null
          ? SignUpOutcome.confirmByEmailLink
          : SignUpOutcome.signedIn,
      _asCloud(response.user ?? _client.auth.currentUser),
    );
  }

  @override
  Future<void> signOut() => _client.auth.signOut();

  // Supabase confirms and resets by emailed link, not by a code typed here.
  @override
  Future<CloudUser> completeMfa(String code) =>
      throw UnsupportedError('Two-factor sign-in is not available on Supabase');

  @override
  Future<void> verifyEmail(String email, String code) =>
      throw UnsupportedError('Supabase confirms email by link');

  @override
  Future<void> resendVerificationCode(String email) =>
      throw UnsupportedError('Supabase confirms email by link');

  @override
  Future<void> forgotPassword(String email) =>
      throw UnsupportedError('Reset your password from your Supabase project');

  @override
  Future<void> resetPassword(String email, String code, String newPassword) =>
      throw UnsupportedError('Reset your password from your Supabase project');

  @override
  Future<bool> hasShopMembership() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;
    final rows = await _client
        .from('shop_members')
        .select('shop_id')
        .eq('user_id', user.id)
        .limit(1);
    return (rows as List).isNotEmpty;
  }

  @override
  Future<void> registerShop(ShopRegistration shop) async {
    await _client.rpc(
      'create_shop',
      params: {
        'target_shop_id': shop.shopId,
        'shop_name': shop.name,
        'shop_phone': shop.phone,
        'shop_email': shop.email,
        'shop_gstin': shop.gstin,
        'shop_address': shop.address,
        'shop_created_at': shop.createdAt?.toIso8601String(),
        'shop_updated_at': shop.updatedAt?.toIso8601String(),
      },
    );
  }

  /// Query the user's role from cloud shop_members.
  @override
  Future<String?> fetchRole(String shopId) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    try {
      final rows = await _client
          .from('shop_members')
          .select('role')
          .eq('shop_id', shopId)
          .eq('user_id', user.id)
          .limit(1);
      if ((rows as List).isEmpty) return null;
      return rows.first['role']?.toString();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> inviteMember(String shopId, String email, String role) async {
    final user = _client.auth.currentUser;
    if (user == null) throw StateError('Sign in first.');
    await _client.from('shop_invites').insert({
      'shop_id': shopId,
      'email': email,
      'role': role,
      'invited_by': user.id,
    });
  }

  @override
  Future<List<ShopMember>> listMembers(String shopId) async {
    final rows = await _client
        .from('shop_members')
        .select('user_id, role, created_at, profiles(email)')
        .eq('shop_id', shopId);
    return (rows as List)
        .map((row) => ShopMember.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Future<List<ShopInvite>> listPendingInvites(String shopId) async {
    final rows = await _client
        .from('shop_invites')
        .select('id, email, role, created_at')
        .eq('shop_id', shopId)
        .filter('accepted_at', 'is', null);
    return (rows as List)
        .map((row) => ShopInvite.fromMap(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  @override
  Future<void> changeMemberRole(
    String shopId,
    String userId,
    String role,
  ) async {
    await _client
        .from('shop_members')
        .update({'role': role})
        .eq('shop_id', shopId)
        .eq('user_id', userId);
  }

  @override
  Future<void> removeMember(String shopId, String userId) async {
    await _client
        .from('shop_members')
        .delete()
        .eq('shop_id', shopId)
        .eq('user_id', userId);
  }

  @override
  Future<void> revokeInvite(String shopId, String inviteId) async {
    await _client.from('shop_invites').delete().eq('id', inviteId);
  }

  @override
  Future<void> dispose() => Supabase.instance.dispose();
}
