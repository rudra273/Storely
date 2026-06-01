import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/shop_profile.dart';
import '../services/cloud_service.dart';
import '../utils/bill_pdf_generator.dart';
import 'scan_screen.dart';

part 'billing/bill_list_widgets.dart';
part 'billing/bill_card.dart';
part 'billing/bill_profit_sheet.dart';
part 'billing/bill_action_widgets.dart';
part 'billing/bill_formatters.dart';

class BillsScreen extends StatefulWidget {
  final int refreshToken;

  const BillsScreen({super.key, this.refreshToken = 0});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  List<Bill> _bills = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void didUpdateWidget(covariant BillsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadBills();
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

  Future<void> _updateBillStatus(
    Bill bill,
    bool isPaid, {
    String? paymentMethod,
  }) async {
    if (bill.id == null) return;
    await DatabaseHelper.instance.updateBillPaidStatus(
      bill.id!,
      isPaid,
      paymentMethod: paymentMethod,
    );
    await _loadBills();
  }

  Future<void> _recordPayment(Bill bill) async {
    if (bill.id == null || bill.balanceDue <= 0) return;
    final amountCtrl = TextEditingController(
      text: bill.balanceDue.toStringAsFixed(2),
    );
    var method = 'cash';
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Record Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Amount received',
                    prefixText: '₹ ',
                    helperText:
                        'Balance: ₹${bill.balanceDue.toStringAsFixed(2)}',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'cash',
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Cash'),
                    ),
                    ButtonSegment(
                      value: 'online',
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('Online'),
                    ),
                  ],
                  selected: {method},
                  onSelectionChanged: (value) =>
                      setDialogState(() => method = value.first),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amountCtrl.text) ?? 0;
                  Navigator.pop(ctx, value);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (amount == null || amount <= 0) return;
      await DatabaseHelper.instance.recordBillPayment(
        bill.id!,
        amount: amount,
        paymentMethod: method,
      );
      await _loadBills();
    } finally {
      amountCtrl.dispose();
    }
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
    final db = DatabaseHelper.instance;
    final shop = await db.getShopProfile();
    final settings = await db.getBillSettings();
    final bytes = await BillPdfGenerator.generate(
      bill: bill,
      shop: shop,
      settings: settings,
    );
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
      ..writeln('Paid: ₹${bill.paidAmount.toStringAsFixed(2)}')
      ..writeln('Balance: ₹${bill.balanceDue.toStringAsFixed(2)}')
      ..writeln('Status: ${_paymentStatusLabel(bill.paymentStatus)}');
    if (bill.paidAmount > 0) {
      buffer.writeln('Payment: ${_paymentMethodLabel(bill.paymentMethod)}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Bills')),
      body: RefreshIndicator(
        color: AppColors.amber,
        onRefresh: _loadBills,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_bills.isEmpty)
              SliverFillRemaining(child: _buildEmpty())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  96,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SearchBar(
                        controller: _searchCtrl,
                        query: _searchQuery,
                        onChanged: (val) => setState(
                          () => _searchQuery = val.trim().toLowerCase(),
                        ),
                        onClear: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_searchQuery.isEmpty) ...[
                        _UnpaidSummary(bills: _bills),
                      ],
                      ..._buildGroupedBillCards(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _isLoading || _bills.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openBillCreator(BillingEntryMode.manual),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('New Bill'),
            ),
    );
  }

  List<Widget> _buildGroupedBillCards() {
    final widgets = <Widget>[];
    String? currentGroup;

    final filtered = _bills.where((b) {
      if (_searchQuery.isEmpty) return true;
      final nameMatches = b.customerName.toLowerCase().contains(_searchQuery);
      final numMatches = b.billNumber.toLowerCase().contains(_searchQuery);
      final dateMatches = DateFormat(
        'dd MMM yyyy',
      ).format(b.createdAt).toLowerCase().contains(_searchQuery);
      return nameMatches || numMatches || dateMatches;
    }).toList();

    for (final bill in filtered) {
      final group = _dateGroupTitle(bill.createdAt);
      if (group != currentGroup) {
        currentGroup = group;
        if (widgets.isNotEmpty) {
          widgets.add(const SizedBox(height: AppSpacing.xl));
        }
        widgets.add(_DateLabel(title: group));
        widgets.add(const SizedBox(height: AppSpacing.sm));
      }
      widgets.add(
        _BillCard(
          bill: bill,
          onDelete: () => _deleteBill(bill),
          onStatusChanged: (isPaid, method) =>
              _updateBillStatus(bill, isPaid, paymentMethod: method),
          onRecordPayment: () => _recordPayment(bill),
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: AppRadius.lgRadius,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 36,
                color: AppColors.inkFaint,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No bills yet', style: AppText.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create your first bill to get started',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => _openBillCreator(BillingEntryMode.manual),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Create Bill'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────
