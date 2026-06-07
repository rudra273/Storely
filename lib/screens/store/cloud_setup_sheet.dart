part of '../store_screen.dart';

class _CloudSetupSheet extends StatefulWidget {
  const _CloudSetupSheet();

  @override
  State<_CloudSetupSheet> createState() => _CloudSetupSheetState();
}

/// Which section of the Cloud Sync sheet to show, derived from [CloudState].
enum _CloudStage {
  /// No backend configured yet — offer one-tap enable + advanced own-Supabase.
  notConfigured,

  /// Configured but signed out — show the email/password auth form.
  signedOut,

  /// Signed in but attached to no shop — prompt to register a shop.
  needsRegistration,

  /// Signed in, first sync found local data — upload-vs-fresh choice.
  firstSyncChoice,

  /// Signed in and a member of a cloud shop — show the account card.
  member,
}

class _CloudSetupSheetState extends State<_CloudSetupSheet> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _anonKeyCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  late CloudBackendMode _mode;

  /// Reveals the "use your own Supabase" form in the not-configured stage.
  bool _showAdvanced = false;
  bool _isBusy = false;
  String? _sheetError;
  String? _sheetMessage;

  @override
  void initState() {
    super.initState();
    final config = CloudService.instance.state.value.config;
    // When the bundled Storely Cloud creds aren't compiled in, the one-tap
    // path can't work — fall back to the own-Supabase form, expanded.
    final storelyCloudAvailable = CloudDefaults.isAvailable;
    _mode = storelyCloudAvailable
        ? CloudService.instance.state.value.mode
        : CloudBackendMode.ownSupabase;
    _showAdvanced = !storelyCloudAvailable && config == null;
    _urlCtrl = TextEditingController(text: config?.url ?? '');
    _anonKeyCtrl = TextEditingController(text: config?.anonKey ?? '');
    _emailCtrl = TextEditingController(
      text: CloudService.instance.state.value.user?.email ?? '',
    );
    _passwordCtrl = TextEditingController();
  }

  _CloudStage _stageFor(CloudState state) {
    if (!state.isConfigured) return _CloudStage.notConfigured;
    if (!state.isSignedIn) return _CloudStage.signedOut;
    if (state.needsShopRegistration) return _CloudStage.needsRegistration;
    if (state.firstSyncChoicePending) return _CloudStage.firstSyncChoice;
    return _CloudStage.member;
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

  /// Enable the bundled Storely Cloud backend in one tap (Option A).
  Future<void> _enableStorelyCloud() => _run(
    CloudService.instance.useStorelyCloud,
    successMessage: 'Storely Cloud enabled',
  );

  /// Save a user-provided Supabase URL + anon key (Option B, advanced).
  Future<void> _saveOwnSupabase() => _run(
    () => CloudService.instance.saveConfig(
      CloudConfig(url: _urlCtrl.text, anonKey: _anonKeyCtrl.text),
    ),
    successMessage: 'Cloud settings saved',
  );

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
      setState(() => _showAdvanced = !CloudDefaults.isAvailable);
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
        final stage = _stageFor(state);
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
                    _buildBanner(state),
                    const SizedBox(height: 16),
                    ..._buildStage(stage, state),
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
                    if (state.isConfigured) ...[
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: _isBusy ? null : _disableCloud,
                        icon: const Icon(Icons.cloud_off_outlined, size: 18),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        label: const Text('Disable Cloud Sync'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The status / error banner shown under the title for every stage.
  Widget _buildBanner(CloudState state) {
    if (_sheetError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _CloudStatusMessage(text: _sheetError!, isError: true),
      );
    }
    if (_sheetMessage != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _CloudStatusMessage(text: _sheetMessage!),
      );
    }
    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _CloudStatusMessage(text: state.error!, isError: true),
      );
    }
    return const SizedBox.shrink();
  }

  List<Widget> _buildStage(_CloudStage stage, CloudState state) {
    switch (stage) {
      case _CloudStage.notConfigured:
        return [
          _EnableCloudSection(
            mode: _mode,
            showAdvanced: _showAdvanced,
            storelyCloudAvailable: CloudDefaults.isAvailable,
            busy: _isBusy,
            urlCtrl: _urlCtrl,
            anonKeyCtrl: _anonKeyCtrl,
            onToggleAdvanced: () =>
                setState(() => _showAdvanced = !_showAdvanced),
            onModeChanged: (m) => setState(() => _mode = m),
            onEnableStorely: _enableStorelyCloud,
            onSaveOwnSupabase: _saveOwnSupabase,
          ),
        ];
      case _CloudStage.signedOut:
        return [
          _AuthSection(
            emailCtrl: _emailCtrl,
            passwordCtrl: _passwordCtrl,
            busy: _isBusy,
            onSignIn: _signIn,
            onSignUp: _signUp,
          ),
        ];
      case _CloudStage.needsRegistration:
        return [
          _CloudAccountCard(state: state, compact: true),
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
        ];
      case _CloudStage.firstSyncChoice:
        return [
          _CloudAccountCard(state: state, compact: true),
          const SizedBox(height: 12),
          const _FirstSyncChoicePrompt(),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isBusy
                  ? null
                  : () => _chooseFirstSync(FirstSyncMode.uploadExisting),
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
                  : () => _chooseFirstSync(FirstSyncMode.startFresh),
              icon: const Icon(Icons.fiber_new_outlined),
              label: const Text('Start Fresh (new data only)'),
            ),
          ),
        ];
      case _CloudStage.member:
        final canUpload =
            state.shopRole == 'owner' || state.shopRole == 'admin';
        return [
          _CloudAccountCard(state: state, compact: false),
          if (canUpload) ...[
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
        ];
    }
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

/// Stage A — no backend yet. One-tap "Enable Storely Cloud" plus an advanced
/// disclosure for users who want to point at their own Supabase project.
class _EnableCloudSection extends StatelessWidget {
  final CloudBackendMode mode;
  final bool showAdvanced;
  final bool storelyCloudAvailable;
  final bool busy;
  final TextEditingController urlCtrl;
  final TextEditingController anonKeyCtrl;
  final VoidCallback onToggleAdvanced;
  final ValueChanged<CloudBackendMode> onModeChanged;
  final Future<void> Function() onEnableStorely;
  final Future<void> Function() onSaveOwnSupabase;

  const _EnableCloudSection({
    required this.mode,
    required this.showAdvanced,
    required this.storelyCloudAvailable,
    required this.busy,
    required this.urlCtrl,
    required this.anonKeyCtrl,
    required this.onToggleAdvanced,
    required this.onModeChanged,
    required this.onEnableStorely,
    required this.onSaveOwnSupabase,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (storelyCloudAvailable) ...[
          const _StorelyCloudBlurb(),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : onEnableStorely,
              icon: const Icon(Icons.cloud_done_outlined),
              label: const Text('Enable Storely Cloud'),
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: busy ? null : onToggleAdvanced,
              icon: Icon(
                showAdvanced
                    ? Icons.expand_less_rounded
                    : Icons.tune_rounded,
                size: 18,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.inkMutedOf(context),
              ),
              label: const Text('Advanced — use your own Supabase'),
            ),
          ),
        ],
        if (showAdvanced || !storelyCloudAvailable) ...[
          const SizedBox(height: 4),
          if (storelyCloudAvailable) ...[
            _BackendModeSelector(
              mode: mode,
              enabled: !busy,
              onChanged: onModeChanged,
            ),
            const SizedBox(height: 12),
          ],
          if (mode == CloudBackendMode.ownSupabase ||
              !storelyCloudAvailable) ...[
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Supabase URL',
                prefixIcon: Icon(Icons.link_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: anonKeyCtrl,
              decoration: const InputDecoration(
                labelText: 'Supabase anon key',
                prefixIcon: Icon(Icons.key_outlined),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onSaveOwnSupabase,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Cloud Settings'),
              ),
            ),
          ] else ...[
            // Advanced open but mode is still Storely Cloud — nudge toward the
            // one-tap button above.
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onEnableStorely,
                icon: const Icon(Icons.cloud_done_outlined),
                label: const Text('Enable Storely Cloud'),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

/// Stage B — configured but signed out. Email/password auth form.
class _AuthSection extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool busy;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignUp;

  const _AuthSection({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.busy,
    required this.onSignIn,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passwordCtrl,
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
                onPressed: busy ? null : onSignIn,
                icon: const Icon(Icons.login_rounded),
                label: const Text('Sign In'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSignUp,
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: const Text('Sign Up'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Signed-in account card: email, role pill, and last-sync time. Used as a
/// compact header on the registration / first-sync stages and as the full card
/// on the member stage.
class _CloudAccountCard extends StatelessWidget {
  final CloudState state;
  final bool compact;

  const _CloudAccountCard({required this.state, required this.compact});

  @override
  Widget build(BuildContext context) {
    final email = state.user?.email ?? 'Signed in';
    final role = state.shopRole;
    final lastSync = state.lastSyncedAt;
    return AppCard(
      child: Row(
        children: [
          const LeadingIconChip(
            icon: Icons.cloud_done_outlined,
            color: AppColors.success,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subtitle,
                ),
                if (!compact && lastSync != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    _formatCloudTime(lastSync.toLocal()),
                    style: AppText.caption,
                  ),
                ],
              ],
            ),
          ),
          if (role != null) ...[
            const SizedBox(width: 10),
            StatusPill(
              label: role.toUpperCase(),
              variant: role == 'owner' || role == 'admin'
                  ? PillVariant.warning
                  : PillVariant.info,
            ),
          ],
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
