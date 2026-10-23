import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Hides the app's content in Android's recent-apps preview while App Lock
/// is on (Android 13+ hides only the preview; older versions use
/// FLAG_SECURE, which also blocks screenshots). See MainActivity.kt.
class SecureWindow {
  static const _channel = MethodChannel('storely/window');

  static Future<void> setSecure(bool secure) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('setSecure', {'secure': secure});
    } on MissingPluginException {
      // Tests / platforms without the channel.
    } on PlatformException catch (error) {
      debugPrint('SecureWindow.setSecure failed: $error');
    }
  }
}
