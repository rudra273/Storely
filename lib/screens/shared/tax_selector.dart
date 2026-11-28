import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/product.dart';
import '../../theme/app_theme.dart';

/// An item's GST taxability, GST rate and cess rate, as picked in the UI.
class TaxSelection {
  final String taxType;
  final double gstPercent;
  final double cessPercent;

  const TaxSelection({
    this.taxType = TaxType.taxable,
    this.gstPercent = 0,
    this.cessPercent = 0,
  });

  bool get isTaxable => taxType == TaxType.taxable;

  /// None and Tax Exempt never carry GST or cess.
  TaxSelection normalised() =>
      isTaxable ? this : TaxSelection(taxType: TaxType.clean(taxType));

  TaxSelection copyWith({
    String? taxType,
    double? gstPercent,
    double? cessPercent,
  }) => TaxSelection(
    taxType: taxType ?? this.taxType,
    gstPercent: gstPercent ?? this.gstPercent,
    cessPercent: cessPercent ?? this.cessPercent,
  );

  String get label => taxLabel(taxType, gstPercent, cessPercent);

  @override
  bool operator ==(Object other) =>
      other is TaxSelection &&
      other.taxType == taxType &&
      other.gstPercent == gstPercent &&
      other.cessPercent == cessPercent;

  @override
  int get hashCode => Object.hash(taxType, gstPercent, cessPercent);
}

String _rateText(double value) => value == value.roundToDouble()
    ? value.toStringAsFixed(0)
    : value.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '');

/// GST selector: None, Tax Exempt, GST 0/5/12/18/28% (plus the current rate
/// when it is not a standard slab) and an optional "+ Cess" picker.
class TaxSelector extends StatelessWidget {
  final TaxSelection value;
  final ValueChanged<TaxSelection> onChanged;

  /// Shown under the chips, e.g. "From category Beverages".
  final String? helperText;

  const TaxSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.helperText,
  });

  @override
  Widget build(BuildContext context) {
    final rates = <double>[
      ...gstRatePresets,
      if (value.isTaxable && !gstRatePresets.contains(value.gstPercent))
        value.gstPercent,
    ];
    final cess = value.cessPercent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'GST',
          style: AppText.caption.copyWith(color: AppColors.inkMutedOf(context)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          children: [
            ChoiceChip(
              key: const ValueKey('tax-none'),
              label: const Text('None'),
              selected: value.taxType == TaxType.none,
              onSelected: (_) =>
                  onChanged(const TaxSelection(taxType: TaxType.none)),
            ),
            ChoiceChip(
              key: const ValueKey('tax-exempt'),
              label: const Text('Tax Exempt'),
              selected: value.taxType == TaxType.exempt,
              onSelected: (_) =>
                  onChanged(const TaxSelection(taxType: TaxType.exempt)),
            ),
            for (final rate in rates)
              ChoiceChip(
                key: ValueKey('tax-gst-${_rateText(rate)}'),
                label: Text('GST ${_rateText(rate)}%'),
                selected: value.isTaxable && value.gstPercent == rate,
                onSelected: (_) => onChanged(
                  TaxSelection(
                    gstPercent: rate,
                    cessPercent: value.isTaxable ? cess : 0,
                  ),
                ),
              ),
            ActionChip(
              key: const ValueKey('tax-gst-other'),
              avatar: const Icon(Icons.more_horiz_rounded, size: 16),
              label: const Text('Other rate'),
              onPressed: () async {
                final rate = await _pickOtherGstRate(context);
                if (rate == null) return;
                onChanged(
                  TaxSelection(
                    gstPercent: rate,
                    cessPercent: value.isTaxable ? cess : 0,
                  ),
                );
              },
            ),
          ],
        ),
        if (value.isTaxable) ...[
          const SizedBox(height: AppSpacing.xs),
          InputChip(
            key: const ValueKey('tax-cess'),
            avatar: Icon(
              cess > 0 ? Icons.local_offer_outlined : Icons.add_rounded,
              size: 16,
            ),
            label: Text(cess > 0 ? 'Cess ${_rateText(cess)}%' : 'Cess'),
            selected: cess > 0,
            onPressed: () async {
              final picked = await showCessPicker(context, current: cess);
              if (picked == null) return;
              onChanged(value.copyWith(cessPercent: picked));
            },
            onDeleted: cess > 0
                ? () => onChanged(value.copyWith(cessPercent: 0))
                : null,
          ),
        ],
        if (helperText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            helperText!,
            style: AppText.caption.copyWith(
              color: AppColors.inkMutedOf(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// Less common GST slabs the API accepts (see [allowedGstRates]).
Future<double?> _pickOtherGstRate(BuildContext context) {
  return showDialog<double>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Other GST rate'),
      children: [
        for (final rate in allowedGstRates)
          if (!gstRatePresets.contains(rate))
            SimpleDialogOption(
              key: ValueKey('tax-gst-other-${_rateText(rate)}'),
              onPressed: () => Navigator.pop(dialogContext, rate),
              child: Text('GST ${_rateText(rate)}%'),
            ),
      ],
    ),
  );
}

/// Picks a cess rate: a common preset, a custom %, or none (returns 0).
/// Returns null when dismissed.
Future<double?> showCessPicker(BuildContext context, {double current = 0}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CessPickerSheet(current: current),
  );
}

class _CessPickerSheet extends StatefulWidget {
  final double current;

  const _CessPickerSheet({required this.current});

  @override
  State<_CessPickerSheet> createState() => _CessPickerSheetState();
}

class _CessPickerSheetState extends State<_CessPickerSheet> {
  late final TextEditingController _custom;
  String? _error;

  @override
  void initState() {
    super.initState();
    final isPreset = cessRatePresets.contains(widget.current);
    _custom = TextEditingController(
      text: widget.current > 0 && !isPreset ? _rateText(widget.current) : '',
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _applyCustom() {
    final value = double.tryParse(_custom.text.trim());
    if (value == null || value < 0 || value > 400) {
      setState(() => _error = 'Enter a cess % between 0 and 400');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Cess', style: AppText.title),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Compensation cess is charged on the taxable value, on top of GST.',
            style: AppText.caption.copyWith(
              color: AppColors.inkMutedOf(context),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              ChoiceChip(
                key: const ValueKey('cess-none'),
                label: const Text('No cess'),
                selected: widget.current == 0,
                onSelected: (_) => Navigator.pop(context, 0.0),
              ),
              for (final rate in cessRatePresets)
                ChoiceChip(
                  key: ValueKey('cess-${_rateText(rate)}'),
                  label: Text('${_rateText(rate)}%'),
                  selected: widget.current == rate,
                  onSelected: (_) => Navigator.pop(context, rate),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('cess-custom'),
                  controller: _custom,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Custom cess',
                    suffixText: '%',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _applyCustom(),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: FilledButton(
                  key: const ValueKey('cess-custom-apply'),
                  onPressed: _applyCustom,
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet that picks a tax setting for several items at once
/// ("Set GST" bulk action). Returns null when dismissed.
Future<TaxSelection?> showTaxSelectionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  TaxSelection initial = const TaxSelection(gstPercent: 18),
  String confirmLabel = 'Apply',
}) {
  return showModalBottomSheet<TaxSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _TaxSelectionSheet(
      title: title,
      subtitle: subtitle,
      initial: initial,
      confirmLabel: confirmLabel,
    ),
  );
}

class _TaxSelectionSheet extends StatefulWidget {
  final String title;
  final String? subtitle;
  final TaxSelection initial;
  final String confirmLabel;

  const _TaxSelectionSheet({
    required this.title,
    required this.subtitle,
    required this.initial,
    required this.confirmLabel,
  });

  @override
  State<_TaxSelectionSheet> createState() => _TaxSelectionSheetState();
}

class _TaxSelectionSheetState extends State<_TaxSelectionSheet> {
  late TaxSelection _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: AppText.title),
          if (widget.subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.subtitle!,
              style: AppText.caption.copyWith(
                color: AppColors.inkMutedOf(context),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          TaxSelector(
            value: _value,
            onChanged: (next) => setState(() => _value = next.normalised()),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            key: const ValueKey('tax-sheet-apply'),
            onPressed: () => Navigator.pop(context, _value.normalised()),
            child: Text('${widget.confirmLabel} · ${_value.label}'),
          ),
        ],
      ),
    );
  }
}
