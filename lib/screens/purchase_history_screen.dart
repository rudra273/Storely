import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/purchase_document.dart';
import '../services/cloud_service.dart';

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

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
      setState(() => _documents = _loadPage());
    }
  }

  @override
  void dispose() {
    CloudService.instance.state.removeListener(_cloudChanged);
    super.dispose();
  }

  Future<void> _refresh() async {
    final next = _loadPage();
    setState(() => _documents = next);
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final allowed =
        DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Purchase history'),
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
                            title: Text(document.supplier ?? 'No supplier'),
                            subtitle: Text(
                              '${document.date} · ${_status(document.syncState)}',
                            ),
                            trailing: Text(purchaseMoney(document.subtotal)),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _PurchaseDetails(document: document),
                              ),
                            ),
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

class _PurchaseDetails extends StatelessWidget {
  final PurchaseDocument document;
  const _PurchaseDetails({required this.document});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: CloudService.instance.state,
    builder: (context, _, _) => Scaffold(
      appBar: AppBar(title: const Text('Purchase receipt')),
      body: !(DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true)
          ? const Center(
              child: Text(
                'Purchase history is available to owners and admins.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  document.supplier ?? 'No supplier',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('Receipt date: ${document.date}'),
                Text(_status(document.syncState)),
                Text(
                  document.origin == 'android'
                      ? 'Created on Android'
                      : 'Created on the web',
                ),
                if (document.syncError != null)
                  Text(
                    document.syncError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const Text('Payment: Not recorded'),
                if (document.toJson()['invoice_number'] != null)
                  Text(
                    'Supplier invoice: ${document.toJson()['invoice_number']}',
                  ),
                const SizedBox(height: 12),
                for (final item in document.items)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['product_name'] as String,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            '${item['quantity']} ${item['unit_name'] ?? ''} × ${purchaseMoney(item['unit_cost'] as String)}',
                          ),
                          Text(purchaseMoney(item['amount'] as String)),
                          if (item['batch_no'] != null)
                            Text('Batch: ${item['batch_no']}'),
                          if (item['expiry_date'] != null)
                            Text('Expires: ${item['expiry_date']}'),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  'Stock cost subtotal: ${purchaseMoney(document.subtotal)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'Payment, tax and additional charges are not recorded in this receipt.',
                ),
              ],
            ),
    ),
  );
}
