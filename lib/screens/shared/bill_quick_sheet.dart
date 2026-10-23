import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../db/database_helper.dart';
import '../../models/bill.dart';
import '../../services/bill_share.dart';
import '../../services/dues_reminder.dart';
import '../../theme/app_theme.dart';
import '../../utils/money.dart';
import 'record_payment_dialog.dart';

/// A bill at a glance with the usual follow-ups: record a payment, send a
/// WhatsApp reminder, share the PDF. Returns true when something changed.
Future<bool> showBillQuickSheet(BuildContext context, Bill bill) async {
  final changed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BillQuickSheet(bill: bill),
  );
  return changed == true;
}

class _BillQuickSheet extends StatefulWidget {
  final Bill bill;

  const _BillQuickSheet({required this.bill});

  @override
  State<_BillQuickSheet> createState() => _BillQuickSheetState();
}

class _BillQuickSheetState extends State<_BillQuickSheet> {
  bool _busy = false;

  Bill get bill => widget.bill;

  void _toast(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  Future<void> _recordPayment() async {
    final entry = await showDialog<PaymentEntry>(
      context: context,
      builder: (_) => RecordPaymentDialog(balanceDue: bill.balanceDue),
    );
    if (entry == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await DatabaseHelper.instance.recordBillPayment(
        bill.id!,
        amount: entry.amount,
        paymentMethod: entry.method,
        paymentReference: entry.reference,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(friendlyError(error));
    }
  }

  Future<void> _remind() async {
    final db = DatabaseHelper.instance;
    final shop = await db.getShopProfile();
    final settings = await db.getBillSettings();
    final text = DuesReminder.message(
      customerName: bill.customerName,
      shopName: shop?.name ?? 'our shop',
      unpaidBills: [bill],
      upiId: settings.upiId,
    );
    final link = DuesReminder.whatsAppLink(bill.customerPhone, text);
    if (!mounted) return;
    if (link == null) {
      _toast('This bill has no phone number');
      return;
    }
    final opened = await launchUrl(link, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _toast('Unable to open WhatsApp');
  }

  Future<void> _share() async {
    try {
      await BillShare.sharePdf(bill);
    } catch (error) {
      if (mounted) _toast(friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final age = DateTime.now().difference(bill.createdAt).inDays;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bill.customerName.isEmpty ? 'Walk-in' : bill.customerName,
              style: AppText.title,
            ),
            Text(
              [
                bill.billNumber,
                DateFormat('dd MMM yyyy').format(bill.createdAt),
                if (age > 0) '$age days ago',
              ].join(' · '),
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final item in bill.items.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  '${item.productName} × ${item.quantityLabel}',
                  style: AppText.body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (bill.items.length > 4)
              Text('+ ${bill.items.length - 4} more', style: AppText.caption),
            const Divider(height: AppSpacing.xl),
            _Row('Total', rupees(bill.totalAmount)),
            _Row('Paid', rupees(bill.paidAmount)),
            _Row('Balance due', rupees(bill.balanceDue), bold: true),
            const SizedBox(height: AppSpacing.lg),
            if (bill.balanceDue > 0.005)
              FilledButton.icon(
                key: const ValueKey('quick-record-payment'),
                onPressed: _busy ? null : _recordPayment,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record payment'),
              ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy || bill.customerPhone == null
                        ? null
                        : _remind,
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Remind'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share bill'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;

  const _Row(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = bold ? AppText.subtitle : AppText.body;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}
