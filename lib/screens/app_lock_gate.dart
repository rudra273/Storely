import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../services/app_settings_service.dart';
import '../theme/app_theme.dart';

class AppLockGate extends StatefulWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _enabled = AppSettingsService.instance.appLockEnabled;
  bool _unlocked = !AppSettingsService.instance.appLockEnabled;
  bool _authenticating = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSettingsService.instance.addListener(_handleSettingsChanged);
    if (_enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
    }
  }

  @override
  void dispose() {
    AppSettingsService.instance.removeListener(_handleSettingsChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_enabled) return;
    if (state == AppLifecycleState.resumed) {
      if (!_unlocked && !_authenticating) _authenticate();
      return;
    }
    if (_authenticating) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      setState(() {
        _unlocked = false;
        _message = null;
      });
    }
  }

  void _handleSettingsChanged() {
    final enabled = AppSettingsService.instance.appLockEnabled;
    if (!mounted || enabled == _enabled) return;
    setState(() {
      _enabled = enabled;
      _unlocked = true;
      _message = null;
    });
  }

  Future<void> _authenticate() async {
    if (!_enabled || _authenticating) return;
    setState(() {
      _authenticating = true;
      _message = null;
    });

    final result = await AppLockService.instance.authenticate(
      reason: 'Unlock Storely to continue',
    );
    if (!mounted) return;

    setState(() {
      _authenticating = false;
      _unlocked = result.success;
      _message = result.success ? null : result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled || _unlocked) return widget.child;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppColors.brandOf(context).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock_outline_rounded,
                      color: AppColors.brandOf(context),
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Storely Locked', style: AppText.title),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Use fingerprint, face unlock, PIN, pattern, or passcode.',
                    textAlign: TextAlign.center,
                    style: AppText.caption.copyWith(
                      color: AppColors.inkMutedOf(context),
                    ),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: AppText.caption.copyWith(color: AppColors.error),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _authenticating ? null : _authenticate,
                      icon: _authenticating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_rounded),
                      label: Text(_authenticating ? 'Checking...' : 'Unlock'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
