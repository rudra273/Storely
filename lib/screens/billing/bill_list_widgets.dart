part of '../bills_screen.dart';

// ── Unpaid summary (collapsible) ──────────────────────────────────────────────

class _UnpaidSummary extends StatelessWidget {
  final List<Bill> bills;
  const _UnpaidSummary({required this.bills});

  @override
  Widget build(BuildContext context) {
    final unpaid = bills.where((b) => !b.isPaid).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (unpaid.isEmpty) return const SizedBox.shrink();

    final customerTotals = <String, double>{};
    for (final b in unpaid) {
      final name = b.customerName.trim().isEmpty
          ? 'Walk-in'
          : b.customerName.trim();
      customerTotals[name] = (customerTotals[name] ?? 0) + b.balanceDue;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            leading: const LeadingIconChip(
              icon: Icons.warning_amber_rounded,
              color: AppColors.error,
            ),
            title: Text(
              'Unpaid Bills Summary',
              style: AppText.subtitle.copyWith(color: AppColors.error),
            ),
            subtitle: Text(
              '${unpaid.length} pending bill${unpaid.length != 1 ? 's' : ''}',
              style: AppText.caption,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: [
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Text(
                'TOTAL DUE BY CUSTOMER',
                style: AppText.label.copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...customerTotals.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: AppText.body)),
                      Text(
                        '₹${e.value.toStringAsFixed(2)}',
                        style: AppText.subtitle.copyWith(
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'ALL UNPAID BILLS',
                style: AppText.label.copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...unpaid.map(
                (b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          DateFormat('dd MMM').format(b.createdAt),
                          style: AppText.caption,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.customerName,
                              style: AppText.body.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '#${b.billNumber.length > 4 ? b.billNumber.substring(b.billNumber.length - 4) : b.billNumber}',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${b.balanceDue.toStringAsFixed(0)}',
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Active / Cancelled filter ─────────────────────────────────────────────────

class _BillFilterTabs extends StatelessWidget {
  final bool showCancelled;
  final int activeCount;
  final int cancelledCount;
  final ValueChanged<bool> onChanged;

  const _BillFilterTabs({
    required this.showCancelled,
    required this.activeCount,
    required this.cancelledCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _FilterChip(
              label: 'Active',
              count: activeCount,
              selected: !showCancelled,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _FilterChip(
              label: 'Cancelled',
              count: cancelledCount,
              selected: showCancelled,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.surfaceOf(context)
              : Colors.transparent,
          borderRadius: AppRadius.smRadius,
          border: selected
              ? Border.all(color: AppColors.borderOf(context))
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          '$label ($count)',
          style: AppText.body.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? AppColors.inkOf(context)
                : AppColors.inkMutedOf(context),
          ),
        ),
      ),
    );
  }
}

// ── Cancelled bill card ───────────────────────────────────────────────────────

class _CancelledBillCard extends StatelessWidget {
  final Bill bill;
  final VoidCallback onDuplicate;

  const _CancelledBillCard({required this.bill, required this.onDuplicate});

  @override
  Widget build(BuildContext context) {
    final cancelledAt = bill.cancelledAt ?? bill.updatedAt;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const LeadingIconChip(
                icon: Icons.block_rounded,
                color: AppColors.inkMuted,
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
                      '${_billDisplayId(bill)} · ${bill.itemCount} item${bill.itemCount != 1 ? 's' : ''}',
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
                  const StatusPill(
                    label: 'Cancelled',
                    variant: PillVariant.neutral,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₹${bill.totalAmount.toStringAsFixed(2)}',
                    style: AppText.subtitle.copyWith(
                      fontSize: 14,
                      color: AppColors.inkMuted,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Divider(height: 1),
          const SizedBox(height: AppSpacing.sm),
          _BillMetaRow(
            icon: Icons.event_busy_outlined,
            text:
                'Cancelled ${DateFormat('dd MMM yyyy, hh:mm a').format(cancelledAt)}',
          ),
          if (bill.cancelReason != null && bill.cancelReason!.isNotEmpty)
            _BillMetaRow(
              icon: Icons.notes_outlined,
              text: 'Reason: ${bill.cancelReason}',
            ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: _ActionButton(
              onPressed: onDuplicate,
              icon: Icons.copy_rounded,
              label: 'Duplicate as New',
              color: AppColors.brandOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Date label ────────────────────────────────────────────────────────────────

class _DateLabel extends StatelessWidget {
  final String title;
  const _DateLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(title.toUpperCase(), style: AppText.label);
  }
}

// ── Bill card ─────────────────────────────────────────────────────────────────
