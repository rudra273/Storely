part of '../store_screen.dart';

class _CloudSetupSheet extends StatefulWidget {
  const _CloudSetupSheet();

  @override
  State<_CloudSetupSheet> createState() => _CloudSetupSheetState();
}

class _CloudSetupSheetState extends State<_CloudSetupSheet> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _anonKeyCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  late bool _editingCloudSettings;
  late CloudBackendMode _mode;
  bool _isBusy = false;
  String? _sheetError;
  String? _sheetMessage;

  @override
  void initState() {
    super.initState();
    final config = CloudService.instance.state.value.config;
    _editingCloudSettings = config == null;
    _mode = CloudService.instance.state.value.mode;
    _urlCtrl = TextEditingController(text: config?.url ?? '');
    _anonKeyCtrl = TextEditingController(text: config?.anonKey ?? '');
    _emailCtrl = TextEditingController(
      text: CloudService.instance.state.value.user?.email ?? '',
    );
    _passwordCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _anonKeyCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action, {
    String? successMessage,
    VoidCallback? onSuccess,
  }) async {
    setState(() {
      _isBusy = true;
      _sheetError = null;
      _sheetMessage = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _sheetMessage = successMessage;
      });
      onSuccess?.call();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _sheetError = _cleanCloudError(error);
      });
    }
  }

  Future<void> _saveConfig() {
    final action = _mode == CloudBackendMode.storelyHosted
        ? CloudService.instance.useStorelyCloud
        : () => CloudService.instance.saveConfig(
            CloudConfig(url: _urlCtrl.text, anonKey: _anonKeyCtrl.text),
          );
    return _run(
      action,
      successMessage: _mode == CloudBackendMode.storelyHosted
          ? 'Storely Cloud enabled'
          : 'Cloud settings saved',
      onSuccess: () => setState(() => _editingCloudSettings = false),
    );
  }

  Future<void> _signIn() {
    return _run(
      () => CloudService.instance.signIn(_emailCtrl.text, _passwordCtrl.text),
      successMessage: 'Signed in. Sync will run automatically.',
    );
  }

  Future<void> _signUp() {
    return _run(
      () => CloudService.instance.signUp(_emailCtrl.text, _passwordCtrl.text),
      successMessage: 'Account created. Check email confirmation if required.',
    );
  }

  Future<void> _signOut() =>
      _run(CloudService.instance.signOut, successMessage: 'Signed out');

  Future<void> _registerShop() => _run(
    CloudService.instance.registerShop,
    successMessage: 'Shop registered. Syncing…',
  );

  Future<void> _chooseFirstSync(FirstSyncMode mode) => _run(
    () => CloudService.instance.chooseFirstSync(mode),
    successMessage: mode == FirstSyncMode.uploadExisting
        ? 'Uploading your existing data…'
        : 'Starting fresh — only new data will sync.',
  );

  Future<void> _resyncExistingData() => _run(
    CloudService.instance.resyncExistingData,
    successMessage: 'Checking your existing data…',
  );

  Future<void> _disableCloud() => _run(
    CloudService.instance.clearConfig,
    successMessage: 'Cloud sync disabled',
    onSuccess: () {
      setState(() => _editingCloudSettings = true);
      _urlCtrl.clear();
      _anonKeyCtrl.clear();
    },
  );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isDark = AppColors.isDark(context);
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, state, _) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: isDark
                    ? Border.all(color: AppColors.borderOf(context))
                    : null,
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        height: 4,
                        width: 42,
                        decoration: BoxDecoration(
                          color: AppColors.borderStrongOf(context),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Cloud Sync',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (state.isConfigured && !_editingCloudSettings) ...[
                      _CloudConfiguredSummary(config: state.config!),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => setState(
                                  () => _editingCloudSettings = true,
                                ),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Update Cloud Settings'),
                        ),
                      ),
                    ] else ...[
                      _BackendModeSelector(
                        mode: _mode,
                        enabled: !_isBusy,
                        onChanged: (m) => setState(() => _mode = m),
                      ),
                      const SizedBox(height: 12),
                      if (_mode == CloudBackendMode.storelyHosted) ...[
                        const _StorelyCloudBlurb(),
                        const SizedBox(height: 10),
                      ] else ...[
                        TextField(
                          controller: _urlCtrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Supabase URL',
                            prefixIcon: Icon(Icons.link_rounded),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _anonKeyCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Supabase anon key',
                            prefixIcon: Icon(Icons.key_outlined),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isBusy ? null : _saveConfig,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            _mode == CloudBackendMode.storelyHosted
                                ? 'Enable Storely Cloud'
                                : state.isConfigured
                                ? 'Save Updated Settings'
                                : 'Save Cloud Settings',
                          ),
                        ),
                      ),
                    ],
                    if (_sheetError != null) ...[
                      const SizedBox(height: 10),
                      _CloudStatusMessage(text: _sheetError!, isError: true),
                    ] else if (_sheetMessage != null) ...[
                      const SizedBox(height: 10),
                      _CloudStatusMessage(text: _sheetMessage!),
                    ] else if (state.error != null) ...[
                      const SizedBox(height: 10),
                      _CloudStatusMessage(text: state.error!, isError: true),
                    ],
                    const SizedBox(height: 18),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isBusy || !state.isConfigured
                                ? null
                                : _signIn,
                            icon: const Icon(Icons.login_rounded),
                            label: const Text('Sign In'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isBusy || !state.isConfigured
                                ? null
                                : _signUp,
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Sign Up'),
                          ),
                        ),
                      ],
                    ),
                    if (state.needsShopRegistration) ...[
                      const SizedBox(height: 12),
                      const _RegisterShopPrompt(),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isBusy ? null : _registerShop,
                          icon: const Icon(Icons.storefront_outlined),
                          label: const Text('Register My Shop'),
                        ),
                      ),
                    ],
                    if (state.firstSyncChoicePending) ...[
                      const SizedBox(height: 12),
                      const _FirstSyncChoicePrompt(),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () => _chooseFirstSync(
                                  FirstSyncMode.uploadExisting,
                                ),
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Upload My Existing Data'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy
                              ? null
                              : () =>
                                    _chooseFirstSync(FirstSyncMode.startFresh),
                          icon: const Icon(Icons.fiber_new_outlined),
                          label: const Text('Start Fresh (new data only)'),
                        ),
                      ),
                    ],
                    // Existing owner/admin members can re-offer the upload-vs-
                    // fresh choice on demand — for when local data was never
                    // pushed to the cloud (e.g. an earlier first sync finalized
                    // without uploading). Hidden while the prompt is already
                    // showing or the user still needs to register.
                    if (state.isSignedIn &&
                        state.membership == CloudMembership.member &&
                        !state.firstSyncChoicePending &&
                        (state.shopRole == 'owner' ||
                            state.shopRole == 'admin')) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : _resyncExistingData,
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Upload Local Data to Cloud'),
                        ),
                      ),
                    ],
                    if (state.isSignedIn) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isBusy ? null : _signOut,
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign Out'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _isBusy || !state.isConfigured
                          ? null
                          : _disableCloud,
                      icon: const Icon(Icons.cloud_off_outlined),
                      label: const Text('Disable Cloud Sync'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BackendModeSelector extends StatelessWidget {
  final CloudBackendMode mode;
  final bool enabled;
  final ValueChanged<CloudBackendMode> onChanged;

  const _BackendModeSelector({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          _segment(
            context,
            label: 'Storely Cloud',
            icon: Icons.cloud_outlined,
            value: CloudBackendMode.storelyHosted,
          ),
          _segment(
            context,
            label: 'Own Supabase',
            icon: Icons.dns_outlined,
            value: CloudBackendMode.ownSupabase,
          ),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required IconData icon,
    required CloudBackendMode value,
  }) {
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: enabled && !selected ? () => onChanged(value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.surfaceOf(context)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: selected
                ? Border.all(color: AppColors.borderStrongOf(context))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? AppColors.brandOf(context)
                    : AppColors.inkMutedOf(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? AppColors.inkOf(context)
                      : AppColors.inkMutedOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StorelyCloudBlurb extends StatelessWidget {
  const _StorelyCloudBlurb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 18,
            color: AppColors.brandOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No setup needed. Storely manages the cloud for you — just sign up '
              'with your email and password below. Shop owners can invite staff '
              'from the Members screen.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkMutedOf(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterShopPrompt extends StatelessWidget {
  const _RegisterShopPrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're signed in but don't belong to a shop yet. Register this "
              'device\'s shop to become its owner — then you can invite staff '
              'from the Members screen.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkOf(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FirstSyncChoicePrompt extends StatelessWidget {
  const _FirstSyncChoicePrompt();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.cloud_sync_outlined,
            size: 18,
            color: AppColors.brandOf(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This device already has data. Upload it to the cloud now, or '
              'start fresh and sync only data you add from now on.',
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: AppColors.inkOf(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudConfiguredSummary extends StatelessWidget {
  final CloudConfig config;

  const _CloudConfiguredSummary({required this.config});

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(config.url)?.host;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_done_outlined, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              host == null || host.isEmpty ? 'Cloud settings saved' : host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _CloudStatusMessage extends StatelessWidget {
  final String text;
  final bool isError;

  const _CloudStatusMessage({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.success.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isError ? AppColors.error : AppColors.success,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _cleanCloudError(Object error) {
  final value = error.toString();
  return value
      .replaceFirst('AuthException(message: ', '')
      .replaceFirst('PostgrestException(message: ', '')
      .replaceFirst('StorageException(message: ', '')
      .replaceFirst('Exception: ', '')
      .replaceFirst('Invalid argument: ', '')
      .replaceAll(RegExp(r', statusCode:.*\)$'), '')
      .replaceAll(RegExp(r', code:.*\)$'), '')
      .trim();
}

String _formatCloudTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return 'last sync $hour:$minute';
}

String? _cleanOptional(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed.isEmpty ? null : trimmed;
}
