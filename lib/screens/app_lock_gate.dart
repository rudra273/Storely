import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../services/app_settings_service.dart';
import '../services/secure_window.dart';
import '../theme/app_theme.dart';

/// App Lock, placed in MaterialApp.builder so it sits above the Navigator:
/// it covers every screen, sheet and dialog (not just Home), and the app
/// underneath stays mounted, so unlocking returns to exactly where the user
/// was. While locked, an invisible route on top swallows Android back so
/// nothing pops behind the lock screen.
class AppLockGate extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const AppLockGate({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _enabled = AppSettingsService.instance.appLockEnabled;
  bool _unlocked = !AppSettingsService.instance.appLockEnabled;
  bool _authenticating = false;
  String? _message;
  Route<void>? _backBlocker;

  bool get _locked => _enabled && !_unlocked;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSettingsService.instance.addListener(_handleSettingsChanged);
    SecureWindow.setSecure(_enabled);
    if (_enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncBackBlocker();
        _authenticate();
      });
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
    // Not on `inactive`: the biometric prompt and notification shade cause
    // it. Recents previews are hidden by SecureWindow instead.
    if (_authenticating) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _lock();
    }
  }

  void _lock() {
    if (!mounted || _locked) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _unlocked = false;
      _message = null;
    });
    _syncBackBlocker();
  }

  void _handleSettingsChanged() {
    final enabled = AppSettingsService.instance.appLockEnabled;
    if (!mounted || enabled == _enabled) return;
    SecureWindow.setSecure(enabled);
    setState(() {
      _enabled = enabled;
      _unlocked = true;
      _message = null;
    });
    _syncBackBlocker();
  }

  /// Keeps a transparent, non-poppable route on top while locked.
  void _syncBackBlocker() {
    final navigator = widget.navigatorKey.currentState;
    if (navigator == null) return;
    if (_locked && _backBlocker == null) {
      final route = PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) =>
            const PopScope(canPop: false, child: SizedBox.shrink()),
      );
      _backBlocker = route;
      navigator.push(route);
    } else if (!_locked && _backBlocker != null) {
      final route = _backBlocker!;
      _backBlocker = null;
      if (route.isActive) navigator.removeRoute(route);
    }
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
    _syncBackBlocker();
  }

  @override
  Widget build(BuildContext context) {
    final locked = _locked;
    return Stack(
      children: [
        TickerMode(
          enabled: !locked,
          child: ExcludeSemantics(excluding: locked, child: widget.child),
        ),
        if (locked) Positioned.fill(child: _lockScreen(context)),
      ],
    );
  }

  Widget _lockScreen(BuildContext context) {
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
