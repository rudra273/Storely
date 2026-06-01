import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_theme.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Storely', style: AppText.title),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Inventory and billing companion for small stores.',
                  style: AppText.caption,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Storely helps small retailers manage products, generate bills, and track daily sales from one simple mobile app.',
                  style: AppText.body.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                const LeadingIconChip(
                  icon: Icons.verified_outlined,
                  color: AppColors.amber,
                ),
                const SizedBox(width: AppSpacing.md),
                Text('Version', style: AppText.subtitle),
                const Spacer(),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data?.version ?? '—',
                      style: AppText.body.copyWith(color: AppColors.inkMuted),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('What You Can Do', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '• Add and organize products by category and supplier.\n'
                  '• Scan barcodes/QR codes for faster billing.\n'
                  '• Track unpaid bills and daily sales.\n'
                  '• Export and print billing/QR data for store operations.',
                  style: AppText.body.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Release Notes', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Version 1.0.1 includes core inventory management, billing, QR scanning, and store setup features for first production release.',
                  style: AppText.body.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
