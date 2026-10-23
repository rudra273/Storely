import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/bill_totals.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';

/// Report shortcuts shown at the top of the Reports (KPI) screen.
class ReportShortcuts extends StatelessWidget {
  final VoidCallback? onGstr1;

  const ReportShortcuts({super.key, this.onGstr1});

  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.menu_book_outlined, 'Day book', const DayBookScreen()),
      (Icons.trending_up_rounded, 'Profit & loss', const ProfitLossScreen()),
      (Icons.schedule_rounded, 'Dues ageing', const ReceivablesScreen()),
      (Icons.inventory_2_outlined, 'Stock value', const StockValueScreen()),
    ];
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
        children: [
          for (final (icon, label, screen) in items)
            _ShortcutTile(
              icon: icon,
              label: label,
              onTap: () => _open(context, screen),
            ),
          if (onGstr1 != null)
            _ShortcutTile(
              icon: Icons.receipt_long_outlined,
              label: 'GSTR-1',
              onTap: onGstr1!,
            ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: SizedBox(
        width: 96,
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.brandOf(context)),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// Label/value row used across the reports.
class _Line extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  const _Line(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = (bold ? AppText.subtitle : AppText.body).copyWith(
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Loads [load] and rebuilds on [reloadKey] changes, with waiting/error
/// states handled once for every report.
class _ReportLoader<T> extends StatefulWidget {
  final Object reloadKey;
  final Future<T> Function() load;
  final Widget Function(T data) builder;

  const _ReportLoader({
    required this.reloadKey,
    required this.load,
    required this.builder,
  });

  @override
  State<_ReportLoader<T>> createState() => _ReportLoaderState<T>();
}

class _ReportLoaderState<T> extends State<_ReportLoader<T>> {
  late Future<T> _future = widget.load();

  @override
  void didUpdateWidget(covariant _ReportLoader<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              child: Text(
                'Could not load this report.\n${snap.error}',
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ),
          );
        }
        return widget.builder(snap.data as T);
      },
    );
  }
}

// ── Day book ────────────────────────────────────────────────────────────────

class DayBookScreen extends StatefulWidget {
  const DayBookScreen({super.key});

  @override
  State<DayBookScreen> createState() => _DayBookScreenState();
}

class _DayBookScreenState extends State<DayBookScreen> {
  DateTime _date = DateTime.now();

  bool get _isToday => _day(_date) == _day(DateTime.now());

  void _shift(int days) =>
      setState(() => _date = _date.add(Duration(days: days)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: navyAppBar(title: 'Day book'),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
                onPressed: () => _shift(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  _isToday
                      ? 'Today, ${DateFormat('dd MMM').format(_date)}'
                      : DateFormat('EEE, dd MMM yyyy').format(_date),
                  textAlign: TextAlign.center,
                  style: AppText.subtitle,
                ),
              ),
              IconButton(
                tooltip: 'Next day',
                onPressed: _isToday ? null : () => _shift(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Expanded(
            child: _ReportLoader<DayBook>(
              reloadKey: _day(_date),
              load: () => DatabaseHelper.instance.dayBook(_day(_date)),
              builder: (book) => _DayBookBody(book: book),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayBookBody extends StatelessWidget {
  final DayBook book;

  const _DayBookBody({required this.book});

  static String _method(String m) => switch (m) {
    'upi' => 'UPI',
    'card' => 'Card',
    'bank' => 'Bank',
    'cash' => 'Cash',
    _ => m,
  };

  @override
  Widget build(BuildContext context) {
    final entries = <({DateTime at, String title, String sub, double amount})>[
      for (final b in book.bills)
        (
          at: DateTime.parse(b['created_at'] as String),
          title:
              '${b['document_type'] == 'credit_note' ? 'Credit note' : 'Bill'}'
              ' ${b['bill_number']}',
          sub: b['customer_name'] as String? ?? '',
          amount: (b['total_amount'] as num).toDouble(),
        ),
      for (final e in book.expenses)
        (
          at: e.date,
          title: 'Expense · ${e.category}',
          sub: [_method(e.paymentMethod), ?e.notes].join(' · '),
          amount: -e.amount,
        ),
    ]..sort((a, b) => a.at.compareTo(b.at));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xxxl,
      ),
      children: [
        AppCard(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Line('Sales (bills)', rupees(book.sales)),
              for (final m in book.paymentsByMethod.entries)
                _Line('Received · ${_method(m.key)}', signedRupees(m.value)),
              _Line('Expenses', '-${rupees(book.totalExpenses)}'),
              const Divider(),
              _Line(
                'Net cash for the day',
                signedRupees(book.netCash),
                bold: true,
                color: book.netCash < 0 ? AppColors.error : null,
              ),
              Text(
                'Cash received, less cash refunds and cash expenses.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Text(
              'Nothing recorded on this day.',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          )
        else
          for (final e in entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Text(
                DateFormat('hh:mm a').format(e.at),
                style: AppText.caption,
              ),
              title: Text(e.title),
              subtitle: e.sub.isEmpty ? null : Text(e.sub),
              trailing: Text(
                signedRupees(e.amount),
                style: AppText.subtitle.copyWith(
                  color: e.amount < 0 ? AppColors.error : null,
                ),
              ),
            ),
      ],
    );
  }
}

// ── Profit & loss ───────────────────────────────────────────────────────────

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final last = DateTime(_month.year, _month.month + 1, 0);
    final isCurrent =
        _month.year == DateTime.now().year &&
        _month.month == DateTime.now().month;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: navyAppBar(title: 'Profit & loss'),
      body: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1),
                ),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(_month),
                  textAlign: TextAlign.center,
                  style: AppText.subtitle,
                ),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: isCurrent
                    ? null
                    : () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1),
                      ),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Expanded(
            child: _ReportLoader<ProfitAndLoss>(
              reloadKey: _day(_month),
              load: () => DatabaseHelper.instance.profitAndLoss(
                from: _day(_month),
                to: _day(last),
              ),
              builder: (pl) => ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xxxl,
                ),
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line(
                          'Sales (excl. GST, net of returns)',
                          rupees(pl.sales),
                        ),
                        _Line(
                          'Cost of goods sold',
                          '-${rupees(pl.costOfGoods)}',
                        ),
                        const Divider(),
                        _Line(
                          'Gross profit',
                          signedRupees(pl.grossProfit),
                          bold: true,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        for (final e in pl.expensesByCategory.entries)
                          _Line(e.key, '-${rupees(e.value)}'),
                        if (pl.expensesByCategory.isEmpty)
                          Text('No expenses recorded', style: AppText.caption),
                        const Divider(),
                        _Line(
                          'Net profit',
                          signedRupees(pl.netProfit),
                          bold: true,
                          color: pl.netProfit < 0
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    [
                      if (pl.gstCollected > 0.005)
                        'GST collected ${rupees(pl.gstCollected)} is owed to '
                            'the government, so it is left out above.',
                      'Cost uses the cost price saved on each bill.',
                    ].join(' '),
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Receivables ageing ──────────────────────────────────────────────────────

class ReceivablesScreen extends StatelessWidget {
  const ReceivablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: navyAppBar(title: 'Dues ageing'),
      body: _ReportLoader<List<AgeingRow>>(
        reloadKey: 0,
        load: DatabaseHelper.instance.receivablesAgeing,
        builder: (rows) {
          final totals = List<double>.generate(
            4,
            (i) => rows.fold(0.0, (s, r) => s + r.buckets[i]),
          );
          final grand = totals.fold(0.0, (s, v) => s + v);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line('Customers owe you', rupees(grand), bold: true),
                        for (var b = 0; b < 4; b++)
                          _Line(
                            DatabaseReports.ageingBuckets[b],
                            rupees(totals[b]),
                            color: b >= 2 && totals[b] > 0
                                ? AppColors.error
                                : null,
                          ),
                        if (rows.isEmpty)
                          Text('Nothing is due. 🎉', style: AppText.caption),
                      ],
                    ),
                  ),
                );
              }
              final row = rows[i - 1];
              final oldest = row.buckets.lastIndexWhere((v) => v > 0.005);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row.customerName),
                subtitle: Text(
                  [
                    if (row.customerPhone != null &&
                        row.customerPhone!.isNotEmpty)
                      row.customerPhone!,
                    'oldest ${DatabaseReports.ageingBuckets[oldest]}',
                  ].join(' · '),
                ),
                trailing: Text(
                  rupees(row.total),
                  style: AppText.subtitle.copyWith(
                    color: oldest >= 2 ? AppColors.error : null,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ── Stock valuation ─────────────────────────────────────────────────────────

class StockValueScreen extends StatelessWidget {
  const StockValueScreen({super.key});

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: navyAppBar(title: 'Stock value'),
      body: _ReportLoader<List<StockValueRow>>(
        reloadKey: 0,
        load: DatabaseHelper.instance.stockValuation,
        builder: (rows) {
          final cost = rows.fold(0.0, (s, r) => s + r.costValue);
          final sale = rows.fold(0.0, (s, r) => s + r.saleValue);
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxxl,
            ),
            itemCount: rows.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Line('Stock at cost', rupees(cost), bold: true),
                        _Line('At selling price', rupees(sale)),
                        _Line(
                          'Expected margin',
                          signedRupees(roundMoney(sale - cost)),
                        ),
                        Text(
                          '${rows.length} items in stock. Cost is the '
                          'weighted-average purchase price.',
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                );
              }
              final row = rows[i - 1];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(row.name),
                subtitle: Text(
                  [
                    '${_qty(row.quantity)} ${row.unit ?? ''}'.trim(),
                    ?row.category,
                  ].join(' · '),
                ),
                trailing: Text(rupees(row.costValue), style: AppText.subtitle),
              );
            },
          );
        },
      ),
    );
  }
}
