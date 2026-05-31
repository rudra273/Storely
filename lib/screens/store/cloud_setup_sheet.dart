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
  bool _isBusy = false;
  String? _sheetError;
  String? _sheetMessage;

  @override
  void initState() {
    super.initState();
    final config = CloudService.instance.state.value.config;
    _editingCloudSettings = config == null;
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
    return _run(
      () => CloudService.instance.saveConfig(
        CloudConfig(url: _urlCtrl.text, anonKey: _anonKeyCtrl.text),
      ),
      successMessage: 'Cloud settings saved',
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
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, state, _) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: AppColors.creamDark,
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
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isBusy ? null : _saveConfig,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            state.isConfigured
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
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.creamDark),
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
