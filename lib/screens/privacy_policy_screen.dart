import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _policyText = '''
Storely Privacy Policy
Effective Date: April 29, 2026

1. Introduction
Storely is designed to help store owners manage inventory and billing. This Privacy Policy explains how the app handles the information you enter.

2. Data Stored Locally
By default, the information you enter is stored locally on your device, including:
- Store details (such as shop name and settings)
- Product details (name, price, quantity, unit, barcode, category, supplier)
- Billing information created in the app

3. Cloud Sync & Third-Party Processors
Storely can be used completely offline. If you choose to enable the optional Cloud Sync feature, the app connects to the Supabase project configured. 
- The data is synchronized to Supabase servers.
- Supabase acts as a third-party data processor. Their privacy policy can be found at https://supabase.com/privacy.
- You are responsible for ensuring you have the legal right to synchronize your store's data to the cloud.

4. Permissions Used
- Camera: Used exclusively for scanning barcodes and QR codes. Images are processed locally and not uploaded.
- Network State & Internet: Used to check connectivity and synchronize data to your configured Supabase project.
- Storage/Files: Used to import/export Excel, CSV files, and save PDF bills to your device.

5. Data Sharing
Storely does not sell your personal data. Storely does not contain advertising SDKs or third-party trackers. Storely does not share data with third parties by default. If you export a file or share a bill through another app (like WhatsApp), the information you share is governed by that app's privacy policy.

6. Data Security
Because data is stored on your device by default, you are responsible for securing access to your device. If using Cloud Sync, ensure you only use the "anon public" key in the app configuration and securely manage your Supabase database access rules.

7. Data Deletion & Retention
- Local Data: You can delete all your local data at any time by uninstalling the Storely app or clearing the app data in your device settings.
- Cloud Data: If you enabled Cloud Sync, you can delete your data directly from your Supabase project dashboard. 
- Requesting Deletion: If you require assistance deleting an account associated with Cloud Sync, you may contact us at the email below.

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
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text(
          'Privacy Policy',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
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
      body: Container(
        width: double.infinity,
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SingleChildScrollView(
          child: SelectableText(
            _policyText,
            style: TextStyle(
              color: AppColors.textDark,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
