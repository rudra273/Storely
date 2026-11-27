part of '../scan_screen.dart';

enum _BillCreatedAction { newBill, done, viewInvoice }

class _BillSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Key? valueKey;
  final Color? valueColor;

  const _BillSummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueKey,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = isTotal
        ? AppColors.inkOf(context)
        : AppColors.inkMutedOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            key: valueKey,
            style: TextStyle(
              color: valueColor ?? labelColor,
              fontSize: isTotal ? 20 : 14,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Bill Created!" with the next steps: share the PDF (WhatsApp, print...),
/// view the saved invoice, start a new bill, or finish.
class _BillCreatedDialog extends StatefulWidget {
  final Bill? bill;
  final double totalAmount;
  final double paidAmount;
  final String summary;

  const _BillCreatedDialog({
    required this.bill,
    required this.totalAmount,
    required this.paidAmount,
    required this.summary,
  });

  @override
  State<_BillCreatedDialog> createState() => _BillCreatedDialogState();
}

class _BillCreatedDialogState extends State<_BillCreatedDialog> {
  bool _sharing = false;
  bool _printing = false;

  Future<void> _print() async {
    final bill = widget.bill;
    if (bill == null || _printing) return;
    setState(() => _printing = true);
    try {
      await ThermalPrinterService.instance.printBill(bill);
    } on PrinterException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printing failed. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _share() async {
    final bill = widget.bill;
    if (bill == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      await BillShare.sharePdf(bill);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the bill PDF')),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.bill?.totalAmount ?? widget.totalAmount;
    final received = widget.bill?.paidAmount ?? widget.paidAmount;
    final balanceDue =
        widget.bill?.balanceDue ??
        (total - received).clamp(0.0, total).toDouble();
    return AlertDialog(
      icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
      title: Text(context.l10n.billCreated),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rupees(total),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.summary,
              style: TextStyle(color: AppColors.inkMutedOf(context)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.softBgOf(context),
                borderRadius: AppRadius.mdRadius,
                border: Border.all(color: AppColors.borderOf(context)),
              ),
              child: Column(
                children: [
                  _BillSummaryRow(
                    label: context.l10n.total,
                    value: rupees(total),
                    valueKey: const ValueKey('checkout-completion-total'),
                  ),
                  _BillSummaryRow(
                    label: context.l10n.received,
                    value: rupees(received),
                    valueKey: const ValueKey('checkout-completion-received'),
                  ),
                  _BillSummaryRow(
                    label: 'Balance due',
                    value: rupees(balanceDue),
                    valueKey: const ValueKey('checkout-completion-balance'),
                    valueColor: balanceDue > 0.005 ? AppColors.error : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.bill == null || _sharing ? null : _share,
                icon: _sharing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.share_rounded),
                label: Text(context.l10n.sharePdf),
              ),
            ),
            if (ThermalPrinterService.instance.isConfigured) ...[
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: widget.bill == null || _printing ? null : _print,
                  icon: _printing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.print_rounded),
                  label: Text(context.l10n.printReceipt),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: const ValueKey('checkout-completion-view'),
                onPressed: widget.bill == null
                    ? null
                    : () => Navigator.pop(
                        context,
                        _BillCreatedAction.viewInvoice,
                      ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View invoice'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('checkout-completion-new'),
          onPressed: () => Navigator.pop(context, _BillCreatedAction.newBill),
          child: Text(context.l10n.newBill),
        ),
        FilledButton(
          key: const ValueKey('checkout-completion-done'),
          onPressed: () => Navigator.pop(context, _BillCreatedAction.done),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandOf(context),
            foregroundColor: AppColors.isDark(context)
                ? Colors.black
                : Colors.white,
          ),
          child: Text(context.l10n.done),
        ),
      ],
    );
  }
}

sealed class _HeldSheetSelection {
  const _HeldSheetSelection();
}

class _ResumeHeldBill extends _HeldSheetSelection {
  final HeldBill bill;
  const _ResumeHeldBill(this.bill);
}

class _ClaimedDraftHandoff extends _HeldSheetSelection {
  final DraftHandoff handoff;
  const _ClaimedDraftHandoff(this.handoff);
}

/// Parked carts: tap to resume, or delete. When signed into a cloud shop, also
/// shows available single-consumer cloud handoffs to take over or discard.
class _HeldBillsSheet extends StatefulWidget {
  final List<HeldBill> held;
  final Future<void> Function(HeldBill bill) onDelete;
  final bool showCloudHandoffs;
  final Future<List<DraftHandoff>> Function()? onLoadCloudHandoffs;
  final Future<DraftHandoff> Function(DraftHandoff handoff)?
  onClaimCloudHandoff;
  final Future<void> Function(DraftHandoff handoff)? onDiscardCloudHandoff;

  const _HeldBillsSheet({
    required this.held,
    required this.onDelete,
    this.showCloudHandoffs = false,
    this.onLoadCloudHandoffs,
    this.onClaimCloudHandoff,
    this.onDiscardCloudHandoff,
  });

  @override
  State<_HeldBillsSheet> createState() => _HeldBillsSheetState();
}

class _HeldBillsSheetState extends State<_HeldBillsSheet> {
  late final List<HeldBill> _held = List.of(widget.held);
  List<DraftHandoff> _handoffs = const [];
  bool _loadingHandoffs = false;
  String? _busyHandoffId;
  String? _handoffMessage;

  @override
  void initState() {
    super.initState();
    if (widget.showCloudHandoffs && widget.onLoadCloudHandoffs != null) {
      _refreshCloudHandoffs();
    }
  }

  Future<void> _refreshCloudHandoffs({bool clearMessage = false}) async {
    final loader = widget.onLoadCloudHandoffs;
    if (loader == null) return;
    setState(() {
      _loadingHandoffs = true;
      if (clearMessage) _handoffMessage = null;
    });
    try {
      final list = await loader();
      if (!mounted) return;
      setState(() {
        _handoffs = list;
        _loadingHandoffs = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingHandoffs = false;
        _handoffMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _claimHandoff(DraftHandoff handoff) async {
    final claimer = widget.onClaimCloudHandoff;
    if (claimer == null || _busyHandoffId != null) return;
    setState(() {
      _busyHandoffId = handoff.uuid;
      _handoffMessage = null;
    });
    try {
      final claimed = await claimer(handoff);
      if (!mounted) return;
      Navigator.pop(context, _ClaimedDraftHandoff(claimed));
    } on DraftHandoffAlreadyClaimedException catch (error) {
      if (!mounted) return;
      setState(() {
        _busyHandoffId = null;
        _handoffMessage = error.message;
      });
      await _refreshCloudHandoffs();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyHandoffId = null;
        _handoffMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Future<void> _discardHandoff(DraftHandoff handoff) async {
    final discarder = widget.onDiscardCloudHandoff;
    if (discarder == null || _busyHandoffId != null) return;
    setState(() {
      _busyHandoffId = handoff.uuid;
      _handoffMessage = null;
    });
    try {
      await discarder(handoff);
      if (!mounted) return;
      setState(() {
        _busyHandoffId = null;
        _handoffs = _handoffs
            .where((item) => item.uuid != handoff.uuid)
            .toList();
      });
    } on DraftHandoffAlreadyClaimedException catch (error) {
      if (!mounted) return;
      setState(() {
        _busyHandoffId = null;
        _handoffMessage = error.message;
      });
      await _refreshCloudHandoffs();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyHandoffId = null;
        _handoffMessage = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  Widget _buildCloudHandoffsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Cloud handoffs',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const ValueKey('handoff-refresh'),
              tooltip: 'Refresh cloud handoffs',
              onPressed: _loadingHandoffs
                  ? null
                  : () => _refreshCloudHandoffs(clearMessage: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        if (_handoffMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.1),
              borderRadius: AppRadius.smRadius,
              border: Border.all(
                color: AppColors.error.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              _handoffMessage!,
              style: TextStyle(color: AppColors.error, fontSize: 13),
            ),
          ),
        if (_loadingHandoffs)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_handoffs.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              'No cloud handoffs available.',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          )
        else
          for (var i = 0; i < _handoffs.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _handoffs[i].label.isNotEmpty
                              ? _handoffs[i].label
                              : 'Draft cart',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'From ${_handoffs[i].sourceDeviceLabel} · '
                          '${_handoffs[i].itemCount} '
                          'item${_handoffs[i].itemCount == 1 ? '' : 's'}',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  TextButton(
                    key: ValueKey('handoff-discard-${_handoffs[i].uuid}'),
                    onPressed: _busyHandoffId != null
                        ? null
                        : () => _discardHandoff(_handoffs[i]),
                    child: const Text('Discard'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    key: ValueKey('handoff-claim-${_handoffs[i].uuid}'),
                    onPressed: _busyHandoffId != null
                        ? null
                        : () => _claimHandoff(_handoffs[i]),
                    child: _busyHandoffId == _handoffs[i].uuid
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Take over'),
                  ),
                ],
              ),
            ),
          ],
        const SizedBox(height: AppSpacing.md),
        const Divider(height: 1),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.l10n.heldBills, style: AppText.title),
            const SizedBox(height: AppSpacing.sm),
            if (widget.showCloudHandoffs) _buildCloudHandoffsSection(context),
            if (_held.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Text(
                  context.l10n.noHeldBills,
                  textAlign: TextAlign.center,
                  style: AppText.caption,
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _held.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  final bill = _held[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(bill.label),
                    subtitle: Text(
                      '${bill.items.length} item${bill.items.length == 1 ? '' : 's'}'
                      ' · ${rupees(bill.total)}',
                    ),
                    onTap: bill.readOnly
                        ? () => showDialog<void>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(bill.label),
                              content: SingleChildScrollView(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Read-only backup from another device. Resume the original cart on that device to avoid duplicate billing.',
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    for (final item in bill.items)
                                      Text(
                                        '${item.productName} × ${item.quantity} · ${rupees(item.subtotal)}',
                                      ),
                                  ],
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Close'),
                                ),
                              ],
                            ),
                          )
                        : () => Navigator.pop(context, _ResumeHeldBill(bill)),
                    leading: bill.readOnly
                        ? const Icon(Icons.lock_outline)
                        : null,
                    trailing: bill.readOnly
                        ? null
                        : IconButton(
                            tooltip: 'Delete held bill',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              try {
                                await widget.onDelete(bill);
                                if (mounted) {
                                  setState(
                                    () => _held.removeWhere(
                                      (row) => row.id == bill.id,
                                    ),
                                  );
                                }
                              } catch (error) {
                                if (!mounted || !context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not delete this cart: $error',
                                    ),
                                  ),
                                );
                              }
                            },
                          ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
