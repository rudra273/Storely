import 'package:local_auth/local_auth.dart';

class AppLockAuthResult {
  final bool success;
  final String? message;

  const AppLockAuthResult._(this.success, [this.message]);

  const AppLockAuthResult.success() : this._(true);
  const AppLockAuthResult.failure(String message) : this._(false, message);
}

class AppLockService {
  static final AppLockService instance = AppLockService._();

  AppLockService._();

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isSupported() async {
    try {
      return _auth.isDeviceSupported();
    } on LocalAuthException {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<AppLockAuthResult> authenticate({required String reason}) async {
    try {
      final didAuthenticate = await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );
      return didAuthenticate
          ? const AppLockAuthResult.success()
          : const AppLockAuthResult.failure(
              'Authentication was not completed.',
            );
    } on LocalAuthException catch (error) {
      return AppLockAuthResult.failure(_messageFor(error));
    } catch (_) {
      return const AppLockAuthResult.failure(
        'Unable to verify the device lock. Try again.',
      );
    }
  }

  String _messageFor(LocalAuthException error) {
    switch (error.code) {
      case LocalAuthExceptionCode.noCredentialsSet:
        return 'Set a device PIN, pattern, password, or biometric first.';
      case LocalAuthExceptionCode.noBiometricsEnrolled:
        return 'Add a fingerprint or face unlock first, or use device lock.';
      case LocalAuthExceptionCode.noBiometricHardware:
        return 'This device does not support secure local authentication.';
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
        return 'Device authentication is temporarily unavailable.';
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return 'Too many attempts. Unlock the device and try again.';
      case LocalAuthExceptionCode.userCanceled:
        return 'Authentication was cancelled.';
      case LocalAuthExceptionCode.timeout:
      case LocalAuthExceptionCode.systemCanceled:
        return 'Authentication did not finish. Try again.';
      case LocalAuthExceptionCode.authInProgress:
        return 'Authentication is already in progress.';
      case LocalAuthExceptionCode.uiUnavailable:
        return 'Device authentication is not available right now.';
      case LocalAuthExceptionCode.userRequestedFallback:
        return 'Use the device lock option to continue.';
      case LocalAuthExceptionCode.deviceError:
      case LocalAuthExceptionCode.unknownError:
        return error.description ?? 'Unable to authenticate. Try again.';
    }
  }
}
