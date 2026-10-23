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

    setState(() {
      _checkingAppLock = true;
      _appLockMessage = null;
    });

    final supported = !value || await AppLockService.instance.isSupported();
    if (!mounted) return;
    if (!supported) {
      setState(() {
        _checkingAppLock = false;
        _appLockMessage =
            'Set a device PIN, pattern, password, or biometric first.';
      });
      return;
    }

    // Turning the lock off needs the same proof as turning it on, so
    // whoever picks up an unlocked phone cannot simply switch it off.
    final result = await AppLockService.instance.authenticate(
      reason: value
          ? 'Confirm your device lock to enable Storely App Lock'
          : 'Confirm your device lock to turn off Storely App Lock',
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
      _appLockEnabled = value;
      _checkingAppLock = false;
      _appLockMessage = null;
    });
    await AppSettingsService.instance.setAppLockEnabled(value);
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
          Row(
            children: [
              const _PanelIcon(icon: Icons.translate_rounded),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(context.l10n.language, style: AppText.subtitle),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<AppLanguage>(
            key: const ValueKey('language-picker'),
            segments: [
              for (final language in AppLanguage.values)
                ButtonSegment(
                  value: language,
                  label: Text(
                    language == AppLanguage.system ? 'Auto' : language.label,
                  ),
                ),
            ],
            selected: {AppSettingsService.instance.language},
            showSelectedIcon: false,
            onSelectionChanged: (selection) async {
              await AppSettingsService.instance.setLanguage(selection.first);
              if (mounted) setState(() {});
            },
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
          const SizedBox(height: AppSpacing.sm),
          ListenableBuilder(
            listenable: ThermalPrinterService.instance,
            builder: (context, _) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const _PanelIcon(icon: Icons.print_outlined),
              title: const Text('Receipt printer'),
              subtitle: Text(
                printerLabel(ThermalPrinterService.instance),
                style: AppText.caption,
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: AppColors.surfaceOf(context),
                builder: (_) => const PrinterSetupSheet(),
              ),
            ),
          ),
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
