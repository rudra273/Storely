import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_radius.dart';

enum PillVariant { low, out, paid, unpaid, success, warning, info }

class StatusPill extends StatelessWidget {
  final String label;
  final PillVariant variant;

  const StatusPill({super.key, required this.label, required this.variant});

  factory StatusPill.low() =>
      const StatusPill(label: 'Low', variant: PillVariant.low);
  factory StatusPill.out() =>
      const StatusPill(label: 'Out', variant: PillVariant.out);
  factory StatusPill.paid() =>
      const StatusPill(label: 'Paid', variant: PillVariant.paid);
  factory StatusPill.unpaid() =>
      const StatusPill(label: 'Unpaid', variant: PillVariant.unpaid);

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppRadius.smRadius,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }

  (Color bg, Color fg) get _colors => switch (variant) {
    PillVariant.out => (AppColors.error.withValues(alpha: 0.1), AppColors.error),
    PillVariant.low => (AppColors.amber.withValues(alpha: 0.12), AppColors.amber),
    PillVariant.paid => (AppColors.success.withValues(alpha: 0.1), AppColors.success),
    PillVariant.unpaid => (AppColors.error.withValues(alpha: 0.1), AppColors.error),
    PillVariant.success => (AppColors.success.withValues(alpha: 0.1), AppColors.success),
    PillVariant.warning => (AppColors.amber.withValues(alpha: 0.12), AppColors.amber),
    PillVariant.info => (AppColors.navy.withValues(alpha: 0.08), AppColors.navy),
  };
}
