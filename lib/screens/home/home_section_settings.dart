import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../services/home_section_prefs.dart';
import '../../models/low_stock_threshold.dart';

const _countChoices = [3, 5, 10, HomeSectionPrefs.showAll];

String _countLabel(int value) =>
    value >= HomeSectionPrefs.showAll ? 'All' : '$value';

/// Shared bottom-sheet shell: grabber + title + content.
class _SettingsSheet extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SettingsSheet({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.brandOf(context)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    title,
                    style: AppText.title.copyWith(
                      color: AppColors.inkOf(context),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    Icons.close_rounded,
                    size: 20,
                    color: AppColors.inkMutedOf(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _SettingLabel extends StatelessWidget {
  final String text;
  const _SettingLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      text,
      style: AppText.label.copyWith(color: AppColors.inkMutedOf(context)),
    ),
  );
}

/// A row of selectable choice chips.
class _ChoiceChips<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;

  const _ChoiceChips({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: values.map((v) {
        final isSel = v == selected;
        return ChoiceChip(
          label: Text(labelOf(v)),
          selected: isSel,
          onSelected: (_) => onSelected(v),
          showCheckmark: false,
          labelStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: isSel
                ? AppColors.brandOf(context)
                : AppColors.inkMutedOf(context),
          ),
          selectedColor: AppColors.brandOf(
            context,
          ).withValues(alpha: AppColors.isDark(context) ? 0.22 : 0.12),
          backgroundColor: AppColors.softBgOf(context),
          side: BorderSide(
            color: isSel
                ? AppColors.brandOf(context)
                : AppColors.borderOf(context),
          ),
        );
      }).toList(),
    );
  }
}

/// ── Unpaid Bills settings ───────────────────────────────────────────────────
Future<void> showUnpaidBillsSettings(BuildContext context) {
  final prefs = HomeSectionPrefs.instance;
  return showDialog(
    context: context,
    builder: (ctx) => AnimatedBuilder(
      animation: prefs,
      builder: (ctx, _) => _SettingsSheet(
        title: 'Unpaid Bills',
        icon: Icons.receipt_long_outlined,
        children: [
          const _SettingLabel('SHOW ON HOME'),
          _ChoiceChips<int>(
            values: _countChoices,
            selected: prefs.unpaidCount,
            labelOf: _countLabel,
            onSelected: prefs.setUnpaidCount,
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SettingLabel('SORT BY'),
          _ChoiceChips<UnpaidBillsSort>(
            values: UnpaidBillsSort.values,
            selected: prefs.unpaidSort,
            labelOf: (s) => s.label,
            onSelected: prefs.setUnpaidSort,
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.unpaidHidden,
            onChanged: prefs.setUnpaidHidden,
            activeThumbColor: AppColors.amber,
            title: Text(
              'Hide this section',
              style: AppText.body.copyWith(color: AppColors.inkOf(ctx)),
            ),
          ),
        ],
      ),
    ),
  );
}

/// ── Needs Attention settings ────────────────────────────────────────────────
/// [threshold] is the current low-stock threshold; [onThreshold] persists a new
/// value (DB-backed) and may throw if the user lacks permission.
Future<void> showNeedsAttentionSettings(
  BuildContext context, {
  required double threshold,
  required Future<void> Function(double) onThreshold,
}) {
  return showDialog(
    context: context,
    builder: (ctx) =>
        _NeedsAttentionSheet(threshold: threshold, onThreshold: onThreshold),
  );
}

class _NeedsAttentionSheet extends StatefulWidget {
  final double threshold;
  final Future<void> Function(double) onThreshold;

  const _NeedsAttentionSheet({
    required this.threshold,
    required this.onThreshold,
  });

  @override
  State<_NeedsAttentionSheet> createState() => _NeedsAttentionSheetState();
}

class _NeedsAttentionSheetState extends State<_NeedsAttentionSheet> {
  late final TextEditingController _thresholdCtrl;
  late double _savedThreshold;
  bool _saving = false;
  String? _thresholdError;

  @override
  void initState() {
    super.initState();
    _savedThreshold = widget.threshold;
    _thresholdCtrl = TextEditingController(
      text: lowStockThresholdText(widget.threshold),
    );
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveThreshold() async {
    if (_saving) return;
    final threshold = LowStockThreshold.parse(_thresholdCtrl.text);
    if (threshold == null) {
      setState(() => _thresholdError = 'Use 0–999999999, up to 4 decimals');
      return;
    }
    if (threshold.value == _savedThreshold) {
      setState(() => _thresholdError = null);
      return;
    }
    setState(() {
      _saving = true;
      _thresholdError = null;
    });
    try {
      await widget.onThreshold(threshold.value);
      if (!mounted) return;
      setState(() {
        _savedThreshold = threshold.value;
        _thresholdCtrl.text = threshold.text;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _thresholdError = error is FormatException
              ? error.message
              : friendlyError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = HomeSectionPrefs.instance;
    return AnimatedBuilder(
      animation: prefs,
      builder: (context, _) => _SettingsSheet(
        title: 'Needs Attention',
        icon: Icons.warning_amber_rounded,
        children: [
          const _SettingLabel('LOW-STOCK THRESHOLD'),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Flag stock at or below',
                  style: AppText.body.copyWith(color: AppColors.inkOf(context)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 88,
                child: TextField(
                  key: const ValueKey('low-stock-threshold-input'),
                  enabled: !_saving,
                  controller: _thresholdCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  style: AppText.subtitle.copyWith(
                    color: AppColors.inkOf(context),
                  ),
                  decoration: InputDecoration(isDense: true, suffixText: 'qty'),
                  onTapOutside: (_) => _saveThreshold(),
                  onSubmitted: (_) => _saveThreshold(),
                ),
              ),
            ],
          ),
          if (_thresholdError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _thresholdError!,
              style: AppText.caption.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          const _SettingLabel('SHOW ON HOME'),
          _ChoiceChips<int>(
            values: _countChoices,
            selected: prefs.attentionCount,
            labelOf: _countLabel,
            onSelected: prefs.setAttentionCount,
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: prefs.attentionHidden,
            onChanged: prefs.setAttentionHidden,
            activeThumbColor: AppColors.amber,
            title: Text(
              'Hide this section',
              style: AppText.body.copyWith(color: AppColors.inkOf(context)),
            ),
          ),
        ],
      ),
    );
  }
}
