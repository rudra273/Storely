part of '../products_screen.dart';

class _ProductSheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _ProductSheetHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrongOf(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.softBgOf(context),
                    foregroundColor: AppColors.inkOf(context),
                    minimumSize: const Size(38, 38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseContextBar extends StatelessWidget {
  final DateTime date;
  final String? supplier;

  const _PurchaseContextBar({required this.date, required this.supplier});

  @override
  Widget build(BuildContext context) {
    final supplierLabel = (supplier == null || supplier!.isEmpty)
        ? 'No supplier'
        : supplier!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: AppRadius.mdRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 16,
            color: AppColors.brandOf(context),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_formatFullDate(date)}  ·  $supplierLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.brandOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _EditorSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.brandOf(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: AppColors.brandOf(context)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              if (trailing != null)
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing!,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final bool active;

  const _ModePill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.amber.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? AppColors.success : AppColors.amber,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DirectPriceControl extends StatelessWidget {
  final bool directPrice;
  final ValueChanged<bool> onChanged;

  const _DirectPriceControl({
    required this.directPrice,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PriceModeSegment(
              icon: Icons.auto_graph_rounded,
              title: 'Formula',
              subtitle: 'GST + margin',
              selected: !directPrice,
              onTap: () {
                if (directPrice) onChanged(false);
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PriceModeSegment(
              icon: Icons.edit_note_rounded,
              title: 'Direct',
              subtitle: 'Manual price',
              selected: directPrice,
              onTap: () {
                if (!directPrice) onChanged(true);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceModeSegment extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PriceModeSegment({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: AppColors.navy.withValues(alpha: 0.18))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? AppColors.navy : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.navy : AppColors.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSheetActionBar extends StatelessWidget {
  final double sellingPrice;
  final String? unit;
  final bool isEditing;
  final bool isSaving;
  final Future<void> Function() onPressed;

  const _ProductSheetActionBar({
    required this.sellingPrice,
    required this.unit,
    required this.isEditing,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final unitText = unit == null || unit!.trim().isEmpty ? '' : ' / $unit';
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + bottomPadding),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        border: Border(top: BorderSide(color: AppColors.borderOf(context))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selling Price',
                    style: TextStyle(
                      color: AppColors.inkMutedOf(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${sellingPrice.toStringAsFixed(2)}$unitText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.brandOf(context),
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: isSaving ? null : onPressed,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isEditing ? Icons.check_rounded : Icons.add_rounded),
            label: Text(
              isSaving
                  ? 'Saving'
                  : isEditing
                  ? 'Update'
                  : 'Add',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingCalculationTable extends StatelessWidget {
  final TextEditingController gstCtrl;
  final TextEditingController overheadCtrl;
  final TextEditingController marginCtrl;
  final bool directPrice;
  final bool expanded;
  final PriceBreakdown breakdown;
  final bool gstRegistered;
  final String gstSourceHint;
  final String overheadSourceHint;
  final String marginSourceHint;
  final VoidCallback onGstChanged;
  final VoidCallback onOverheadChanged;
  final VoidCallback onMarginChanged;
  final VoidCallback onResetGst;
  final VoidCallback onResetOverhead;
  final VoidCallback? onResetMargin;
  final VoidCallback onToggleExpanded;

  const _PricingCalculationTable({
    required this.gstCtrl,
    required this.overheadCtrl,
    required this.marginCtrl,
    required this.directPrice,
    required this.expanded,
    required this.breakdown,
    required this.gstRegistered,
    required this.gstSourceHint,
    required this.overheadSourceHint,
    required this.marginSourceHint,
    required this.onGstChanged,
    required this.onOverheadChanged,
    required this.onMarginChanged,
    required this.onResetGst,
    required this.onResetOverhead,
    required this.onResetMargin,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Price Breakdown',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        gstRegistered
                            ? 'GST shown on selling price'
                            : 'GST shown on purchase cost',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _ModePill(
                  label: breakdown.wasDirectPrice ? 'direct' : 'formula',
                  active: !breakdown.wasDirectPrice,
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onToggleExpanded,
                  tooltip: expanded
                      ? 'Hide price breakdown'
                      : 'Show price breakdown',
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(34, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            if (!gstRegistered)
              _PricingInputRow(
                label: 'GST on purchase',
                controller: gstCtrl,
                suffixText: '%',
                result: breakdown.landedCost,
                delta: breakdown.gstAmount,
                sourceHint: gstSourceHint,
                onResetSource: onResetGst,
                onChanged: onGstChanged,
              ),
            _PricingInputRow(
              label: 'Overhead',
              controller: overheadCtrl,
              prefixText: '₹',
              result: breakdown.totalCost,
              delta: breakdown.overheadCost,
              sourceHint: overheadSourceHint,
              onResetSource: onResetOverhead,
              onChanged: onOverheadChanged,
            ),
            _PricingInputRow(
              label: 'Margin',
              controller: marginCtrl,
              suffixText: '%',
              result: breakdown.preGstSellingPrice,
              delta: breakdown.profitAmount,
              sourceHint: marginSourceHint,
              onResetSource: onResetMargin,
              onChanged: onMarginChanged,
              readOnly: directPrice,
            ),
            if (gstRegistered)
              _PricingInputRow(
                label: 'GST on sell',
                controller: gstCtrl,
                suffixText: '%',
                result: breakdown.sellingPrice,
                delta: breakdown.gstAmount,
                sourceHint: gstSourceHint,
                onResetSource: onResetGst,
                onChanged: onGstChanged,
              ),
          ],
        ],
      ),
    );
  }
}

class _PricingInputRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? prefixText;
  final String? suffixText;
  final double result;
  final double? delta;
  final VoidCallback onChanged;
  final bool readOnly;
  final String? sourceHint;
  final VoidCallback? onResetSource;

  const _PricingInputRow({
    required this.label,
    required this.controller,
    this.prefixText,
    this.suffixText,
    required this.result,
    this.delta,
    required this.onChanged,
    this.readOnly = false,
    this.sourceHint,
    this.onResetSource,
  });

  @override
  Widget build(BuildContext context) {
    final deltaText = delta == null ? '' : '+${delta!.toStringAsFixed(2)}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 340;
        final inputWidth = tight ? 78.0 : 88.0;
        final resultWidth = tight ? 78.0 : 94.0;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    if (sourceHint != null) ...[
                      const SizedBox(height: 2),
                      _SourceResetChip(
                        label: sourceHint!,
                        onReset: onResetSource,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: inputWidth,
                child: TextFormField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  textAlign: TextAlign.end,
                  readOnly: readOnly,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: readOnly
                        ? AppColors.borderStrongOf(
                            context,
                          ).withValues(alpha: 0.7)
                        : AppColors.raisedSurfaceOf(context),
                    prefixText: prefixText,
                    suffixText: suffixText,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) => onChanged(),
                  validator: (value) {
                    final number = double.tryParse(value ?? '');
                    if (value != null && value.isNotEmpty && number == null) {
                      return 'Invalid';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: resultWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (delta != null)
                      Text(
                        deltaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textDark,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    Text(
                      '₹${result.toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SourceResetChip extends StatelessWidget {
  final String label;
  final VoidCallback? onReset;

  const _SourceResetChip({required this.label, this.onReset});

  @override
  Widget build(BuildContext context) {
    final canReset = onReset != null && label == 'product custom';
    return PopupMenuButton<String>(
      enabled: onReset != null,
      tooltip: 'Pricing source',
      padding: EdgeInsets.zero,
      onSelected: (_) => onReset?.call(),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'default',
          enabled: canReset,
          child: Row(
            children: [
              const Icon(Icons.restart_alt_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canReset
                      ? 'Use category/global default'
                      : 'Already using default',
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: label == 'product custom'
              ? AppColors.amber.withValues(alpha: 0.12)
              : AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: label == 'product custom'
                      ? AppColors.amber
                      : AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (onReset != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: label == 'product custom'
                    ? AppColors.amber
                    : AppColors.textMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OptionDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final String? noValueLabel;
  final String? addLabel;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAdd;
  static const _addValue = '__storely_add_option__';

  const _OptionDropdown({
    required this.label,
    required this.value,
    required this.options,
    this.noValueLabel,
    this.addLabel,
    required this.onChanged,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      if (value != null && value!.isNotEmpty && !options.contains(value))
        value!,
      ...options,
    ];

    return DropdownButtonFormField<String>(
      initialValue: value != null && value!.isNotEmpty ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(noValueLabel ?? 'No $label'),
        ),
        ...items.map(
          (option) => DropdownMenuItem(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
        ),
        DropdownMenuItem<String>(
          value: _addValue,
          child: Row(
            children: [
              const Icon(Icons.add_rounded, size: 18),
              const SizedBox(width: 8),
              Text(addLabel ?? 'Add $label'),
            ],
          ),
        ),
      ],
      onChanged: (selected) {
        if (selected == _addValue) {
          onAdd();
          return;
        }
        onChanged(selected);
      },
    );
  }
}

class _SourcePill extends StatelessWidget {
  final String label;
  final bool imported;

  const _SourcePill({required this.label, required this.imported});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              imported
                  ? Icons.upload_file_rounded
                  : Icons.phone_android_rounded,
              size: 12,
              color: AppColors.navy,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
