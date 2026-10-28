part of '../store_screen.dart';

class _CloudSetupSheet extends StatefulWidget {
  const _CloudSetupSheet();

  @override
  State<_CloudSetupSheet> createState() => _CloudSetupSheetState();
}

/// Which section of the Cloud Sync sheet to show, derived from [CloudState].
enum _CloudStage {
  /// No cloud backend configured yet.
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
  late final TextEditingController _emailCtrl;
  late final TextEditingController _passwordCtrl;
  bool _isBusy = false;
  String? _sheetError;
  String? _sheetMessage;

  @override
  void initState() {
    super.initState();
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

  Future<void> _signIn() async {
    var signedIn = false;
    await _run(() async {
      // Confirms the email address or asks for a second-factor code when the
      // account needs it, before reporting success.
      signedIn = await signInWithChallenges(
        context,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
    });
    if (signedIn && mounted) {
      setState(() => _sheetMessage = 'Signed in. Sync will run automatically.');
    }
  }

  Future<void> _signUp() async {
    setState(() {
      _isBusy = true;
      _sheetError = null;
      _sheetMessage = null;
    });
    try {
      final outcome = await CloudService.instance.signUp(
        _emailCtrl.text,
        _passwordCtrl.text,
      );
      var confirmed = false;
      if (outcome == SignUpOutcome.emailCodeSent && mounted) {
        confirmed = await showEmailCodeDialog(
          context,
          email: _emailCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _sheetMessage = switch (outcome) {
          SignUpOutcome.emailCodeSent when confirmed =>
            'Email confirmed. You can sign in now.',
          SignUpOutcome.emailCodeSent =>
            'Account created. Confirm your email with the code we sent, then sign in.',
          _ => 'Account created. Check email confirmation if required.',
        };
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _sheetError = _cleanCloudError(error);
      });
    }
  }

  Future<void> _forgotPassword() async {
    final changed = await showResetPasswordDialog(
      context,
      email: _emailCtrl.text.trim(),
    );
    if (changed && mounted) {
      setState(
        () => _sheetMessage = 'Password changed. Sign in with your new one.',
      );
    }
  }

  Future<void> _signOut() =>
      _run(CloudService.instance.signOut, successMessage: 'Signed out');

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
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _isBusy
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const PremiumRequestScreen(),
                              ),
                            ),
                      icon: const Icon(Icons.workspace_premium_outlined),
                      label: const Text('Request Premium / View Request'),
                    ),
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
            storelyCloudAvailable: CloudDefaults.isAvailable,
            busy: _isBusy,
            onEnableStorely: _enableStorelyCloud,
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
            onForgotPassword: CloudService.instance.supportsEmailCodes
                ? _forgotPassword
                : null,
          ),
        ];
      case _CloudStage.needsRegistration:
        return [
          _CloudAccountCard(state: state, compact: true),
          const SizedBox(height: 12),
          const Text(
            'Open your premium request above to activate this shop after approval.',
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
              'Storely Premium includes cloud sync and web access. Request approval above, or sign in to an existing premium shop.',
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

class _EnableCloudSection extends StatelessWidget {
  final bool storelyCloudAvailable;
  final bool busy;
  final Future<void> Function() onEnableStorely;
  const _EnableCloudSection({
    required this.storelyCloudAvailable,
    required this.busy,
    required this.onEnableStorely,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _StorelyCloudBlurb(),
      const SizedBox(height: 12),
      if (storelyCloudAvailable)
        FilledButton.icon(
          onPressed: busy ? null : onEnableStorely,
          icon: const Icon(Icons.cloud_done_outlined),
          label: const Text('Enable Storely Cloud'),
        )
      else
        const Text(
          'Cloud activation is not available yet. Your data stays on this device.',
        ),
    ],
  );
}

/// Stage B — configured but signed out. Email/password auth form.
class _AuthSection extends StatelessWidget {
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool busy;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignUp;

  /// Shown only when the cloud can reset a password from the app.
  final VoidCallback? onForgotPassword;

  const _AuthSection({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.busy,
    required this.onSignIn,
    required this.onSignUp,
    this.onForgotPassword,
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
        if (onForgotPassword != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('cloud-forgot-password'),
              onPressed: busy ? null : onForgotPassword,
              child: const Text('Forgot password?'),
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
