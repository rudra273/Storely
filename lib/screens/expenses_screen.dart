import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/database_helper.dart';
import '../models/expense.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';

/// Shop expenses by month, opened from Home → Workspace. Staff can view;
/// only the owner or an admin can add, edit or delete.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  List<Expense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _day(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _load() async {
    final last = DateTime(_month.year, _month.month + 1, 0);
    try {
      final expenses = await DatabaseHelper.instance.getExpenses(
        from: _day(_month),
        to: _day(last),
      );
      if (!mounted) return;
      setState(() {
        _expenses = expenses;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Could not load expenses: $error');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _shiftMonth(int delta) {
    setState(() {
      _month = DateTime(_month.year, _month.month + delta);
      _loading = true;
    });
    _load();
  }

  Future<void> _edit([Expense? expense]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExpenseSheet(expense: expense),
    );
    if (!mounted || saved != true) return;
    await _load();
  }

  Future<void> _delete(Expense expense) async {
    try {
      await DatabaseHelper.instance.deleteExpense(expense.id!);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _snack('Expense deleted');
    } catch (error) {
      if (!mounted) return;
      _snack('Could not delete: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCurrentMonth =
        _month.year == DateTime.now().year &&
        _month.month == DateTime.now().month;
    final total = _expenses.fold<double>(0, (sum, e) => sum + e.amount);
    final byCategory = <String, double>{};
    for (final e in _expenses) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }
    final categories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, cloudState, _) {
        final canManage = cloudState.isAdmin;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: navyAppBar(title: 'Expenses'),
          floatingActionButton: canManage
              ? FloatingActionButton.extended(
                  key: const ValueKey('add-expense'),
                  onPressed: () => _edit(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add expense'),
                )
              : null,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  0,
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous month',
                      onPressed: () => _shiftMonth(-1),
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
                      onPressed: isCurrentMonth ? null : () => _shiftMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Spent this month', style: AppText.caption),
                      const SizedBox(height: AppSpacing.xs),
                      Text(rupees(total), style: AppText.display),
                      if (categories.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          children: [
                            for (final c in categories.take(4))
                              StatusPill(
                                label: '${c.key} ${rupees(c.value)}',
                                variant: PillVariant.info,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: _loading
                    ? const AppSkeletonList()
                    : _expenses.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xxl),
                          child: Text(
                            canManage
                                ? 'No expenses this month. Add rent, salary, '
                                      'tea or transport to see your real profit.'
                                : 'No expenses this month.',
                            textAlign: TextAlign.center,
                            style: AppText.caption,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.sm,
                          AppSpacing.lg,
                          AppSpacing.xxxl * 3,
                        ),
                        itemCount: _expenses.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) => _ExpenseRow(
                          expense: _expenses[i],
                          onTap: canManage ? () => _edit(_expenses[i]) : null,
                          onDelete: canManage
                              ? () => _delete(_expenses[i])
                              : null,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final Expense expense;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const _ExpenseRow({required this.expense, this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.category, style: AppText.subtitle),
                const SizedBox(height: 2),
                Text(
                  [
                    DateFormat('dd MMM').format(expense.date),
                    _methodLabel(expense.paymentMethod),
                    if (expense.notes != null) expense.notes!,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          Text(rupees(expense.amount), style: AppText.subtitle),
          if (onDelete != null)
            IconButton(
              tooltip: 'Delete',
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline,
                color: AppColors.inkFaintOf(context),
              ),
            ),
        ],
      ),
    );
  }
}

String _methodLabel(String method) => switch (method) {
  'upi' => 'UPI',
  'card' => 'Card',
  'bank' => 'Bank',
  _ => 'Cash',
};

class _ExpenseSheet extends StatefulWidget {
  final Expense? expense;

  const _ExpenseSheet({this.expense});

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late final _amount = TextEditingController(
    text: widget.expense == null
        ? ''
        : widget.expense!.amount.toStringAsFixed(2),
  );
  late final _notes = TextEditingController(text: widget.expense?.notes ?? '');
  late String _category = widget.expense?.category ?? Expense.categories.first;
  late String _method = widget.expense?.paymentMethod ?? 'cash';
  late DateTime _date = widget.expense?.date ?? DateTime.now();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await DatabaseHelper.instance.saveExpense(
        Expense(
          id: widget.expense?.id,
          date: _date,
          amount: amount,
          category: _category,
          paymentMethod: _method,
          notes: _notes.text,
        ),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = {...Expense.categories, _category}.toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.expense == null ? 'Add expense' : 'Edit expense',
                style: AppText.title,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('expense-amount'),
                controller: _amount,
                autofocus: widget.expense == null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: 'Amount *',
                  prefixText: '₹ ',
                  errorText: _error,
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Category', style: AppText.label),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      label: Text(c),
                      selected: _category == c,
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'cash', label: Text('Cash')),
                  ButtonSegment(value: 'upi', label: Text('UPI')),
                  ButtonSegment(value: 'bank', label: Text('Bank')),
                ],
                selected: {_method == 'card' ? 'bank' : _method},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _method = v.first),
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: _pickDate,
                borderRadius: AppRadius.mdRadius,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Date',
                    prefixIcon: Icon(Icons.event_outlined, size: 18),
                  ),
                  child: Text(DateFormat('dd MMM yyyy').format(_date)),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save expense'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
