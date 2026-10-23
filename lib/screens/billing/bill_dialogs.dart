part of '../bills_screen.dart';

// Bill dialogs own their TextEditingControllers so the controllers are
// disposed with the dialog itself, after its exit animation. Disposing them
// right after `await showDialog` returns (while the route is still animating
// out) makes the closing TextField touch a disposed controller.

class _CancelBillDialog extends StatefulWidget {
  final String billLabel;

  const _CancelBillDialog({required this.billLabel});

  @override
  State<_CancelBillDialog> createState() => _CancelBillDialogState();
}

class _CancelBillDialogState extends State<_CancelBillDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: Icon(Icons.block_rounded, color: AppColors.error, size: 32),
      title: const Text('Cancel Bill'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Cancel ${widget.billLabel}? Stock and customer ledger will be reversed.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _reasonCtrl,
            textCapitalization: TextCapitalization.sentences,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Reason',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Keep Bill'),
        ),
        TestKeys.tag(
          TestKeys.confirmBtn,
          FilledButton(
            onPressed: () => Navigator.pop(context, _reasonCtrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel Bill'),
          ),
          button: true,
        ),
      ],
    );
  }
}

class _PaymentEntry {
  final double amount;
  final String method;
  final String? reference;

  const _PaymentEntry({
    required this.amount,
    required this.method,
    required this.reference,
  });
}

class _RecordPaymentDialog extends StatefulWidget {
  final double balanceDue;

  const _RecordPaymentDialog({required this.balanceDue});

  @override
  State<_RecordPaymentDialog> createState() => _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends State<_RecordPaymentDialog> {
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
      _PaymentEntry(
        amount: value!,
        method: _method,
        reference: _method == 'online' ? _txnRefCtrl.text : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record Payment'),
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

class _TransactionIdDialog extends StatefulWidget {
  const _TransactionIdDialog();

  @override
  State<_TransactionIdDialog> createState() => _TransactionIdDialogState();
}

class _TransactionIdDialogState extends State<_TransactionIdDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Transaction ID'),
      content: TextField(
        controller: _ctrl,
        textCapitalization: TextCapitalization.characters,
        decoration: const InputDecoration(
          labelText: 'Transaction ID (optional)',
          prefixIcon: Icon(Icons.receipt_long_outlined),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Skip'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
