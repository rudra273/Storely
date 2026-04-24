import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../main.dart';
import '../db/database_helper.dart';
import '../models/product.dart';
import '../models/pricing.dart';
import '../utils/csv_importer.dart';
import 'qr_sheet_screen.dart';

enum _ProductSortMode {
  lastAdded('Last Added'),
  firstAdded('First Added'),
  nameAsc('A to Z'),
  nameDesc('Z to A');

  final String label;
  const _ProductSortMode(this.label);
}

class ProductsScreen extends StatefulWidget {
  final int refreshToken;

  const ProductsScreen({super.key, this.refreshToken = 0});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<Product> _allProducts = [];
  List<Product> _filtered = [];
  List<String> _categories = [];
  List<String> _suppliers = [];
  List<String> _units = [];
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedSuppliers = {};
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  bool _isUpdatingPrices = false;
  int _lowStockThreshold = 5;
  _ProductSortMode _sortMode = _ProductSortMode.lastAdded;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _searchCtrl.addListener(_applyFilter);
  }

  @override
  void didUpdateWidget(covariant ProductsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) {
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() {
      if (_allProducts.isEmpty) {
        _isLoading = true;
      } else {
        _isUpdatingPrices = true;
      }
    });
    final db = DatabaseHelper.instance;
    await db.refreshAllProductSellingPrices();
    final products = await db.getAllProducts();
    final categories = await db.getCategories();
    final suppliers = await db.getSuppliers();
    final units = await db.getUnits();
    final lowStockThreshold = await db.getLowStockThreshold();
    if (!mounted) return;
    setState(() {
      _allProducts = products;
      _categories = categories;
      _suppliers = suppliers;
      _units = units;
      _lowStockThreshold = lowStockThreshold;
      _selectedCategories.removeWhere((value) => !_categories.contains(value));
      _selectedSuppliers.removeWhere((value) => !_suppliers.contains(value));
      _isLoading = false;
      _isUpdatingPrices = false;
    });
    _applyFilter();
  }

  void _applyFilter() {
    if (!mounted) return;
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      final filtered = _allProducts.where((p) {
        final matchesCategory =
            _selectedCategories.isEmpty ||
            (p.category != null && _selectedCategories.contains(p.category));
        final matchesSupplier =
            _selectedSuppliers.isEmpty ||
            (p.supplier != null && _selectedSuppliers.contains(p.supplier));
        final matchesSearch =
            query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            (p.itemCode?.toLowerCase().contains(query) ?? false) ||
            (p.category?.toLowerCase().contains(query) ?? false) ||
            (p.unit?.toLowerCase().contains(query) ?? false) ||
            (p.supplier?.toLowerCase().contains(query) ?? false) ||
            p.sourceLabel.toLowerCase().contains(query);
        return matchesCategory && matchesSupplier && matchesSearch;
      }).toList();
      filtered.sort(_compareProducts);
      _filtered = filtered;
    });
  }

  int _compareProducts(Product a, Product b) {
    switch (_sortMode) {
      case _ProductSortMode.lastAdded:
        return b.createdAt.compareTo(a.createdAt);
      case _ProductSortMode.firstAdded:
        return a.createdAt.compareTo(b.createdAt);
      case _ProductSortMode.nameAsc:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case _ProductSortMode.nameDesc:
        return b.name.toLowerCase().compareTo(a.name.toLowerCase());
    }
  }

  Future<void> _showSortOptions() async {
    final selected = await showModalBottomSheet<_ProductSortMode>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.creamDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Sort Products',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              ..._ProductSortMode.values.map(
                (mode) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(mode.label),
                  trailing: mode == _sortMode
                      ? const Icon(Icons.check_rounded, color: AppColors.navy)
                      : null,
                  onTap: () => Navigator.pop(ctx, mode),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || selected == _sortMode) return;
    setState(() => _sortMode = selected);
    _applyFilter();
  }

  // ── CSV/Excel Import ──
  Future<void> _importCsv() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final products = file.bytes != null
          ? await CsvImporter.parseBytes(
              file.bytes!,
              fileName: file.name,
              extension: file.extension,
            )
          : file.path != null
          ? await CsvImporter.parseFile(
              file.path!,
              fileName: file.name,
              extension: file.extension,
            )
          : throw Exception('Could not read the selected file');

      if (mounted) Navigator.pop(context); // dismiss loading

      if (products.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No products found in file')),
          );
        }
        return;
      }
      if (mounted) _showImportDialog(products);
    } catch (e) {
      if (mounted) Navigator.pop(context); // dismiss loading
      _showImportError(e);
    }
  }

  void _showImportError(Object error) {
    if (!mounted) return;
    final message = error.toString().replaceFirst('Exception: ', '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline, color: AppColors.error, size: 36),
        title: const Text('Import Failed'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _runImportAction(
    BuildContext sheetContext,
    Future<String> Function() action,
  ) async {
    Navigator.pop(sheetContext);
    try {
      final message = await action();
      await _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      _showImportError(e);
    }
  }

  void _openQrSheet() {
    if (_allProducts.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add products first!')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QrSheetScreen(products: _allProducts)),
    );
  }

  Future<void> _showMultiSelectFilter({
    required String title,
    required List<String> options,
    required Set<String> selected,
    required Future<void> Function(String value) onAdd,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.75,
            ),
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.creamDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final value = await _showAddOptionDialog(title);
                        if (value == null || !mounted || !ctx.mounted) return;
                        await onAdd(value);
                        if (!mounted || !ctx.mounted) return;
                        setState(() {
                          if (title == 'Category' &&
                              !_categories.contains(value)) {
                            _categories.add(value);
                            _categories.sort();
                          }
                          if (title == 'Supplier' &&
                              !_suppliers.contains(value)) {
                            _suppliers.add(value);
                            _suppliers.sort();
                          }
                          selected.add(value);
                        });
                        _applyFilter();
                        setSheet(() {});
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: options.isEmpty
                      ? Center(
                          child: Text(
                            'No ${title.toLowerCase()} options yet',
                            style: TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (_, i) {
                            final option = options[i];
                            final checked = selected.contains(option);
                            return CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: checked,
                              title: Text(option),
                              activeColor: AppColors.navy,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    selected.add(option);
                                  } else {
                                    selected.remove(option);
                                  }
                                });
                                _applyFilter();
                                setSheet(() {});
                              },
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(selected.clear);
                        _applyFilter();
                        setSheet(() {});
                      },
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                      ),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String?> _showAddOptionDialog(String label) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _AddOptionDialog(label: label),
    );
  }

  void _showImportDialog(List<Product> products) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
          ),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.creamDark,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Icon + Title
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.amber.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.upload_file_rounded,
                    color: AppColors.amber,
                    size: 36,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Import ${products.length} Products',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose how to import the data',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 8),
                // Preview
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cream,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ListView(
                    shrinkWrap: true,
                    children: products
                        .take(5)
                        .map(
                          (p) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                if (p.itemCode != null) ...[
                                  Text(
                                    p.itemCode!,
                                    style: TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  p.priceLabel,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                if (products.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '...and ${products.length - 5} more',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                // Replace All
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _runImportAction(ctx, () async {
                      final count = await DatabaseHelper.instance
                          .replaceAllProducts(products);
                      return '✓ Replaced with $count products';
                    }),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text(
                      'Replace All',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // Merge
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _runImportAction(ctx, () async {
                      final result = await DatabaseHelper.instance
                          .mergeProducts(products);
                      return '✓ Added ${result['added']}, updated ${result['updated']}';
                    }),
                    icon: const Icon(Icons.merge_rounded),
                    label: const Text(
                      'Merge & Update',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.navy,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Add/Edit Sheet ──
  Future<void> _showAddEditSheet({Product? product}) async {
    final isEditing = product != null;
    final db = DatabaseHelper.instance;
    final globalPricing = await db.getGlobalPricingSettings();
    var selectedCategoryPricing = product?.category == null
        ? null
        : await db.getCategoryPricing(product!.category!);
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final purchaseCtrl = TextEditingController(
      text: product != null ? product.purchasePrice.toStringAsFixed(2) : '',
    );
    final manualPriceCtrl = TextEditingController(
      text: product?.manualPrice != null
          ? product!.manualPrice!.toStringAsFixed(2)
          : product != null
          ? product.mrp.toStringAsFixed(2)
          : '',
    );
    final qtyCtrl = TextEditingController(
      text: product != null ? product.quantity.toString() : '',
    );
    final totalCtrl = TextEditingController(
      text: product != null
          ? (product.purchasePrice * product.quantity).toStringAsFixed(2)
          : '',
    );
    String? selectedCategory = product?.category;
    String? selectedSupplier = product?.supplier;
    String? selectedUnit = product?.unit;
    double effectiveGst() =>
        selectedCategoryPricing?.gstPercent ?? globalPricing.defaultGstPercent;
    double effectiveOverhead() =>
        selectedCategoryPricing?.overheadCost ??
        globalPricing.defaultOverheadCost;
    double effectiveMargin() =>
        selectedCategoryPricing?.profitMarginPercent ??
        globalPricing.defaultProfitMarginPercent;
    final gstCtrl = TextEditingController(
      text: (product?.gstPercent ?? effectiveGst()).toStringAsFixed(2),
    );
    final overheadCtrl = TextEditingController(
      text: (product?.overheadCost ?? effectiveOverhead()).toStringAsFixed(2),
    );
    final marginCtrl = TextEditingController(
      text: (product?.profitMarginPercent ?? effectiveMargin()).toStringAsFixed(
        2,
      ),
    );
    var directPrice = product?.directPriceToggle ?? false;
    final formKey = GlobalKey<FormState>();
    String? nameError;
    var syncingTotals = false;
    var syncingPrice = false;

    void setFieldText(TextEditingController controller, String value) {
      if (controller.text == value) return;
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }

    void updateTotalFromPriceAndQty() {
      if (syncingTotals) return;
      syncingTotals = true;
      final price = double.tryParse(purchaseCtrl.text);
      final quantity = int.tryParse(qtyCtrl.text);
      if (price != null && price > 0 && quantity != null && quantity >= 0) {
        setFieldText(totalCtrl, (price * quantity).toStringAsFixed(2));
      } else if (purchaseCtrl.text.isEmpty || qtyCtrl.text.isEmpty) {
        setFieldText(totalCtrl, '');
      }
      syncingTotals = false;
    }

    void updateQtyFromTotal() {
      if (syncingTotals) return;
      syncingTotals = true;
      final price = double.tryParse(purchaseCtrl.text);
      final total = double.tryParse(totalCtrl.text);
      if (price != null && price > 0 && total != null && total >= 0) {
        setFieldText(qtyCtrl, (total / price).round().toString());
      } else if (totalCtrl.text.isEmpty) {
        setFieldText(qtyCtrl, '');
      }
      syncingTotals = false;
    }

    double marginForSellingPrice(double sellingPrice) {
      final purchasePrice = double.tryParse(purchaseCtrl.text) ?? 0;
      final gstPercent = double.tryParse(gstCtrl.text) ?? 0;
      final overhead = double.tryParse(overheadCtrl.text) ?? 0;
      final purchaseGst = globalPricing.gstRegistered
          ? 0.0
          : purchasePrice * gstPercent / 100;
      final totalCost = purchasePrice + purchaseGst + overhead;
      final preGstSelling = globalPricing.gstRegistered
          ? sellingPrice / (1 + gstPercent / 100)
          : sellingPrice;
      return totalCost <= 0 ? 0 : (preGstSelling - totalCost) / totalCost * 100;
    }

    void updateMarginFromDirectPrice() {
      if (syncingPrice || !directPrice) return;
      final sellingPrice = double.tryParse(manualPriceCtrl.text);
      if (sellingPrice == null || sellingPrice <= 0) return;
      syncingPrice = true;
      setFieldText(
        marginCtrl,
        marginForSellingPrice(sellingPrice).toStringAsFixed(2),
      );
      syncingPrice = false;
    }

    PriceBreakdown buildPreview() {
      final purchasePrice = double.tryParse(purchaseCtrl.text) ?? 0;
      final manualPrice = double.tryParse(manualPriceCtrl.text);
      final draft = Product(
        id: product?.id,
        itemCode: product?.itemCode,
        name: nameCtrl.text.trim().isEmpty ? 'Product' : nameCtrl.text.trim(),
        category: selectedCategory,
        mrp: manualPrice ?? product?.mrp ?? purchasePrice,
        purchasePrice: purchasePrice,
        gstPercent: double.tryParse(gstCtrl.text),
        overheadCost: double.tryParse(overheadCtrl.text),
        profitMarginPercent: double.tryParse(marginCtrl.text),
        directPriceToggle: directPrice,
        manualPrice: manualPrice,
        quantity: int.tryParse(qtyCtrl.text) ?? 0,
        unit: selectedUnit,
        supplier: selectedSupplier,
        source: product?.source ?? ProductSource.mobile,
        createdAt: product?.createdAt,
      );
      return PricingCalculator.resolveProductPrice(
        draft,
        globalPricing,
        selectedCategoryPricing,
      );
    }

    Future<void> updateCategoryPricing(
      String? value,
      StateSetter setSheet,
    ) async {
      selectedCategory = value;
      selectedCategoryPricing = value == null
          ? null
          : await DatabaseHelper.instance.getCategoryPricing(value);
      setFieldText(gstCtrl, effectiveGst().toStringAsFixed(2));
      setFieldText(overheadCtrl, effectiveOverhead().toStringAsFixed(2));
      setFieldText(marginCtrl, effectiveMargin().toStringAsFixed(2));
      updateMarginFromDirectPrice();
      if (mounted) setSheet(() {});
    }

    purchaseCtrl.addListener(updateTotalFromPriceAndQty);
    qtyCtrl.addListener(updateTotalFromPriceAndQty);
    manualPriceCtrl.addListener(updateMarginFromDirectPrice);
    updateMarginFromDirectPrice();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final preview = buildPreview();
          return SafeArea(
            top: false,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.9,
              ),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.creamDark,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        isEditing ? 'Edit Product' : 'Add Product',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _SourcePill(
                        label: isEditing
                            ? product.sourceLabel
                            : 'Mobile · code auto-created',
                        imported: product?.isImported ?? false,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Product Name *',
                          errorText: nameError,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      _OptionDropdown(
                        label: 'Category',
                        value: selectedCategory,
                        options: _categories,
                        onChanged: (value) {
                          updateCategoryPricing(value, setSheet);
                        },
                        onAdd: () async {
                          final value = await _showAddOptionDialog('Category');
                          if (value == null || !mounted || !ctx.mounted) return;
                          await DatabaseHelper.instance.addCategoryOption(
                            value,
                          );
                          if (!mounted || !ctx.mounted) return;
                          setState(() {
                            if (!_categories.contains(value)) {
                              _categories.add(value);
                              _categories.sort();
                            }
                          });
                          await updateCategoryPricing(value, setSheet);
                        },
                      ),
                      const SizedBox(height: 14),
                      _OptionDropdown(
                        label: 'Supplier',
                        value: selectedSupplier,
                        options: _suppliers,
                        onChanged: (value) {
                          setSheet(() => selectedSupplier = value);
                        },
                        onAdd: () async {
                          final value = await _showAddOptionDialog('Supplier');
                          if (value == null || !mounted || !ctx.mounted) return;
                          await DatabaseHelper.instance.addSupplierOption(
                            value,
                          );
                          if (!mounted || !ctx.mounted) return;
                          setState(() {
                            if (!_suppliers.contains(value)) {
                              _suppliers.add(value);
                              _suppliers.sort();
                            }
                          });
                          setSheet(() => selectedSupplier = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      _OptionDropdown(
                        label: 'Unit',
                        value: selectedUnit,
                        options: _units,
                        noValueLabel: 'No Unit',
                        addLabel: 'Add custom',
                        onChanged: (value) {
                          setSheet(() => selectedUnit = value);
                        },
                        onAdd: () async {
                          final value = await _showAddOptionDialog('Unit');
                          if (value == null || !mounted || !ctx.mounted) return;
                          await DatabaseHelper.instance.addUnitOption(value);
                          if (!mounted || !ctx.mounted) return;
                          setState(() {
                            if (!_units.any(
                              (unit) =>
                                  unit.toLowerCase() == value.toLowerCase(),
                            )) {
                              _units.add(value);
                              _units.sort(
                                (a, b) =>
                                    a.toLowerCase().compareTo(b.toLowerCase()),
                              );
                            }
                          });
                          setSheet(() => selectedUnit = value);
                        },
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Direct Price'),
                        subtitle: Text(
                          directPrice
                              ? 'Use manual selling price'
                              : 'Use GST, overhead and margin formula',
                        ),
                        value: directPrice,
                        activeThumbColor: AppColors.navy,
                        onChanged: (value) => setSheet(() {
                          directPrice = value;
                          updateMarginFromDirectPrice();
                        }),
                      ),
                      const SizedBox(height: 14),
                      _PricingCalculationTable(
                        purchaseCtrl: purchaseCtrl,
                        gstCtrl: gstCtrl,
                        overheadCtrl: overheadCtrl,
                        marginCtrl: marginCtrl,
                        manualPriceCtrl: manualPriceCtrl,
                        directPrice: directPrice,
                        breakdown: preview,
                        gstRegistered: globalPricing.gstRegistered,
                        onChanged: () {
                          updateMarginFromDirectPrice();
                          setSheet(() {});
                        },
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: qtyCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Quantity *',
                                prefixIcon: Icon(
                                  Icons.layers_outlined,
                                  size: 18,
                                ),
                              ),
                              onChanged: (_) => setSheet(() {}),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Required';
                                final n = int.tryParse(v);
                                return (n == null || n < 0) ? 'Invalid' : null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: totalCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}'),
                                ),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Stock Value (₹)',
                                prefixIcon: Icon(
                                  Icons.calculate_outlined,
                                  size: 18,
                                ),
                              ),
                              onChanged: (_) {
                                updateQtyFromTotal();
                                setSheet(() {});
                              },
                              validator: (v) {
                                if (v == null || v.isEmpty) return null;
                                final n = double.tryParse(v);
                                return (n == null || n < 0) ? 'Invalid' : null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final name = nameCtrl.text.trim();
                          final unique = await DatabaseHelper.instance
                              .isNameUnique(name, excludeId: product?.id);
                          if (!unique) {
                            setSheet(
                              () => nameError = '"$name" already exists',
                            );
                            return;
                          }
                          try {
                            final p = Product(
                              id: product?.id,
                              itemCode: product?.itemCode,
                              name: name,
                              category: selectedCategory,
                              mrp: preview.sellingPrice,
                              purchasePrice: double.parse(purchaseCtrl.text),
                              gstPercent: double.tryParse(gstCtrl.text),
                              overheadCost: double.tryParse(overheadCtrl.text),
                              profitMarginPercent: double.tryParse(
                                marginCtrl.text,
                              ),
                              directPriceToggle: directPrice,
                              manualPrice: directPrice
                                  ? double.tryParse(manualPriceCtrl.text)
                                  : null,
                              quantity: int.parse(qtyCtrl.text),
                              unit: selectedUnit,
                              supplier: selectedSupplier,
                              source: product?.source ?? ProductSource.mobile,
                              createdAt: product?.createdAt,
                            );
                            if (isEditing) {
                              await DatabaseHelper.instance.updateProduct(p);
                            } else {
                              await DatabaseHelper.instance.insertProduct(p);
                            }
                            if (ctx.mounted) Navigator.pop(ctx);
                            _loadProducts();
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error: $e')),
                              );
                            }
                          }
                        },
                        icon: Icon(isEditing ? Icons.check : Icons.add),
                        label: Text(
                          isEditing ? 'Update' : 'Add Product',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.navy,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        purchaseCtrl.removeListener(updateTotalFromPriceAndQty);
        qtyCtrl.removeListener(updateTotalFromPriceAndQty);
        nameCtrl.dispose();
        purchaseCtrl.dispose();
        manualPriceCtrl.dispose();
        gstCtrl.dispose();
        overheadCtrl.dispose();
        marginCtrl.dispose();
        qtyCtrl.dispose();
        totalCtrl.dispose();
      });
    });
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: AppColors.error, size: 32),
        title: const Text('Delete Product'),
        content: Text('Remove "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deleteProduct(product.id!);
      _loadProducts();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Search products...',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                  filled: false,
                ),
              )
            : const Text(
                'Products',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
        actions: [
          // Search toggle
          IconButton(
            onPressed: () {
              setState(() {
                _searchOpen = !_searchOpen;
                if (!_searchOpen) {
                  _searchCtrl.clear();
                }
              });
            },
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
          ),
          // QR Sheet
          IconButton(
            onPressed: _openQrSheet,
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'QR Sheet',
          ),
          if (_allProducts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_allProducts.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _allProducts.isEmpty
          ? _buildEmpty()
          : _buildContent(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'import',
            onPressed: _importCsv,
            backgroundColor: AppColors.amber,
            foregroundColor: Colors.white,
            child: const Icon(Icons.upload_file_rounded),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'add',
            onPressed: () => _showAddEditSheet(),
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            child: const Icon(Icons.add_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: const BoxDecoration(
              color: AppColors.creamDark,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              size: 56,
              color: AppColors.textMuted.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No products yet',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Add manually or import from CSV',
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: _importCsv,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Import CSV'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: _FilterDropdownButton(
                  label: 'Category',
                  count: _selectedCategories.length,
                  onTap: () => _showMultiSelectFilter(
                    title: 'Category',
                    options: _categories,
                    selected: _selectedCategories,
                    onAdd: DatabaseHelper.instance.addCategoryOption,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 4,
                child: _FilterDropdownButton(
                  label: 'Supplier',
                  count: _selectedSuppliers.length,
                  onTap: () => _showMultiSelectFilter(
                    title: 'Supplier',
                    options: _suppliers,
                    selected: _selectedSuppliers,
                    onAdd: DatabaseHelper.instance.addSupplierOption,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 3,
                child: _SortDropdownButton(
                  label: _sortMode.label,
                  onTap: _showSortOptions,
                ),
              ),
            ],
          ),
        ),
        if (_isUpdatingPrices)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Updating prices...',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        if (_selectedCategories.isNotEmpty || _selectedSuppliers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedCategories.clear();
                    _selectedSuppliers.clear();
                  });
                  _applyFilter();
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: const Text('Clear filters'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ),
        // ── Product List ──
        Expanded(
          child: _filtered.isEmpty
              ? Center(
                  child: Text(
                    'No matching products',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) => _ProductCard(
                    product: _filtered[i],
                    lowStockThreshold: _lowStockThreshold,
                    onTap: () => _showAddEditSheet(product: _filtered[i]),
                    onDelete: () => _deleteProduct(_filtered[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

String? _normaliseOptionName(String value) {
  final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  return trimmed.isEmpty ? null : trimmed;
}

class _AddOptionDialog extends StatefulWidget {
  final String label;

  const _AddOptionDialog({required this.label});

  @override
  State<_AddOptionDialog> createState() => _AddOptionDialogState();
}

class _AddOptionDialogState extends State<_AddOptionDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _normaliseOptionName(_controller.text);
    if (text == null) return;
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add ${widget.label}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(labelText: '${widget.label} name'),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: AppColors.navy),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _FilterDropdownButton extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback onTap;

  const _FilterDropdownButton({
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasSelection = count > 0;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: hasSelection ? AppColors.navy : AppColors.textDark,
        backgroundColor: Colors.white,
        side: BorderSide(
          color: hasSelection ? AppColors.navy : AppColors.creamDark,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              hasSelection ? '$label ($count)' : label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
        ],
      ),
    );
  }
}

class _SortDropdownButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SortDropdownButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.creamDark),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sort_rounded, size: 18),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingCalculationTable extends StatelessWidget {
  final TextEditingController purchaseCtrl;
  final TextEditingController gstCtrl;
  final TextEditingController overheadCtrl;
  final TextEditingController marginCtrl;
  final TextEditingController manualPriceCtrl;
  final bool directPrice;
  final PriceBreakdown breakdown;
  final bool gstRegistered;
  final VoidCallback onChanged;

  const _PricingCalculationTable({
    required this.purchaseCtrl,
    required this.gstCtrl,
    required this.overheadCtrl,
    required this.marginCtrl,
    required this.manualPriceCtrl,
    required this.directPrice,
    required this.breakdown,
    required this.gstRegistered,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                gstRegistered ? 'GST Registered Pricing' : 'Pricing Breakdown',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: breakdown.wasDirectPrice
                      ? AppColors.amber.withValues(alpha: 0.14)
                      : AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  breakdown.wasDirectPrice ? 'direct' : 'auto',
                  style: TextStyle(
                    color: breakdown.wasDirectPrice
                        ? AppColors.amber
                        : AppColors.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '₹${breakdown.sellingPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _PricingInputRow(
            label: gstRegistered ? 'Item rate (ex-GST)' : 'Item rate',
            controller: purchaseCtrl,
            prefixText: '₹',
            result: breakdown.purchasePrice,
            onChanged: onChanged,
            requiredPositive: true,
          ),
          if (!gstRegistered)
            _PricingInputRow(
              label: 'GST on purchase',
              controller: gstCtrl,
              suffixText: '%',
              result: breakdown.landedCost,
              delta: breakdown.gstAmount,
              onChanged: onChanged,
            ),
          _PricingInputRow(
            label: 'Overhead',
            controller: overheadCtrl,
            prefixText: '₹',
            result: breakdown.totalCost,
            delta: breakdown.overheadCost,
            onChanged: onChanged,
          ),
          _PricingInputRow(
            label: 'Margin',
            controller: marginCtrl,
            suffixText: '%',
            result: breakdown.preGstSellingPrice,
            delta: breakdown.profitAmount,
            onChanged: onChanged,
            readOnly: directPrice,
          ),
          if (gstRegistered)
            _PricingInputRow(
              label: 'GST on sell',
              controller: gstCtrl,
              suffixText: '%',
              result: breakdown.sellingPrice,
              delta: breakdown.gstAmount,
              onChanged: onChanged,
            ),
          const Divider(height: 18),
          if (directPrice)
            _PricingInputRow(
              label: 'Selling price',
              controller: manualPriceCtrl,
              prefixText: '₹',
              result: breakdown.sellingPrice,
              onChanged: onChanged,
              requiredPositive: true,
              isTotal: true,
            )
          else
            _PricingResultRow(
              label: 'Selling price',
              value: breakdown.sellingPrice,
              isTotal: true,
            ),
        ],
      ),
    );
  }
}

class _PricingInputRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String? prefixText;
  final String? suffixText;
  final double result;
  final double? delta;
  final VoidCallback onChanged;
  final bool requiredPositive;
  final bool isTotal;
  final bool readOnly;

  const _PricingInputRow({
    required this.label,
    required this.controller,
    this.prefixText,
    this.suffixText,
    required this.result,
    this.delta,
    required this.onChanged,
    this.requiredPositive = false,
    this.isTotal = false,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final deltaText = delta == null ? '' : ' +${delta!.toStringAsFixed(2)} =';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: TextStyle(
                color: isTotal ? AppColors.navy : AppColors.textDark,
                fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 96,
            child: TextFormField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              textAlign: TextAlign.end,
              readOnly: readOnly,
              decoration: InputDecoration(
                isDense: true,
                filled: readOnly,
                prefixText: prefixText,
                suffixText: suffixText,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
              ),
              onChanged: (_) => onChanged(),
              validator: (value) {
                final number = double.tryParse(value ?? '');
                if (requiredPositive && (number == null || number <= 0)) {
                  return 'Invalid';
                }
                if (!requiredPositive &&
                    value != null &&
                    value.isNotEmpty &&
                    number == null) {
                  return 'Invalid';
                }
                return null;
              },
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              '$deltaText ₹${result.toStringAsFixed(2)}',
              textAlign: TextAlign.end,
              style: TextStyle(
                color: isTotal ? AppColors.navy : AppColors.textMuted,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingResultRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isTotal;

  const _PricingResultRow({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isTotal ? AppColors.navy : AppColors.textMuted,
                fontWeight: isTotal ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            '₹${value.toStringAsFixed(2)}',
            style: TextStyle(
              color: isTotal ? AppColors.navy : AppColors.textDark,
              fontWeight: isTotal ? FontWeight.w900 : FontWeight.w700,
              fontSize: isTotal ? 16 : 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _OptionDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final String? noValueLabel;
  final String? addLabel;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAdd;
  static const _addValue = '__storely_add_option__';

  const _OptionDropdown({
    required this.label,
    required this.value,
    required this.options,
    this.noValueLabel,
    this.addLabel,
    required this.onChanged,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      if (value != null && value!.isNotEmpty && !options.contains(value))
        value!,
      ...options,
    ];

    return DropdownButtonFormField<String>(
      initialValue: value != null && value!.isNotEmpty ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text(noValueLabel ?? 'No $label'),
        ),
        ...items.map(
          (option) => DropdownMenuItem(
            value: option,
            child: Text(option, overflow: TextOverflow.ellipsis),
          ),
        ),
        DropdownMenuItem<String>(
          value: _addValue,
          child: Row(
            children: [
              const Icon(Icons.add_rounded, size: 18),
              const SizedBox(width: 8),
              Text(addLabel ?? 'Add $label'),
            ],
          ),
        ),
      ],
      onChanged: (selected) {
        if (selected == _addValue) {
          onAdd();
          return;
        }
        onChanged(selected);
      },
    );
  }
}

class _SourcePill extends StatelessWidget {
  final String label;
  final bool imported;

  const _SourcePill({required this.label, required this.imported});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              imported
                  ? Icons.upload_file_rounded
                  : Icons.phone_android_rounded,
              size: 14,
              color: AppColors.navy,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Product Card (Professional Design) ──
class _ProductCard extends StatelessWidget {
  final Product product;
  final int lowStockThreshold;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    required this.lowStockThreshold,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLowStock = product.quantity <= lowStockThreshold;
    final isOutOfStock = product.quantity == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isOutOfStock
            ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: category badge + source + delete
              Row(
                children: [
                  if (product.category != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.navy.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        product.category!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _sourceBadge(product.sourceLabel, product.isImported),
                  const SizedBox(width: 8),
                  _sourceBadge(
                    product.directPriceToggle ? 'direct' : 'auto',
                    product.directPriceToggle,
                  ),
                  const Spacer(),
                  // Stock badge
                  if (isOutOfStock)
                    _stockBadge('OUT', AppColors.error)
                  else if (isLowStock)
                    _stockBadge('LOW', AppColors.amber),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: AppColors.textMuted.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Product name
              Text(
                product.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              // Bottom row: price + qty + supplier
              Row(
                children: [
                  // Price
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      product.priceLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.amber,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Quantity
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 14,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    product.quantityLabel,
                    style: TextStyle(
                      fontSize: 13,
                      color: isLowStock ? AppColors.error : AppColors.textMuted,
                      fontWeight: isLowStock
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                  const Spacer(),
                  // Supplier
                  if (product.supplier != null)
                    Flexible(
                      child: Text(
                        product.supplier!,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stockBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _sourceBadge(String text, bool imported) {
    final color = imported ? AppColors.amber : AppColors.navy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            imported ? Icons.upload_file_rounded : Icons.phone_android_rounded,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
