import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_theme.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                  'Offline-first inventory, purchase, billing, and customer management for small stores.',
                  style: AppText.caption,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Storely is built for shop owners who need a practical mobile workflow: set up the shop, add stock through purchases, bill customers, track unpaid balances, and keep product pricing consistent.',
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
                    final info = snapshot.data;
                    return Text(
                      info == null
                          ? '1.0.4'
                          : '${info.version}+${info.buildNumber}',
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
                  '• Create purchases with date and supplier, then add or import products.\n'
                  '• Use automatic pricing from GST, overhead, and margin defaults, or direct selling price per product.\n'
                  '• Generate bills with payment status, discounts, GST snapshots, and customer balances.\n'
                  '• Print or share PDF bills with optional shop logo and digital signature.\n'
                  '• Generate product QR or barcode label sheets for scanning.\n'
                  '• Track low stock, unpaid bills, customers, suppliers, and analytics.',
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
                Text('How Data Works', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Storely works offline by default and stores business data on your device. Optional cloud sync can be connected to your own Supabase project for owner and staff access across devices.',
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
                Text('Recommended Setup', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '1. Complete Shop Profile and GST status.\n'
                  '2. Set Pricing Defaults and Bill Settings.\n'
                  '3. Add suppliers, categories, and units as needed.\n'
                  '4. Add stock through Products > New Purchase.\n'
                  '5. Create bills from Scan & Bill or Manual Bill.',
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
                Text('Support', style: AppText.subtitle),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'For privacy questions, setup help, or production support, contact rosmoxx@gmail.com.',
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
                  'Version 1.0.4 brings refinements to the billing flow, a redesigned full bill page, quick navigation improvements, GST display fixes, the account section, and bug fixes for a smoother experience.',
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
