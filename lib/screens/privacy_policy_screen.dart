import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _policyText = '''
Storely Privacy Policy
Effective Date: June 1, 2026

1. Introduction
Storely is designed to help store owners manage inventory, purchases, suppliers, customers, billing, and store settings. This Privacy Policy explains how Storely handles information that you enter into the app.

2. Data Stored Locally
By default, the information you enter is stored locally on your device. Storely does not operate its own server to collect this data. Local data may include:
- Store details, including shop profile, GST settings, bill settings, invoice numbering settings, logo, and digital signature files selected by you
- Product details, including product name, product code, barcode, price, purchase price, quantity, unit, category, supplier, HSN/SAC details, and pricing settings
- Purchase and stock movement history, including purchase date, supplier, quantity, and unit cost
- Supplier and customer details that you choose to enter, such as names, phone numbers, email addresses, GSTIN, and balances
- Billing information created in the app, including bill items, bill number, totals, discounts, GST snapshots, payment status, payment method, and customer details entered for the bill
- Imported CSV or Excel product data and exported or shared PDF bills

3. Optional User-Configured Cloud Sync
Storely can be used completely offline. Cloud Sync is optional and works only when you configure the app with your own Supabase project URL and anon public key.
- Storely does not provide or control the Supabase project used for Cloud Sync.
- Storely does not receive, access, sell, or manage the data synced to your Supabase project.
- If you enable Cloud Sync, the data you choose to sync is sent from your device to the Supabase project configured by you.
- Supabase authentication in your own project may use email addresses to create and manage owner and staff accounts.
- Owner and staff access is controlled by the shop membership data and Supabase policies in your configured Supabase project.
- Your use of Supabase is governed by your Supabase project settings and Supabase's privacy policy: https://supabase.com/privacy.
- You are responsible for ensuring you have the legal right to store or sync any store, customer, supplier, product, and billing data that you enter into Storely.

4. Permissions Used
- Camera: Used exclusively for scanning barcodes and QR codes. Camera images are not saved by Storely or uploaded by Storely for this feature.
- Network State & Internet: Used to check connectivity and synchronize data to your configured Supabase project.
- Storage/Files/Photos: Used only when you choose files, such as importing CSV/XLSX product files, selecting bill logo or digital signature images, or saving/sharing PDF bills.

5. Data Sharing
Storely does not sell your personal data. Storely does not contain advertising SDKs or third-party trackers. Storely does not share data with third parties by default.
- If you enable Cloud Sync, data is sent to the Supabase project configured by you. Storely does not operate that cloud project and does not collect that data on Storely-owned servers.
- If you export a file or share a bill through another app, the information you share is governed by that app's privacy policy.
- If you add staff members to your shop, those members may access the shop data according to the role and permissions configured in your Supabase project and Storely schema.

6. Data Security
Because data is stored on your device by default, you are responsible for securing access to your device. If using Cloud Sync, you are responsible for securely managing your Supabase project, access rules, authentication settings, staff membership, and anon public key. Never place a Supabase service role key inside Storely.

7. Data Deletion & Retention
- Local Data: You can delete all your local data at any time by uninstalling the Storely app or clearing the app data in your device settings.
- Cloud Data: If you enabled Cloud Sync, cloud data is stored in the Supabase project configured by you. You can delete cloud data, users, and authentication records from your Supabase project dashboard.
- Storely Server Data: Storely does not operate a Storely-owned backend for collecting your app data, so Storely does not hold a separate copy of your shop, product, supplier, customer, or bill records.
- Shared Files: PDF bills, exported files, or files sent through other apps remain wherever you saved or shared them. Delete those copies from the destination app or storage location if needed.
- Assistance: For privacy questions or help understanding deletion steps, contact rosmoxx@gmail.com.

8. Children's Privacy
Storely is a business tool and is not designed for children under 13.

9. Policy Updates
This Privacy Policy may be updated in future releases. Any changes will be reflected in the latest app version and the Play Store listing.

10. Contact
For any privacy-related questions, data deletion requests, or concerns, contact us at:
rosmoxx@gmail.com
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Privacy Policy'),
        actions: [
          IconButton(
            tooltip: 'Copy policy',
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: _policyText));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Privacy policy copied')),
              );
            },
            icon: const Icon(Icons.copy_all_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: AppCard(
          child: SingleChildScrollView(
            child: SelectableText(
              _policyText,
              style: AppText.body.copyWith(height: 1.55),
            ),
          ),
        ),
      ),
    );
  }
}
