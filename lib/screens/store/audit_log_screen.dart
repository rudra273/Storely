import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';

/// Shop-wide chronological audit & activity trail (bills, products, stock).
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  final _searchCtrl = TextEditingController();
  String? _entityType; // null = All
  String _query = '';
  bool _loading = true;
  List<AuditEntry> _entries = const [];

  static const _filters = <(String?, String, String)>[
    (null, 'All', 'audit-filter-all'),
    ('bill', 'Bills', 'audit-filter-bill'),
    ('product', 'Products', 'audit-filter-product'),
    ('stock', 'Stock', 'audit-filter-stock'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await DatabaseHelper.instance.getShopAuditLog(
      entityType: _entityType,
      query: _query,
    );
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final format = DateFormat('dd MMM yyyy, hh:mm a');
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Activity & audit')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('audit-log-search'),
                  controller: _searchCtrl,
                  onChanged: (value) {
                    _query = value.trim();
                    _load();
                  },
                  decoration: InputDecoration(
                    hintText: 'Search activity, actor, or details',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              _query = '';
                              _load();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in _filters) ...[
                        ChoiceChip(
                          key: ValueKey(filter.$3),
                          label: Text(filter.$2),
                          selected: _entityType == filter.$1,
                          onSelected: (_) {
                            if (_entityType == filter.$1) return;
                            setState(() => _entityType = filter.$1);
                            _load();
                          },
                        ),
                        const SizedBox(width: AppSpacing.xs),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        _query.isEmpty && _entityType == null
                            ? 'No activity recorded yet.'
                            : 'No matching activity entries.',
                        style: AppText.body.copyWith(
                          color: AppColors.inkMutedOf(context),
                        ),
                      ),
                    ),
                  )
                : RefreshIndicator(
                    color: AppColors.amber,
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.xl,
                      ),
                      itemCount: _entries.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) => _AuditEntryCard(
                        entry: _entries[index],
                        formattedTime: format.format(_entries[index].at),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AuditEntryCard extends StatelessWidget {
  final AuditEntry entry;
  final String formattedTime;

  const _AuditEntryCard({required this.entry, required this.formattedTime});

  @override
  Widget build(BuildContext context) {
    final isWarning =
        entry.action == AuditAction.cancelled ||
        entry.action == AuditAction.markedUnpaid ||
        entry.action == AuditAction.deleted;
    final icon = switch (entry.entityType) {
      'product' => Icons.inventory_2_outlined,
      'stock' => Icons.swap_vert_rounded,
      _ => switch (entry.action) {
        AuditAction.cancelled => Icons.block_rounded,
        AuditAction.payment => Icons.payments_outlined,
        AuditAction.markedUnpaid => Icons.undo_rounded,
        AuditAction.creditNote => Icons.assignment_return_outlined,
        _ => Icons.receipt_long_outlined,
      },
    };
    final entityLabel = switch (entry.entityType) {
      'bill' => 'Bill',
      'product' => 'Product',
      'stock' => 'Stock',
      _ => entry.entityType,
    };
    final accent = isWarning ? AppColors.error : AppColors.brandOf(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.label,
                        style: AppText.subtitle.copyWith(
                          color: isWarning ? AppColors.error : null,
                        ),
                      ),
                    ),
                    StatusPill(
                      label: entityLabel,
                      variant: switch (entry.entityType) {
                        'stock' => PillVariant.warning,
                        'product' => PillVariant.info,
                        _ => isWarning ? PillVariant.unpaid : PillVariant.paid,
                      },
                    ),
                  ],
                ),
                if (entry.details != null && entry.details!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(entry.details!, style: AppText.body),
                ],
                const SizedBox(height: 4),
                Text(
                  '$formattedTime · ${entry.actor}',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
