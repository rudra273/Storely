import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/database_helper.dart';
import '../models/purchase_document.dart';
import '../models/supplier.dart';
import '../services/api/api_client.dart';
import '../services/cloud_service.dart';
import '../utils/decimal_text.dart';
import 'products_screen.dart' show openNewPurchaseFlow;
import 'supplier_payments_screen.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  final bool? isCloudLinkedOverride;

  const PurchaseHistoryScreen({super.key, this.isCloudLinkedOverride});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  late Future<List<PurchaseDocument>> _documents;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _documents = _loadPage();
    CloudService.instance.state.addListener(_cloudChanged);
  }

  Future<List<PurchaseDocument>> _loadPage() =>
      (DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true)
      ? DatabaseHelper.instance.getPurchaseDocuments(offset: _page * 50)
      : Future.value(const []);

  void _cloudChanged() {
    if (mounted) {
      setState(() {
        _documents = _loadPage();
      });
    }
  }

  @override
  void dispose() {
    CloudService.instance.state.removeListener(_cloudChanged);
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = _loadPage();
    setState(() {
      _documents = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final allowed =
        DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchases'),
        actions: [
          IconButton(
            tooltip: 'Refresh purchases',
            onPressed: () async {
              try {
                await _refresh();
              } catch (_) {}
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: allowed
          ? FloatingActionButton.extended(
              heroTag: 'new-purchase',
              onPressed: () async {
                await openNewPurchaseFlow(context);
                if (mounted) await _refresh();
              },
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('New purchase'),
            )
          : null,
      body: !allowed
          ? const Center(
              child: Text(
                'Purchase history is available to owners and admins.',
              ),
            )
          : FutureBuilder<List<PurchaseDocument>>(
              future: _documents,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Purchases could not be loaded. ${snapshot.error}',
                    ),
                  );
                }
                final documents = snapshot.data ?? [];
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const Text(
                        'Saved purchases from this phone and the web. Older stock entries remain in stock history.',
                      ),
                      const SizedBox(height: 12),
                      if (documents.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('No purchase documents on this page.'),
                        ),
                      for (final document in documents)
                        Card(
                          child: ListTile(
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    document.supplier ?? 'No supplier',
                                  ),
                                ),
                                if (document.isReversed)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.errorContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Reversed',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onErrorContainer,
                                      ),
                                    ),
                                  )
                                else if (document.returns.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.tertiaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Returned',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onTertiaryContainer,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Text(
                              '${document.date} · ${_status(document.syncState)}',
                            ),
                            trailing: Text(
                              purchaseMoney(document.total ?? document.subtotal),
                            ),
                            onTap: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => _PurchaseDetails(
                                    document: document,
                                    isCloudLinkedOverride:
                                        widget.isCloudLinkedOverride,
                                  ),
                                ),
                              );
                              if (mounted) await _refresh();
                            },
                          ),
                        ),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _page == 0
                                ? null
                                : () {
                                    _page--;
                                    _cloudChanged();
                                  },
                            child: const Text('Previous'),
                          ),
                          TextButton(
                            onPressed: documents.length < 50
                                ? null
                                : () {
                                    _page++;
                                    _cloudChanged();
                                  },
                            child: const Text('More purchases'),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

String _status(String state) => switch (state) {
  'synced' => 'Document synced',
  'error' => 'Sync needs review',
  'local' => 'Local only',
  _ => 'Waiting for document sync',
};

String _paymentStatusLabel(String status) =>
    const {
      'not_recorded': 'Not recorded',
      'unpaid': 'Unpaid',
      'partial': 'Part paid',
      'paid': 'Paid',
    }[status] ??
    status;

String _methodLabel(String? method) =>
    const {
      'cash': 'Cash',
      'upi': 'UPI',
      'card': 'Card',
      'bank_transfer': 'Bank transfer',
      'online': 'Online',
    }[method] ??
    (method ?? '');

String _friendlyPurchaseError(Object error) {
  if (error is ApiException) {
    return switch (error.code) {
      'payments_recorded' =>
        'Cannot reverse this purchase while supplier payments are recorded against it. Reverse those payments first.',
      'stock_used' =>
        'Cannot complete this action because some of the received stock has already been sold or adjusted.',
      'returns_recorded' =>
        'Cannot reverse this purchase because purchase returns (debit notes) have already been recorded against it.',
      'purchase_reversed' => 'This purchase has already been reversed.',
      'refund_method_required' =>
        'Select a refund method because the return exceeds the remaining balance due.',
      _ => error.message,
    };
  }
  return error.toString();
}

class _PurchaseDetails extends StatefulWidget {
  final PurchaseDocument document;
  final bool? isCloudLinkedOverride;

  const _PurchaseDetails({
    required this.document,
    this.isCloudLinkedOverride,
  });

  @override
  State<_PurchaseDetails> createState() => _PurchaseDetailsState();
}

class _PurchaseDetailsState extends State<_PurchaseDetails> {
  static const _uuid = Uuid();
  late PurchaseDocument _document;
  bool _busy = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _document = widget.document;
  }

  bool get _isCloudLinked =>
      widget.isCloudLinkedOverride ?? CloudService.instance.state.value.isCloudLinkedAdmin;

  Future<void> _reloadFromDb() async {
    final fresh = await DatabaseHelper.instance.getPurchaseDocumentByUuid(
      _document.uuid,
    );
    if (mounted && fresh != null) {
      setState(() => _document = fresh);
    }
  }

  Future<void> _openPaySupplier() async {
    final supplierUuid = _document.supplierUuid;
    if (supplierUuid == null || supplierUuid.isEmpty) return;
    SupplierProfile? profile;
    try {
      final profiles = await DatabaseHelper.instance.getSupplierProfiles();
      for (final p in profiles) {
        if (p.uuid == supplierUuid) {
          profile = p;
          break;
        }
      }
    } catch (_) {}
    profile ??= SupplierProfile(
      uuid: supplierUuid,
      name: _document.supplier ?? 'Supplier',
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SupplierPaymentsScreen(
          supplier: profile!,
          initialPurchaseUuid: _document.uuid,
          isCloudLinkedOverride: widget.isCloudLinkedOverride,
        ),
      ),
    );
    await _reloadFromDb();
  }

  Future<void> _openRecordPaymentTermsDialog() async {
    final taxController = TextEditingController(text: _document.taxAmount);
    final chargesController = TextEditingController(
      text: _document.chargesAmount,
    );
    final discountController = TextEditingController(
      text: _document.discountAmount,
    );
    final paidController = TextEditingController();
    String status = 'unpaid';
    String method = 'cash';
    DateTime? dueDate = _document.dueDate == null
        ? null
        : DateTime.tryParse(_document.dueDate!);
    String? dialogError;

    final payload = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          String day(DateTime d) => d.toIso8601String().substring(0, 10);
          return AlertDialog(
            title: const Text('Record payment terms'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (dialogError != null) ...[
                    Text(
                      dialogError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: taxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'GST / Tax (₹)'),
                  ),
                  TextField(
                    controller: chargesController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Other charges (₹)',
                    ),
                  ),
                  TextField(
                    controller: discountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Discount (₹)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(
                      labelText: 'Payment status',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                      DropdownMenuItem(
                        value: 'partial',
                        child: Text('Part paid'),
                      ),
                      DropdownMenuItem(value: 'paid', child: Text('Paid')),
                    ],
                    onChanged: (v) => setDialogState(() => status = v ?? 'unpaid'),
                  ),
                  if (status == 'partial')
                    TextField(
                      controller: paidController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount paid now (₹)',
                      ),
                    ),
                  if (status == 'partial' || status == 'paid')
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: const InputDecoration(
                        labelText: 'Payment method',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'upi', child: Text('UPI')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(
                          value: 'bank_transfer',
                          child: Text('Bank transfer'),
                        ),
                        DropdownMenuItem(
                          value: 'online',
                          child: Text('Online'),
                        ),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => method = v ?? 'cash'),
                    ),
                  TextButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: dueDate ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => dueDate = picked);
                      }
                    },
                    child: Text(
                      dueDate == null
                          ? 'Set due date (optional)'
                          : 'Due date: ${day(dueDate!)}',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final tax = taxController.text.trim().isEmpty
                      ? '0'
                      : taxController.text.trim();
                  final charges = chargesController.text.trim().isEmpty
                      ? '0'
                      : chargesController.text.trim();
                  final discount = discountController.text.trim().isEmpty
                      ? '0'
                      : discountController.text.trim();
                  final decimalRe = RegExp(r'^\d+(\.\d{1,2})?$');
                  if (!decimalRe.hasMatch(tax) ||
                      !decimalRe.hasMatch(charges) ||
                      !decimalRe.hasMatch(discount)) {
                    setDialogState(
                      () => dialogError =
                          'Enter valid amounts with up to two decimals.',
                    );
                    return;
                  }
                  if (status == 'partial') {
                    final paid = paidController.text.trim();
                    if (!decimalRe.hasMatch(paid) ||
                        decimalScaledInteger(paid, scale: 2) <= BigInt.zero) {
                      setDialogState(
                        () => dialogError =
                            'Enter a valid partial payment amount.',
                      );
                      return;
                    }
                  }
                  Navigator.of(context).pop(<String, Object?>{
                    'tax_amount': tax,
                    'charges_amount': charges,
                    'discount_amount': discount,
                    'due_date': dueDate == null ? null : day(dueDate!),
                    'payment_status': status,
                    if (status == 'partial')
                      'paid_amount': paidController.text.trim(),
                    if (status == 'partial' || status == 'paid')
                      'payment_method': method,
                  });
                },
                child: const Text('Save terms'),
              ),
            ],
          );
        },
      ),
    );
    taxController.dispose();
    chargesController.dispose();
    discountController.dispose();
    paidController.dispose();

    if (payload == null || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await CloudService.instance.recordPurchasePaymentTerms(
        _document.uuid,
        payload,
      );
      await _reloadFromDb();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment terms recorded.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = _friendlyPurchaseError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReturnItemsSheet() async {
    final returnableItems = _document.lineItems
        .where((i) => i.hasReturnableQuantity)
        .toList();
    if (returnableItems.isEmpty) return;

    final qtyControllers = {
      for (final item in returnableItems) item.uuid: TextEditingController(),
    };
    final reasonController = TextEditingController();
    final taxController = TextEditingController(text: '0.00');
    String refundMethod = 'cash';
    String? sheetError;

    BigInt balanceDueCents() {
      if (_document.isNotRecorded || _document.balanceDue == null) {
        return BigInt.zero;
      }
      return decimalScaledInteger(_document.balanceDue!, scale: 2);
    }

    BigInt computeReturnTotalCents() {
      var subtotal = BigInt.zero;
      for (final item in returnableItems) {
        final raw = qtyControllers[item.uuid]!.text.trim();
        if (raw.isEmpty) continue;
        if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(raw)) continue;
        subtotal += purchaseLineCents(raw, item.unitCost);
      }
      final taxRaw = taxController.text.trim();
      final taxCents = RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(taxRaw)
          ? decimalScaledInteger(taxRaw, scale: 2)
          : BigInt.zero;
      return subtotal + taxCents;
    }

    final payload = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final totalCents = computeReturnTotalCents();
          final dueCents = balanceDueCents();
          final needsRefundMethod =
              !_document.isNotRecorded && totalCents > dueCents && totalCents > BigInt.zero;
          final refundCents = needsRefundMethod
              ? totalCents - dueCents
              : BigInt.zero;
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Return items (Debit note)',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  if (sheetError != null) ...[
                    Text(
                      sheetError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (final item in returnableItems) ...[
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              Text(
                                'Returnable: ${item.returnableQuantity} ${item.unitName ?? ''} · ${purchaseMoney(item.unitCost)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 110,
                          child: TextField(
                            controller: qtyControllers[item.uuid],
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Return qty',
                              isDense: true,
                            ),
                            onChanged: (_) => setSheetState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason (min 3 characters)',
                    ),
                  ),
                  TextField(
                    controller: taxController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tax / GST credit (₹, optional)',
                    ),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Return total: ${purchaseMoney(purchaseCentsText(totalCents))}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (needsRefundMethod) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Refund due from supplier: ${purchaseMoney(purchaseCentsText(refundCents))}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: refundMethod,
                      decoration: const InputDecoration(
                        labelText: 'Refund method',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'upi', child: Text('UPI')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(
                          value: 'bank_transfer',
                          child: Text('Bank transfer'),
                        ),
                        DropdownMenuItem(
                          value: 'online',
                          child: Text('Online'),
                        ),
                      ],
                      onChanged: (v) =>
                          setSheetState(() => refundMethod = v ?? 'cash'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          final reason = reasonController.text.trim();
                          if (reason.length < 3) {
                            setSheetState(
                              () => sheetError =
                                  'Enter a reason of at least 3 characters.',
                            );
                            return;
                          }
                          final itemsPayload = <Map<String, Object?>>[];
                          for (final item in returnableItems) {
                            final raw = qtyControllers[item.uuid]!.text.trim();
                            if (raw.isEmpty) continue;
                            if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(raw)) {
                              setSheetState(
                                () => sheetError =
                                    'Invalid quantity for ${item.productName}.',
                              );
                              return;
                            }
                            final scaled = decimalScaledInteger(raw, scale: 4);
                            if (scaled <= BigInt.zero) continue;
                            final maxScaled = decimalScaledInteger(
                              item.returnableQuantity,
                              scale: 4,
                            );
                            if (scaled > maxScaled) {
                              setSheetState(
                                () => sheetError =
                                    'Return qty for ${item.productName} exceeds ${item.returnableQuantity}.',
                              );
                              return;
                            }
                            itemsPayload.add({
                              'purchase_item_uuid': item.uuid,
                              'quantity': normalizePurchaseDecimal(raw),
                            });
                          }
                          if (itemsPayload.isEmpty) {
                            setSheetState(
                              () => sheetError =
                                  'Enter a return quantity for at least one item.',
                            );
                            return;
                          }
                          final taxRaw = taxController.text.trim().isEmpty
                              ? '0.00'
                              : taxController.text.trim();
                          if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(taxRaw)) {
                            setSheetState(
                              () => sheetError = 'Enter a valid tax amount.',
                            );
                            return;
                          }
                          final today = DateTime.now()
                              .toIso8601String()
                              .substring(0, 10);
                          Navigator.of(context).pop(<String, Object?>{
                            'request_key': _uuid.v4(),
                            'return_date': today,
                            'reason': reason,
                            'tax_amount': taxRaw,
                            'refund_method': needsRefundMethod
                                ? refundMethod
                                : null,
                            'items': itemsPayload,
                          });
                        },
                        child: const Text('Record return'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    for (final c in qtyControllers.values) {
      c.dispose();
    }
    reasonController.dispose();
    taxController.dispose();

    if (payload == null || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await CloudService.instance.createPurchaseReturn(_document.uuid, payload);
      await _reloadFromDb();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase return recorded.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = _friendlyPurchaseError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openReversePurchaseDialog() async {
    final reasonController = TextEditingController();
    String? dialogError;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reverse purchase'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Reversing removes the received stock and excludes this purchase from supplier dues.',
              ),
              const SizedBox(height: 12),
              if (dialogError != null) ...[
                Text(
                  dialogError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Reversal reason (min 3 characters)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final text = reasonController.text.trim();
                if (text.length < 3) {
                  setDialogState(
                    () => dialogError =
                        'Enter a reason of at least 3 characters.',
                  );
                  return;
                }
                Navigator.of(context).pop(text);
              },
              child: const Text('Reverse purchase'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();

    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _actionError = null;
    });
    try {
      await CloudService.instance.reversePurchase(
        _document.uuid,
        reason: reason,
      );
      await _reloadFromDb();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase reversed.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = _friendlyPurchaseError(error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: CloudService.instance.state,
      builder: (context, _, _) {
        final allowed =
            DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true;
        final isCloudLinked = _isCloudLinked;
        final colorScheme = Theme.of(context).colorScheme;
        final lineItems = _document.lineItems;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Purchase receipt'),
            actions: [
              if (allowed && isCloudLinked && _document.canReverse)
                PopupMenuButton<String>(
                  enabled: !_busy,
                  onSelected: (value) {
                    if (value == 'reverse') {
                      _openReversePurchaseDialog();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'reverse',
                      child: Text('Reverse purchase'),
                    ),
                  ],
                ),
            ],
          ),
          body: !allowed
              ? const Center(
                  child: Text(
                    'Purchase history is available to owners and admins.',
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_document.isReversed) ...[
                      Card(
                        color: colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.cancel_outlined,
                                    color: colorScheme.onErrorContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Reversed purchase',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: colorScheme.onErrorContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                              if (_document.reversalReason != null &&
                                  _document.reversalReason!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Reason: ${_document.reversalReason}',
                                  style: TextStyle(
                                    color: colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 2),
                              Text(
                                'Reversed at: ${_document.reversedAt}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colorScheme.onErrorContainer,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_actionError != null) ...[
                      Card(
                        color: colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _actionError!,
                            style: TextStyle(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      _document.supplier ?? 'No supplier',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('Receipt date: ${_document.date}'),
                    Text(_status(_document.syncState)),
                    Text(
                      _document.origin == 'android'
                          ? 'Created on Android'
                          : 'Created on the web',
                    ),
                    if (_document.syncError != null)
                      Text(
                        _document.syncError!,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    Text(
                      'Payment: ${_paymentStatusLabel(_document.paymentStatus)}',
                    ),
                    if (_document.invoiceNumber != null)
                      Text('Supplier invoice: ${_document.invoiceNumber}'),
                    if (_document.dueDate != null)
                      Text('Due date: ${_document.dueDate}'),
                    const SizedBox(height: 12),
                    if (!_document.isReversed) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_document.canPaySupplier)
                            FilledButton.icon(
                              onPressed: _busy ? null : _openPaySupplier,
                              icon: const Icon(Icons.payments_outlined),
                              label: const Text('Pay supplier'),
                            ),
                          if (isCloudLinked && _document.canRecordPaymentTerms)
                            OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : _openRecordPaymentTermsDialog,
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('Record payment terms'),
                            ),
                          if (isCloudLinked && _document.hasReturnableItems)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _openReturnItemsSheet,
                              icon: const Icon(Icons.assignment_return_outlined),
                              label: const Text('Return items'),
                            ),
                        ],
                      ),
                      if (!isCloudLinked) ...[
                        const SizedBox(height: 8),
                        Card(
                          color: colorScheme.surfaceContainerHighest,
                          child: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Local-only mode: sign in to cloud sync to record payment terms, return items, or reverse posted purchases.',
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                    ],
                    for (final item in lineItems)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                '${item.quantity} ${item.unitName ?? ''} × ${purchaseMoney(item.unitCost)}',
                              ),
                              Text(purchaseMoney(item.amount)),
                              if (item.hasReturnedQuantity)
                                Text(
                                  'Returned: ${item.returnedQuantity} · Returnable: ${item.returnableQuantity}',
                                  style: TextStyle(
                                    color: colorScheme.tertiary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              if (item.batchNo != null)
                                Text('Batch: ${item.batchNo}'),
                              if (item.expiryDate != null)
                                Text('Expires: ${item.expiryDate}'),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Stock cost subtotal: ${purchaseMoney(_document.subtotal)}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_document.total != null) ...[
                      Text('GST: ${purchaseMoney(_document.taxAmount)}'),
                      Text(
                        'Other charges: ${purchaseMoney(_document.chargesAmount)}',
                      ),
                      Text(
                        'Discount: ${purchaseMoney(_document.discountAmount)}',
                      ),
                      Text('Total: ${purchaseMoney(_document.total!)}'),
                    ],
                    if (_document.hasReturnedTotal)
                      Text(
                        'Returned: ${purchaseMoney(_document.returnedTotal)}',
                        style: TextStyle(
                          color: colorScheme.tertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (_document.balanceDue != null)
                      Text(
                        'Balance due: ${purchaseMoney(_document.balanceDue!)}',
                      ),
                    if (_document.payments.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Payments',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final payment in _document.payments)
                        Text(
                          '${payment['payment_date']} · ${purchaseMoney(payment['amount'] as String)} · ${_methodLabel(payment['payment_method'] as String?)}',
                        ),
                    ],
                    if (_document.returns.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Returns / Debit notes',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      for (final ret in _document.returns)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      ret.returnNumber.isEmpty
                                          ? 'Debit note'
                                          : ret.returnNumber,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                    Text(
                                      purchaseMoney(ret.total),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleSmall,
                                    ),
                                  ],
                                ),
                                Text('${ret.returnDate} · ${ret.reason}'),
                                if (decimalScaledInteger(
                                      ret.payableCredit,
                                      scale: 4,
                                    ) >
                                    BigInt.zero)
                                  Text(
                                    'Payable credit: ${purchaseMoney(ret.payableCredit)}',
                                  ),
                                if (decimalScaledInteger(
                                      ret.refundAmount,
                                      scale: 4,
                                    ) >
                                    BigInt.zero)
                                  Text(
                                    'Refund: ${purchaseMoney(ret.refundAmount)} (${_methodLabel(ret.refundMethod)})',
                                  ),
                                for (final item in ret.items)
                                  Text(
                                    '• ${item.productName}: ${item.quantity} ${item.unitName ?? ''} (${purchaseMoney(item.amount)})',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (_document.isNotRecorded && !_document.isReversed)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Payment is not recorded. This receipt does not count towards supplier dues.',
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
