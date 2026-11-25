/// Search only task labels and fixed aliases, never stored settings values.
bool matchesSettingsSearch(String query, String title) {
  final needle = String.fromCharCodes(
    query.trim().runes.take(60),
  ).toLowerCase();
  if (needle.isEmpty) return true;
  final aliases = switch (title) {
    'Shop Profile' => 'shop name address phone email GSTIN business details',
    'Pricing Defaults' =>
      'billing GST scheme tax rates margin overhead pricing',
    'Low-stock alert' =>
      'catalog low-stock low stock threshold inventory warning',
    'Bill Settings' =>
      'billing invoice layout logo footer signature number paper size',
    'App Settings' =>
      'data & security theme appearance dark light language lock security receipt printer printing',
    'Backup & restore' => 'data & security file export import backup restore',
    'Cloud Backup & Sync' => 'account cloud backup sync synchronization',
    'Team Members' => 'account staff invite members access permissions',
    'Categories' || 'Suppliers' => 'catalog',
    'Report a problem' || 'Privacy policy' || 'About' => 'help & about',
    'Account' || 'Sign In' => 'account sign in login premium subscription',
    _ => '',
  };
  return '$title $aliases'.toLowerCase().contains(needle);
}
