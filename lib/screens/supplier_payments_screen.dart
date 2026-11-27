import 'dart:convert';

import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/purchase_document.dart';
import '../models/supplier.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';

class SupplierPaymentsScreen extends StatefulWidget {
  final SupplierProfile supplier;
  final String? initialPurchaseUuid;
  final bool? isCloudLinkedOverride;

  const SupplierPaymentsScreen({
    super.key,
    required this.supplier,
    this.initialPurchaseUuid,
    this.isCloudLinkedOverride,
  });

  @override
  State<SupplierPaymentsScreen> createState() => _SupplierPaymentsScreenState();
}

class _SupplierPaymentsScreenState extends State<SupplierPaymentsScreen> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _notes = TextEditingController();
  late Future<Map<String, dynamic>> _statement;
  String? _selectedPurchaseUuid;
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;

  String _day(DateTime value) => value.toIso8601String().substring(0, 10);

  bool get _isCloudLinked =>
      widget.isCloudLinkedOverride ??
      CloudService.instance.state.value.isCloudLinkedAdmin;

  @override
  void initState() {
    super.initState();
    _selectedPurchaseUuid = widget.initialPurchaseUuid;
    _reload();
  }

  void _reload() {
    _statement = DatabaseHelper.instance.supplierAccounting(
      widget.supplier.uuid,
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await DatabaseHelper.instance.queueSupplierPayment(
        widget.supplier.uuid,
        _amount.text.trim(),
        _method,
        _day(_date),
        purchaseUuid: _selectedPurchaseUuid,
        reference: _reference.text.trim().isEmpty
            ? null
            : _reference.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (!mounted) return;
      _amount.clear();
      _reference.clear();
      _notes.clear();
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Payment saved on this device. Sync to confirm it with the shop.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sync() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudService.instance.syncNow(reason: 'Supplier payment');
      if (!mounted) return;
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reverseConfirmedPayment(String paymentUuid) async {
    final reasonController = TextEditingController();
    String? dialogError;
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reverse supplier payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Reversing restores the balance due on the allocated purchase receipts.',
              ),
              const SizedBox(height: 12),
              if (dialogError != null) ...[
                Text(
                  dialogError!,
                  style: const TextStyle(color: AppColors.error),
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
              child: const Text('Reverse payment'),
            ),
          ],
        ),
      ),
    );
    reasonController.dispose();

    if (reason == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await CloudService.instance.reverseSupplierPayment(
        widget.supplier.uuid,
        paymentUuid,
        reason: reason,
      );
      if (!mounted) return;
      setState(_reload);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Supplier payment reversed.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Map<String, dynamic>> _confirmedPaymentsFromReceipts(
    List<PurchaseDocument> receipts,
  ) {
    final byUuid = <String, Map<String, dynamic>>{};
    for (final receipt in receipts) {
      for (final payment in receipt.payments) {
        final uuid = payment['uuid']?.toString();
        if (uuid == null || uuid.isEmpty) continue;
        byUuid.putIfAbsent(uuid, () => Map<String, dynamic>.from(payment));
      }
    }
    final list = byUuid.values.toList()
      ..sort(
        (a, b) => (b['payment_date']?.toString() ?? '').compareTo(
          a['payment_date']?.toString() ?? '',
        ),
      );
    return list;
  }

  String _formatSyncFreshness(DateTime? lastSyncedAt) {
    if (lastSyncedAt == null) return 'Not synced yet';
    final local = lastSyncedAt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Last synced: $y-$m-$d $hh:$mm';
  }

  Widget _queueStatusBadge(BuildContext context, Map<String, Object?> row) {
    final syncState = row['sync_state']?.toString();
    final commandState = row['command_state']?.toString();
    final scheme = Theme.of(context).colorScheme;
    final bool isFailed =
        syncState == 'error' ||
        commandState == 'rejected' ||
        commandState == 'conflict';
    final (String label, Color bg, Color fg) = isFailed
        ? (
            'Needs attention / Failed',
            scheme.errorContainer,
            scheme.onErrorContainer,
          )
        : syncState == 'synced'
        ? ('Confirmed', scheme.primaryContainer, scheme.onPrimaryContainer)
        : syncState == 'local'
        ? (
            'Local only',
            scheme.surfaceContainerHighest,
            scheme.onSurfaceVariant,
          )
        : (
            'Pending sync',
            scheme.tertiaryContainer,
            scheme.onTertiaryContainer,
          );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: CloudService.instance.state,
    builder: (context, _, _) => Scaffold(
      appBar: navyAppBar(title: widget.supplier.name),
      body: !(DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true)
          ? const Center(child: Text('Supplier payments require admin access.'))
          : FutureBuilder<Map<String, dynamic>>(
              future: _statement,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load supplier payments: ${snapshot.error}',
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                final receipts = data['receipts'] as List<PurchaseDocument>;
                final queue = data['queue'] as List<Map<String, Object?>>;
                final summary = data['summary'] as SupplierBalanceSummary;
                final openReceipts = receipts
                    .where((r) => !r.isReversed && r.hasBalanceDue)
                    .toList();
                final effectiveSelection =
                    _selectedPurchaseUuid != null &&
                        openReceipts.any((r) => r.uuid == _selectedPurchaseUuid)
                    ? _selectedPurchaseUuid
                    : null;
                final confirmedPayments = _confirmedPaymentsFromReceipts(
                  receipts,
                );
                final colorScheme = Theme.of(context).colorScheme;

                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Confirmed balance: ${purchaseMoney(summary.confirmedBalance)}',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Pending on this device: ${purchaseMoney(summary.pendingPaymentsTotal)}',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: summary.hasPendingPayments
                                        ? colorScheme.tertiary
                                        : null,
                                    fontWeight: summary.hasPendingPayments
                                        ? FontWeight.w600
                                        : null,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Projected balance after sync: ${purchaseMoney(summary.projectedBalance)}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _formatSyncFreshness(summary.lastSyncedAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (summary.unrecordedReceiptsCount > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${summary.unrecordedReceiptsCount} purchase(s) have unrecorded payment terms and are excluded from dues.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            if (summary.failedPaymentsCount > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${summary.failedPaymentsCount} queued payment(s) need attention.',
                                style: TextStyle(
                                  color: colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (receipts.isNotEmpty) ...[
                      Text(
                        'Purchase receipts',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final receipt in receipts)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${receipt.date} · ${receipt.invoiceNumber ?? 'Purchase'}',
                          ),
                          subtitle: Text(
                            receipt.isReversed
                                ? 'Reversed'
                                : receipt.paymentStatus,
                          ),
                          trailing: Text(
                            receipt.isReversed
                                ? 'Reversed'
                                : receipt.balanceDue == null
                                ? 'Not recorded'
                                : purchaseMoney(receipt.balanceDue!),
                          ),
                        ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Record payment',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                    DropdownButtonFormField<String?>(
                      initialValue: effectiveSelection,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Allocation',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Oldest unpaid bills (FIFO)'),
                        ),
                        for (final receipt in openReceipts)
                          DropdownMenuItem<String?>(
                            value: receipt.uuid,
                            child: Text(
                              '${receipt.date} · ${receipt.invoiceNumber ?? 'Purchase'} (${purchaseMoney(receipt.balanceDue!)})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) =>
                              setState(() => _selectedPurchaseUuid = value),
                    ),
                    TextField(
                      controller: _amount,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Amount (₹)',
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _method,
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
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _method = value!),
                    ),
                    TextField(
                      controller: _reference,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Reference (optional)',
                      ),
                    ),
                    TextField(
                      controller: _notes,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: _date,
                                firstDate: DateTime(2000),
                                lastDate: DateTime.now(),
                              );
                              if (!mounted || date == null) return;
                              setState(() => _date = date);
                            },
                      child: Text('Payment date: ${_day(_date)}'),
                    ),
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: const Text('Save payment on this device'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _busy ? null : _sync,
                      child: const Text('Sync payments'),
                    ),
                    if (confirmedPayments.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Confirmed server payments',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final payment in confirmedPayments)
                        Card(
                          child: ListTile(
                            title: Text(
                              '${purchaseMoney(payment['amount'].toString())} · ${payment['payment_method'] ?? ''}',
                            ),
                            subtitle: Text(
                              [
                                payment['payment_date']?.toString() ?? '',
                                if (payment['reference'] != null &&
                                    payment['reference'].toString().isNotEmpty)
                                  'Ref: ${payment['reference']}',
                                if (payment['notes'] != null &&
                                    payment['notes'].toString().isNotEmpty)
                                  payment['notes'].toString(),
                              ].where((s) => s.isNotEmpty).join(' · '),
                            ),
                            trailing: _isCloudLinked &&
                                    payment['reversed_at'] == null
                                ? TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _reverseConfirmedPayment(
                                            payment['uuid'].toString(),
                                          ),
                                    child: const Text('Reverse'),
                                  )
                                : payment['reversed_at'] != null
                                ? const Text('Reversed')
                                : null,
                          ),
                        ),
                    ],
                    if (queue.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Device payment queue',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      for (final row in queue)
                        () {
                          final payload = Map<String, dynamic>.from(
                            jsonDecode(row['payload'] as String) as Map,
                          );
                          final amountStr = payload['amount']?.toString();
                          final ref = payload['reference']?.toString();
                          final notes = payload['notes']?.toString();
                          return Card(
                            child: ListTile(
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      amountStr != null
                                          ? '${purchaseMoney(amountStr)} · ${payload['payment_date'] ?? ''}'
                                          : row['created_at'].toString(),
                                    ),
                                  ),
                                  _queueStatusBadge(context, row),
                                ],
                              ),
                              subtitle: Text(
                                row['last_error']?.toString() ??
                                    [
                                      payload['payment_method']?.toString() ??
                                          '',
                                      if (payload['purchase_uuid'] != null)
                                        'Specific invoice',
                                      if (ref != null && ref.isNotEmpty)
                                        'Ref: $ref',
                                      if (notes != null && notes.isNotEmpty)
                                        notes,
                                    ].where((s) => s.isNotEmpty).join(' · '),
                              ),
                            ),
                          );
                        }(),
                    ],
                  ],
                );
              },
            ),
    ),
  );
}
