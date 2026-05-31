part of '../store_screen.dart';

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title.toUpperCase(), style: AppText.label);
  }
}

class _CloudSyncPanel extends StatelessWidget {
  final VoidCallback onSetup;
  final Future<void> Function() onSync;

  const _CloudSyncPanel({required this.onSetup, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, state, _) {
        final email = state.user?.email;
        final role = state.shopRole;
        final roleStr = role != null
            ? ' (${role[0].toUpperCase()}${role.substring(1)})'
            : '';
        final subtitle = !state.isConfigured
            ? 'Local only'
            : email == null
            ? 'Configured • sign in to sync'
            : 'Signed in as $email$roleStr';
        final lastSync = state.lastSyncedAt == null
            ? null
            : _formatCloudTime(state.lastSyncedAt!.toLocal());
        return _StorePanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _PanelIcon(icon: Icons.cloud_sync_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Cloud Sync',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          lastSync == null ? subtitle : '$subtitle • $lastSync',
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cloud setup',
                    onPressed: onSetup,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  IconButton(
                    tooltip: 'Sync now',
                    onPressed:
                        state.isConfigured &&
                            state.isSignedIn &&
                            !state.isSyncing
                        ? onSync
                        : null,
                    icon: state.isSyncing
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync_rounded),
                  ),
                ],
              ),
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 12),
                ),
              ] else if (state.message != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.message!,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
