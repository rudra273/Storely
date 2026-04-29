import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/shop_profile.dart';
import '../utils/bill_pdf_generator.dart';
import 'scan_screen.dart';

class BillsScreen extends StatefulWidget {
  final int refreshToken;

  const BillsScreen({super.key, this.refreshToken = 0});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  List<Bill> _bills = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void didUpdateWidget(covariant BillsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadBills();
    }
  }

  Future<void> _loadBills() async {
    final bills = await DatabaseHelper.instance.getAllBills();
    if (mounted) {
      setState(() {
        _bills = bills;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: AppColors.error, size: 32),
        title: const Text('Delete Bill'),
        content: Text('Delete ${_billDisplayId(bill)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deleteBill(bill.id!);
      _loadBills();
    }
  }

  Future<void> _updateBillStatus(Bill bill, bool isPaid) async {
    if (bill.id == null) return;
    await DatabaseHelper.instance.updateBillPaidStatus(bill.id!, isPaid);
    await _loadBills();
  }

  Future<void> _openBillCreator(BillingEntryMode mode) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanScreen(initialMode: mode)),
    );
    await _loadBills();
  }

  Future<void> _sendBillOnWhatsApp(Bill bill) async {
    final phone = _whatsAppPhone(bill.customerPhone);
    if (phone == null) return;

    final uri = Uri.https('wa.me', '/$phone', {
      'text': _buildBillMessage(
        bill,
        await DatabaseHelper.instance.getShopProfile(),
      ),
    });
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open WhatsApp')));
    }
  }

  Future<void> _shareBillPdf(Bill bill) async {
    final shop = await DatabaseHelper.instance.getShopProfile();
    final bytes = await BillPdfGenerator.generate(bill: bill, shop: shop);
    await Printing.sharePdf(
      bytes: bytes,
      filename: BillPdfGenerator.filename(bill),
    );
  }

  String? _whatsAppPhone(String? value) {
    final phone = value?.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone == null || phone.isEmpty || phone == '91') return null;
    if (phone.length == 10) return '91$phone';
    return phone;
  }

  String _buildBillMessage(Bill bill, ShopProfile? shop) {
    final buffer = StringBuffer()
      ..writeln(shop?.name ?? 'Storely')
      ..writeln(_billDisplayId(bill))
      ..writeln('Customer: ${bill.customerName}')
      ..writeln(
        'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt)}',
      );
    if (shop?.gstin != null) buffer.writeln('GSTIN: ${shop!.gstin}');
    if (shop?.address != null) buffer.writeln(shop!.address);
    buffer
      ..writeln('')
      ..writeln('Items:');
    for (final item in bill.items) {
      buffer.writeln(
        '- ${item.productName} ${item.quantityLabel} x ${item.priceLabel}: ₹${item.subtotal.toStringAsFixed(2)}',
      );
    }
    buffer
      ..writeln('')
      ..writeln('Subtotal: ₹${bill.subtotalAmount.toStringAsFixed(2)}');
    if (bill.discountAmount > 0) {
      buffer.writeln(
        'Discount (${bill.discountPercent.toStringAsFixed(2)}%): -₹${bill.discountAmount.toStringAsFixed(2)}',
      );
    }
    buffer
      ..writeln('Total: ₹${bill.totalAmount.toStringAsFixed(2)}')
      ..writeln('Status: ${bill.isPaid ? 'Paid' : 'Unpaid'}');
    if (bill.isPaid) {
      buffer.writeln('Payment: ${_paymentMethodLabel(bill.paymentMethod)}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text(
          'Bills',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _bills.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _loadBills,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _buildUnpaidSummary(),
                  ..._buildGroupedBillCards(),
                ],
              ),
            ),
      floatingActionButton: _isLoading || _bills.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openBillCreator(BillingEntryMode.manual),
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('New Bill'),
            ),
    );
  }

  Widget _buildUnpaidSummary() {
    final unpaid = _bills.where((b) => !b.isPaid).toList();
    if (unpaid.isEmpty) return const SizedBox.shrink();

    unpaid.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    Map<String, double> customerTotals = {};
    for (var b in unpaid) {
      final name = b.customerName.trim().isEmpty ? 'Walk-in' : b.customerName.trim();
      customerTotals[name] = (customerTotals[name] ?? 0) + b.totalAmount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Unpaid Bills (Dues)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.error),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 35,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Bill #', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: unpaid.map((b) => DataRow(cells: [
                DataCell(Text(DateFormat('dd MMM').format(b.createdAt))),
                DataCell(Text(b.billNumber.length > 4 ? b.billNumber.substring(b.billNumber.length - 4) : b.billNumber)),
                DataCell(Text(b.customerName)),
                DataCell(Text('₹${b.totalAmount.toStringAsFixed(0)}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600))),
              ])).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Total Due by Customer',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 35,
              dataRowMaxHeight: 40,
              columns: const [
                DataColumn(label: Text('Customer', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Total Due', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: customerTotals.entries.map((e) => DataRow(cells: [
                DataCell(Text(e.key)),
                DataCell(Text('₹${e.value.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w700))),
              ])).toList(),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 8),
      ],
    );
  }

  List<Widget> _buildGroupedBillCards() {
    final widgets = <Widget>[];
    String? currentGroup;

    for (final bill in _bills) {
      final group = _dateGroupTitle(bill.createdAt);
      if (group != currentGroup) {
        currentGroup = group;
        widgets.add(_DateHeader(title: group));
      }

      widgets.add(
        _BillCard(
          bill: bill,
          onDelete: () => _deleteBill(bill),
          onStatusChanged: (isPaid) => _updateBillStatus(bill, isPaid),
          onSendWhatsApp: () => _sendBillOnWhatsApp(bill),
          onSharePdf: () => _shareBillPdf(bill),
        ),
      );
    }

    return widgets;
  }

  String _dateGroupTitle(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final billDate = DateTime(date.year, date.month, date.day);
    final daysAgo = today.difference(billDate).inDays;
    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: AppColors.creamDark,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No bills yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Search products to create your first bill',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => _openBillCreator(BillingEntryMode.manual),
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Create Bill'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String title;
  const _DateHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _BillCard extends StatefulWidget {
  final Bill bill;
  final VoidCallback onDelete;
  final VoidCallback onSendWhatsApp;
  final VoidCallback onSharePdf;
  final ValueChanged<bool> onStatusChanged;
  const _BillCard({
    required this.bill,
    required this.onDelete,
    required this.onSendWhatsApp,
    required this.onSharePdf,
    required this.onStatusChanged,
  });
  @override
  State<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<_BillCard> {
  bool _expanded = false;

  Future<void> _showProfitSummary() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillProfitSheet(bill: widget.bill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final dateStr = DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_outlined,
                      color: AppColors.amber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bill.customerName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_billDisplayId(bill)} • $dateStr',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _PaymentChip(isPaid: bill.isPaid),
                      const SizedBox(height: 4),
                      if (bill.isPaid) ...[
                        _MethodChip(method: bill.paymentMethod),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        '₹${bill.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '${bill.itemCount} items',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textMuted,
                  ),
                ],
              ),
            ),
          ),
          // Expanded items
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                children: [
                  if (bill.customerPhone != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.phone_outlined,
                            size: 16,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            bill.customerPhone!,
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...bill.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          Text(
                            '${item.quantityLabel} x ${item.priceLabel}',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '₹${item.subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(),
                  if (bill.discountAmount > 0) ...[
                    _AmountRow(
                      label: 'Subtotal',
                      value: '₹${bill.subtotalAmount.toStringAsFixed(2)}',
                    ),
                    _AmountRow(
                      label: 'Discount',
                      value:
                          '${bill.discountPercent.toStringAsFixed(2)}% • - ₹${bill.discountAmount.toStringAsFixed(2)}',
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 0,
                          children: [
                            TextButton.icon(
                              onPressed: widget.onDelete,
                              icon: const Icon(Icons.delete_outline, size: 18),
                              label: const Text('Delete'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.error,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () =>
                                  widget.onStatusChanged(!bill.isPaid),
                              icon: Icon(
                                bill.isPaid
                                    ? Icons.pending_actions_outlined
                                    : Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: Text(
                                bill.isPaid ? 'Mark Unpaid' : 'Mark Paid',
                              ),
                              style: TextButton.styleFrom(
                                foregroundColor: bill.isPaid
                                    ? AppColors.textMuted
                                    : AppColors.success,
                              ),
                            ),
                            if (bill.customerPhone != null)
                              TextButton.icon(
                                onPressed: widget.onSendWhatsApp,
                                icon: const Icon(Icons.send_outlined, size: 18),
                                label: const Text('WhatsApp'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.success,
                                ),
                              ),
                            TextButton.icon(
                              onPressed: widget.onSharePdf,
                              icon: const Icon(
                                Icons.ios_share_rounded,
                                size: 18,
                              ),
                              label: const Text('Share'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.navy,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _showProfitSummary,
                              icon: const Icon(
                                Icons.trending_up_rounded,
                                size: 18,
                              ),
                              label: const Text('View Profit'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Total: ₹${bill.totalAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

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
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.creamDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${_billDisplayId(bill)} Profit',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              ...bill.items.map((item) => _ProfitItemRow(item: item)),
              const SizedBox(height: 8),
              TextField(
                controller: _commissionCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Commission % from profit (optional)',
                  suffixText: '%',
                ),
                onChanged: (value) => setState(() {
                  _commissionPercent = (double.tryParse(value) ?? 0)
                      .clamp(0, 100)
                      .toDouble();
                }),
              ),
              const Divider(height: 24),
              _ProfitTotalRow('Total Revenue', revenue),
              _ProfitTotalRow('Total Cost', cost),
              _ProfitTotalRow('Gross Profit', profit),
              _ProfitTotalRow('Commission Payable', commission),
              _ProfitTotalRow('Your Net Profit', net),
              _ProfitTotalRow('GST Collected', gst),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saveCommission,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Commission'),
                style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfitItemRow extends StatelessWidget {
  final BillItem item;

  const _ProfitItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                item.wasDirectPrice ? 'direct' : 'formula',
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${item.quantityLabel}    Sold: ₹${item.sellingPriceSnapshot.toStringAsFixed(2)}    Cost: ₹${item.costSnapshot.toStringAsFixed(2)}    Profit: ₹${item.profitSnapshot.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

class _ProfitTotalRow extends StatelessWidget {
  final String label;
  final double value;

  const _ProfitTotalRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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

class _PaymentChip extends StatelessWidget {
  final bool isPaid;
  const _PaymentChip({required this.isPaid});

  @override
  Widget build(BuildContext context) {
    final color = isPaid ? AppColors.success : AppColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isPaid ? 'Paid' : 'Unpaid',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String method;
  const _MethodChip({required this.method});

  @override
  Widget build(BuildContext context) {
    final online = method == 'online';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (online ? AppColors.navy : AppColors.amber).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        _paymentMethodLabel(method),
        style: TextStyle(
          color: online ? AppColors.navy : AppColors.amber,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _paymentMethodLabel(String method) {
  return method == 'online' ? 'Online' : 'Cash';
}

String _billDisplayId(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  // Strip the internal SHOP-LOCAL-local- prefix for display.
  final cleaned = bill.billNumber.replaceFirst(
    RegExp(r'^SHOP-LOCAL-local-'),
    'INV-',
  );
  return cleaned;
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  const _AmountRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: AppColors.textMuted)),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
