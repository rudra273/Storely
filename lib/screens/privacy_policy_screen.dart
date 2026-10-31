import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const String _policyText = '''
Storely Privacy Policy
Effective Date: October 28, 2026

1. Introduction
Storely is designed to help store owners manage inventory, purchases, suppliers, customers, billing, and store settings. This Privacy Policy explains how Storely handles information that you enter into the app.

2. Data Stored Locally
By default, the information you enter is stored locally on your device. Local-only use does not upload these business records. Local data may include:
- Store details, including shop profile, GST settings, bill settings, invoice numbering settings, logo, and digital signature files selected by you
- Product details, including product name, product code, barcode, price, purchase price, quantity, unit, category, supplier, HSN/SAC details, and pricing settings
- Purchase and stock movement history, including purchase date, supplier, quantity, and unit cost
- Supplier and customer details that you choose to enter, such as names, phone numbers, email addresses, GSTIN, and balances
- Billing information created in the app, including bill items, bill number, totals, discounts, GST snapshots, payment status, payment method, and customer details entered for the bill
- Imported CSV or Excel product data and exported or shared PDF bills

3. Optional Storely Cloud
Storely works offline and stores business data on your device by default. Storely Cloud uses the Storely API for account access and optional synchronization. Premium cloud business access requires approval and an active subscription.
- When cloud access is enabled, Storely processes the shop, product, supplier, customer, billing and settings records submitted for synchronization on its backend.
- A premium request sends your shop name, contact name and phone number with your consent so our team can contact you. It does not upload products, customers or bills. A private receipt is stored securely on your phone for request status.
- Cloud accounts use email addresses for authentication and account recovery. Approved activation requires your verified account and explicit upload consent; a local backup is created first.
- Authorized shop members can access cloud records according to their roles.
- You are responsible for having permission to store and synchronize the business and contact information you enter.

4. Permissions Used
- Camera: Used exclusively for scanning barcodes and QR codes. Camera images are not saved by Storely or uploaded by Storely for this feature.
- Network State & Internet: Used to check connectivity and synchronize data to the Storely API.
- Storage/Files/Photos: Used only when you choose files, such as importing CSV/XLSX product files, selecting bill logo or digital signature images, or saving/sharing PDF bills.

5. Data Sharing
Storely does not sell your personal data. Storely does not contain advertising SDKs or third-party trackers. Storely does not share data with third parties by default.
- If you enable Cloud Sync, submitted records are processed by the Storely backend.
- If you export a file or share a bill through another app, the information you share is governed by that app's privacy policy.
- If you add staff members to your shop, those members may access the shop data according to the role and permissions assigned to them in your Storely shop.

6. Data Security
Secure your device and account credentials. API connections use HTTPS. Cloud access is controlled by shop membership and permissions. Keep a separate backup of important records, especially any changes that have not synchronized successfully.

7. Data Deletion & Retention
- Local Data: You can delete all your local data at any time by uninstalling the Storely app or clearing the app data in your device settings.
- Cloud Data: Signing out, uninstalling the app or clearing local data does not delete cloud records. Use the cloud account deletion controls or contact support for assistance with shop data deletion and retention.
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
