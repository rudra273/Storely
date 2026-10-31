part of '../products_screen.dart';

class PurchaseProductPicker extends StatefulWidget {
  final List<Product> products;
  final Future<String?> Function(BuildContext) scanBarcode;
  const PurchaseProductPicker({
    super.key,
    required this.products,
    required this.scanBarcode,
  });
  @override
  State<PurchaseProductPicker> createState() => _PurchaseProductPickerState();
}

class _PurchaseProductPickerState extends State<PurchaseProductPicker> {
  final _search = TextEditingController();
  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final matches = widget.products
        .where(
          (p) =>
              p.trackStock &&
              (query.isEmpty ||
                  p.name.toLowerCase().contains(query) ||
                  (p.productCode?.toLowerCase().contains(query) ?? false) ||
                  (p.barcode?.toLowerCase().contains(query) ?? false)),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            children: [
              Text(
                'Choose product to restock',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Search name, code or barcode',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'Scan barcode',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: () async {
                      final code = await widget.scanBarcode(context);
                      if (!mounted || code == null) return;
                      setState(() => _search.text = code);
                    },
                  ),
                ),
              ),
              Expanded(
                child: matches.isEmpty
                    ? const Center(
                        child: Text(
                          'No tracked products match. Add a new product from the purchase.',
                        ),
                      )
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (_, i) {
                          final p = matches[i];
                          return ListTile(
                            title: Text(p.name),
                            subtitle: Text(
                              '${p.productCode ?? p.barcode ?? 'No code'} · Stock ${p.quantityLabel}',
                            ),
                            onTap: () => Navigator.pop(context, p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PurchaseRestockSheet extends StatefulWidget {
  final Product product;
  final PurchaseDraftLine? line;
  const PurchaseRestockSheet({super.key, required this.product, this.line});
  @override
  State<PurchaseRestockSheet> createState() => _PurchaseRestockSheetState();
}

class _PurchaseRestockSheetState extends State<PurchaseRestockSheet> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _quantity;
  late TextEditingController _cost;
  late TextEditingController _batch;
  DateTime? _expiry;
  @override
  void initState() {
    super.initState();
    CloudService.instance.state.addListener(_accessChanged);
    final p = widget.line?.product ?? widget.product;
    _quantity = TextEditingController(
      text: widget.line == null
          ? ''
          : purchaseDecimal(widget.line!.quantityAdded),
    );
    _cost = TextEditingController(text: purchaseDecimal(p.purchasePrice));
    _batch = TextEditingController(
      text: widget.line?.product.purchaseBatchNo ?? '',
    );
    _expiry = widget.line?.product.purchaseExpiry;
  }

  void _accessChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    CloudService.instance.state.removeListener(_accessChanged);
    _quantity.dispose();
    _cost.dispose();
    _batch.dispose();
    super.dispose();
  }

  String? _number(String? text, {bool positive = false}) {
    final raw = text?.trim() ?? '';
    if (!RegExp(r'^\d+(\.\d{1,4})?$').hasMatch(raw)) {
      return 'Enter a number with up to 4 decimal places';
    }
    final value = double.tryParse(raw);
    if (value == null ||
        !value.isFinite ||
        value > 9999999999.9999 ||
        (positive && value <= 0)) {
      return positive
          ? 'Enter a quantity greater than zero'
          : 'Enter a valid cost';
    }
    return null;
  }

  void _save() {
    if (!(DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true)) {
      return;
    }
    if (!_form.currentState!.validate()) return;
    final quantity = double.parse(_quantity.text.trim());
    final p = PurchaseDraftLine.productFromJson({
      ...PurchaseDraftLine.productJson(widget.product),
      'purchase_price': double.parse(_cost.text.trim()),
      'quantity_cache': quantity,
      'purchase_batch_no': _batch.text.trim().isEmpty
          ? null
          : _batch.text.trim(),
      'purchase_expiry': _expiry?.toIso8601String(),
    });
    Navigator.pop(
      context,
      PurchaseDraftLine(
        product: p,
        quantityAdded: quantity,
        restockTarget: widget.product,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      !(DatabaseHelper.instance.isAdminMutationAllowed?.call() ?? true)
      ? const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Purchase costs are available to owners and admins only.',
            ),
          ),
        )
      : SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.product.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('Current stock: ${widget.product.quantityLabel}'),
                    Text(
                      widget.product.directPriceToggle
                          ? 'Selling price and product settings stay unchanged.'
                          : 'Pricing rules stay unchanged. Automatic selling prices may update with stock cost.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _quantity,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'Quantity received (${widget.product.unit ?? 'pcs'})',
                      ),
                      validator: (value) => _number(value, positive: true),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Unit purchase cost',
                        helperText:
                            'Last cost is a suggestion. Enter the cost for this receipt.',
                      ),
                      validator: _number,
                    ),
                    ExpansionTile(
                      title: const Text('Batch and expiry (optional)'),
                      children: [
                        TextFormField(
                          controller: _batch,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            labelText: 'Batch number',
                          ),
                        ),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _expiry ?? DateTime.now(),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2100),
                                );
                                if (date != null && mounted) {
                                  setState(() => _expiry = date);
                                }
                              },
                              child: Text(
                                _expiry == null
                                    ? 'Choose expiry date'
                                    : 'Expires ${_formatFullDate(_expiry!)}',
                              ),
                            ),
                            if (_expiry != null)
                              TextButton(
                                onPressed: () => setState(() => _expiry = null),
                                child: const Text('Clear expiry'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _save,
                      child: Text(
                        widget.line == null ? 'Add to purchase' : 'Update line',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
}
