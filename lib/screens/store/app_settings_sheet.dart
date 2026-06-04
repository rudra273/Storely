part of '../store_screen.dart';

class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet();

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  AppThemePreference _themePreference =
      AppSettingsService.instance.themePreference;
  bool _appLockEnabled = AppSettingsService.instance.appLockEnabled;
  bool _checkingAppLock = false;
  String? _appLockMessage;

  Future<void> _setTheme(AppThemePreference value) async {
    setState(() => _themePreference = value);
    await AppSettingsService.instance.setThemePreference(value);
  }

  Future<void> _setAppLock(bool value) async {
    if (value == _appLockEnabled || _checkingAppLock) return;

    if (!value) {
      setState(() {
        _appLockEnabled = false;
        _appLockMessage = null;
      });
      await AppSettingsService.instance.setAppLockEnabled(false);
      return;
    }

    setState(() {
      _checkingAppLock = true;
      _appLockMessage = null;
    });

    final supported = await AppLockService.instance.isSupported();
    if (!mounted) return;
    if (!supported) {
      setState(() {
        _checkingAppLock = false;
        _appLockMessage =
            'Set a device PIN, pattern, password, or biometric first.';
      });
      return;
    }

    final result = await AppLockService.instance.authenticate(
      reason: 'Confirm your device lock to enable Storely App Lock',
    );
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _checkingAppLock = false;
        _appLockMessage = result.message;
      });
      return;
    }

    setState(() {
      _appLockEnabled = true;
      _checkingAppLock = false;
      _appLockMessage = null;
    });
    await AppSettingsService.instance.setAppLockEnabled(true);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSheetFrame(
      title: 'App Settings',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _PanelIcon(icon: Icons.palette_outlined),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Theme', style: AppText.subtitle),
                    const SizedBox(height: 2),
                    Text(
                      'Use system, light, or dark mode.',
                      style: AppText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SegmentedButton<AppThemePreference>(
            segments: const [
              ButtonSegment(
                value: AppThemePreference.system,
                icon: Icon(Icons.brightness_auto_outlined),
                label: Text('System'),
              ),
              ButtonSegment(
                value: AppThemePreference.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: AppThemePreference.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {_themePreference},
            onSelectionChanged: (selection) => _setTheme(selection.first),
          ),
          const SizedBox(height: AppSpacing.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.md),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            secondary: const _PanelIcon(icon: Icons.lock_outline_rounded),
            title: const Text('App Lock'),
            subtitle: Text(
              _appLockEnabled
                  ? 'Fingerprint or device lock is required.'
                  : 'Use fingerprint, PIN, pattern, or passcode.',
              style: AppText.caption,
            ),
            value: _appLockEnabled,
            activeThumbColor: AppColors.brandOf(context),
            onChanged: _checkingAppLock ? null : _setAppLock,
          ),
          if (_checkingAppLock) ...[
            const SizedBox(height: AppSpacing.xs),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (_appLockMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _appLockMessage!,
              style: AppText.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
