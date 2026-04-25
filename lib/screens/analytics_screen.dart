import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../main.dart';
import '../models/bill.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Bill> _bills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bills = await DatabaseHelper.instance.getAllBills();
    if (!mounted) return;
    setState(() {
      _bills = bills;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _bills.expand((bill) => bill.items).toList();
    final revenue = items.fold(0.0, (sum, item) => sum + item.subtotal);
    final cost = items.fold(0.0, (sum, item) => sum + item.totalCost);
    final grossProfit = items.fold(0.0, (sum, item) => sum + item.totalProfit);
    final commission = _bills.fold(
      0.0,
      (sum, bill) =>
          sum +
          (bill.items.fold(0.0, (s, item) => s + item.totalProfit) *
              bill.profitCommissionPercent /
              100),
    );
    final gst = items.fold(0.0, (sum, item) => sum + item.totalGst);
    final net = grossProfit - commission;
    final topSelling = _topSelling(items);

    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text(
          'Analytics',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _AnalyticsPanel(
                    title: 'Business Overview',
                    children: [
                      _MetricRow('Revenue', revenue),
                      _MetricRow('Total Cost', cost),
                      _MetricRow('Gross Profit', grossProfit),
                      _MetricRow('Commission Paid', commission),
                      _MetricRow('Net Profit', net),
                      _MetricRow('GST Collected', gst),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AnalyticsPanel(
                    title: 'Commission vs Net Profit',
                    children: [
                      _BarRow(
                        label: 'Commission',
                        value: commission,
                        max: grossProfit == 0 ? 1 : grossProfit,
                        color: AppColors.amber,
                      ),
                      _BarRow(
                        label: 'Net retained',
                        value: net,
                        max: grossProfit == 0 ? 1 : grossProfit,
                        color: AppColors.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AnalyticsPanel(
                    title: 'Top Selling by Unit Volume',
                    children: topSelling.isEmpty
                        ? [
                            const Text(
                              'No billed products yet',
                              style: TextStyle(color: AppColors.textMuted),
                            ),
                          ]
                        : topSelling
                              .map(
                                (row) => _BarRow(
                                  label: row.label,
                                  value: row.quantity.toDouble(),
                                  max: topSelling.first.quantity.toDouble(),
                                  valueLabel: '${row.quantity} ${row.unit}'
                                      .trim(),
                                  color: AppColors.navy,
                                ),
                              )
                              .toList(),
                  ),
                ],
              ),
            ),
    );
  }

  List<_TopSellingRow> _topSelling(List<BillItem> items) {
    final byProduct = <String, _TopSellingRow>{};
    for (final item in items) {
      final key = '${item.productName.toLowerCase()}|${item.unitLabel}';
      final existing = byProduct[key];
      byProduct[key] = _TopSellingRow(
        label: item.productName,
        unit: item.unitLabel,
        quantity: (existing?.quantity ?? 0) + item.quantity,
      );
    }
    final rows = byProduct.values.toList()
      ..sort((a, b) => b.quantity.compareTo(a.quantity));
    return rows.take(8).toList();
  }
}

class _TopSellingRow {
  final String label;
  final String unit;
  final int quantity;

  const _TopSellingRow({
    required this.label,
    required this.unit,
    required this.quantity,
  });
}

class _AnalyticsPanel extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _AnalyticsPanel({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final double value;

  const _MetricRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted)),
          const Spacer(),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final String? valueLabel;
  final Color color;

  const _BarRow({
    required this.label,
    required this.value,
    required this.max,
    this.valueLabel,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final fraction = max <= 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                valueLabel ?? '₹${value.toStringAsFixed(2)}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: AppColors.creamDark,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
