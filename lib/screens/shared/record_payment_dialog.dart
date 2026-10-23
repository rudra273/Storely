import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/money.dart';
import '../../utils/test_keys.dart';

/// Amount + cash/online (+ optional transaction id) for a payment received.
/// Validates inline: accepts "1,000", rejects 0 or more than [balanceDue].
class PaymentEntry {
  final double amount;
  final String method;
  final String? reference;

  const PaymentEntry({
    required this.amount,
    required this.method,
    required this.reference,
  });
}

class RecordPaymentDialog extends StatefulWidget {
  final double balanceDue;
  final String title;

  const RecordPaymentDialog({
    super.key,
    required this.balanceDue,
    this.title = 'Record Payment',
  });

  @override
  State<RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<RecordPaymentDialog> {
  late final TextEditingController _amountCtrl = TextEditingController(
    text: widget.balanceDue.toStringAsFixed(2),
  );
  final _txnRefCtrl = TextEditingController();
  var _method = 'cash';
  String? _amountError;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _txnRefCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_amountCtrl.text.replaceAll(',', '').trim());
    final error = value == null || value <= 0
        ? 'Enter an amount greater than 0'
        : value > widget.balanceDue + 0.005
        ? 'Cannot be more than the balance due'
        : null;
    if (error != null) {
      setState(() => _amountError = error);
      return;
    }
    Navigator.pop(
      context,
      PaymentEntry(
        amount: value!,
        method: _method,
        reference: _method == 'online' ? _txnRefCtrl.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount received',
              prefixText: '₹ ',
              helperText: 'Balance: ${rupees(widget.balanceDue)}',
              errorText: _amountError,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'cash',
                icon: Icon(Icons.payments_outlined),
                label: Text('Cash'),
              ),
              ButtonSegment(
                value: 'online',
                icon: Icon(Icons.account_balance_wallet_outlined),
                label: Text('Online'),
              ),
            ],
            selected: {_method},
            onSelectionChanged: (value) =>
                setState(() => _method = value.first),
          ),
          if (_method == 'online') ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _txnRefCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Transaction ID (optional)',
                prefixIcon: Icon(Icons.receipt_long_outlined),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TestKeys.tag(
          TestKeys.saveBtn,
          FilledButton(onPressed: _save, child: const Text('Save')),
          button: true,
        ),
      ],
    );
  }
}
