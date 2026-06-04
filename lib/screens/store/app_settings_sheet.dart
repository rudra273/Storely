part of '../store_screen.dart';

class _AppSettingsSheet extends StatefulWidget {
  const _AppSettingsSheet();

  @override
  State<_AppSettingsSheet> createState() => _AppSettingsSheetState();
}

class _AppSettingsSheetState extends State<_AppSettingsSheet> {
  AppThemePreference _themePreference =
      AppSettingsService.instance.themePreference;

  Future<void> _setTheme(AppThemePreference value) async {
    setState(() => _themePreference = value);
    await AppSettingsService.instance.setThemePreference(value);
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
