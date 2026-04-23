import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _policyText = '''
Storely Privacy Policy
Effective Date: April 23, 2026

1. Introduction
Storely is designed to help store owners manage inventory and billing. This Privacy Policy explains how the app handles the information you enter.

2. Data Stored Locally
Storely does not collect, upload, or store your data on any server in version 1.0.0. The information you enter is stored locally on your device, including:
- Store details (such as shop name and settings)
- Product details (name, price, quantity, barcode, category, supplier)
- Billing information created in the app

3. How Data Is Stored
In version 1.0.0, your data is stored in a local database on your device. Storely does not require an account login, cloud sync, or server storage in this version.

4. Permissions Used
- Camera: used only for barcode and QR scanning.
- File access: used for importing and exporting files such as invoices, CSV or Excel files, and QR sheets.

5. Data Sharing
Storely does not sell your personal data. No advertising SDK is included in version 1.0.0. Storely does not share data with third parties by default. If you choose to export a file, print a bill, or send a bill through another app such as WhatsApp, the information you share may be handled by that selected app or service.

6. Data Security
Storely follows standard mobile app development practices. Because data is stored on your device, you are responsible for securing access to your device.

7. Your Control
You can modify or delete store, product, and billing records from within the app. Uninstalling the app may remove local app data, depending on your device settings.

8. Children's Privacy
Storely is not designed for children under 13, and it is intended for business use.

9. Policy Updates
This Privacy Policy may be updated in future releases. Any changes should be reflected in the latest app version and the Play Store listing.

10. Contact
For any privacy-related questions or concerns, contact us at:
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
