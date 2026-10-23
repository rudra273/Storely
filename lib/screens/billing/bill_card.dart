part of '../bills_screen.dart';

class _BillCard extends StatefulWidget {
  final Bill bill;
  final VoidCallback onCancel;
  final VoidCallback onEdit;
  final VoidCallback onSendWhatsApp;
  final VoidCallback onSharePdf;
  final void Function(
    bool isPaid,
    String? paymentMethod,
    String? paymentReference,
  )
  onStatusChanged;
  final VoidCallback onRecordPayment;

  /// Admin action to issue a credit note (sales return); null when not
  /// allowed for this bill.
  final VoidCallback? onReturn;

  /// Not uploaded to cloud yet (only set when the phone syncs).
  final bool waitingToSync;

  const _BillCard({
    this.onReturn,
    this.waitingToSync = false,
    required this.bill,
    required this.onCancel,
    required this.onEdit,
    required this.onSendWhatsApp,
    required this.onSharePdf,
    required this.onStatusChanged,
    required this.onRecordPayment,
  });

  @override
  State<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<_BillCard> {
  bool _expanded = false;

  Future<void> _togglePaidStatus() async {
    final bill = widget.bill;
    if (bill.isPaid) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Mark as unpaid?'),
          content: Text(
            'This removes all recorded payments on this bill '
            '(${rupees(bill.paidAmount)}). '
            'Use this only to correct a mistake.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Paid'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Mark Unpaid'),
            ),
          ],
        ),
      );
      if (confirmed == true) widget.onStatusChanged(false, null, null);
      return;
    }
    final method = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment Method'),
        content: const Text('How was this bill paid?'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, 'cash'),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Cash'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'online'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
            label: const Text('Online'),
          ),
        ],
      ),
    );
    if (method == null) return;
    String? reference;
    if (method == 'online') {
      if (!mounted) return;
      reference = await _promptTransactionId();
      if (!mounted) return;
    }
    widget.onStatusChanged(true, method, reference);
  }

  /// Prompts for an optional online transaction id. Returns the entered value
  /// (may be empty/null); a dismissed dialog also yields null. The bill is still
  /// marked paid either way — the id is optional.
  Future<String?> _promptTransactionId() {
    return showDialog<String>(
      context: context,
      builder: (_) => const _TransactionIdDialog(),
    );
  }

  Future<void> _print() async {
    try {
      await ThermalPrinterService.instance.printBill(widget.bill);
    } on PrinterException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Printing failed. Try again.')),
      );
    }
  }

  Future<void> _showProfitSummary() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillProfitSheet(bill: widget.bill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final dateStr = DateFormat('hh:mm a').format(bill.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: AppRadius.mdRadius,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const LeadingIconChip(
                      icon: Icons.receipt_outlined,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bill.customerName.isEmpty
                                ? 'Walk-in'
                                : bill.customerName,
                            style: AppText.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_billDisplayId(bill)} · $dateStr · ${bill.itemCount} item${bill.itemCount != 1 ? 's' : ''}',
                            style: AppText.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (bill.isCreditNote)
                              const _CreditNoteChip()
                            else
                              _PaymentChip(status: bill.paymentStatus),
                            if (!bill.isCreditNote && bill.paidAmount > 0) ...[
                              const SizedBox(width: 4),
                              _MethodChip(method: bill.paymentMethod),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          rupees(bill.totalAmount),
                          style: AppText.subtitle.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: AppColors.inkFaintOf(context),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    if (widget.waitingToSync)
                      const Padding(
                        padding: EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _BillMetaRow(
                          icon: Icons.cloud_upload_outlined,
                          text: 'Saved on this phone · waiting to sync',
                        ),
                      ),
                    if (bill.isCreditNote && bill.originalBillNumber != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _BillMetaRow(
                          icon: Icons.undo_rounded,
                          text:
                              'Against ${bill.originalBillNumber}'
                              '${bill.cancelReason == null ? '' : ' · ${bill.cancelReason}'}',
                        ),
                      ),
                    if (bill.customerPhone != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Icon(
                              Icons.phone_outlined,
                              size: 15,
                              color: AppColors.inkMutedOf(context),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(bill.customerPhone!, style: AppText.caption),
                          ],
                        ),
                      ),
                    if (bill.billType == Bill.typeB2b ||
                        bill.customerGstin != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (bill.customerGstin != null)
                              _BillMetaRow(
                                icon: Icons.badge_outlined,
                                text: 'GSTIN ${bill.customerGstin}',
                              ),
                            if (bill.customerGstLegalName != null)
                              _BillMetaRow(
                                icon: Icons.business_center_outlined,
                                text: bill.customerGstLegalName!,
                              ),
                            if (bill.customerGstTradeName != null)
                              _BillMetaRow(
                                icon: Icons.storefront_outlined,
                                text: bill.customerGstTradeName!,
                              ),
                            if (bill.customerAddressSnapshot != null)
                              _BillMetaRow(
                                icon: Icons.location_on_outlined,
                                text: bill.customerAddressSnapshot!,
                              ),
                            if (bill.placeOfSupplyStateCode != null)
                              _BillMetaRow(
                                icon: Icons.map_outlined,
                                text:
                                    'Place of supply ${bill.placeOfSupplyStateCode}',
                              ),
                          ],
                        ),
                      ),
                    ...bill.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.productName,
                                style: AppText.body,
                              ),
                            ),
                            Text(
                              '${item.quantityLabel} × ${item.priceLabel}',
                              style: AppText.caption,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              rupees(item.subtotal),
                              style: AppText.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: AppSpacing.lg),
                    if (bill.discountAmount > 0 ||
                        bill.roundOffAmount != 0) ...[
                      _AmountRow(
                        label: 'Subtotal',
                        value: rupees(bill.subtotalAmount),
                      ),
                      if (bill.discountAmount > 0)
                        _AmountRow(
                          label:
                              'Discount ${bill.discountPercent.toStringAsFixed(2)}%',
                          value: '−${rupees(bill.discountAmount)}',
                        ),
                      if (bill.roundOffAmount != 0)
                        _AmountRow(
                          label: 'Round off',
                          value: signedRupees(bill.roundOffAmount),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: AppText.subtitle),
                        Text(
                          rupees(bill.totalAmount),
                          style: AppText.subtitle.copyWith(
                            color: AppColors.inkOf(context),
                          ),
                        ),
                      ],
                    ),
                    if (bill.paidAmount > 0 || bill.balanceDue > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _AmountRow(label: 'Paid', value: rupees(bill.paidAmount)),
                      _AmountRow(
                        label: 'Balance',
                        value: rupees(bill.balanceDue),
                      ),
                    ],
                    if (bill.transactionReference != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _AmountRow(
                        label: 'Txn ID',
                        value: bill.transactionReference!,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      children: [
                        if (CloudService.instance.state.value.isAdmin) ...[
                          _ActionButton(
                            onPressed: widget.onCancel,
                            icon: Icons.block_rounded,
                            label: 'Cancel',
                            color: AppColors.error,
                          ),
                          if (!bill.isCreditNote)
                            _ActionButton(
                              onPressed: widget.onEdit,
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                              color: AppColors.brandOf(context),
                            ),
                          if (widget.onReturn != null)
                            _ActionButton(
                              onPressed: widget.onReturn!,
                              icon: Icons.assignment_return_outlined,
                              label: 'Return',
                              color: AppColors.amber,
                            ),
                        ],
                        if (!bill.isCreditNote &&
                            (!bill.isPaid ||
                                CloudService.instance.state.value.isAdmin))
                          _ActionButton(
                            onPressed: _togglePaidStatus,
                            icon: bill.isPaid
                                ? Icons.pending_actions_outlined
                                : Icons.check_circle_outline,
                            label: bill.isPaid ? 'Mark Unpaid' : 'Mark Paid',
                            color: bill.isPaid
                                ? AppColors.inkMutedOf(context)
                                : AppColors.success,
                          ),
                        if (!bill.isCreditNote && bill.balanceDue > 0)
                          _ActionButton(
                            onPressed: widget.onRecordPayment,
                            icon: Icons.payments_outlined,
                            label: 'Record Payment',
                            color: AppColors.amber,
                          ),
                        if (!bill.isCreditNote && bill.customerPhone != null)
                          _ActionButton(
                            onPressed: widget.onSendWhatsApp,
                            icon: Icons.send_outlined,
                            label: 'WhatsApp',
                            color: AppColors.success,
                          ),
                        if (ThermalPrinterService.instance.isConfigured)
                          _ActionButton(
                            onPressed: _print,
                            icon: Icons.print_outlined,
                            label: 'Print',
                            color: AppColors.brandOf(context),
                          ),
                        _ActionButton(
                          onPressed: widget.onSharePdf,
                          icon: Icons.ios_share_rounded,
                          label: 'Share',
                          color: AppColors.brandOf(context),
                        ),
                        if (!bill.isCreditNote)
                          _ActionButton(
                            onPressed: _showProfitSummary,
                            icon: Icons.trending_up_rounded,
                            label: 'View Profit',
                            color: AppColors.brandOf(context),
                          ),
                        _ActionButton(
                          onPressed: () => showBillHistory(context, bill),
                          icon: Icons.history_rounded,
                          label: 'History',
                          color: AppColors.inkMutedOf(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BillMetaRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _BillMetaRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: AppColors.inkMutedOf(context)),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: AppText.caption)),
        ],
      ),
    );
  }
}

// ── Profit sheet ──────────────────────────────────────────────────────────────

class _CreditNoteChip extends StatelessWidget {
  const _CreditNoteChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.amber.withValues(alpha: 0.15),
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        'Credit note',
        style: AppText.caption.copyWith(
          color: AppColors.amber,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
