/// Storely API configuration. There are no user-entered backend credentials.
class CloudDefaults {
  const CloudDefaults._();
  static const apiUrl = String.fromEnvironment('STORELY_API_URL');
  static bool get apiAvailable {
    final uri = Uri.tryParse(apiUrl);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty;
  }

  static const devCaBase64 = String.fromEnvironment('STORELY_DEV_CA_B64');

  // The server enforces subscriptions; accounts can submit/claim requests before
  // gaining business access. Without a bundled API, free offline use still works.
  static bool get isAvailable => apiAvailable;
}
