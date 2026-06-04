part of '../store_screen.dart';

class _ShopPanel extends StatelessWidget {
  final ShopProfile? profile;
  final bool gstRegistered;
  final VoidCallback? onEdit;
  final String? roleLabel;

  const _ShopPanel({
    required this.profile,
    required this.gstRegistered,
    required this.onEdit,
    this.roleLabel,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (profile?.phone != null) profile!.phone!,
      if (profile?.email != null) profile!.email!,
      if (profile?.gstin != null) 'GSTIN ${profile!.gstin}',
      gstRegistered ? 'GST registered' : 'GST not registered',
    ];
    return _StorePanel(
      child: Row(
        children: [
          const _PanelIcon(icon: Icons.storefront_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Shop', style: AppText.caption),
                    if (roleLabel != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      StatusPill(
                        label: roleLabel!.toUpperCase(),
                        variant: roleLabel == 'owner' || roleLabel == 'admin'
                            ? PillVariant.warning
                            : PillVariant.info,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  profile?.name ?? 'No shop name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.title,
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption,
                  ),
                ],
              ],
            ),
          ),
          if (onEdit != null)
            IconButton.filledTonal(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Edit shop profile',
            )
          else
            Tooltip(
              message: 'Only admin or owner can edit',
              child: Icon(
                Icons.lock_outline_rounded,
                color: AppColors.inkMutedOf(context).withValues(alpha: 0.5),
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}

class _StoreActionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _StoreActionRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          _PanelIcon(icon: icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppText.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColors.inkFaintOf(context),
            size: 20,
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String name;
  final VoidCallback? onSettings;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _OptionRow({
    required this.name,
    this.onSettings,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.xs,
          AppSpacing.xs,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.subtitle,
              ),
            ),
            if (onSettings != null)
              IconButton(
                onPressed: onSettings,
                icon: const Icon(Icons.tune_rounded, size: 18),
                tooltip: 'Pricing',
                visualDensity: VisualDensity.compact,
              ),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 18),
              tooltip: 'Edit',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 18),
              color: AppColors.error,
              tooltip: 'Delete',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
