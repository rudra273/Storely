import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../main.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _scanCooldown = Duration(seconds: 1);
  static const _invalidScanCooldown = Duration(seconds: 2);

  final MobileScannerController _camController = MobileScannerController();
  final List<BillItem> _items = [];
  bool _isProcessing = false;
  bool _isSavingBill = false;
  bool _showAddedStatus = false;
  String? _lastScanned;

  double get _subtotal => _items.fold(0, (sum, i) => sum + i.subtotal);
  int get _itemCount => _items.fold(0, (sum, i) => sum + i.quantity);

  @override
  void dispose() {
    _camController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
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
      final mrp = (data['mrp'] as num?)?.toDouble() ?? 0;
      final unit = _cleanOptionalText(data['unit'] as String?);

      // Check if already in list
      final existing = _items.indexWhere(
        (i) => i.productName.toLowerCase() == name.toLowerCase(),
      );

      setState(() {
        if (existing >= 0) {
          _items[existing].quantity++;
          _items[existing].unit ??= unit;
        } else {
          _items.add(BillItem(productName: name, mrp: mrp, unit: unit));
        }
        _showAddedStatus = true;
      });

      HapticFeedback.mediumImpact();
      _allowNextScanAfter(_scanCooldown);
    } catch (_) {
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
    required double discountPercent,
    required bool isPaid,
  }) async {
    if (_items.isEmpty) return null;
    if (_isSavingBill) return null;

    setState(() => _isSavingBill = true);
    final subtotal = _subtotal;
    final percent = discountPercent.clamp(0, 100).toDouble();
    final discount = subtotal * percent / 100;
    final total = subtotal - discount;
    final itemCopies = _items
        .map(
          (item) => BillItem(
            productName: item.productName,
            mrp: item.mrp,
            unit: item.unit,
            quantity: item.quantity,
          ),
        )
        .toList();

    final bill = Bill(
      customerName: customerName.trim().isEmpty
          ? 'Walk-in Customer'
          : customerName.trim(),
      customerPhone: _cleanOptionalText(customerPhone),
      subtotalAmount: subtotal,
      discountPercent: percent,
      discountAmount: discount,
      totalAmount: total,
      itemCount: _itemCount,
      isPaid: isPaid,
    );

    try {
      return await DatabaseHelper.instance.insertBill(bill, itemCopies);
    } finally {
      if (mounted) setState(() => _isSavingBill = false);
    }
  }

  Future<void> _openBillSheet() async {
    if (_items.isEmpty) return;

    final customerController = TextEditingController();
    final phoneController = TextEditingController(text: '+91 ');
    final discountController = TextEditingController();
    var discountPercent = 0.0;
    var isPaid = true;

    try {
      final draft = await showModalBottomSheet<_BillDraft>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (ctx, setSheetState) {
              final percent = discountPercent.clamp(0, 100).toDouble();
              final discount = _subtotal * percent / 100;
              final total = _subtotal - discount;
              return SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    MediaQuery.viewInsetsOf(ctx).bottom + 20,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Create Bill',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: customerController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Customer name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Phone number (optional)',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _BillSummaryRow(
                        label: 'Subtotal',
                        value: '₹${_subtotal.toStringAsFixed(2)}',
                      ),
                      _BillSummaryRow(label: 'Items', value: '$_itemCount'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: discountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          TextInputFormatter.withFunction((oldValue, newValue) {
                            final isValid = RegExp(
                              r'^\d*\.?\d{0,2}$',
                            ).hasMatch(newValue.text);
                            return isValid ? newValue : oldValue;
                          }),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Discount percentage',
                          suffixText: '%',
                        ),
                        onChanged: (value) {
                          setSheetState(() {
                            discountPercent = double.tryParse(value) ?? 0;
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: true,
                            icon: Icon(Icons.check_circle_outline),
                            label: Text('Paid'),
                          ),
                          ButtonSegment(
                            value: false,
                            icon: Icon(Icons.pending_actions_outlined),
                            label: Text('Unpaid'),
                          ),
                        ],
                        selected: {isPaid},
                        onSelectionChanged: (value) =>
                            setSheetState(() => isPaid = value.first),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cream,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: [
                            _BillSummaryRow(
                              label:
                                  'Discount (${percent.toStringAsFixed(2)}%)',
                              value: '- ₹${discount.toStringAsFixed(2)}',
                            ),
                            const Divider(height: 20),
                            _BillSummaryRow(
                              label: 'Grand Total',
                              value: '₹${total.toStringAsFixed(2)}',
                              isTotal: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(
                              sheetContext,
                              _BillDraft(
                                customerName: customerController.text,
                                customerPhone: phoneController.text,
                                discountPercent: percent,
                                isPaid: isPaid,
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: const Text('Generate Bill'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.amber,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      if (draft == null) return;
      final billId = await _completeBill(
        customerName: draft.customerName,
        customerPhone: draft.customerPhone,
        discountPercent: draft.discountPercent,
        isPaid: draft.isPaid,
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
        isPaid: draft.isPaid,
      );
    } finally {
      customerController.dispose();
      phoneController.dispose();
      discountController.dispose();
    }
  }

  Future<void> _showBillCreatedDialog({
    required int billId,
    required String customerName,
    required double totalAmount,
    required int itemCount,
    required bool isPaid,
  }) async {
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
                '$customerName\nBill #$billId • $itemCount item${itemCount != 1 ? 's' : ''} • ${isPaid ? 'Paid' : 'Unpaid'}',
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
  }

  void _updateQty(int index, int delta) {
    setState(() {
      _items[index].quantity += delta;
      if (_items[index].quantity <= 0) _items.removeAt(index);
    });
  }

  void _setQty(int index, int quantity) {
    if (quantity < 1) return;
    setState(() => _items[index].quantity = quantity);
  }

  String? _cleanOptionalText(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed == null || trimmed.isEmpty || trimmed == '+91') return null;
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        title: const Text(
          'Scan & Bill',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        actions: [
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
          // ── Camera Preview ──
          Container(
            height: 280,
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
                MobileScanner(controller: _camController, onDetect: _onDetect),
                // Scan overlay
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
                // Status indicator
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
                          '✓ Item added!',
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
          ),
          const SizedBox(height: 8),
          Text(
            _items.isEmpty
                ? 'Point camera at product QR code'
                : '${_items.length} item${_items.length != 1 ? 's' : ''} scanned',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 12),
          // ── Scanned Items List ──
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.cream,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                            'No items scanned yet',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 14,
                            ),
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
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
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
                                        color: AppColors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Qty controls
                              Container(
                                decoration: BoxDecoration(
                                  color: AppColors.cream,
                                  borderRadius: BorderRadius.circular(10),
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
                                        initialValue: '${item.quantity}',
                                        textAlign: TextAlign.center,
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
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
                                          final quantity = int.tryParse(value);
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
            ),
          ),
        ],
      ),
      // ── Bottom Total + Complete Button ──
      bottomNavigationBar: _items.isNotEmpty
          ? Container(
              color: AppColors.cream,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(16),
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
}

class _BillSummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;

  const _BillSummaryRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: isTotal ? AppColors.textDark : AppColors.textMuted,
              fontSize: isTotal ? 16 : 14,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: isTotal ? AppColors.textDark : AppColors.textMuted,
              fontSize: isTotal ? 20 : 14,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillDraft {
  final String customerName;
  final String? customerPhone;
  final double discountPercent;
  final bool isPaid;

  const _BillDraft({
    required this.customerName,
    required this.customerPhone,
    required this.discountPercent,
    required this.isPaid,
  });
}
