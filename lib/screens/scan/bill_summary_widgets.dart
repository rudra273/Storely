part of '../scan_screen.dart';

class _BillSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _BillSummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? AppColors.textDark : AppColors.textMuted,
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: isTotal ? AppColors.textDark : AppColors.textMuted,
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
/// start a new bill, or finish. Android back counts as Done.
class _BillCreatedDialog extends StatefulWidget {
  final Bill? bill;
  final double totalAmount;
  final String summary;

  const _BillCreatedDialog({
    required this.bill,
    required this.totalAmount,
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
    return AlertDialog(
      icon: const Icon(Icons.check_circle, color: AppColors.success, size: 48),
      title: Text(context.l10n.billCreated),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            rupees(widget.totalAmount),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            widget.summary,
            style: TextStyle(color: AppColors.inkMutedOf(context)),
            textAlign: TextAlign.center,
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(context.l10n.newBill),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
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

/// Parked carts: tap to resume, or delete.
class _HeldBillsSheet extends StatefulWidget {
  final List<HeldBill> held;
  final Future<void> Function(HeldBill bill) onDelete;

  const _HeldBillsSheet({required this.held, required this.onDelete});

  @override
  State<_HeldBillsSheet> createState() => _HeldBillsSheetState();
}

class _HeldBillsSheetState extends State<_HeldBillsSheet> {
  late final List<HeldBill> _held = List.of(widget.held);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.l10n.heldBills, style: AppText.title),
          const SizedBox(height: AppSpacing.sm),
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
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
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
                    onTap: () => Navigator.pop(context, bill),
                    trailing: IconButton(
                      tooltip: 'Delete held bill',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () async {
                        await widget.onDelete(bill);
                        if (mounted) setState(() => _held.removeAt(index));
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
