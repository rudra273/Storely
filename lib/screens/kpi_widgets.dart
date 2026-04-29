import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../main.dart';

// ── Formatters ──────────────────────────────────────────────────────────────
String fmtRupee(double v) {
  if (v >= 1e7) return '₹${(v / 1e7).toStringAsFixed(2)}Cr';
  if (v >= 1e5) return '₹${(v / 1e5).toStringAsFixed(2)}L';
  if (v >= 1e3) return '₹${(v / 1e3).toStringAsFixed(1)}K';
  return '₹${v.toStringAsFixed(2)}';
}

String fmtNum(double v) {
  if (v >= 1e7) return '${(v / 1e7).toStringAsFixed(2)}Cr';
  if (v >= 1e5) return '${(v / 1e5).toStringAsFixed(2)}L';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

String fmtPct(double v) => '${v.toStringAsFixed(1)}%';

// ── Section Header ───────────────────────────────────────────────────────────
class KpiSectionHeader extends StatelessWidget {
  final String emoji;
  final String title;
  const KpiSectionHeader({super.key, required this.emoji, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 28, 0, 14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.navy, AppColors.navyLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: AppColors.navy,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Base Panel ───────────────────────────────────────────────────────────────
class KpiPanel extends StatelessWidget {
  final Widget child;
  const KpiPanel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PanelTitle extends StatelessWidget {
  final String text;
  const _PanelTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          letterSpacing: 0.2,
        ),
      );
}

// ── Empty State ──────────────────────────────────────────────────────────────
class KpiEmpty extends StatelessWidget {
  final String title;
  const KpiEmpty({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 20),
          Center(
            child: Column(
              children: [
                Icon(Icons.bar_chart_rounded,
                    size: 36, color: AppColors.textMuted.withValues(alpha: 0.3)),
                const SizedBox(height: 8),
                const Text(
                  'No data available',
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── KPI Stat Card ────────────────────────────────────────────────────────────
class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final Color? valueColor;
  final IconData? icon;

  const KpiCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.valueColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppColors.textMuted),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: valueColor ?? AppColors.navy,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Two cards side by side ───────────────────────────────────────────────────
class KpiCardRow extends StatelessWidget {
  final Widget left;
  final Widget right;
  const KpiCardRow({super.key, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

// ── Horizontal Bar List ──────────────────────────────────────────────────────
class KpiHorizBarList extends StatelessWidget {
  final String title;
  final List<({String label, double value})> items;
  final bool isRupee;
  final Color? barColor;

  const KpiHorizBarList({
    super.key,
    required this.title,
    required this.items,
    this.isRupee = true,
    this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return KpiEmpty(title: title);
    final maxVal =
        items.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);
    final color = barColor ?? AppColors.amber;
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 14),
          ...items.map((item) {
            final fraction =
                maxVal <= 0 ? 0.0 : (item.value / maxVal).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isRupee ? fmtRupee(item.value) : fmtNum(item.value),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 7,
                      backgroundColor: AppColors.creamDark,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Donut Chart ──────────────────────────────────────────────────────────────
class KpiDonut extends StatelessWidget {
  final String title;
  final List<({String label, double value, Color color})> segments;

  const KpiDonut({super.key, required this.title, required this.segments});

  @override
  Widget build(BuildContext context) {
    final nonZero = segments.where((s) => s.value > 0).toList();
    if (nonZero.isEmpty) return KpiEmpty(title: title);
    final total = nonZero.fold(0.0, (s, e) => s + e.value);
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                height: 130,
                width: 130,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 36,
                    sections: nonZero.map((s) {
                      final pct = total > 0 ? s.value / total * 100 : 0.0;
                      return PieChartSectionData(
                        value: s.value,
                        color: s.color,
                        radius: 34,
                        title: '${pct.toStringAsFixed(0)}%',
                        titleStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: nonZero.map((s) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: s.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            fmtRupee(s.value),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Bar Chart ────────────────────────────────────────────────────────────────
class KpiBarChart extends StatelessWidget {
  final String title;
  final List<({String label, double value})> data;
  final bool isRupee;
  final Color? barColor;

  const KpiBarChart({
    super.key,
    required this.title,
    required this.data,
    this.isRupee = false,
    this.barColor,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return KpiEmpty(title: title);
    final maxVal =
        data.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);
    final color = barColor ?? AppColors.navy;
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 16),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxVal * 1.25 + 1,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) =>
                        AppColors.navy.withValues(alpha: 0.9),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                      isRupee
                          ? fmtRupee(rod.toY)
                          : fmtNum(rod.toY),
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      getTitlesWidget: (val, _) {
                        final i = val.toInt();
                        if (i < 0 || i >= data.length) {
                          return const SizedBox();
                        }
                        final lbl = data[i].label;
                        final short =
                            lbl.length > 5 ? lbl.substring(0, 5) : lbl;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            short,
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.creamDark,
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: data.asMap().entries.map((e) {
                  return BarChartGroupData(
                    x: e.key,
                    barRods: [
                      BarChartRodData(
                        toY: e.value.value,
                        color: color,
                        width: (200 / data.length.clamp(1, 14)).clamp(8, 28),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Line Chart ───────────────────────────────────────────────────────────────
class KpiLineChart extends StatelessWidget {
  final String title;
  final List<({String label, double value})> data;
  final bool isRupee;

  const KpiLineChart({
    super.key,
    required this.title,
    required this.data,
    this.isRupee = true,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return KpiEmpty(title: title);
    final maxVal =
        data.map((e) => e.value).fold(0.0, (a, b) => a > b ? a : b);
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxVal * 1.25 + 1,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        AppColors.navy.withValues(alpha: 0.9),
                    getTooltipItems: (spots) => spots
                        .map((s) => LineTooltipItem(
                              isRupee ? fmtRupee(s.y) : fmtNum(s.y),
                              const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ))
                        .toList(),
                  ),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.creamDark,
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval:
                          (data.length / 5.0).ceilToDouble().clamp(1, 999),
                      getTitlesWidget: (val, _) {
                        final i = val.toInt();
                        if (i < 0 || i >= data.length) {
                          return const SizedBox();
                        }
                        final lbl = data[i].label;
                        final short =
                            lbl.length > 5 ? lbl.substring(lbl.length - 5) : lbl;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            short,
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textMuted,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: data
                        .asMap()
                        .entries
                        .map((e) => FlSpot(e.key.toDouble(), e.value.value))
                        .toList(),
                    isCurved: true,
                    color: AppColors.amber,
                    barWidth: 3,
                    dotData: FlDotData(
                      show: data.length <= 12,
                      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                        radius: 3,
                        color: AppColors.amber,
                        strokeColor: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.amber.withValues(alpha: 0.08),
                    ),
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

// ── Gauge Card ───────────────────────────────────────────────────────────────
class KpiGaugeCard extends StatelessWidget {
  final String title;
  final double value;
  final String? target;
  final bool higherIsBetter;

  const KpiGaugeCard({
    super.key,
    required this.title,
    required this.value,
    this.target,
    this.higherIsBetter = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color c;
    if (higherIsBetter) {
      c = value >= 70
          ? AppColors.success
          : value >= 40
              ? AppColors.amber
              : AppColors.error;
    } else {
      c = value <= 5
          ? AppColors.success
          : value <= 15
              ? AppColors.amber
              : AppColors.error;
    }
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmtPct(value),
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: c,
                      ),
                    ),
                    if (target != null)
                      Text(
                        'Target: $target',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 56,
                width: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: (value / 100).clamp(0.0, 1.0),
                      strokeWidth: 7,
                      backgroundColor: AppColors.creamDark,
                      valueColor: AlwaysStoppedAnimation<Color>(c),
                    ),
                    Text(
                      '${value.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: c,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: (value / 100).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: AppColors.creamDark,
              valueColor: AlwaysStoppedAnimation<Color>(c),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data Table Card ──────────────────────────────────────────────────────────
class KpiDataTableCard extends StatelessWidget {
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final int? badgeCount;
  final Color? badgeColor;

  const KpiDataTableCard({
    super.key,
    required this.title,
    required this.columns,
    required this.rows,
    this.badgeCount,
    this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return KpiEmpty(title: title);
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _PanelTitle(title)),
              if (badgeCount != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: (badgeColor ?? AppColors.error)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: badgeColor ?? AppColors.error,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 32,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 44,
              columnSpacing: 18,
              headingTextStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
              columns: columns
                  .map((c) => DataColumn(label: Text(c)))
                  .toList(),
              rows: rows.map((r) {
                return DataRow(
                  cells: r.asMap().entries.map((e) {
                    return DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          e.value,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: e.key == 0
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }).toList(),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading skeleton ─────────────────────────────────────────────────────────
class KpiLoadingCard extends StatelessWidget {
  final String title;
  const KpiLoadingCard({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return KpiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(title),
          const SizedBox(height: 20),
          const Center(
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
