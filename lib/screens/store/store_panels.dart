part of '../store_screen.dart';

class _SectionLabel extends StatelessWidget {
  final String title;

  const _SectionLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title.toUpperCase(), style: AppText.label);
  }
}

/// The "Account" settings section: sign-in, cloud backup/sync, and (for
/// owners/admins) team members — rendered as standard [_StoreActionRow]s so it
/// matches the rest of the Store screen instead of a one-off panel.
class _AccountSection extends StatelessWidget {
  final VoidCallback onSetup;
  final Future<void> Function() onSync;
  final VoidCallback onMembers;

  const _AccountSection({
    required this.onSetup,
    required this.onSync,
    required this.onMembers,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, state, _) {
        final email = state.user?.email;
        final role = state.shopRole;
        final roleLabel = role != null && role.isNotEmpty
            ? ' • ${role[0].toUpperCase()}${role.substring(1)}'
            : '';

        // Account row — who is signed in (or a prompt to sign in).
        final accountTitle = state.isSignedIn ? 'Account' : 'Sign In';
        final accountSubtitle = email != null
            ? '$email$roleLabel'
            : 'Sign in to back up and sync your data';

        // Cloud backup & sync row — reflects current sync state.
        final lastSync = state.lastSyncedAt == null
            ? null
            : _formatCloudTime(state.lastSyncedAt!.toLocal());
        final String syncSubtitle;
        if (state.error != null) {
          syncSubtitle = state.error!;
        } else if (state.isSyncing) {
          syncSubtitle = 'Syncing…';
        } else if (!state.isConfigured || !state.isSignedIn) {
          syncSubtitle = 'Sign in to enable backup & sync';
        } else if (lastSync != null) {
          syncSubtitle = 'Last synced $lastSync';
        } else {
          syncSubtitle = 'Tap to sync now';
        }
        final canSync =
            state.isConfigured && state.isSignedIn && !state.isSyncing;

        // Owners/admins of a registered cloud shop can manage members.
        final canManageMembers =
            state.isConfigured &&
            state.isSignedIn &&
            state.membership == CloudMembership.member &&
            (state.shopRole == 'owner' || state.shopRole == 'admin');

        return Column(
          children: [
            _StoreActionRow(
              title: accountTitle,
              subtitle: accountSubtitle,
              icon: Icons.person_outline_rounded,
              onTap: onSetup,
            ),
            const SizedBox(height: AppSpacing.sm),
            _StoreActionRow(
              title: 'Cloud Backup & Sync',
              subtitle: syncSubtitle,
              icon: Icons.cloud_sync_outlined,
              onTap: canSync ? () => onSync() : onSetup,
            ),
            if (canManageMembers) ...[
              const SizedBox(height: AppSpacing.sm),
              _StoreActionRow(
                title: 'Team Members',
                subtitle: 'Invite and manage staff access',
                icon: Icons.group_outlined,
                onTap: onMembers,
              ),
            ],
          ],
        );
      },
    );
  }
}
