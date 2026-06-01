part of '../products_screen.dart';

class _AddOptionDialog extends StatefulWidget {
  final String label;

  const _AddOptionDialog({required this.label});

  @override
  State<_AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<_AddOptionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _normaliseOptionName(_controller.text);
    if (text == null) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add ${widget.label}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: '${widget.label} name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ProductFilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ProductFilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasSelection = count > 0;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: hasSelection ? AppColors.navy : AppColors.textDark,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: hasSelection ? AppColors.navy : AppColors.creamDark,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.tune_rounded, size: 17),
      label: Text(
        hasSelection ? 'Filter ($count)' : 'Filter',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;
  final bool isClearAction;

  const _ActiveFilterChip({
    required this.label,
    required this.onDeleted,
    this.isClearAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isClearAction ? AppColors.textMuted : AppColors.navy,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      deleteIcon: Icon(
        isClearAction ? Icons.filter_alt_off_rounded : Icons.close_rounded,
        size: 16,
      ),
      onDeleted: onDeleted,
      backgroundColor: isClearAction
          ? Colors.white
          : AppColors.navy.withValues(alpha: 0.08),
      side: BorderSide(
        color: isClearAction ? AppColors.creamDark : AppColors.navy,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _SortDropdownButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SortDropdownButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.creamDark),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.sort_rounded, size: 17),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _FilterSheetSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> options;
  final Set<String> selected;
  final String emptyText;
  final void Function(String value, bool selected) onChanged;

  const _FilterSheetSection({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.emptyText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.creamDark),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.navy),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (options.isEmpty)
            Text(emptyText, style: const TextStyle(color: AppColors.textMuted))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 164),
              child: Scrollbar(
                thumbVisibility: options.length > 8,
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.only(right: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options
                        .map(
                          (option) => FilterChip(
                            label: Text(
                              option,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selected: selected.contains(option),
                            onSelected: (value) => onChanged(option, value),
                            selectedColor: AppColors.navy.withValues(
                              alpha: 0.12,
                            ),
                            checkmarkColor: AppColors.navy,
                            side: BorderSide(
                              color: selected.contains(option)
                                  ? AppColors.navy
                                  : AppColors.creamDark,
                            ),
                            backgroundColor: Colors.white,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PurchaseDateFilterTile extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _PurchaseDateFilterTile({
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.creamDark),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, size: 18, color: AppColors.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Purchase Date',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  date == null ? 'Any date' : _formatFullDate(date!),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              tooltip: 'Clear date',
              icon: const Icon(Icons.close_rounded),
            ),
          OutlinedButton(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.creamDark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(date == null ? 'Choose' : 'Change'),
          ),
        ],
      ),
    );
  }
}

/// Full-page staging screen for a purchase batch: add/import many products
/// against one supplier+date, then commit them all on Confirm.
