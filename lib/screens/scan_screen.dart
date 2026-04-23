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
  bool _showAddedStatus = false;
  String? _lastScanned;

  double get _total => _items.fold(0, (sum, i) => sum + i.subtotal);

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

      // Check if already in list
      final existing = _items.indexWhere(
        (i) => i.productName.toLowerCase() == name.toLowerCase(),
      );

      setState(() {
        if (existing >= 0) {
          _items[existing].quantity++;
        } else {
          _items.add(BillItem(productName: name, mrp: mrp));
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

  Future<void> _completeBill() async {
    if (_items.isEmpty) return;

    final bill = Bill(
      totalAmount: _total,
      itemCount: _items.fold(0, (sum, i) => sum + i.quantity),
    );

    await DatabaseHelper.instance.insertBill(bill, _items);

    if (mounted) {
      showDialog(
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
                '₹${_total.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_items.length} item${_items.length != 1 ? 's' : ''}',
                style: TextStyle(color: AppColors.textMuted),
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
                                      '₹${item.mrp.toStringAsFixed(2)} each',
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
                                    Text(
                                      '${item.quantity}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
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
                            '₹${_total.toStringAsFixed(2)}',
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
                        onPressed: _completeBill,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text(
                          'Complete Bill',
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
