part of '../bills_screen.dart';

class _ReturnRequest {
  final Map<String, double> quantities;
  final String settlement;
  final String refundMethod;
  final String? reason;

  const _ReturnRequest({
    required this.quantities,
    required this.settlement,
    required this.refundMethod,
    required this.reason,
  });
}

/// Pick what the customer is returning from an invoice, see the credit
/// amount (same GST/round-off maths as billing), and choose to refund it or
/// adjust it against what they still owe.
class _ReturnSheet extends StatefulWidget {
  final Bill bill;
  final Map<String, double> returnable;
  final bool roundOff;

  const _ReturnSheet({
    required this.bill,
    required this.returnable,
    required this.roundOff,
  });

  @override
  State<_ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends State<_ReturnSheet> {
  final _reasonCtrl = TextEditingController();
  final Map<String, double> _qty = {};
  late String _settlement = widget.bill.balanceDue > 0.005
      ? DatabaseBills.creditNoteSettleAdjust
      : DatabaseBills.creditNoteSettleRefund;
  String _method = 'cash';

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  List<BillItem> get _returnableItems => widget.bill.items
      .where((item) => (widget.returnable[item.uuid] ?? 0) > 0)
      .toList();

  double get _creditAmount {
    final lines = [
      for (final item in widget.bill.items)
        if ((_qty[item.uuid] ?? 0) > 0)
          BillItem.fromMap({...item.toMap(0), 'quantity': -_qty[item.uuid]!}),
    ];
    if (lines.isEmpty) return 0;
    return -BillTotals.fromTaxedItems(
      lines,
      roundOff: widget.roundOff,
    ).grandTotal;
  }

  void _step(BillItem item, double delta) {
    final max = widget.returnable[item.uuid] ?? 0;
    final next = ((_qty[item.uuid] ?? 0) + delta).clamp(0.0, max).toDouble();
    setState(() => _qty[item.uuid] = next);
  }

  @override
  Widget build(BuildContext context) {
    final credit = _creditAmount;
    final canAdjust = widget.bill.balanceDue > 0.005;
    final adjustTooBig =
        _settlement == DatabaseBills.creditNoteSettleAdjust &&
        credit > widget.bill.balanceDue + 0.005;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Return items', style: AppText.title),
            Text(
              'From ${widget.bill.billNumber}. Returned stock goes back to '
              'inventory and a credit note is issued.',
              style: AppText.caption,
            ),
            const SizedBox(height: AppSpacing.md),
            if (_returnableItems.isEmpty)
              Text(
                'Everything on this bill has already been returned.',
                style: AppText.caption,
              ),
            for (final item in _returnableItems)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.productName, style: AppText.body),
                          Text(
                            'Up to ${_formatQty(widget.returnable[item.uuid]!)}'
                            ' ${item.unitLabel} · ${item.priceLabel}',
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Less',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => _step(item, -1),
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 36,
                      child: Text(
                        _formatQty(_qty[item.uuid] ?? 0),
                        textAlign: TextAlign.center,
                        style: AppText.subtitle,
                      ),
                    ),
                    IconButton(
                      tooltip: 'More',
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      onPressed: () => _step(item, 1),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<String>(
              segments: [
                if (canAdjust)
                  const ButtonSegment(
                    value: DatabaseBills.creditNoteSettleAdjust,
                    label: Text('Reduce dues'),
                  ),
                const ButtonSegment(
                  value: DatabaseBills.creditNoteSettleRefund,
                  label: Text('Refund'),
                ),
              ],
              selected: {_settlement},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => _settlement = value.first),
            ),
            if (_settlement == DatabaseBills.creditNoteSettleRefund) ...[
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Cash')),
                  ButtonSegment(value: 'online', label: Text('UPI / Online')),
                ],
                selected: {_method},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => _method = value.first),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reasonCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Damaged, wrong item',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _settlement == DatabaseBills.creditNoteSettleAdjust
                        ? 'Reduce dues by'
                        : 'Refund',
                    style: AppText.subtitle,
                  ),
                ),
                Text(rupees(credit), style: AppText.title),
              ],
            ),
            if (adjustTooBig)
              Text(
                'More than the ${rupees(widget.bill.balanceDue)} due. '
                'Choose Refund.',
                style: AppText.caption.copyWith(color: AppColors.error),
              ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: credit <= 0 || adjustTooBig
                  ? null
                  : () => Navigator.pop(
                      context,
                      _ReturnRequest(
                        quantities: {
                          for (final e in _qty.entries)
                            if (e.value > 0) e.key: e.value,
                        },
                        settlement: _settlement,
                        refundMethod: _method,
                        reason: _reasonCtrl.text.trim().isEmpty
                            ? null
                            : _reasonCtrl.text.trim(),
                      ),
                    ),
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('Issue Credit Note'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatQty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
