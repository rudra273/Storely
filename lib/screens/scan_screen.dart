import '../l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../db/database_helper.dart';
import '../services/app_settings_service.dart';
import '../services/bill_share.dart';
import '../services/thermal/thermal_printer_service.dart';
import '../models/bill.dart';
import '../models/bill_totals.dart';
import '../models/customer.dart';
import '../models/held_bill.dart';
import '../models/product.dart';
import '../utils/money.dart';

part 'scan/manual_product_widgets.dart';
part 'scan/customer_suggestion_list.dart';
part 'scan/bill_summary_widgets.dart';
part 'scan/bill_draft.dart';
part 'scan/bill_checkout_sheet.dart';
part 'scan/quantity_input.dart';

enum BillingEntryMode { scan, manual }

class ScanScreen extends StatefulWidget {
  /// Null opens the mode the shop used last (Scan or Search).
  final BillingEntryMode? initialMode;
  final Bill? duplicateFromBill;

  const ScanScreen({super.key, this.initialMode, this.duplicateFromBill});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _scanCooldown = Duration(seconds: 1);
  static const _invalidScanCooldown = Duration(seconds: 2);
  // The scanner reports a code ~every 250ms while it stays in frame. The same
  // code only counts again once it has been out of view for this long, so a
  // product held under the camera is added once, not once per cooldown.
  static const _sameCodeHoldWindow = Duration(milliseconds: 1500);

  final _productSearchCtrl = TextEditingController();
  final List<BillItem> _items = [];
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Map<int, int> _saleCounts = const {};
  late BillingEntryMode _entryMode;
  bool _isProcessing = false;
  bool _isSavingBill = false;
  bool _isOpeningBillSheet = false;
  bool _isLoadingProducts = true;
  bool _showAddedStatus = false;
  String? _lastScanned;
  DateTime? _lastScannedSeenAt;

  double get _subtotal => _items.fold(0, (sum, i) => sum + i.subtotal);
  int get _itemCount =>
      _items.fold<double>(0, (sum, i) => sum + i.quantity).round();

  @override
  void initState() {
    super.initState();
    _entryMode = widget.duplicateFromBill != null
        ? BillingEntryMode.manual
        : widget.initialMode ??
              (AppSettingsService.instance.billingSearchFirst
                  ? BillingEntryMode.manual
                  : BillingEntryMode.scan);
    if (widget.duplicateFromBill != null) {
      _items.addAll(widget.duplicateFromBill!.items.map(_copyItemForNewBill));
      _draftReady = true;
    } else {
      _restoreDraft();
    }
    _productSearchCtrl.addListener(_applyProductSearch);
    _loadProducts();
    _loadHeldCount();
  }

  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // Billing snackbars (e.g. "Restored your unsaved bill") belong to this
    // screen; the app-wide messenger would otherwise keep showing them.
    _messenger?.removeCurrentSnackBar();
    _draftTimer?.cancel();
    if (_draftReady) _saveDraftNow();
    _productSearchCtrl.removeListener(_applyProductSearch);
    _productSearchCtrl.dispose();
    super.dispose();
  }

  // ── Auto-saved cart and held bills ──
  //
  // Every rebuild checks whether the cart changed and, if so, saves it
  // (debounced) so an app kill or a call mid-bill never loses the cart.

  Timer? _draftTimer;
  bool _draftReady = false;
  String _savedDraft = HeldBill.encodeItems(const []);
  int _heldCount = 0;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!_draftReady) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraftNow);
  }

  void _saveDraftNow() {
    final encoded = HeldBill.encodeItems(_items);
    if (encoded == _savedDraft) return;
    _savedDraft = encoded;
    DatabaseHelper.instance.saveCartDraft(List.of(_items));
  }

  Future<void> _restoreDraft() async {
    final draft = await DatabaseHelper.instance.loadCartDraft();
    if (!mounted) return;
    _savedDraft = HeldBill.encodeItems(draft);
    _draftReady = true;
    if (draft.isEmpty || _items.isNotEmpty) return;
    setState(() => _items.addAll(draft));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Restored your unsaved bill (${draft.length} '
          'item${draft.length == 1 ? '' : 's'})',
        ),
        action: SnackBarAction(
          label: context.l10n.discard,
          onPressed: () {
            if (mounted) setState(() => _items.clear());
          },
        ),
      ),
    );
  }

  Future<void> _loadHeldCount() async {
    final held = await DatabaseHelper.instance.getHeldBills();
    if (mounted) setState(() => _heldCount = held.length);
  }

  /// Parks the cart so the next customer can be billed.
  Future<void> _holdCart() async {
    if (_items.isEmpty) return;
    final items = List<BillItem>.of(_items);
    final first = items.first.productName;
    final label =
        '${DateFormat('hh:mm a').format(DateTime.now())} · $first'
        '${items.length > 1 ? ' +${items.length - 1}' : ''}';
    await DatabaseHelper.instance.holdBill(label, items);
    if (!mounted) return;
    setState(() {
      _items.clear();
      _heldCount++;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Held: $label')));
  }

  Future<void> _openHeldBills() async {
    final held = await DatabaseHelper.instance.getHeldBills();
    if (!mounted) return;
    final chosen = await showModalBottomSheet<HeldBill>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceOf(context),
      builder: (_) => _HeldBillsSheet(
        held: held,
        onDelete: (bill) async {
          await DatabaseHelper.instance.deleteHeldBill(bill.id);
          await _loadHeldCount();
        },
      ),
    );
    if (chosen == null || !mounted) return;
    // Swap: the cart being billed is held, so nothing is lost.
    if (_items.isNotEmpty) await _holdCart();
    await DatabaseHelper.instance.deleteHeldBill(chosen.id);
    if (!mounted) return;
    setState(() => _items.addAll(chosen.items));
    await _loadHeldCount();
  }

  Future<void> _loadProducts() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    final saleCounts = await DatabaseHelper.instance.getProductSaleCounts();
    if (!mounted) return;
    // Frequently sold items first, so the usual items are one tap away.
    products.sort((a, b) {
      final byCount = (saleCounts[b.id] ?? 0).compareTo(saleCounts[a.id] ?? 0);
      return byCount != 0
          ? byCount
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    setState(() {
      _allProducts = products;
      _saleCounts = saleCounts;
      _isLoadingProducts = false;
    });
    _applyProductSearch();
  }

  void _applyProductSearch() {
    final query = _productSearchCtrl.text.trim().toLowerCase();
    if (!mounted) return;
    setState(() {
      final products = query.isEmpty
          ? _allProducts
          : _allProducts.where((product) {
              return product.name.toLowerCase().contains(query) ||
                  (product.itemCode?.toLowerCase().contains(query) ?? false) ||
                  (product.barcode?.toLowerCase().contains(query) ?? false) ||
                  (product.category?.toLowerCase().contains(query) ?? false) ||
                  (product.supplier?.toLowerCase().contains(query) ?? false);
            }).toList();
      _filteredProducts = products.take(40).toList();
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    final now = DateTime.now();
    final lastSeenAt = _lastScannedSeenAt;
    final sameCodeStillInView =
        raw == _lastScanned &&
        lastSeenAt != null &&
        now.difference(lastSeenAt) < _sameCodeHoldWindow;
    if (raw == _lastScanned) _lastScannedSeenAt = now;
    if (sameCodeStillInView || _isProcessing) return;

    setState(() => _isProcessing = true);
    _lastScanned = raw;
    _lastScannedSeenAt = now;

    try {
      await _handleScannedCode(raw);
    } catch (_) {
      if (!mounted) return;
      setState(() => _showAddedStatus = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not read this code. Try again.'),
            duration: _invalidScanCooldown,
          ),
        );
      _allowNextScanAfter(_invalidScanCooldown);
    }
  }

  Future<void> _handleScannedCode(String raw) async {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final name = data['name'] as String? ?? 'Unknown';
      final id = (data['id'] as num?)?.toInt();
      final uuid = data['uuid'] as String?;
      final code = data['code'] as String?;
      final barcode = data['barcode'] as String?;
      final product = await DatabaseHelper.instance.findProductForBilling(
        id: id,
        productUuid: uuid,
        itemCode: code,
        barcode: barcode,
        name: name,
      );
      if (product == null) {
        if (!mounted) return;
        setState(() => _showAddedStatus = false);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Product not found for this QR code'),
              duration: _invalidScanCooldown,
            ),
          );
        _allowNextScanAfter(_invalidScanCooldown);
        return;
      }
      final scannedItem = await DatabaseHelper.instance.buildBillItemForProduct(
        product,
      );
      if (!mounted) return;

      _addBillItem(scannedItem);

      HapticFeedback.mediumImpact();
      _allowNextScanAfter(_scanCooldown);
    } catch (_) {
      final product = await DatabaseHelper.instance.findProductForBilling(
        productUuid: raw,
        barcode: raw,
        itemCode: raw,
        name: raw,
      );
      if (product != null) {
        final item = await DatabaseHelper.instance.buildBillItemForProduct(
          product,
        );
        if (!mounted) return;
        _addBillItem(item);
        HapticFeedback.mediumImpact();
        _allowNextScanAfter(_scanCooldown);
        return;
      }
      if (!mounted) return;
      setState(() => _showAddedStatus = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Invalid QR code'),
            duration: _invalidScanCooldown,
          ),
        );
      _allowNextScanAfter(_invalidScanCooldown);
    }
  }

  Future<void> _addProductToBill(Product product) async {
    final item = await DatabaseHelper.instance.buildBillItemForProduct(product);
    if (!mounted) return;
    _addBillItem(item);
    HapticFeedback.selectionClick();
    // Ready for the next item: clear the search after an add.
    if (_productSearchCtrl.text.isNotEmpty) _productSearchCtrl.clear();
  }

  BillItem _copyItemForNewBill(BillItem item) {
    return BillItem(
      productId: item.productId,
      productUuid: item.productUuid,
      productName: item.productName,
      hsnCodeSnapshot: item.hsnCodeSnapshot,
      hsnTypeSnapshot: item.hsnTypeSnapshot,
      mrp: item.mrp,
      unit: item.unit,
      purchasePriceSnapshot: item.purchasePriceSnapshot,
      sellingPriceSnapshot: item.sellingPriceSnapshot,
      costSnapshot: item.costSnapshot,
      profitSnapshot: item.profitSnapshot,
      commissionSnapshot: item.commissionSnapshot,
      gstSnapshot: item.gstSnapshot,
      gstPercentSnapshot: item.gstPercentSnapshot,
      taxableValueSnapshot: item.taxableValueSnapshot,
      cgstAmountSnapshot: item.cgstAmountSnapshot,
      sgstAmountSnapshot: item.sgstAmountSnapshot,
      igstAmountSnapshot: item.igstAmountSnapshot,
      wasDirectPrice: item.wasDirectPrice,
      quantity: item.quantity,
      mrpSnapshot: item.mrpSnapshot,
    );
  }

  void _addBillItem(BillItem item) {
    final existing = _items.indexWhere(
      (existingItem) =>
          (item.productId != null &&
              existingItem.productId == item.productId) ||
          (item.productId == null &&
              existingItem.productName.toLowerCase() ==
                  item.productName.toLowerCase()),
    );
    final available = _availableStockForItem(item);
    if (available != null) {
      final currentQty = existing >= 0 ? _items[existing].quantity : 0.0;
      if (exceedsStock(currentQty + 1, available)) {
        _showStockLimitMessage(item.productName, available);
      }
    }

    setState(() {
      if (existing >= 0) {
        _items[existing].quantity++;
        _items[existing].unit ??= item.unit;
      } else {
        _items.add(item);
      }
      _showAddedStatus = _entryMode == BillingEntryMode.scan;
    });
  }

  double? _availableStockForItem(BillItem item) {
    final productId = item.productId;
    if (productId == null) return null;
    for (final product in _allProducts) {
      if (product.id == productId) {
        return product.trackStock ? product.quantity : null;
      }
    }
    return null;
  }

  /// Selling past the recorded stock is allowed (counts often lag the
  /// shelf); this only warns, and stock goes negative.
  void _showStockLimitMessage(String productName, double available) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            available <= stockQuantityEpsilon
                ? '"$productName" shows no stock. Added anyway.'
                : 'Only ${_formatQuantityInput(available)} in stock for '
                      '"$productName". Added anyway.',
          ),
        ),
      );
  }

  void _allowNextScanAfter(Duration duration) {
    Future.delayed(duration, () {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _showAddedStatus = false;
      });
    });
  }

  Future<({int id, BillTotals totals})?> _completeBill({
    required String customerName,
    required String? customerPhone,
    required String billType,
    required String? customerGstin,
    required String? customerGstLegalName,
    required String? customerGstTradeName,
    required String? customerAddress,
    required String? placeOfSupplyStateCode,
    required double discountPercent,
    required double paidAmount,
    required String paymentMethod,
    String? transactionReference,
  }) async {
    if (_items.isEmpty) return null;
    if (_isSavingBill) return null;

    setState(() => _isSavingBill = true);
    final percent = discountPercent.clamp(0, 100).toDouble();
    final shop = await DatabaseHelper.instance.getShopProfile();
    final settings = await DatabaseHelper.instance.getBillSettings();
    final gstRegistered = shop?.gstRegistered ?? false;
    final shopStateCode = _stateCodeFromGstin(shop?.gstin);
    final supplyStateCode =
        _cleanStateCode(placeOfSupplyStateCode) ??
        _stateCodeFromGstin(customerGstin);
    final interState =
        gstRegistered &&
        shopStateCode != null &&
        supplyStateCode != null &&
        shopStateCode != supplyStateCode;
    final itemCopies = _items
        .map(
          (item) => BillTotals.taxedItem(
            item,
            discountPercent: percent,
            gstRegistered: gstRegistered,
            interState: interState,
          ),
        )
        .toList();
    final totals = BillTotals.fromTaxedItems(
      itemCopies,
      roundOff: settings.roundOffTotal,
    );
    final total = totals.grandTotal;
    final received = paidAmount.clamp(0, total).toDouble();

    final bill = Bill(
      billType: billType,
      customerName: customerName.trim().isEmpty
          ? 'Walk-in Customer'
          : customerName.trim(),
      customerPhone: _cleanOptionalText(customerPhone),
      customerGstin: _cleanOptionalText(customerGstin)?.toUpperCase(),
      customerGstLegalName: _cleanOptionalText(customerGstLegalName),
      customerGstTradeName: _cleanOptionalText(customerGstTradeName),
      customerAddressSnapshot: _cleanOptionalText(customerAddress),
      placeOfSupplyStateCode: supplyStateCode,
      subtotalAmount: totals.subtotal,
      discountPercent: percent,
      discountAmount: totals.discountAmount,
      taxableAmount: totals.taxableAmount,
      cgstAmount: totals.cgstAmount,
      sgstAmount: totals.sgstAmount,
      igstAmount: totals.igstAmount,
      roundOffAmount: totals.roundOffAmount,
      totalAmount: total,
      itemCount: _itemCount,
      isPaid: received >= total - 0.005,
      paymentMethod: paymentMethod,
      paidAmount: received,
      transactionReference: transactionReference,
      duplicatedFromBillUuid: widget.duplicateFromBill?.uuid,
    );

    try {
      final id = await DatabaseHelper.instance.insertBill(bill, itemCopies);
      return (id: id, totals: totals);
    } finally {
      if (mounted) setState(() => _isSavingBill = false);
    }
  }

  Future<void> _openBillSheet() async {
    if (_items.isEmpty || _isOpeningBillSheet || _isSavingBill) return;
    _isOpeningBillSheet = true;
    try {
      await _runBillCheckout();
    } finally {
      _isOpeningBillSheet = false;
    }
  }

  Future<void> _runBillCheckout() async {
    final customers = await DatabaseHelper.instance.getAllCustomers();
    final settings = await DatabaseHelper.instance.getBillSettings();
    if (!mounted) return;
    final cartItems = List<BillItem>.of(_items);
    // GST-inclusive prices: the payable total does not depend on GST
    // registration or inter-state supply, only on discount and round-off.
    BillTotals totalsFor(double discountPercent) => BillTotals.forCart(
      cartItems,
      discountPercent: discountPercent,
      gstRegistered: false,
      interState: false,
      roundOff: settings.roundOffTotal,
    );

    try {
      final draft = await showModalBottomSheet<_BillDraft>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: AppColors.surfaceOf(context),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (_) => _BillCheckoutSheet(
          customers: customers,
          totalsFor: totalsFor,
          itemCount: _itemCount,
          initialBill: widget.duplicateFromBill,
        ),
      );
      if (draft == null) return;
      final saved = await _completeBill(
        customerName: draft.customerName,
        customerPhone: draft.customerPhone,
        billType: draft.billType,
        customerGstin: draft.customerGstin,
        customerGstLegalName: draft.customerGstLegalName,
        customerGstTradeName: draft.customerGstTradeName,
        customerAddress: draft.customerAddress,
        placeOfSupplyStateCode: draft.placeOfSupplyStateCode,
        discountPercent: draft.discountPercent,
        paidAmount: draft.paidAmount,
        paymentMethod: draft.paymentMethod,
        transactionReference: draft.transactionReference,
      );
      if (saved == null || !mounted) return;
      final totalAmount = saved.totals.grandTotal;
      final itemCount = _itemCount;
      // The bill is saved: empty the cart now so no path back to this screen
      // (e.g. Android back on the success dialog) can save it a second time.
      setState(() => _items.clear());
      final startNewBill = await _showBillCreatedDialog(
        billId: saved.id,
        customerName: draft.customerName.trim().isEmpty
            ? 'Walk-in Customer'
            : draft.customerName.trim(),
        totalAmount: totalAmount,
        itemCount: itemCount,
        isPaid: draft.paidAmount >= totalAmount - 0.005,
      );
      if (!mounted) return;
      if (startNewBill) {
        _loadProducts(); // stock changed
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Returns true when the user wants to start another bill right away.
  Future<bool> _showBillCreatedDialog({
    required int billId,
    required String customerName,
    required double totalAmount,
    required int itemCount,
    required bool isPaid,
  }) async {
    final bill = await DatabaseHelper.instance.getBillById(billId);
    final billLabel = bill?.billNumber.isNotEmpty == true
        ? bill!.billNumber
        : 'Bill #$billId';
    if (!mounted) return false;
    final newBill = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BillCreatedDialog(
        bill: bill,
        totalAmount: totalAmount,
        summary:
            '$customerName\n$billLabel • $itemCount item${itemCount != 1 ? 's' : ''} • ${isPaid ? 'Paid' : 'Unpaid'}',
      ),
    );
    return newBill == true;
  }

  void _updateQty(int index, int delta) {
    if (delta > 0) {
      final available = _availableStockForItem(_items[index]);
      if (available != null &&
          exceedsStock(_items[index].quantity + delta, available)) {
        _showStockLimitMessage(_items[index].productName, available);
      }
    }
    setState(() {
      _items[index].quantity += delta;
      if (_items[index].quantity <= 0) _items.removeAt(index);
    });
  }

  void _setQty(int index, double quantity) {
    if (quantity <= 0) return;
    final available = _availableStockForItem(_items[index]);
    if (available != null && exceedsStock(quantity, available)) {
      _showStockLimitMessage(_items[index].productName, available);
    }
    setState(() => _items[index].quantity = quantity);
  }

  String? _cleanOptionalText(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed == null || trimmed.isEmpty || trimmed == '+91') return null;
    return trimmed;
  }

  String? _stateCodeFromGstin(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.length < 2) return null;
    final code = trimmed.substring(0, 2);
    return RegExp(r'^\d{2}$').hasMatch(code) ? code : null;
  }

  String? _cleanStateCode(String? value) {
    final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == null || digits.isEmpty) return null;
    return digits.padLeft(2, '0').substring(0, 2);
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SegmentedButton<BillingEntryMode>(
        segments: [
          ButtonSegment(
            value: BillingEntryMode.scan,
            icon: Icon(Icons.qr_code_scanner_rounded),
            label: Text(context.l10n.navScan),
          ),
          ButtonSegment(
            value: BillingEntryMode.manual,
            icon: Icon(Icons.search_rounded),
            label: Text(context.l10n.search),
          ),
        ],
        selected: {_entryMode},
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.isDark(context)
              ? AppColors.darkSurfaceRaised
              : AppColors.navyLight,
          selectedBackgroundColor: AppColors.amber,
          foregroundColor: Colors.white,
          selectedForegroundColor: Colors.white,
        ),
        onSelectionChanged: (selection) {
          setState(() {
            _entryMode = selection.first;
            _showAddedStatus = false;
          });
          AppSettingsService.instance.setBillingSearchFirst(
            selection.first == BillingEntryMode.manual,
          );
        },
      ),
    );
  }

  Widget _buildEntryPanel(double height) {
    return _entryMode == BillingEntryMode.scan
        ? _buildScanPanel(height)
        : _buildManualPanel(height);
  }

  Widget _buildScanPanel(double height) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.amber.withValues(alpha: 0.5),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error, _) => _ScannerUnavailable(
              message:
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Camera permission is off. Allow it in Settings, or add '
                        'items by search.'
                  : 'Camera is not available. Add items by search.',
              onUseSearch: () {
                setState(() => _entryMode = BillingEntryMode.manual);
                AppSettingsService.instance.setBillingSearchFirst(true);
              },
            ),
          ),
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.amber.withValues(alpha: 0.7),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          if (_showAddedStatus)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    context.l10n.itemAdded,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildManualPanel(double height) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          TextField(
            controller: _productSearchCtrl,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: context.l10n.searchProducts,
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          if (_productSearchCtrl.text.isEmpty && _saleCounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.frequentlySold,
                  style: AppText.caption,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _isLoadingProducts
                ? const Center(child: CircularProgressIndicator())
                : _allProducts.isEmpty
                ? _ManualEmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: context.l10n.addProductsFirst,
                  )
                : _filteredProducts.isEmpty
                ? _ManualEmptyState(
                    icon: Icons.search_off_rounded,
                    message: context.l10n.noMatchingProducts,
                  )
                : ListView.separated(
                    itemCount: _filteredProducts.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final product = _filteredProducts[index];
                      return _ManualProductTile(
                        product: product,
                        onAdd: () => _addProductToBill(product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _entryHintText() {
    if (_entryMode == BillingEntryMode.scan) {
      return _items.isEmpty
          ? context.l10n.pointCamera
          : '${_items.length} item${_items.length != 1 ? 's' : ''} added';
    }
    if (_items.isNotEmpty) {
      return context.l10n.itemsInBill(_items.length);
    }
    return 'Search by product name, code, category or supplier';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final headerSurface = isDark ? AppColors.darkBg : AppColors.navy;
    return PopScope(
      canPop: _items.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await _confirmDiscard();
        if (!discard || !context.mounted) return;
        setState(() => _items.clear());
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: headerSurface,
        appBar: AppBar(
          title: Text(
            widget.duplicateFromBill != null
                ? context.l10n.duplicateBill
                : _entryMode == BillingEntryMode.scan
                ? 'Scan & Bill'
                : context.l10n.manualBill,
          ),
          backgroundColor: headerSurface,
          foregroundColor: Colors.white,
          actions: [
            AppInfoAction(
              title: 'Billing Help',
              intro:
                  'Build the bill first, then complete checkout with customer and payment details.',
              sections: [
                AppInfoSection(
                  title: context.l10n.addItems,
                  points: [
                    'Scan mode reads Storely product labels and barcode values.',
                    'Manual mode lets you search by product name, code, category, or supplier.',
                    'Use quantity controls on each bill row before completing the bill.',
                  ],
                ),
                AppInfoSection(
                  title: context.l10n.completeBill,
                  points: [
                    'Before Generate Bill, this screen is your editable draft.',
                    'Complete Bill opens checkout for customer, discount, and payment details.',
                    'Saved bills keep price, GST, and profit snapshots from the moment of billing.',
                    'For corrections after saving, cancel the old bill and duplicate it as a new bill.',
                    'Selling more than the recorded stock shows a warning; stock then goes negative.',
                  ],
                ),
              ],
            ),
            if (_heldCount > 0)
              TextButton.icon(
                onPressed: _openHeldBills,
                icon: const Icon(
                  Icons.inventory_rounded,
                  color: AppColors.amber,
                ),
                label: Text(
                  context.l10n.heldCount(_heldCount),
                  style: const TextStyle(color: AppColors.amber),
                ),
              ),
            if (_items.isNotEmpty)
              IconButton(
                tooltip: context.l10n.holdBill,
                onPressed: _holdCart,
                icon: const Icon(
                  Icons.pause_circle_outline_rounded,
                  color: AppColors.amber,
                ),
              ),
            if (_items.isNotEmpty)
              TextButton(
                onPressed: _clearWithUndo,
                child: Text(
                  context.l10n.clear,
                  style: TextStyle(color: AppColors.amber),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 520;
                  final panelHeight = (constraints.maxHeight * 0.42).clamp(
                    180.0,
                    280.0,
                  );

                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildModeSelector(),
                      _buildEntryPanel(panelHeight),
                      if (!compact) ...[
                        const SizedBox(height: 8),
                        Text(
                          _entryHintText(),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else
                        const SizedBox(height: 8),
                      Expanded(child: _buildBillItemsPanel()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        // ── Bottom Total + Complete Button ──
        bottomNavigationBar: _items.isNotEmpty
            ? Container(
                color: AppColors.bgOf(context),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.isDark(context)
                          ? AppColors.darkSurfaceRaised
                          : AppColors.navy,
                      borderRadius: AppRadius.lgRadius,
                    ),
                    child: Row(
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.total,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              rupees(_subtotal),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        TestKeys.tag(
                          TestKeys.scanBillBtn,
                          FilledButton.icon(
                            onPressed: _openBillSheet,
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: Text(
                              context.l10n.bill,
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.amber,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          button: true,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.discardBillQ),
        content: Text(
          '${_items.length} item${_items.length == 1 ? '' : 's'} in the cart '
          'will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.keepBilling),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(context.l10n.discard),
          ),
        ],
      ),
    );
    return discard == true;
  }

  void _clearWithUndo() {
    final removed = List<BillItem>.of(_items);
    setState(() => _items.clear());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Cleared ${removed.length} item${removed.length == 1 ? '' : 's'}',
          ),
          action: SnackBarAction(
            label: context.l10n.undo,
            onPressed: () {
              if (!mounted || _items.isNotEmpty) return;
              setState(() => _items.addAll(removed));
            },
          ),
        ),
      );
  }

  Widget _buildBillItemsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
      ),
      child: _items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.qr_code_scanner,
                    size: 48,
                    color: AppColors.textMuted.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.noItemsYet,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
              itemCount: _items.length,
              itemBuilder: (_, i) {
                final item = _items[i];
                return Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceOf(context),
                    borderRadius: AppRadius.mdRadius,
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.priceLabel,
                              style: TextStyle(
                                color: AppColors.inkMutedOf(context),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Qty controls
                      Container(
                        decoration: BoxDecoration(
                          color: AppColors.softBgOf(context),
                          borderRadius: AppRadius.smRadius,
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => _updateQty(i, -1),
                              icon: const Icon(Icons.remove, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: _QuantityInput(
                                key: ObjectKey(item),
                                quantity: item.quantity,
                                onChanged: (quantity) => _setQty(i, quantity),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _updateQty(i, 1),
                              icon: const Icon(Icons.add, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Subtotal
                      Text(
                        rupees(item.subtotal),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
