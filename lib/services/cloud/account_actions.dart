/// The account steps the sign-in dialogs need. [CloudService] implements this;
/// tests supply a fake, so the dialogs can be checked without a server.
abstract class AccountActions {
  Future<void> signIn(
    String email,
    String password, {
    bool syncAfterAuth = true,
  });

  /// Second step of signing in, after a second-factor code is asked for.
  Future<void> completeMfa(String code, {bool syncAfterAuth = true});

  Future<void> verifyEmail(String email, String code);
  Future<void> resendVerificationCode(String email);
  Future<void> forgotPassword(String email);
  Future<void> resetPassword(String email, String code, String newPassword);
}
