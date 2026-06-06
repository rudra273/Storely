/// Compile-time defaults for the Storely-hosted Supabase backend (Option A).
///
/// These are injected at build time so the real project values never live in
/// source control:
///
///   flutter run \
///     --dart-define=STORELY_CLOUD_URL=https://xxxx.supabase.co \
///     --dart-define=STORELY_CLOUD_ANON_KEY=eyJhbGci...
///
/// The anon key is safe to ship in the APK — it only grants access *through*
/// Row Level Security. The service-role key must NEVER be defined here.
class CloudDefaults {
  const CloudDefaults._();

  static const url = String.fromEnvironment('STORELY_CLOUD_URL');
  static const anonKey = String.fromEnvironment('STORELY_CLOUD_ANON_KEY');

  /// True when the app was built with valid Storely-hosted credentials, i.e.
  /// the "Use Storely Cloud" option can be offered to the user.
  static bool get isAvailable => url.isNotEmpty && anonKey.isNotEmpty;
}
