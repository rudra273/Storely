import '../sync/sync_backend.dart';

/// The signed-in person, whatever service they signed in to.
class CloudUser {
  final String id;
  final String email;

  const CloudUser({required this.id, required this.email});
}

/// A member of a cloud shop.
class ShopMember {
  final String userId;
  final String role;
  final String? email;
  final DateTime? joinedAt;

  const ShopMember({
    required this.userId,
    required this.role,
    this.email,
    this.joinedAt,
  });

  bool get isOwner => role == 'owner';

  /// Storely API shape: the email is a plain field.
  factory ShopMember.fromApi(Map<String, dynamic> map) => ShopMember(
    userId: map['user_id']?.toString() ?? '',
    role: map['role']?.toString() ?? 'staff',
    email: map['email']?.toString(),
    joinedAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
  );
}

/// A pending invite to a cloud shop.
class ShopInvite {
  final String id;
  final String email;
  final String role;
  final DateTime? createdAt;

  const ShopInvite({
    required this.id,
    required this.email,
    required this.role,
    this.createdAt,
  });

  factory ShopInvite.fromMap(Map<String, dynamic> map) {
    return ShopInvite(
      id: map['id']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      role: map['role']?.toString() ?? 'staff',
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? ''),
    );
  }
}

/// What registering a shop in the cloud sends.
class ShopRegistration {
  final String shopId;
  final String name;
  final String? phone;
  final String? email;
  final String? gstin;
  final String? address;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ShopRegistration({
    required this.shopId,
    required this.name,
    this.phone,
    this.email,
    this.gstin,
    this.address,
    this.createdAt,
    this.updatedAt,
  });
}

/// What happened when someone created an account.
enum SignUpOutcome {
  /// Signed in straight away.
  signedIn,

  /// The service emailed a 6-digit code to type into the app (Storely API).
  emailCodeSent,
}

/// The result of creating an account. [user] is set when the service already
/// knows who they are.
class SignUpResult {
  final SignUpOutcome outcome;
  final CloudUser? user;

  const SignUpResult(this.outcome, [this.user]);
}

/// The password was right, but a second-factor code is needed to finish.
class CloudMfaRequired implements Exception {
  const CloudMfaRequired();

  @override
  String toString() => 'Enter the code from your authenticator app.';
}

/// The address has not been confirmed yet; a code is needed first.
class CloudEmailNotVerified implements Exception {
  final String email;

  const CloudEmailNotVerified(this.email);

  @override
  String toString() => 'Confirm your email address first.';
}

/// A cloud provider, as the rest of the app sees it. [CloudService] holds exactly
/// one of these, so screens never learn the transport details.
abstract class CloudBackend {
  CloudUser? get currentUser;
  Stream<CloudUser?> get userChanges;

  /// What the sync engine talks to.
  SyncBackend get sync;

  /// True when sign-up is confirmed with a code typed into the app, and passwords
  /// can be reset from the app (the Storely API).
  bool get supportsEmailCodes;

  Future<CloudUser> signIn(String email, String password);
  Future<SignUpResult> signUp(String email, String password);
  Future<void> signOut();

  /// Second step of signing in when [CloudMfaRequired] was thrown.
  Future<CloudUser> completeMfa(String code);
  Future<void> verifyEmail(String email, String code);
  Future<void> resendVerificationCode(String email);
  Future<void> forgotPassword(String email);
  Future<void> resetPassword(String email, String code, String newPassword);

  Future<bool> hasShopMembership();
  Future<void> registerShop(ShopRegistration shop);
  Future<String?> fetchRole(String shopId);

  Future<void> inviteMember(String shopId, String email, String role);
  Future<List<ShopMember>> listMembers(String shopId);
  Future<List<ShopInvite>> listPendingInvites(String shopId);
  Future<void> changeMemberRole(String shopId, String userId, String role);
  Future<void> removeMember(String shopId, String userId);
  Future<void> revokeInvite(String shopId, String inviteId);

  Future<void> dispose();
}
