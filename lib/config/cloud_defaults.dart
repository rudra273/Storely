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

  /// The Storely API (replaces the Supabase project above after cutover):
  ///   --dart-define=STORELY_API_URL=https://api.example.com
  /// It must be https; anything else is ignored.
  static const apiUrl = String.fromEnvironment('STORELY_API_URL');

  static bool get apiAvailable => apiUrl.startsWith('https://');

  /// True when the app was built with Storely-hosted Supabase credentials.
  static bool get supabaseAvailable => url.isNotEmpty && anonKey.isNotEmpty;

  /// True when the "Use Storely Cloud" option can be offered to the user: the
  /// Storely API when this build has one, otherwise the hosted Supabase project.
  static bool get isAvailable => apiAvailable || supabaseAvailable;
}
