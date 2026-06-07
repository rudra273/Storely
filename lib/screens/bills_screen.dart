import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/shop_profile.dart';
import '../services/cloud_service.dart';
import '../utils/bill_pdf_generator.dart';
import 'scan_screen.dart';
import 'store/bill_settings_screen.dart';

part 'billing/bill_list_widgets.dart';
part 'billing/bill_card.dart';
part 'billing/bill_profit_sheet.dart';
part 'billing/bill_action_widgets.dart';
part 'billing/bill_formatters.dart';

class BillsScreen extends StatefulWidget {
  final int refreshToken;

  /// Whether the Bills tab is the one currently shown in the [AppShell].
  /// The shell keeps every tab mounted in an `IndexedStack`, so without this
  /// the "New Bill" FAB would briefly animate in over other screens (e.g. when
  /// returning from a pushed page) even though Bills isn't visible.
  final bool isActiveMainTab;

  const BillsScreen({
    super.key,
    this.refreshToken = 0,
    this.isActiveMainTab = true,
  });
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  List<Bill> _bills = [];
  List<Bill> _cancelledBills = [];
  bool _showCancelled = false;
  bool _isLoading = true;
  bool _searchOpen = false;
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
    final db = DatabaseHelper.instance;
    final bills = await db.getAllBills();
    final cancelled = await db.getCancelledBills();
    if (mounted) {
      setState(() {
        _bills = bills;
        _cancelledBills = cancelled;
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBill(Bill bill) async {
    if (bill.id == null) return;
    final reasonCtrl = TextEditingController();
    try {
      final reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.block_rounded, color: AppColors.error, size: 32),
          title: const Text('Cancel Bill'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Cancel ${_billDisplayId(bill)}? Stock and customer ledger will be reversed.',
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: reasonCtrl,
                textCapitalization: TextCapitalization.sentences,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep Bill'),
            ),
            TestKeys.tag(
              TestKeys.confirmBtn,
              FilledButton(
                onPressed: () => Navigator.pop(ctx, reasonCtrl.text),
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Cancel Bill'),
              ),
              button: true,
            ),
          ],
        ),
      );
      if (reason == null) return;
      await DatabaseHelper.instance.cancelBill(
        bill.id!,
        reason: reason.trim().isEmpty ? 'Correction required' : reason,
      );
      await _loadBills();
    } finally {
      reasonCtrl.dispose();
    }
  }

  Future<void> _updateBillStatus(
    Bill bill,
    bool isPaid, {
    String? paymentMethod,
    String? paymentReference,
  }) async {
    if (bill.id == null) return;
    await DatabaseHelper.instance.updateBillPaidStatus(
      bill.id!,
      isPaid,
      paymentMethod: paymentMethod,
      paymentReference: paymentReference,
    );
    await _loadBills();
  }

  Future<void> _recordPayment(Bill bill) async {
    if (bill.id == null || bill.balanceDue <= 0) return;
    final amountCtrl = TextEditingController(
      text: bill.balanceDue.toStringAsFixed(2),
    );
    final txnRefCtrl = TextEditingController();
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
                if (method == 'online') ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: txnRefCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Transaction ID (optional)',
                      prefixIcon: Icon(Icons.receipt_long_outlined),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TestKeys.tag(
                TestKeys.saveBtn,
                FilledButton(
                  onPressed: () {
                    final value = double.tryParse(amountCtrl.text) ?? 0;
                    Navigator.pop(ctx, value);
                  },
                  child: const Text('Save'),
                ),
                button: true,
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
        paymentReference: method == 'online' ? txnRefCtrl.text : null,
      );
      await _loadBills();
    } finally {
      amountCtrl.dispose();
      txnRefCtrl.dispose();
    }
  }

  Future<void> _openBillSettings() async {
    // Bill settings drive how invoices are rendered/shared; reload after in case
    // anything visible here (e.g. shared PDF output) depends on them.
    await Navigator.push(
      context,
      MaterialPageRoute<bool>(builder: (_) => const BillSettingsScreen()),
    );
    if (mounted) await _loadBills();
  }

  Future<void> _openBillCreator(BillingEntryMode mode) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanScreen(initialMode: mode)),
    );
    await _loadBills();
  }

  Future<void> _duplicateBill(Bill bill) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScanScreen(
          initialMode: BillingEntryMode.manual,
          duplicateFromBill: bill,
        ),
      ),
    );
    await _loadBills();
  }

  Future<void> _editBillDetails(Bill bill) async {
    if (bill.id == null) return;
    final isB2b = bill.billType == Bill.typeB2b;
    final nameCtrl = TextEditingController(
      text: bill.customerName == 'Walk-in Customer' ? '' : bill.customerName,
    );
    final phoneCtrl = TextEditingController(text: bill.customerPhone ?? '');
    final gstinCtrl = TextEditingController(text: bill.customerGstin ?? '');
    final legalNameCtrl = TextEditingController(
      text: bill.customerGstLegalName ?? '',
    );
    final tradeNameCtrl = TextEditingController(
      text: bill.customerGstTradeName ?? '',
    );
    final addressCtrl = TextEditingController(
      text: bill.customerAddressSnapshot ?? '',
    );
    final stateCodeCtrl = TextEditingController(
      text: bill.placeOfSupplyStateCode ?? '',
    );
    try {
      final saved = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _EditBuyerDetailsSheet(
          isB2b: isB2b,
          nameCtrl: nameCtrl,
          phoneCtrl: phoneCtrl,
          gstinCtrl: gstinCtrl,
          legalNameCtrl: legalNameCtrl,
          tradeNameCtrl: tradeNameCtrl,
          addressCtrl: addressCtrl,
          stateCodeCtrl: stateCodeCtrl,
        ),
      );
      if (saved != true) return;
      await DatabaseHelper.instance.updateBillCustomerDetails(
        bill.id!,
        customerName: nameCtrl.text,
        customerPhone: phoneCtrl.text,
        customerGstin: gstinCtrl.text,
        customerGstLegalName: legalNameCtrl.text,
        customerGstTradeName: tradeNameCtrl.text,
        customerAddressSnapshot: addressCtrl.text,
        placeOfSupplyStateCode: stateCodeCtrl.text,
        isB2b: isB2b,
      );
      await _loadBills();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buyer details updated'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      nameCtrl.dispose();
      phoneCtrl.dispose();
      gstinCtrl.dispose();
      legalNameCtrl.dispose();
      tradeNameCtrl.dispose();
      addressCtrl.dispose();
      stateCodeCtrl.dispose();
    }
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
    return PopScope(
      canPop: !_searchOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_searchOpen) {
          setState(() {
            _searchOpen = false;
            _searchCtrl.clear();
            _searchQuery = '';
          });
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: _searchOpen
              ? TestKeys.tag(
                  TestKeys.billSearchField,
                  TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    cursorColor: AppColors.amber,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      hintText: 'Search bills...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 16,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onChanged: (val) => setState(
                      () => _searchQuery = val.trim().toLowerCase(),
                    ),
                  ),
                  textField: true,
                )
              : const Text('Bills'),
          actions: [
            IconButton(
              onPressed: () {
                setState(() {
                  _searchOpen = !_searchOpen;
                  if (!_searchOpen) {
                    _searchCtrl.clear();
                    _searchQuery = '';
                  }
                });
              },
              icon: Icon(_searchOpen ? Icons.close : Icons.search),
            ),
            if (!_searchOpen)
              IconButton(
                tooltip: 'Bill settings',
                onPressed: _openBillSettings,
                icon: const Icon(Icons.tune_rounded),
              ),
            const AppInfoAction(
              title: 'Bills Help',
              intro:
                  'Bills keep the sale record, payment status, and printable invoice together.',
              sections: [
                AppInfoSection(
                  title: 'Create bills',
                  points: [
                    'Use New Bill for manual billing, or Scan & Bill from home for product labels.',
                    'Until Generate Bill, the billing screen is an editable draft.',
                    'Products added to a bill use price snapshots so old bills do not change when product prices change later.',
                    'Bill settings in Store control invoice title, numbering, logo, signature, and visible fields.',
                  ],
                ),
                AppInfoSection(
                  title: 'After saving',
                  points: [
                    'Final bills are locked for amount, GST, item, and customer snapshot corrections.',
                    'For mistakes, cancel the old bill with a reason and duplicate it as a new bill.',
                    'Unpaid and partial bills can be updated with Record Payment.',
                    'Share PDF creates a printable invoice from the saved bill data.',
                    'WhatsApp sharing uses the customer phone saved on the bill.',
                  ],
                ),
              ],
            ),
            const SizedBox(width: 8),
          ],
        ),
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
            else if (_bills.isEmpty && _cancelledBills.isEmpty)
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
                      // Always shown so the Cancelled tab stays reachable even
                      // when there are no cancelled bills yet (count shows 0).
                      _BillFilterTabs(
                        showCancelled: _showCancelled,
                        activeCount: _bills.length,
                        cancelledCount: _cancelledBills.length,
                        onChanged: (showCancelled) =>
                            setState(() => _showCancelled = showCancelled),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_showCancelled) ...[
                        ..._buildCancelledBillCards(),
                      ] else ...[
                        if (_searchQuery.isEmpty) ...[
                          _UnpaidSummary(bills: _bills),
                        ],
                        ..._buildGroupedBillCards(),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      // Hidden only when there are no bills of any kind (the full-page empty
      // state has its own Create button). When only cancelled bills remain, the
      // FAB must stay so a new bill is still reachable.
      floatingActionButton:
          !widget.isActiveMainTab ||
              _isLoading ||
              (_bills.isEmpty && _cancelledBills.isEmpty)
          ? null
          : TestKeys.tag(
              TestKeys.createBillBtn,
              FloatingActionButton.extended(
                onPressed: () => _openBillCreator(BillingEntryMode.manual),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('New Bill'),
              ),
              button: true,
            ),
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
        TestKeys.tag(
          TestKeys.billRow(bill.id ?? bill.billNumber),
          _BillCard(
            bill: bill,
            onCancel: () => _cancelBill(bill),
            onEdit: () => _editBillDetails(bill),
            onStatusChanged: (isPaid, method, reference) => _updateBillStatus(
              bill,
              isPaid,
              paymentMethod: method,
              paymentReference: reference,
            ),
            onRecordPayment: () => _recordPayment(bill),
            onSendWhatsApp: () => _sendBillOnWhatsApp(bill),
            onSharePdf: () => _shareBillPdf(bill),
          ),
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildCancelledBillCards() {
    final filtered = _cancelledBills.where((b) {
      if (_searchQuery.isEmpty) return true;
      final nameMatches = b.customerName.toLowerCase().contains(_searchQuery);
      final numMatches = b.billNumber.toLowerCase().contains(_searchQuery);
      final reasonMatches =
          b.cancelReason?.toLowerCase().contains(_searchQuery) ?? false;
      return nameMatches || numMatches || reasonMatches;
    }).toList();

    if (filtered.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
          child: Center(
            child: Text(
              _searchQuery.isEmpty
                  ? 'No cancelled bills'
                  : 'No cancelled bills match your search',
              style: AppText.body.copyWith(color: AppColors.inkMuted),
            ),
          ),
        ),
      ];
    }

    return [
      for (final bill in filtered)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: _CancelledBillCard(
            bill: bill,
            onDuplicate: () => _duplicateBill(bill),
          ),
        ),
    ];
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
            TestKeys.tag(
              TestKeys.createBillBtn,
              FilledButton.icon(
                onPressed: () => _openBillCreator(BillingEntryMode.manual),
                icon: const Icon(Icons.receipt_long_rounded),
                label: const Text('Create Bill'),
              ),
              button: true,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────
