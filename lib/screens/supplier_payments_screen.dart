import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/purchase_document.dart';
import '../models/supplier.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';

class SupplierPaymentsScreen extends StatefulWidget {
  final SupplierProfile supplier;
  const SupplierPaymentsScreen({super.key, required this.supplier});
  @override
  State<SupplierPaymentsScreen> createState() => _SupplierPaymentsScreenState();
}

class _SupplierPaymentsScreenState extends State<SupplierPaymentsScreen> {
  final _amount = TextEditingController();
  late Future<Map<String, dynamic>> _statement;
  String _method = 'cash';
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;
  String _day(DateTime value) => value.toIso8601String().substring(0, 10);
  @override
  void initState() {
    super.initState();
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
      );
      if (!mounted) return;
      _amount.clear();
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
                return ListView.builder(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: receipts.length + queue.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Balance due: ${purchaseMoney(data['balance'] as String)}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'Based on purchases available on this device. Sync before paying when possible. Payments are allocated oldest first.',
                          ),
                        ],
                      );
                    }
                    if (index <= receipts.length) {
                      final receipt = receipts[index - 1];
                      return ListTile(
                        title: Text(
                          '${receipt.date} · ${receipt.toJson()['invoice_number'] ?? 'Purchase'}',
                        ),
                        subtitle: Text(receipt.paymentStatus),
                        trailing: Text(
                          receipt.balanceDue == null
                              ? 'Not recorded'
                              : purchaseMoney(receipt.balanceDue!),
                        ),
                      );
                    }
                    if (index == receipts.length + 1) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.md),
                          if (_error != null)
                            Text(
                              _error!,
                              style: const TextStyle(color: AppColors.error),
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
                              DropdownMenuItem(
                                value: 'cash',
                                child: Text('Cash'),
                              ),
                              DropdownMenuItem(
                                value: 'upi',
                                child: Text('UPI'),
                              ),
                              DropdownMenuItem(
                                value: 'card',
                                child: Text('Card'),
                              ),
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
                          OutlinedButton(
                            onPressed: _busy ? null : _sync,
                            child: const Text('Sync payments'),
                          ),
                        ],
                      );
                    }
                    final row = queue[index - receipts.length - 2];
                    return ListTile(
                      title: Text(
                        '${row['sync_state'] == 'synced'
                            ? 'Confirmed'
                            : row['sync_state'] == 'local'
                            ? 'Local only'
                            : row['sync_state'] == 'error'
                            ? 'Needs review'
                            : 'Waiting to sync'} · ${row['created_at']}',
                      ),
                      subtitle: Text(
                        row['last_error']?.toString() ??
                            'Saved payment request',
                      ),
                    );
                  },
                );
              },
            ),
    ),
  );
}
