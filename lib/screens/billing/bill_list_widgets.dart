part of '../bills_screen.dart';

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search by name, bill # or date...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: onClear,
              )
            : null,
      ),
    );
  }
}

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
