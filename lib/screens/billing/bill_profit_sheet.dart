part of '../bills_screen.dart';

class _BillProfitSheet extends StatefulWidget {
  final Bill bill;
  const _BillProfitSheet({required this.bill});

  @override
  State<_BillProfitSheet> createState() => _BillProfitSheetState();
}

class _BillProfitSheetState extends State<_BillProfitSheet> {
  late final TextEditingController _commissionCtrl;
  late double _commissionPercent;

  @override
  void initState() {
    super.initState();
    _commissionPercent = widget.bill.profitCommissionPercent;
    _commissionCtrl = TextEditingController(
      text: _commissionPercent == 0
          ? ''
          : _commissionPercent.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _commissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCommission() async {
    final billId = widget.bill.id;
    if (billId == null) return;
    await DatabaseHelper.instance.updateBillProfitCommissionPercent(
      billId,
      _commissionPercent,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Commission saved for this bill')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final revenue = bill.items.fold(0.0, (sum, item) => sum + item.subtotal);
    final cost = bill.items.fold(0.0, (sum, item) => sum + item.totalCost);
    final profit = bill.items.fold(0.0, (sum, item) => sum + item.totalProfit);
    final commission = profit > 0 ? profit * _commissionPercent / 100 : 0.0;
    final gst = bill.items.fold(0.0, (sum, item) => sum + item.totalGst);
    final net = profit - commission;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: AppRadius.pillRadius,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('${_billDisplayId(bill)} Profit', style: AppText.title),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                color: AppColors.bg,
                child: Column(
                  children: [
                    _ProfitRow('Total Revenue', revenue),
                    _ProfitRow('Purchase Cost', cost),
                    _ProfitRow('Overhead', 0.0),
                    if (gst > 0) _ProfitRow('GST', gst),
                    const Divider(height: AppSpacing.lg),
                    _ProfitRow(
                      'Gross Profit',
                      profit,
                      isBold: true,
                      color: AppColors.success,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Text(
                          'Partner Commission %',
                          style: AppText.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 80,
                          height: 36,
                          child: TextField(
                            controller: _commissionCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.zero,
                              suffixText: '%',
                              border: OutlineInputBorder(
                                borderRadius: AppRadius.smRadius,
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: AppRadius.smRadius,
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                            ),
                            onChanged: (value) => setState(() {
                              _commissionPercent = (double.tryParse(value) ?? 0)
                                  .clamp(0, 100)
                                  .toDouble();
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (commission > 0) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ProfitRow(
                        'Commission Payable',
                        -commission,
                        color: AppColors.error,
                      ),
                    ],
                    const Divider(height: AppSpacing.xl),
                    _ProfitRow('Net Profit', net, isBold: true, fontSize: 18),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: _saveCommission,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Commission'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _ProfitRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  final Color? color;
  final double fontSize;

  const _ProfitRow(
    this.label,
    this.value, {
    this.isBold = false,
    this.color,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color ?? AppColors.inkMuted,
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          Text(
            '${value < 0 ? '−' : ''}₹${value.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: fontSize,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
