import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/bill_totals.dart';
import '../models/shop_profile.dart';
import '../services/cloud_service.dart';
import '../services/bill_share.dart';
import '../services/thermal/thermal_printer_service.dart';
import 'scan_screen.dart';
import 'shared/record_payment_dialog.dart';
import 'store/bill_settings_screen.dart';
import '../utils/money.dart';

part 'billing/bill_history_sheet.dart';
part 'billing/bill_list_widgets.dart';
part 'billing/bill_card.dart';
part 'billing/bill_profit_sheet.dart';
part 'billing/bill_action_widgets.dart';
part 'billing/bill_formatters.dart';
part 'billing/bill_dialogs.dart';
part 'billing/return_sheet.dart';

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

  Set<String> _unsyncedBillUuids = const {};

  Future<void> _loadBills() async {
    final db = DatabaseHelper.instance;
    final bills = await db.getAllBills();
    final cancelled = await db.getCancelledBills();
    final cloud = CloudService.instance.state.value;
    final unsynced = cloud.isConfigured && cloud.isSignedIn
        ? await db.unsyncedBillUuids()
        : const <String>{};
    if (mounted) {
      setState(() {
        _unsyncedBillUuids = unsynced;
        _bills = bills;
        _cancelledBills = cancelled;
        _isLoading = false;
      });
    }
  }

  Future<void> _cancelBill(Bill bill) async {
    if (bill.id == null) return;
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _CancelBillDialog(billLabel: _billDisplayId(bill)),
    );
    if (reason == null) return;
    try {
      await DatabaseHelper.instance.cancelBill(
        bill.id!,
        reason: reason.trim().isEmpty ? 'Correction required' : reason,
      );
      await _loadBills();
    } catch (e) {
      _showActionError(e);
    }
  }

  Future<void> _updateBillStatus(
    Bill bill,
    bool isPaid, {
    String? paymentMethod,
    String? paymentReference,
  }) async {
    if (bill.id == null) return;
    try {
      await DatabaseHelper.instance.updateBillPaidStatus(
        bill.id!,
        isPaid,
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
      );
      await _loadBills();
    } catch (e) {
      _showActionError(e);
    }
  }

  Future<void> _returnItems(Bill bill) async {
    if (bill.id == null) return;
    final db = DatabaseHelper.instance;
    final returnable = await db.returnableQuantities(bill.id!);
    final settings = await db.getBillSettings();
    if (!mounted) return;
    final request = await showModalBottomSheet<_ReturnRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceOf(context),
      builder: (_) => _ReturnSheet(
        bill: bill,
        returnable: returnable,
        roundOff: settings.roundOffTotal,
      ),
    );
    if (request == null) return;
    try {
      final creditNoteId = await db.createCreditNote(
        billId: bill.id!,
        quantities: request.quantities,
        settlement: request.settlement,
        refundMethod: request.refundMethod,
        reason: request.reason,
      );
      await _loadBills();
      final creditNote = await db.getBillById(creditNoteId);
      if (!mounted || creditNote == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Credit note ${creditNote.billNumber} issued'),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () => BillShare.sharePdf(creditNote),
            ),
          ),
        );
    } catch (e) {
      _showActionError(e);
    }
  }

  void _showActionError(Object error) {
    debugPrint('Bill action failed: $error');
    if (!mounted) return;
    final message = switch (error) {
      ArgumentError(:final message) => '$message',
      StateError(:final message) => message,
      _ => 'Something went wrong. Please try again.',
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recordPayment(Bill bill) async {
    if (bill.id == null || bill.balanceDue <= 0) return;
    final entry = await showDialog<PaymentEntry>(
      context: context,
      builder: (_) => RecordPaymentDialog(balanceDue: bill.balanceDue),
    );
    if (entry == null) return;
    try {
      await DatabaseHelper.instance.recordBillPayment(
        bill.id!,
        amount: entry.amount,
        paymentMethod: entry.method,
        paymentReference: entry.reference,
      );
      await _loadBills();
    } catch (e) {
      _showActionError(e);
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
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
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

  Future<void> _shareBillPdf(Bill bill) => BillShare.sharePdf(bill);

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
        '- ${item.productName} ${item.quantityLabel} x ${item.priceLabel}: ${rupees(item.subtotal)}',
      );
    }
    buffer
      ..writeln('')
      ..writeln('Subtotal: ${rupees(bill.subtotalAmount)}');
    if (bill.discountAmount > 0) {
      buffer.writeln(
        'Discount (${bill.discountPercent.toStringAsFixed(2)}%): -${rupees(bill.discountAmount)}',
      );
    }
    if (bill.roundOffAmount != 0) {
      buffer.writeln('Round off: ${signedRupees(bill.roundOffAmount)}');
    }
    buffer
      ..writeln('Total: ${rupees(bill.totalAmount)}')
      ..writeln('Paid: ${rupees(bill.paidAmount)}')
      ..writeln('Balance: ${rupees(bill.balanceDue)}')
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
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim().toLowerCase()),
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
                const SliverFillRemaining(child: AppSkeletonList())
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
                  // A lazy list: only the bill cards on screen are built and
                  // laid out, so shops with thousands of bills scroll fine.
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
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
                    ], addAutomaticKeepAlives: false),
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
            waitingToSync: _unsyncedBillUuids.contains(bill.uuid),
            onCancel: () => _cancelBill(bill),
            onEdit: () => _editBillDetails(bill),
            onStatusChanged: (isPaid, method, reference) => _updateBillStatus(
              bill,
              isPaid,
              paymentMethod: method,
              paymentReference: reference,
            ),
            onRecordPayment: () => _recordPayment(bill),
            onReturn:
                !bill.isCreditNote && CloudService.instance.state.value.isAdmin
                ? () => _returnItems(bill)
                : null,
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
              style: AppText.body.copyWith(
                color: AppColors.inkMutedOf(context),
              ),
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
    return AppEmptyState(
      icon: Icons.receipt_long_outlined,
      title: 'No bills yet',
      message: 'Create your first bill to get started',
      secondaryAction: TestKeys.tag(
        TestKeys.createBillBtn,
        FilledButton.icon(
          onPressed: () => _openBillCreator(BillingEntryMode.manual),
          icon: const Icon(Icons.receipt_long_rounded),
          label: const Text('Create Bill'),
        ),
        button: true,
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────
