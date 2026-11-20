import 'package:flutter/material.dart';

import '../../models/checkout_settlement.dart';
import '../../theme/app_theme.dart';
import '../../utils/money.dart';
import '../../utils/decimal_text.dart';
import '../../utils/test_keys.dart';

/// Amount + payment method (+ optional reference) for a payment received.
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
    BigInt amount;
    BigInt balance;
    try {
      final text = _amountCtrl.text.trim();
      // Keep established US and Indian grouping while refusing malformed input.
      final plain = RegExp(r'^\d+(?:\.\d{1,2})?$');
      final grouped = RegExp(
        r'^(?:\d{1,3}(?:,\d{3})+|\d{1,2}(?:,\d{2})*,\d{3})(?:\.\d{1,2})?$',
      );
      if (!plain.hasMatch(text) && !grouped.hasMatch(text)) {
        throw const FormatException('Invalid payment amount');
      }
      amount = decimalScaledInteger(text.replaceAll(',', ''), scale: 2);
      balance = decimalScaledInteger(
        widget.balanceDue.toStringAsFixed(2),
        scale: 2,
      );
    } on FormatException {
      setState(
        () => _amountError =
            'Enter a valid amount with at most two decimal places',
      );
      return;
    }
    final error = amount <= BigInt.zero
        ? 'Enter an amount greater than 0'
        : amount > balance
        ? 'Cannot be more than the balance due'
        : null;
    if (error != null) {
      setState(() => _amountError = error);
      return;
    }
    final trimmedRef = _txnRefCtrl.text.trim();
    Navigator.pop(
      context,
      PaymentEntry(
        amount: amount.toDouble() / 100,
        method: _method,
        reference: _method == 'cash'
            ? null
            : (trimmedRef.isEmpty ? null : trimmedRef),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('payment-amount'),
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount received',
                prefixText: '₹ ',
                helperText: 'Balance: ${rupees(widget.balanceDue)}',
                errorText: _amountError,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in checkoutPaymentMethods)
                  ChoiceChip(
                    key: ValueKey('payment-method-$method'),
                    label: Text(paymentMethodLabel(method)),
                    selected: _method == method,
                    onSelected: (_) => setState(() => _method = method),
                  ),
              ],
            ),
            if (_method != 'cash') ...[
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('payment-reference'),
                controller: _txnRefCtrl,
                maxLength: 100,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Reference (optional)',
                  prefixIcon: Icon(Icons.receipt_long_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Storely records the payment method and reference on the invoice; it does not collect the payment itself.',
                style: AppText.caption,
              ),
            ],
          ],
        ),
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
