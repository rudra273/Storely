part of '../bills_screen.dart';

/// Shows who changed a bill and when (audit trail), oldest first.
Future<void> showBillHistory(BuildContext context, Bill bill) async {
  final entries = await DatabaseHelper.instance.getBillAudit(bill.uuid);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _BillHistorySheet(bill: bill, entries: entries),
  );
}

class _BillHistorySheet extends StatelessWidget {
  final Bill bill;
  final List<AuditEntry> entries;

  const _BillHistorySheet({required this.bill, required this.entries});

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd MMM yyyy, hh:mm a');
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('History', style: AppText.title),
            Text(_billDisplayId(bill), style: AppText.caption),
            const SizedBox(height: AppSpacing.md),
            _HistoryRow(
              icon: Icons.receipt_long_outlined,
              title: bill.isCreditNote ? 'Credit note created' : 'Bill created',
              details: rupees(bill.totalAmount),
              when: format.format(bill.createdAt),
            ),
            for (final e in entries)
              _HistoryRow(
                icon: switch (e.action) {
                  AuditAction.cancelled => Icons.block_rounded,
                  AuditAction.payment => Icons.payments_outlined,
                  AuditAction.markedUnpaid => Icons.undo_rounded,
                  AuditAction.creditNote => Icons.assignment_return_outlined,
                  _ => Icons.edit_outlined,
                },
                title: e.label,
                details: e.details,
                when: '${format.format(e.at)} · ${e.actor}',
                warning:
                    e.action == AuditAction.cancelled ||
                    e.action == AuditAction.markedUnpaid,
              ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  'No changes since it was created.',
                  style: AppText.caption,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? details;
  final String when;
  final bool warning;

  const _HistoryRow({
    required this.icon,
    required this.title,
    required this.details,
    required this.when,
    this.warning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.error : AppColors.inkMutedOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.subtitle.copyWith(color: color)),
                if (details != null && details!.isNotEmpty)
                  Text(details!, style: AppText.body),
                Text(when, style: AppText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
