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
      title: const Text('Bill Created!'),
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
              label: const Text('Share PDF (WhatsApp, print…)'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('New Bill'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, false),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.brandOf(context),
            foregroundColor: AppColors.isDark(context)
                ? Colors.black
                : Colors.white,
          ),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
