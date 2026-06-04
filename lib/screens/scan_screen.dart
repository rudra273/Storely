import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../models/product.dart';

part 'scan/manual_product_widgets.dart';
part 'scan/customer_suggestion_list.dart';
part 'scan/bill_summary_widgets.dart';
part 'scan/bill_draft.dart';
part 'scan/bill_checkout_sheet.dart';

enum BillingEntryMode { scan, manual }

class ScanScreen extends StatefulWidget {
  final BillingEntryMode initialMode;
  final Bill? duplicateFromBill;

  const ScanScreen({
    super.key,
    this.initialMode = BillingEntryMode.scan,
    this.duplicateFromBill,
  });
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _scanCooldown = Duration(seconds: 1);
  static const _invalidScanCooldown = Duration(seconds: 2);

  final _productSearchCtrl = TextEditingController();
  final List<BillItem> _items = [];
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  late BillingEntryMode _entryMode;
  bool _isProcessing = false;
  bool _isSavingBill = false;
  bool _isLoadingProducts = true;
  bool _showAddedStatus = false;
  String? _lastScanned;

  double get _subtotal => _items.fold(0, (sum, i) => sum + i.subtotal);
  int get _itemCount =>
      _items.fold<double>(0, (sum, i) => sum + i.quantity).round();

  @override
  void initState() {
    super.initState();
    _entryMode = widget.duplicateFromBill == null
        ? widget.initialMode
        : BillingEntryMode.manual;
    if (widget.duplicateFromBill != null) {
      _items.addAll(widget.duplicateFromBill!.items.map(_copyItemForNewBill));
    }
    _productSearchCtrl.addListener(_applyProductSearch);
    _loadProducts();
  }

  @override
  void dispose() {
    _productSearchCtrl.removeListener(_applyProductSearch);
    _productSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    if (!mounted) return;
    setState(() {
      _allProducts = products;
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
    if (_isProcessing) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    if (raw == _lastScanned) return; // Avoid duplicate rapid scans

    setState(() => _isProcessing = true);
    _lastScanned = raw;

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
      if (available <= 0 || currentQty + 1 > available) {
        _showStockLimitMessage(item.productName, available);
        return;
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
      if (product.id == productId) return product.quantity;
    }
    return null;
  }

  void _showStockLimitMessage(String productName, double available) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            available <= 0
                ? '"$productName" is out of stock'
                : 'Only ${_formatQuantityInput(available)} available for "$productName"',
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
        _lastScanned = null;
      });
    });
  }

  Future<int?> _completeBill({
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
  }) async {
    if (_items.isEmpty) return null;
    if (_isSavingBill) return null;

    setState(() => _isSavingBill = true);
    final subtotal = _subtotal;
    final percent = discountPercent.clamp(0, 100).toDouble();
    final discount = subtotal * percent / 100;
    final total = subtotal - discount;
    final shop = await DatabaseHelper.instance.getShopProfile();
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
          (item) => _taxAdjustedItemCopy(
            item,
            discountPercent: percent,
            gstRegistered: gstRegistered,
            interState: interState,
          ),
        )
        .toList();
    final received = paidAmount.clamp(0, total).toDouble();
    final taxableTotal = itemCopies.fold(
      0.0,
      (sum, item) => sum + item.totalTaxableValue,
    );
    final cgstTotal = itemCopies.fold(0.0, (sum, item) => sum + item.totalCgst);
    final sgstTotal = itemCopies.fold(0.0, (sum, item) => sum + item.totalSgst);
    final igstTotal = itemCopies.fold(0.0, (sum, item) => sum + item.totalIgst);

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
      subtotalAmount: subtotal,
      discountPercent: percent,
      discountAmount: discount,
      taxableAmount: taxableTotal,
      cgstAmount: cgstTotal,
      sgstAmount: sgstTotal,
      igstAmount: igstTotal,
      totalAmount: total,
      itemCount: _itemCount,
      isPaid: received >= total,
      paymentMethod: paymentMethod,
      paidAmount: received,
      duplicatedFromBillUuid: widget.duplicateFromBill?.uuid,
    );

    try {
      return await DatabaseHelper.instance.insertBill(bill, itemCopies);
    } finally {
      if (mounted) setState(() => _isSavingBill = false);
    }
  }

  BillItem _taxAdjustedItemCopy(
    BillItem item, {
    required double discountPercent,
    required bool gstRegistered,
    required bool interState,
  }) {
    final quantity = item.quantity;
    final gstPercent = item.gstPercentSnapshot ?? 0.0;
    final discountFactor = (1 - discountPercent / 100).clamp(0.0, 1.0);
    final discountedUnitGross = item.sellingPriceSnapshot * discountFactor;
    final taxableUnit = gstRegistered && gstPercent > 0
        ? discountedUnitGross / (1 + gstPercent / 100)
        : discountedUnitGross;
    final gstUnit = gstRegistered
        ? (discountedUnitGross - taxableUnit).clamp(0.0, double.infinity)
        : 0.0;
    final cgstUnit = gstRegistered && !interState ? gstUnit / 2 : 0.0;
    final sgstUnit = gstRegistered && !interState ? gstUnit / 2 : 0.0;
    final igstUnit = gstRegistered && interState ? gstUnit : 0.0;

    return BillItem(
      uuid: item.uuid,
      shopId: item.shopId,
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
      gstSnapshot: _roundMoney(gstUnit),
      gstPercentSnapshot: item.gstPercentSnapshot,
      taxableValueSnapshot: _roundMoney(taxableUnit),
      cgstAmountSnapshot: _roundMoney(cgstUnit),
      sgstAmountSnapshot: _roundMoney(sgstUnit),
      igstAmountSnapshot: _roundMoney(igstUnit),
      wasDirectPrice: item.wasDirectPrice,
      quantity: quantity,
    );
  }

  Future<void> _openBillSheet() async {
    if (_items.isEmpty) return;

    final customers = await DatabaseHelper.instance.getAllCustomers();
    if (!mounted) return;

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
          subtotal: _subtotal,
          itemCount: _itemCount,
          initialBill: widget.duplicateFromBill,
        ),
      );
      if (draft == null) return;
      final billId = await _completeBill(
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
      );
      if (billId == null || !mounted) return;
      await _showBillCreatedDialog(
        billId: billId,
        customerName: draft.customerName.trim().isEmpty
            ? 'Walk-in Customer'
            : draft.customerName.trim(),
        totalAmount:
            _subtotal * (1 - draft.discountPercent.clamp(0, 100) / 100),
        itemCount: _itemCount,
        isPaid:
            draft.paidAmount >=
            _subtotal * (1 - draft.discountPercent.clamp(0, 100) / 100),
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _showBillCreatedDialog({
    required int billId,
    required String customerName,
    required double totalAmount,
    required int itemCount,
    required bool isPaid,
  }) async {
    final bills = await DatabaseHelper.instance.getAllBills();
    final bill = bills.where((bill) => bill.id == billId).firstOrNull;
    final billLabel = bill?.billNumber.isNotEmpty == true
        ? bill!.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-')
        : 'Bill #$billId';
    if (mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle,
            color: AppColors.success,
            size: 48,
          ),
          title: const Text('Bill Created!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '₹${totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$customerName\n$billLabel • $itemCount item${itemCount != 1 ? 's' : ''} • ${isPaid ? 'Paid' : 'Unpaid'}',
                style: TextStyle(color: AppColors.textMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brandOf(ctx),
                foregroundColor: AppColors.isDark(ctx)
                    ? Colors.black
                    : Colors.white,
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  void _updateQty(int index, int delta) {
    if (delta > 0) {
      final available = _availableStockForItem(_items[index]);
      if (available != null && _items[index].quantity + delta > available) {
        _showStockLimitMessage(_items[index].productName, available);
        return;
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
    if (available != null && quantity > available) {
      _showStockLimitMessage(_items[index].productName, available);
      setState(() => _items[index].quantity = available);
      return;
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

  double _roundMoney(double value) => double.parse(value.toStringAsFixed(2));

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SegmentedButton<BillingEntryMode>(
        segments: const [
          ButtonSegment(
            value: BillingEntryMode.scan,
            icon: Icon(Icons.qr_code_scanner_rounded),
            label: Text('Scan'),
          ),
          ButtonSegment(
            value: BillingEntryMode.manual,
            icon: Icon(Icons.search_rounded),
            label: Text('Search'),
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
          MobileScanner(onDetect: _onDetect),
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
                  child: const Text(
                    'Item added!',
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
            decoration: const InputDecoration(
              labelText: 'Search products',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _isLoadingProducts
                ? const Center(child: CircularProgressIndicator())
                : _allProducts.isEmpty
                ? _ManualEmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: 'Add products before manual billing',
                  )
                : _filteredProducts.isEmpty
                ? _ManualEmptyState(
                    icon: Icons.search_off_rounded,
                    message: 'No matching products',
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
          ? 'Point camera at product QR code'
          : '${_items.length} item${_items.length != 1 ? 's' : ''} added';
    }
    if (_items.isNotEmpty) {
      return '${_items.length} item${_items.length != 1 ? 's' : ''} in bill';
    }
    return 'Search by product name, code, category or supplier';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final headerSurface = isDark ? AppColors.darkBg : AppColors.navy;
    return Scaffold(
      backgroundColor: headerSurface,
      appBar: AppBar(
        title: Text(
          widget.duplicateFromBill != null
              ? 'Duplicate Bill'
              : _entryMode == BillingEntryMode.scan
              ? 'Scan & Bill'
              : 'Manual Bill',
        ),
        backgroundColor: headerSurface,
        foregroundColor: Colors.white,
        actions: [
          const AppInfoAction(
            title: 'Billing Help',
            intro:
                'Build the bill first, then complete checkout with customer and payment details.',
            sections: [
              AppInfoSection(
                title: 'Add items',
                points: [
                  'Scan mode reads Storely product labels and barcode values.',
                  'Manual mode lets you search by product name, code, category, or supplier.',
                  'Use quantity controls on each bill row before completing the bill.',
                ],
              ),
              AppInfoSection(
                title: 'Complete bill',
                points: [
                  'Before Generate Bill, this screen is your editable draft.',
                  'Complete Bill opens checkout for customer, discount, and payment details.',
                  'Saved bills keep price, GST, and profit snapshots from the moment of billing.',
                  'For corrections after saving, cancel the old bill and duplicate it as a new bill.',
                  'If stock is insufficient, bill creation is blocked before saving.',
                ],
              ),
            ],
          ),
          if (_items.isNotEmpty)
            TextButton(
              onPressed: () => setState(() => _items.clear()),
              child: const Text(
                'Clear',
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
                            'Total',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            '₹${_subtotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _openBillSheet,
                        icon: const Icon(Icons.receipt_long_rounded),
                        label: const Text(
                          'Bill',
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
                    ],
                  ),
                ),
              ),
            )
          : null,
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
                    'No items added yet',
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
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            SizedBox(
                              width: 44,
                              child: TextFormField(
                                key: ValueKey(
                                  '${item.productName}-${item.mrp}-${item.quantity}',
                                ),
                                initialValue: _formatQuantityInput(
                                  item.quantity,
                                ),
                                textAlign: TextAlign.center,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,3}'),
                                  ),
                                ],
                                decoration: const InputDecoration(
                                  isDense: true,
                                  filled: false,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 8,
                                  ),
                                  border: InputBorder.none,
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                                onChanged: (value) {
                                  final quantity = double.tryParse(value);
                                  if (quantity != null) {
                                    _setQty(i, quantity);
                                  }
                                },
                              ),
                            ),
                            IconButton(
                              onPressed: () => _updateQty(i, 1),
                              icon: const Icon(Icons.add, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Subtotal
                      Text(
                        '₹${item.subtotal.toStringAsFixed(2)}',
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
