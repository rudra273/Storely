import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../main.dart';
import '../db/database_helper.dart';
import '../models/product.dart';
import '../models/product_purchase.dart';
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
  Map<int, ProductPurchaseSummary> _purchaseSummaries = {};
  Set<int> _purchaseDateProductIds = {};
  final Set<String> _selectedCategories = {};
  final Set<String> _selectedSuppliers = {};
  final Set<int> _selectedProductIds = {};
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();
  bool _searchOpen = false;
  bool _isUpdatingPrices = false;
  int _lowStockThreshold = 5;
  DateTime? _selectedPurchaseDate;
  _ProductSortMode _sortMode = _ProductSortMode.lastAdded;

  bool get _selectionMode => _selectedProductIds.isNotEmpty;
  int get _activeFilterCount =>
      _selectedCategories.length +
      _selectedSuppliers.length +
      (_selectedPurchaseDate == null ? 0 : 1);

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
    final purchaseSummaries = await db.getProductPurchaseSummaries();
    final purchaseDateProductIds = _selectedPurchaseDate == null
        ? <int>{}
        : await db.getProductIdsPurchasedOn(_selectedPurchaseDate!);
    final lowStockThreshold = await db.getLowStockThreshold();
    if (!mounted) return;
    setState(() {
      _allProducts = products;
      _categories = categories;
      _suppliers = suppliers;
      _units = units;
      _purchaseSummaries = purchaseSummaries;
      _purchaseDateProductIds = purchaseDateProductIds;
      _lowStockThreshold = lowStockThreshold;
      _selectedCategories.removeWhere((value) => !_categories.contains(value));
      _selectedSuppliers.removeWhere((value) => !_suppliers.contains(value));
      final productIds = products
          .map((product) => product.id)
          .whereType<int>()
          .toSet();
      _selectedProductIds.removeWhere((id) => !productIds.contains(id));
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
        final matchesPurchaseDate =
            _selectedPurchaseDate == null ||
            (p.id != null && _purchaseDateProductIds.contains(p.id));
        final matchesSearch =
            query.isEmpty ||
            p.name.toLowerCase().contains(query) ||
            (p.itemCode?.toLowerCase().contains(query) ?? false) ||
            (p.barcode?.toLowerCase().contains(query) ?? false) ||
            (p.category?.toLowerCase().contains(query) ?? false) ||
            (p.unit?.toLowerCase().contains(query) ?? false) ||
            (p.supplier?.toLowerCase().contains(query) ?? false) ||
            p.sourceLabel.toLowerCase().contains(query);
        return matchesCategory &&
            matchesSupplier &&
            matchesPurchaseDate &&
            matchesSearch;
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

  void _toggleProductSelection(Product product) {
    final id = product.id;
    if (id == null) return;
    setState(() {
      if (_selectedProductIds.contains(id)) {
        _selectedProductIds.remove(id);
      } else {
        _selectedProductIds.add(id);
      }
    });
  }

  void _selectAllFilteredProducts() {
    setState(() {
      _selectedProductIds.addAll(
        _filtered.map((product) => product.id).whereType<int>(),
      );
    });
  }

  void _clearProductSelection() {
    setState(_selectedProductIds.clear);
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

  List<Product> _matchingProducts(String query) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    return _allProducts
        .where((product) {
          return product.name.toLowerCase().contains(q) ||
              (product.itemCode?.toLowerCase().contains(q) ?? false) ||
              (product.barcode?.toLowerCase().contains(q) ?? false);
        })
        .take(5)
        .toList();
  }

  int _countImportMatches(List<Product> products) {
    var count = 0;
    final byCode = {
      for (final product in _allProducts)
        if (product.itemCode != null && product.itemCode!.trim().isNotEmpty)
          product.itemCode!.trim().toLowerCase(): product,
    };
    final byBarcode = {
      for (final product in _allProducts)
        if (product.barcode != null && product.barcode!.trim().isNotEmpty)
          product.barcode!.trim().toLowerCase(): product,
    };
    final byName = {
      for (final product in _allProducts)
        product.name.trim().toLowerCase(): product,
    };

    for (final product in products) {
      final code = product.itemCode?.trim().toLowerCase();
      if (code != null && code.isNotEmpty && byCode.containsKey(code)) {
        count++;
        continue;
      }
      final barcode = product.barcode?.trim().toLowerCase();
      if (barcode != null &&
          barcode.isNotEmpty &&
          byBarcode.containsKey(barcode)) {
        count++;
        continue;
      }
      if (byName.containsKey(product.name.trim().toLowerCase())) count++;
    }
    return count;
  }

  Future<void> _showBulkCategoryPicker() async {
    final selected = await _showBulkOptionPicker(
      title: 'Set Category',
      options: _categories,
      emptyLabel: 'No Category',
      addLabel: 'Add Category',
      onAdd: DatabaseHelper.instance.addCategoryOption,
    );
    if (selected == null) return;
    await _bulkUpdateProducts(changeCategory: true, category: selected);
  }

  Future<void> _showBulkSupplierPicker() async {
    final selected = await _showBulkOptionPicker(
      title: 'Set Supplier',
      options: _suppliers,
      emptyLabel: 'No Supplier',
      addLabel: 'Add Supplier',
      onAdd: DatabaseHelper.instance.addSupplierOption,
    );
    if (selected == null) return;
    await _bulkUpdateProducts(changeSupplier: true, supplier: selected);
  }

  Future<String?> _showBulkOptionPicker({
    required String title,
    required List<String> options,
    required String emptyLabel,
    required String addLabel,
    required Future<void> Function(String value) onAdd,
  }) {
    return showModalBottomSheet<String?>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.creamDark,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.block_rounded),
                title: Text(emptyLabel),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, index) {
                    final option = options[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(option, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(ctx, option),
                    );
                  },
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.add_rounded),
                title: Text(addLabel),
                onTap: () async {
                  final value = await _showAddOptionDialog(
                    title.replaceFirst('Set ', ''),
                  );
                  if (value == null || !mounted || !ctx.mounted) return;
                  await onAdd(value);
                  if (ctx.mounted) Navigator.pop(ctx, value);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _bulkUpdateProducts({
    bool changeCategory = false,
    String? category,
    bool changeSupplier = false,
    String? supplier,
  }) async {
    final selectedIds = Set<int>.from(_selectedProductIds);
    if (selectedIds.isEmpty) return;

    try {
      for (final product in _allProducts.where(
        (product) => product.id != null && selectedIds.contains(product.id),
      )) {
        await DatabaseHelper.instance.updateProduct(
          _productWithBulkFields(
            product,
            changeCategory: changeCategory,
            category: category?.isEmpty == true ? null : category,
            changeSupplier: changeSupplier,
            supplier: supplier?.isEmpty == true ? null : supplier,
          ),
        );
      }
      _clearProductSelection();
      await _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Updated ${selectedIds.length} products'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _showImportError(e);
    }
  }

  Future<void> _deleteSelectedProducts() async {
    final selectedIds = Set<int>.from(_selectedProductIds);
    if (selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.delete_outline,
          color: AppColors.error,
          size: 34,
        ),
        title: const Text('Delete Selected Products'),
        content: Text(
          'Remove ${selectedIds.length} selected product${selectedIds.length == 1 ? '' : 's'}?',
        ),
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
    if (confirmed != true) return;

    try {
      for (final id in selectedIds) {
        await DatabaseHelper.instance.deleteProduct(id);
      }
      _clearProductSelection();
      await _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Deleted ${selectedIds.length} products'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      _showImportError(e);
    }
  }

  Product _productWithBulkFields(
    Product product, {
    required bool changeCategory,
    String? category,
    required bool changeSupplier,
    String? supplier,
  }) {
    return product.copyWith(
      clearCategory: changeCategory && category == null,
      category: changeCategory ? category : null,
      clearSupplier: changeSupplier && supplier == null,
      supplier: changeSupplier ? supplier : null,
    );
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

  Product _productWithImportPricing(Product product, bool useDirectPrice) {
    return product.copyWith(
      sellingPrice: product.mrp,
      directPriceToggle: useDirectPrice,
      clearManualPrice: !useDirectPrice,
      manualPrice: useDirectPrice ? product.mrp : null,
      source: ProductSource.imported,
    );
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

  Future<void> _showStockHistory(Product product) async {
    final id = product.id;
    if (id == null) return;
    final movements = await DatabaseHelper.instance.getStockMovementsForProduct(
      id,
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _StockMovementHistorySheet(product: product, movements: movements),
    );
  }

  Future<String?> _scanBarcodeValue(BuildContext sheetContext) {
    var scanned = false;
    return showModalBottomSheet<String>(
      context: sheetContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          height: MediaQuery.sizeOf(ctx).height * 0.62,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Scan Barcode',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MobileScanner(
                  onDetect: (capture) {
                    if (scanned) return;
                    final raw = capture.barcodes
                        .map((barcode) => barcode.rawValue)
                        .whereType<String>()
                        .firstOrNull;
                    if (raw == null || raw.trim().isEmpty) return;
                    scanned = true;
                    Navigator.pop(ctx, raw.trim());
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showProductFilters() async {
    final nextCategories = Set<String>.from(_selectedCategories);
    final nextSuppliers = Set<String>.from(_selectedSuppliers);
    var nextPurchaseDate = _selectedPurchaseDate;

    final applied = await showModalBottomSheet<bool>(
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
                    const Text(
                      'Filters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      _FilterSheetSection(
                        title: 'Category',
                        icon: Icons.category_outlined,
                        options: _categories,
                        selected: nextCategories,
                        emptyText: 'No categories yet',
                        onChanged: (value, selected) {
                          setSheet(() {
                            if (selected) {
                              nextCategories.add(value);
                            } else {
                              nextCategories.remove(value);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _FilterSheetSection(
                        title: 'Supplier',
                        icon: Icons.storefront_outlined,
                        options: _suppliers,
                        selected: nextSuppliers,
                        emptyText: 'No suppliers yet',
                        onChanged: (value, selected) {
                          setSheet(() {
                            if (selected) {
                              nextSuppliers.add(value);
                            } else {
                              nextSuppliers.remove(value);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 14),
                      _PurchaseDateFilterTile(
                        date: nextPurchaseDate,
                        onPick: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: nextPurchaseDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked == null || !ctx.mounted) return;
                          setSheet(() => nextPurchaseDate = picked);
                        },
                        onClear: nextPurchaseDate == null
                            ? null
                            : () => setSheet(() => nextPurchaseDate = null),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setSheet(() {
                          nextCategories.clear();
                          nextSuppliers.clear();
                          nextPurchaseDate = null;
                        });
                      },
                      child: const Text('Clear'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                      ),
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied != true) return;
    final ids = nextPurchaseDate == null
        ? <int>{}
        : await DatabaseHelper.instance.getProductIdsPurchasedOn(
            nextPurchaseDate!,
          );
    if (!mounted) return;
    setState(() {
      _selectedCategories
        ..clear()
        ..addAll(nextCategories);
      _selectedSuppliers
        ..clear()
        ..addAll(nextSuppliers);
      _selectedPurchaseDate = nextPurchaseDate;
      _purchaseDateProductIds = ids;
    });
    _applyFilter();
  }

  void _clearAllFilters() {
    setState(() {
      _selectedCategories.clear();
      _selectedSuppliers.clear();
      _selectedPurchaseDate = null;
      _purchaseDateProductIds = {};
    });
    _applyFilter();
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
      builder: (ctx) {
        var useDirectPrice = false;
        DateTime? purchaseDate;
        var possibleDuplicate = false;
        var duplicateDateMismatch = false;
        var existingMatchCount = _countImportMatches(products);
        var duplicateChecked = false;
        List<Product> importProducts() => products
            .map(
              (product) => _productWithImportPricing(product, useDirectPrice),
            )
            .toList();

        Future<void> refreshDuplicateFlag(StateSetter setSheet) async {
          final matches = _countImportMatches(importProducts());
          final duplicate = await DatabaseHelper.instance
              .previewImportDuplicate(
                importProducts(),
                purchaseDate: purchaseDate,
              );
          if (ctx.mounted) {
            setSheet(() {
              existingMatchCount = matches;
              possibleDuplicate = duplicate.possibleDuplicate;
              duplicateDateMismatch = duplicate.duplicateOnDifferentDate;
            });
          }
        }

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            if (!duplicateChecked) {
              duplicateChecked = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (ctx.mounted) refreshDuplicateFlag(setSheet);
              });
            }
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
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: purchaseDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked == null || !ctx.mounted) return;
                          setSheet(() => purchaseDate = picked);
                          await refreshDuplicateFlag(setSheet);
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                          decoration: BoxDecoration(
                            color: AppColors.cream,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.event_outlined),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Purchase Date',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      purchaseDate == null
                                          ? 'Required before import'
                                          : _formatFullDate(purchaseDate!),
                                      style: TextStyle(
                                        color: purchaseDate == null
                                            ? AppColors.error
                                            : AppColors.textMuted,
                                        fontSize: 12,
                                        fontWeight: purchaseDate == null
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.edit_calendar_rounded),
                            ],
                          ),
                        ),
                      ),
                      if (possibleDuplicate || duplicateDateMismatch) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  possibleDuplicate
                                      ? 'This looks like a duplicate purchase batch. Same date, same products, quantities, prices, and suppliers were imported before.'
                                      : 'Check the purchase date. These rows look like a duplicate batch already imported on a different date.',
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _DirectPriceControl(
                        directPrice: useDirectPrice,
                        onChanged: (value) async {
                          setSheet(() => useDirectPrice = value);
                          await refreshDuplicateFlag(setSheet);
                        },
                      ),
                      const SizedBox(height: 12),
                      _ImportPreviewTable(products: importProducts()),
                      const SizedBox(height: 20),
                      if (existingMatchCount > 0) ...[
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => _runImportAction(ctx, () async {
                              if (purchaseDate == null) {
                                throw Exception(
                                  'Please choose a purchase date before importing.',
                                );
                              }
                              final count = await DatabaseHelper.instance
                                  .replaceAllProducts(
                                    importProducts(),
                                    purchaseDate: purchaseDate!,
                                  );
                              return '✓ Replaced $count imported products';
                            }),
                            icon: const Icon(Icons.swap_horiz_rounded),
                            label: const Text(
                              'Replace',
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
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => _runImportAction(ctx, () async {
                            if (purchaseDate == null) {
                              throw Exception(
                                'Please choose a purchase date before importing.',
                              );
                            }
                            final result = await DatabaseHelper.instance
                                .mergeProducts(
                                  importProducts(),
                                  purchaseDate: purchaseDate!,
                                );
                            final warning =
                                result.possibleDuplicate ||
                                    result.duplicateOnDifferentDate
                                ? ' Possible duplicate batch was appended.'
                                : '';
                            return '✓ Added ${result.added}, updated ${result.updated}.$warning';
                          }),
                          icon: Icon(
                            existingMatchCount == 0
                                ? Icons.add_rounded
                                : Icons.merge_rounded,
                          ),
                          label: Text(
                            existingMatchCount == 0 ? 'Add' : 'Update Stock',
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
            );
          },
        );
      },
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
    final productCodeCtrl = TextEditingController(
      text: product?.productCode ?? '',
    );
    final barcodeCtrl = TextEditingController(text: product?.barcode ?? '');
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
    Product? selectedExistingProduct;
    var purchaseDate = DateTime.now();
    var hideProductSuggestions = false;
    double effectiveGst() =>
        selectedCategoryPricing?.gstPercent ?? globalPricing.defaultGstPercent;
    double effectiveOverhead() =>
        selectedCategoryPricing?.overheadCost ??
        globalPricing.defaultOverheadCost;
    double effectiveMargin() =>
        selectedCategoryPricing?.profitMarginPercent ??
        globalPricing.defaultProfitMarginPercent;
    var gstCustom = product?.gstPercent != null;
    var overheadCustom = product?.overheadCost != null;
    var marginCustom = product?.profitMarginPercent != null;

    String sourceHint(bool custom, bool hasCategoryValue) {
      if (custom) return 'product custom';
      if (hasCategoryValue) return 'from category';
      return 'global default';
    }

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
    var formulaMarginText = marginCtrl.text;
    var directPrice = product?.directPriceToggle ?? false;
    final formKey = GlobalKey<FormState>();
    String? nameError;
    var syncingTotals = false;
    var syncingPrice = false;
    var hasUserEdited = false;
    var isSaving = false;
    var priceBreakdownOpen = true;

    void markEdited() {
      hasUserEdited = true;
    }

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
      final quantity = double.tryParse(qtyCtrl.text);
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
        setFieldText(qtyCtrl, _formatQuantityInput(total / price));
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

    void restoreFormulaMargin() {
      setFieldText(marginCtrl, formulaMarginText);
    }

    PriceBreakdown buildPreview() {
      final purchasePrice = double.tryParse(purchaseCtrl.text) ?? 0;
      final manualPrice = double.tryParse(manualPriceCtrl.text);
      final draft = Product(
        id: product?.id,
        uuid: product?.uuid,
        shopId: product?.shopId ?? 'local-shop',
        productCode: productCodeCtrl.text,
        barcode: barcodeCtrl.text,
        name: nameCtrl.text.trim().isEmpty ? 'Product' : nameCtrl.text.trim(),
        categoryId: product?.categoryId,
        category: selectedCategory,
        supplierId: product?.supplierId,
        unitId: product?.unitId,
        mrp: manualPrice ?? product?.mrp ?? purchasePrice,
        purchasePrice: purchasePrice,
        gstPercent: gstCustom ? double.tryParse(gstCtrl.text) : null,
        overheadCost: overheadCustom
            ? double.tryParse(overheadCtrl.text)
            : null,
        profitMarginPercent: marginCustom
            ? double.tryParse(marginCtrl.text)
            : null,
        directPriceToggle: directPrice,
        manualPrice: manualPrice,
        quantity: double.tryParse(qtyCtrl.text) ?? 0,
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
      if (!gstCustom) setFieldText(gstCtrl, effectiveGst().toStringAsFixed(2));
      if (!overheadCustom) {
        setFieldText(overheadCtrl, effectiveOverhead().toStringAsFixed(2));
      }
      if (!marginCustom) {
        formulaMarginText = effectiveMargin().toStringAsFixed(2);
        if (!directPrice) {
          setFieldText(marginCtrl, formulaMarginText);
        }
      }
      updateMarginFromDirectPrice();
      if (mounted) setSheet(() {});
    }

    purchaseCtrl.addListener(updateTotalFromPriceAndQty);
    qtyCtrl.addListener(updateTotalFromPriceAndQty);
    manualPriceCtrl.addListener(updateMarginFromDirectPrice);
    updateMarginFromDirectPrice();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final preview = buildPreview();
          Future<void> requestClose() async {
            if (isSaving) return;
            if (!hasUserEdited) {
              Navigator.pop(ctx);
              return;
            }
            final discard = await showDialog<bool>(
              context: ctx,
              builder: (dialogCtx) => AlertDialog(
                icon: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.amber,
                  size: 34,
                ),
                title: const Text('Discard changes?'),
                content: const Text(
                  'Your product changes have not been saved.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx, false),
                    child: const Text('Keep Editing'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogCtx, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                    child: const Text('Discard'),
                  ),
                ],
              ),
            );
            if (discard == true && ctx.mounted) Navigator.pop(ctx);
          }

          Future<void> saveProduct() async {
            if (isSaving) return;
            if (!formKey.currentState!.validate()) return;
            setSheet(() => isSaving = true);
            try {
              final name = nameCtrl.text.trim();
              final restockingExisting =
                  !isEditing && selectedExistingProduct != null;
              final unique =
                  restockingExisting ||
                  await DatabaseHelper.instance.isNameUnique(
                    name,
                    excludeId: product?.id,
                  );
              if (!unique) {
                if (ctx.mounted) {
                  setSheet(() {
                    nameError = '"$name" already exists';
                    isSaving = false;
                  });
                }
                return;
              }
              if (restockingExisting) {
                final existing = selectedExistingProduct!;
                final updated = Product(
                  id: existing.id,
                  uuid: existing.uuid,
                  shopId: existing.shopId,
                  productCode: _optionalControllerText(productCodeCtrl),
                  barcode: _optionalControllerText(barcodeCtrl),
                  name: existing.name,
                  categoryId: existing.categoryId,
                  category: selectedCategory,
                  supplierId: existing.supplierId,
                  supplier: selectedSupplier,
                  unitId: existing.unitId,
                  unit: selectedUnit,
                  mrp: preview.sellingPrice,
                  purchasePrice: double.parse(purchaseCtrl.text),
                  gstPercent: gstCustom ? double.tryParse(gstCtrl.text) : null,
                  overheadCost: overheadCustom
                      ? double.tryParse(overheadCtrl.text)
                      : null,
                  profitMarginPercent: marginCustom
                      ? double.tryParse(marginCtrl.text)
                      : null,
                  directPriceToggle: directPrice,
                  manualPrice: directPrice
                      ? double.tryParse(manualPriceCtrl.text)
                      : null,
                  quantity: existing.quantity,
                  source: existing.source,
                  createdAt: existing.createdAt,
                  updatedAt: existing.updatedAt,
                );
                await DatabaseHelper.instance.restockProduct(
                  updated,
                  quantityAdded: double.parse(qtyCtrl.text),
                  purchaseDate: purchaseDate,
                  source: ProductSource.mobile,
                );
                hasUserEdited = false;
                if (ctx.mounted) Navigator.pop(ctx);
                _loadProducts();
                return;
              }
              final p = Product(
                id: product?.id,
                uuid: product?.uuid,
                shopId: product?.shopId ?? 'local-shop',
                productCode: _optionalControllerText(productCodeCtrl),
                barcode: _optionalControllerText(barcodeCtrl),
                name: name,
                categoryId: product?.categoryId,
                category: selectedCategory,
                supplierId: product?.supplierId,
                supplier: selectedSupplier,
                unitId: product?.unitId,
                unit: selectedUnit,
                mrp: preview.sellingPrice,
                purchasePrice: double.parse(purchaseCtrl.text),
                gstPercent: gstCustom ? double.tryParse(gstCtrl.text) : null,
                overheadCost: overheadCustom
                    ? double.tryParse(overheadCtrl.text)
                    : null,
                profitMarginPercent: marginCustom
                    ? double.tryParse(marginCtrl.text)
                    : null,
                directPriceToggle: directPrice,
                manualPrice: directPrice
                    ? double.tryParse(manualPriceCtrl.text)
                    : null,
                quantity: double.parse(qtyCtrl.text),
                source: product?.source ?? ProductSource.mobile,
                createdAt: product?.createdAt,
                updatedAt: product?.updatedAt,
              );
              if (isEditing) {
                await DatabaseHelper.instance.updateProduct(p);
              } else {
                await DatabaseHelper.instance.insertProduct(p);
              }
              hasUserEdited = false;
              if (ctx.mounted) Navigator.pop(ctx);
              _loadProducts();
            } catch (e) {
              if (ctx.mounted) setSheet(() => isSaving = false);
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          }

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) requestClose();
            },
            child: SafeArea(
              top: false,
              bottom: false,
              child: Container(
                width: double.infinity,
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ProductSheetHeader(
                        title: isEditing ? 'Edit Product' : 'Add Product',
                        onClose: requestClose,
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _EditorSection(
                                title: 'Product Details',
                                icon: Icons.inventory_2_outlined,
                                trailing: selectedExistingProduct != null
                                    ? const _ModePill(
                                        label: 'Update stock',
                                        active: true,
                                      )
                                    : _SourcePill(
                                        label: isEditing
                                            ? product.sourceLabel
                                            : 'Mobile product',
                                        imported: product?.isImported ?? false,
                                      ),
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: nameCtrl,
                                      textCapitalization:
                                          TextCapitalization.words,
                                      decoration: InputDecoration(
                                        labelText: 'Product Name *',
                                        errorText: nameError,
                                        prefixIcon: const Icon(
                                          Icons.label_outline_rounded,
                                          size: 18,
                                        ),
                                      ),
                                      onChanged: (_) {
                                        markEdited();
                                        hideProductSuggestions = false;
                                        selectedExistingProduct = null;
                                        if (nameError != null) {
                                          setSheet(() => nameError = null);
                                        } else {
                                          setSheet(() {});
                                        }
                                      },
                                      validator: (v) =>
                                          (v == null || v.trim().isEmpty)
                                          ? 'Required'
                                          : null,
                                    ),
                                    if (!isEditing &&
                                        !hideProductSuggestions &&
                                        _matchingProducts(
                                          nameCtrl.text,
                                        ).isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      _ProductSuggestionList(
                                        products: _matchingProducts(
                                          nameCtrl.text,
                                        ),
                                        summaries: _purchaseSummaries,
                                        onSelected: (match) {
                                          setSheet(() {
                                            selectedExistingProduct = match;
                                            hideProductSuggestions = true;
                                            nameError = null;
                                            setFieldText(nameCtrl, match.name);
                                            setFieldText(
                                              productCodeCtrl,
                                              match.productCode ?? '',
                                            );
                                            setFieldText(
                                              barcodeCtrl,
                                              match.barcode ?? '',
                                            );
                                            setFieldText(
                                              purchaseCtrl,
                                              match.purchasePrice
                                                  .toStringAsFixed(2),
                                            );
                                            setFieldText(
                                              manualPriceCtrl,
                                              (match.manualPrice ?? match.mrp)
                                                  .toStringAsFixed(2),
                                            );
                                            setFieldText(qtyCtrl, '');
                                            setFieldText(totalCtrl, '');
                                            selectedCategory = match.category;
                                            selectedSupplier = match.supplier;
                                            selectedUnit = match.unit;
                                            gstCustom =
                                                match.gstPercent != null;
                                            overheadCustom =
                                                match.overheadCost != null;
                                            marginCustom =
                                                match.profitMarginPercent !=
                                                null;
                                            setFieldText(
                                              gstCtrl,
                                              (match.gstPercent ??
                                                      effectiveGst())
                                                  .toStringAsFixed(2),
                                            );
                                            setFieldText(
                                              overheadCtrl,
                                              (match.overheadCost ??
                                                      effectiveOverhead())
                                                  .toStringAsFixed(2),
                                            );
                                            setFieldText(
                                              marginCtrl,
                                              (match.profitMarginPercent ??
                                                      effectiveMargin())
                                                  .toStringAsFixed(2),
                                            );
                                            directPrice =
                                                match.directPriceToggle;
                                          });
                                        },
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: productCodeCtrl,
                                            textCapitalization:
                                                TextCapitalization.characters,
                                            decoration: const InputDecoration(
                                              labelText: 'Product Code',
                                              prefixIcon: Icon(
                                                Icons.tag_outlined,
                                                size: 18,
                                              ),
                                            ),
                                            onChanged: (_) {
                                              markEdited();
                                              setSheet(() {});
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: TextFormField(
                                            controller: barcodeCtrl,
                                            keyboardType: TextInputType.text,
                                            decoration: InputDecoration(
                                              labelText: 'Barcode',
                                              prefixIcon: const Icon(
                                                Icons.qr_code_scanner_rounded,
                                                size: 18,
                                              ),
                                              suffixIcon: IconButton(
                                                tooltip: 'Scan barcode',
                                                icon: const Icon(
                                                  Icons.center_focus_strong,
                                                ),
                                                onPressed: () async {
                                                  final value =
                                                      await _scanBarcodeValue(
                                                        ctx,
                                                      );
                                                  if (value == null ||
                                                      !ctx.mounted) {
                                                    return;
                                                  }
                                                  markEdited();
                                                  setFieldText(
                                                    barcodeCtrl,
                                                    value,
                                                  );
                                                  setSheet(() {});
                                                },
                                              ),
                                            ),
                                            onTapOutside: (_) =>
                                                FocusScope.of(ctx).unfocus(),
                                            onChanged: (_) {
                                              markEdited();
                                              setSheet(() {});
                                            },
                                            onFieldSubmitted: (_) =>
                                                FocusScope.of(ctx).unfocus(),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    _OptionDropdown(
                                      label: 'Category',
                                      value: selectedCategory,
                                      options: _categories,
                                      onChanged: (value) {
                                        markEdited();
                                        updateCategoryPricing(value, setSheet);
                                      },
                                      onAdd: () async {
                                        final value =
                                            await _showAddOptionDialog(
                                              'Category',
                                            );
                                        if (value == null ||
                                            !mounted ||
                                            !ctx.mounted) {
                                          return;
                                        }
                                        await DatabaseHelper.instance
                                            .addCategoryOption(value);
                                        if (!mounted || !ctx.mounted) return;
                                        setState(() {
                                          if (!_categories.contains(value)) {
                                            _categories.add(value);
                                            _categories.sort();
                                          }
                                        });
                                        await updateCategoryPricing(
                                          value,
                                          setSheet,
                                        );
                                        markEdited();
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _OptionDropdown(
                                            label: 'Supplier',
                                            value: selectedSupplier,
                                            options: _suppliers,
                                            onChanged: (value) {
                                              markEdited();
                                              setSheet(
                                                () => selectedSupplier = value,
                                              );
                                            },
                                            onAdd: () async {
                                              final value =
                                                  await _showAddOptionDialog(
                                                    'Supplier',
                                                  );
                                              if (value == null ||
                                                  !mounted ||
                                                  !ctx.mounted) {
                                                return;
                                              }
                                              await DatabaseHelper.instance
                                                  .addSupplierOption(value);
                                              if (!mounted || !ctx.mounted) {
                                                return;
                                              }
                                              setState(() {
                                                if (!_suppliers.contains(
                                                  value,
                                                )) {
                                                  _suppliers.add(value);
                                                  _suppliers.sort();
                                                }
                                              });
                                              markEdited();
                                              setSheet(
                                                () => selectedSupplier = value,
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: _OptionDropdown(
                                            label: 'Unit',
                                            value: selectedUnit,
                                            options: _units,
                                            noValueLabel: 'No Unit',
                                            addLabel: 'Add custom',
                                            onChanged: (value) {
                                              markEdited();
                                              setSheet(
                                                () => selectedUnit = value,
                                              );
                                            },
                                            onAdd: () async {
                                              final value =
                                                  await _showAddOptionDialog(
                                                    'Unit',
                                                  );
                                              if (value == null ||
                                                  !mounted ||
                                                  !ctx.mounted) {
                                                return;
                                              }
                                              await DatabaseHelper.instance
                                                  .addUnitOption(value);
                                              if (!mounted || !ctx.mounted) {
                                                return;
                                              }
                                              setState(() {
                                                if (!_units.any(
                                                  (unit) =>
                                                      unit.toLowerCase() ==
                                                      value.toLowerCase(),
                                                )) {
                                                  _units.add(value);
                                                  _units.sort(
                                                    (a, b) => a
                                                        .toLowerCase()
                                                        .compareTo(
                                                          b.toLowerCase(),
                                                        ),
                                                  );
                                                }
                                              });
                                              markEdited();
                                              setSheet(
                                                () => selectedUnit = value,
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _EditorSection(
                                title: 'Pricing',
                                icon: Icons.payments_outlined,
                                trailing: _ModePill(
                                  label: globalPricing.gstRegistered
                                      ? 'GST registered'
                                      : 'GST not registered',
                                  active: globalPricing.gstRegistered,
                                ),
                                child: Column(
                                  children: [
                                    _DirectPriceControl(
                                      directPrice: directPrice,
                                      onChanged: (value) => setSheet(() {
                                        markEdited();
                                        if (!directPrice) {
                                          formulaMarginText = marginCtrl.text;
                                        }
                                        directPrice = value;
                                        if (directPrice) {
                                          updateMarginFromDirectPrice();
                                        } else {
                                          restoreFormulaMargin();
                                        }
                                      }),
                                    ),
                                    const SizedBox(height: 10),
                                    TextFormField(
                                      controller: purchaseCtrl,
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
                                        labelText: 'Purchase Price *',
                                        prefixText: '₹',
                                        prefixIcon: Icon(
                                          Icons.currency_rupee_rounded,
                                          size: 18,
                                        ),
                                      ),
                                      onChanged: (_) {
                                        markEdited();
                                        updateMarginFromDirectPrice();
                                        setSheet(() {});
                                      },
                                      validator: (value) {
                                        final number = double.tryParse(
                                          value ?? '',
                                        );
                                        return number == null || number <= 0
                                            ? 'Invalid'
                                            : null;
                                      },
                                    ),
                                    if (directPrice) ...[
                                      const SizedBox(height: 10),
                                      TextFormField(
                                        controller: manualPriceCtrl,
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
                                          labelText: 'Direct Selling Price *',
                                          prefixText: '₹',
                                          prefixIcon: Icon(
                                            Icons.sell_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        onChanged: (_) {
                                          markEdited();
                                          updateMarginFromDirectPrice();
                                          setSheet(() {});
                                        },
                                        validator: (value) {
                                          final number = double.tryParse(
                                            value ?? '',
                                          );
                                          return number == null || number <= 0
                                              ? 'Invalid'
                                              : null;
                                        },
                                      ),
                                    ],
                                    const SizedBox(height: 10),
                                    _PricingCalculationTable(
                                      gstCtrl: gstCtrl,
                                      overheadCtrl: overheadCtrl,
                                      marginCtrl: marginCtrl,
                                      directPrice: directPrice,
                                      expanded: priceBreakdownOpen,
                                      breakdown: preview,
                                      gstRegistered:
                                          globalPricing.gstRegistered,
                                      gstSourceHint: sourceHint(
                                        gstCustom,
                                        selectedCategoryPricing?.gstPercent !=
                                            null,
                                      ),
                                      overheadSourceHint: sourceHint(
                                        overheadCustom,
                                        selectedCategoryPricing?.overheadCost !=
                                            null,
                                      ),
                                      marginSourceHint: sourceHint(
                                        directPrice || marginCustom,
                                        selectedCategoryPricing
                                                ?.profitMarginPercent !=
                                            null,
                                      ),
                                      onGstChanged: () {
                                        markEdited();
                                        gstCustom = true;
                                        updateMarginFromDirectPrice();
                                        setSheet(() {});
                                      },
                                      onOverheadChanged: () {
                                        markEdited();
                                        overheadCustom = true;
                                        updateMarginFromDirectPrice();
                                        setSheet(() {});
                                      },
                                      onMarginChanged: () {
                                        markEdited();
                                        marginCustom = true;
                                        formulaMarginText = marginCtrl.text;
                                        updateMarginFromDirectPrice();
                                        setSheet(() {});
                                      },
                                      onResetGst: () => setSheet(() {
                                        markEdited();
                                        gstCustom = false;
                                        setFieldText(
                                          gstCtrl,
                                          effectiveGst().toStringAsFixed(2),
                                        );
                                        updateMarginFromDirectPrice();
                                      }),
                                      onResetOverhead: () => setSheet(() {
                                        markEdited();
                                        overheadCustom = false;
                                        setFieldText(
                                          overheadCtrl,
                                          effectiveOverhead().toStringAsFixed(
                                            2,
                                          ),
                                        );
                                        updateMarginFromDirectPrice();
                                      }),
                                      onResetMargin: directPrice
                                          ? null
                                          : () => setSheet(() {
                                              markEdited();
                                              marginCustom = false;
                                              formulaMarginText =
                                                  effectiveMargin()
                                                      .toStringAsFixed(2);
                                              setFieldText(
                                                marginCtrl,
                                                formulaMarginText,
                                              );
                                              updateMarginFromDirectPrice();
                                            }),
                                      onToggleExpanded: () => setSheet(
                                        () => priceBreakdownOpen =
                                            !priceBreakdownOpen,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              _EditorSection(
                                title: 'Stock',
                                icon: Icons.warehouse_outlined,
                                child: Column(
                                  children: [
                                    InkWell(
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: ctx,
                                          initialDate: purchaseDate,
                                          firstDate: DateTime(2020),
                                          lastDate: DateTime.now().add(
                                            const Duration(days: 365),
                                          ),
                                        );
                                        if (picked == null) return;
                                        markEdited();
                                        setSheet(() => purchaseDate = picked);
                                      },
                                      borderRadius: BorderRadius.circular(12),
                                      child: InputDecorator(
                                        decoration: const InputDecoration(
                                          labelText: 'Purchase Date',
                                          prefixIcon: Icon(
                                            Icons.event_outlined,
                                            size: 18,
                                          ),
                                        ),
                                        child: Text(
                                          _formatFullDate(purchaseDate),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: TextFormField(
                                            controller: qtyCtrl,
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
                                              labelText: 'Quantity *',
                                              prefixIcon: Icon(
                                                Icons.layers_outlined,
                                                size: 18,
                                              ),
                                            ),
                                            onChanged: (_) {
                                              markEdited();
                                              setSheet(() {});
                                            },
                                            validator: (v) {
                                              if (v == null || v.isEmpty) {
                                                return 'Required';
                                              }
                                              final n = double.tryParse(v);
                                              return (n == null || n < 0)
                                                  ? 'Invalid'
                                                  : null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 10),
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
                                              markEdited();
                                              updateQtyFromTotal();
                                              setSheet(() {});
                                            },
                                            validator: (v) {
                                              if (v == null || v.isEmpty) {
                                                return null;
                                              }
                                              final n = double.tryParse(v);
                                              return (n == null || n < 0)
                                                  ? 'Invalid'
                                                  : null;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      _ProductSheetActionBar(
                        sellingPrice: preview.sellingPrice,
                        unit: selectedUnit,
                        isEditing: isEditing,
                        isSaving: isSaving,
                        onPressed: saveProduct,
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
        productCodeCtrl.dispose();
        barcodeCtrl.dispose();
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
    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) _clearProductSelection();
      },
      child: Scaffold(
        backgroundColor: AppColors.cream,
        appBar: AppBar(
          title: _selectionMode
              ? Text(
                  '${_selectedProductIds.length} selected',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                )
              : _searchOpen
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
            if (_selectionMode) ...[
              IconButton(
                onPressed: _clearProductSelection,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear selection',
              ),
            ] else ...[
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
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _allProducts.isEmpty
            ? _buildEmpty()
            : _buildContent(),
        floatingActionButton: Column(
          mainAxisSize: MainAxisSize.min,
          children: _selectionMode
              ? []
              : [
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
                child: _ProductFilterButton(
                  count: _activeFilterCount,
                  onTap: _showProductFilters,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SortDropdownButton(
                  label: 'Sort: ${_sortMode.label}',
                  onTap: _showSortOptions,
                ),
              ),
            ],
          ),
        ),
        if (_activeFilterCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_selectedCategories.isNotEmpty)
                    _ActiveFilterChip(
                      label: _selectedCategories.length == 1
                          ? 'Category: ${_selectedCategories.first}'
                          : 'Category: ${_selectedCategories.length}',
                      onDeleted: () {
                        setState(_selectedCategories.clear);
                        _applyFilter();
                      },
                    ),
                  if (_selectedSuppliers.isNotEmpty)
                    _ActiveFilterChip(
                      label: _selectedSuppliers.length == 1
                          ? 'Supplier: ${_selectedSuppliers.first}'
                          : 'Supplier: ${_selectedSuppliers.length}',
                      onDeleted: () {
                        setState(_selectedSuppliers.clear);
                        _applyFilter();
                      },
                    ),
                  if (_selectedPurchaseDate != null)
                    _ActiveFilterChip(
                      label:
                          'Date: ${_formatShortDate(_selectedPurchaseDate!)}',
                      onDeleted: () {
                        setState(() {
                          _selectedPurchaseDate = null;
                          _purchaseDateProductIds = {};
                        });
                        _applyFilter();
                      },
                    ),
                  _ActiveFilterChip(
                    label: 'Clear all',
                    onDeleted: _clearAllFilters,
                    isClearAction: true,
                  ),
                ],
              ),
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
        if (_selectionMode)
          _BulkSelectionBar(
            count: _selectedProductIds.length,
            allVisibleSelected:
                _filtered.isNotEmpty &&
                _filtered
                    .map((product) => product.id)
                    .whereType<int>()
                    .every(_selectedProductIds.contains),
            onSelectAll: _selectAllFilteredProducts,
            onClear: _clearProductSelection,
            onSetCategory: _showBulkCategoryPicker,
            onSetSupplier: _showBulkSupplierPicker,
            onDelete: _deleteSelectedProducts,
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
                    purchaseSummary: _filtered[i].id == null
                        ? null
                        : _purchaseSummaries[_filtered[i].id],
                    lowStockThreshold: _lowStockThreshold,
                    selectionMode: _selectionMode,
                    isSelected:
                        _filtered[i].id != null &&
                        _selectedProductIds.contains(_filtered[i].id),
                    onTap: () => _selectionMode
                        ? _toggleProductSelection(_filtered[i])
                        : _showAddEditSheet(product: _filtered[i]),
                    onLongPress: () => _toggleProductSelection(_filtered[i]),
                    onHistory: () => _showStockHistory(_filtered[i]),
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

String _formatShortDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

String _formatFullDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _formatQuantityInput(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(3)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String? _optionalControllerText(TextEditingController controller) {
  final text = controller.text.trim();
  return text.isEmpty ? null : text;
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

class _ProductFilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ProductFilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasSelection = count > 0;
    return OutlinedButton.icon(
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
      icon: const Icon(Icons.tune_rounded, size: 17),
      label: Text(
        hasSelection ? 'Filter ($count)' : 'Filter',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  final String label;
  final VoidCallback onDeleted;
  final bool isClearAction;

  const _ActiveFilterChip({
    required this.label,
    required this.onDeleted,
    this.isClearAction = false,
  });

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isClearAction ? AppColors.textMuted : AppColors.navy,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
      deleteIcon: Icon(
        isClearAction ? Icons.filter_alt_off_rounded : Icons.close_rounded,
        size: 16,
      ),
      onDeleted: onDeleted,
      backgroundColor: isClearAction
          ? Colors.white
          : AppColors.navy.withValues(alpha: 0.08),
      side: BorderSide(
        color: isClearAction ? AppColors.creamDark : AppColors.navy,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _SortDropdownButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SortDropdownButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.creamDark),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: const Icon(Icons.sort_rounded, size: 17),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _FilterSheetSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<String> options;
  final Set<String> selected;
  final String emptyText;
  final void Function(String value, bool selected) onChanged;

  const _FilterSheetSection({
    required this.title,
    required this.icon,
    required this.options,
    required this.selected,
    required this.emptyText,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.creamDark),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.navy),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (options.isEmpty)
            Text(emptyText, style: const TextStyle(color: AppColors.textMuted))
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 164),
              child: Scrollbar(
                thumbVisibility: options.length > 8,
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.only(right: 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: options
                        .map(
                          (option) => FilterChip(
                            label: Text(
                              option,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            selected: selected.contains(option),
                            onSelected: (value) => onChanged(option, value),
                            selectedColor: AppColors.navy.withValues(
                              alpha: 0.12,
                            ),
                            checkmarkColor: AppColors.navy,
                            side: BorderSide(
                              color: selected.contains(option)
                                  ? AppColors.navy
                                  : AppColors.creamDark,
                            ),
                            backgroundColor: Colors.white,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PurchaseDateFilterTile extends StatelessWidget {
  final DateTime? date;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const _PurchaseDateFilterTile({
    required this.date,
    required this.onPick,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.5),
        border: Border.all(color: AppColors.creamDark),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_outlined, size: 18, color: AppColors.navy),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Purchase Date',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  date == null ? 'Any date' : _formatFullDate(date!),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (onClear != null)
            IconButton(
              onPressed: onClear,
              tooltip: 'Clear date',
              icon: const Icon(Icons.close_rounded),
            ),
          OutlinedButton(
            onPressed: onPick,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.navy,
              side: const BorderSide(color: AppColors.creamDark),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(date == null ? 'Choose' : 'Change'),
          ),
        ],
      ),
    );
  }
}

class _ProductSheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _ProductSheetHeader({required this.title, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: AppColors.creamDark)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          children: [
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.creamDark,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.cream,
                    foregroundColor: AppColors.textDark,
                    minimumSize: const Size(38, 38),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? trailing;

  const _EditorSection({
    required this.title,
    required this.icon,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.creamDark),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.navy.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 17, color: AppColors.navy),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              if (trailing != null)
                Flexible(
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: trailing!,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ModePill extends StatelessWidget {
  final String label;
  final bool active;

  const _ModePill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: active
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.amber.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? AppColors.success : AppColors.amber,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DirectPriceControl extends StatelessWidget {
  final bool directPrice;
  final ValueChanged<bool> onChanged;

  const _DirectPriceControl({
    required this.directPrice,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PriceModeSegment(
              icon: Icons.auto_graph_rounded,
              title: 'Formula',
              subtitle: 'GST + margin',
              selected: !directPrice,
              onTap: () {
                if (directPrice) onChanged(false);
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _PriceModeSegment(
              icon: Icons.edit_note_rounded,
              title: 'Direct',
              subtitle: 'Manual price',
              selected: directPrice,
              onTap: () {
                if (!directPrice) onChanged(true);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceModeSegment extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _PriceModeSegment({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: selected
                ? Border.all(color: AppColors.navy.withValues(alpha: 0.18))
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: selected ? AppColors.navy : AppColors.textMuted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppColors.navy : AppColors.textDark,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSheetActionBar extends StatelessWidget {
  final double sellingPrice;
  final String? unit;
  final bool isEditing;
  final bool isSaving;
  final Future<void> Function() onPressed;

  const _ProductSheetActionBar({
    required this.sellingPrice,
    required this.unit,
    required this.isEditing,
    required this.isSaving,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final unitText = unit == null || unit!.trim().isEmpty ? '' : ' / $unit';
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 14 + bottomPadding),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.creamDark)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selling Price',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '₹${sellingPrice.toStringAsFixed(2)}$unitText',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: isSaving ? null : onPressed,
            icon: isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(isEditing ? Icons.check_rounded : Icons.add_rounded),
            label: Text(
              isSaving
                  ? 'Saving'
                  : isEditing
                  ? 'Update'
                  : 'Add',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PricingCalculationTable extends StatelessWidget {
  final TextEditingController gstCtrl;
  final TextEditingController overheadCtrl;
  final TextEditingController marginCtrl;
  final bool directPrice;
  final bool expanded;
  final PriceBreakdown breakdown;
  final bool gstRegistered;
  final String gstSourceHint;
  final String overheadSourceHint;
  final String marginSourceHint;
  final VoidCallback onGstChanged;
  final VoidCallback onOverheadChanged;
  final VoidCallback onMarginChanged;
  final VoidCallback onResetGst;
  final VoidCallback onResetOverhead;
  final VoidCallback? onResetMargin;
  final VoidCallback onToggleExpanded;

  const _PricingCalculationTable({
    required this.gstCtrl,
    required this.overheadCtrl,
    required this.marginCtrl,
    required this.directPrice,
    required this.expanded,
    required this.breakdown,
    required this.gstRegistered,
    required this.gstSourceHint,
    required this.overheadSourceHint,
    required this.marginSourceHint,
    required this.onGstChanged,
    required this.onOverheadChanged,
    required this.onMarginChanged,
    required this.onResetGst,
    required this.onResetOverhead,
    required this.onResetMargin,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cream.withValues(alpha: 0.65),
        border: Border.all(color: AppColors.creamDark),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Price Breakdown',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        gstRegistered
                            ? 'GST shown on selling price'
                            : 'GST shown on purchase cost',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                _ModePill(
                  label: breakdown.wasDirectPrice ? 'direct' : 'formula',
                  active: !breakdown.wasDirectPrice,
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onToggleExpanded,
                  tooltip: expanded
                      ? 'Hide price breakdown'
                      : 'Show price breakdown',
                  icon: Icon(
                    expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                  ),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(34, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 8),
            if (!gstRegistered)
              _PricingInputRow(
                label: 'GST on purchase',
                controller: gstCtrl,
                suffixText: '%',
                result: breakdown.landedCost,
                delta: breakdown.gstAmount,
                sourceHint: gstSourceHint,
                onResetSource: onResetGst,
                onChanged: onGstChanged,
              ),
            _PricingInputRow(
              label: 'Overhead',
              controller: overheadCtrl,
              prefixText: '₹',
              result: breakdown.totalCost,
              delta: breakdown.overheadCost,
              sourceHint: overheadSourceHint,
              onResetSource: onResetOverhead,
              onChanged: onOverheadChanged,
            ),
            _PricingInputRow(
              label: 'Margin',
              controller: marginCtrl,
              suffixText: '%',
              result: breakdown.preGstSellingPrice,
              delta: breakdown.profitAmount,
              sourceHint: marginSourceHint,
              onResetSource: onResetMargin,
              onChanged: onMarginChanged,
              readOnly: directPrice,
            ),
            if (gstRegistered)
              _PricingInputRow(
                label: 'GST on sell',
                controller: gstCtrl,
                suffixText: '%',
                result: breakdown.sellingPrice,
                delta: breakdown.gstAmount,
                sourceHint: gstSourceHint,
                onResetSource: onResetGst,
                onChanged: onGstChanged,
              ),
          ],
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
  final bool readOnly;
  final String? sourceHint;
  final VoidCallback? onResetSource;

  const _PricingInputRow({
    required this.label,
    required this.controller,
    this.prefixText,
    this.suffixText,
    required this.result,
    this.delta,
    required this.onChanged,
    this.readOnly = false,
    this.sourceHint,
    this.onResetSource,
  });

  @override
  Widget build(BuildContext context) {
    final deltaText = delta == null ? '' : '+${delta!.toStringAsFixed(2)}';
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < 340;
        final inputWidth = tight ? 78.0 : 88.0;
        final resultWidth = tight ? 78.0 : 94.0;

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    if (sourceHint != null) ...[
                      const SizedBox(height: 2),
                      _SourceResetChip(
                        label: sourceHint!,
                        onReset: onResetSource,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: inputWidth,
                child: TextFormField(
                  controller: controller,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^\d*\.?\d{0,2}'),
                    ),
                  ],
                  textAlign: TextAlign.end,
                  readOnly: readOnly,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: readOnly
                        ? AppColors.creamDark.withValues(alpha: 0.7)
                        : Colors.white,
                    prefixText: prefixText,
                    suffixText: suffixText,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (_) => onChanged(),
                  validator: (value) {
                    final number = double.tryParse(value ?? '');
                    if (value != null && value.isNotEmpty && number == null) {
                      return 'Invalid';
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: resultWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (delta != null)
                      Text(
                        deltaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    Text(
                      '₹${result.toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        color: AppColors.textDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SourceResetChip extends StatelessWidget {
  final String label;
  final VoidCallback? onReset;

  const _SourceResetChip({required this.label, this.onReset});

  @override
  Widget build(BuildContext context) {
    final canReset = onReset != null && label == 'product custom';
    return PopupMenuButton<String>(
      enabled: onReset != null,
      tooltip: 'Pricing source',
      padding: EdgeInsets.zero,
      onSelected: (_) => onReset?.call(),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: 'default',
          enabled: canReset,
          child: Row(
            children: [
              const Icon(Icons.restart_alt_rounded, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canReset
                      ? 'Use category/global default'
                      : 'Already using default',
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: label == 'product custom'
              ? AppColors.amber.withValues(alpha: 0.12)
              : AppColors.navy.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: label == 'product custom'
                      ? AppColors.amber
                      : AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (onReset != null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 13,
                color: label == 'product custom'
                    ? AppColors.amber
                    : AppColors.textMuted,
              ),
            ],
          ],
        ),
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
      alignment: Alignment.centerRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              imported
                  ? Icons.upload_file_rounded
                  : Icons.phone_android_rounded,
              size: 12,
              color: AppColors.navy,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BulkSelectionBar extends StatelessWidget {
  final int count;
  final bool allVisibleSelected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback onSetCategory;
  final VoidCallback onSetSupplier;
  final VoidCallback onDelete;

  const _BulkSelectionBar({
    required this.count,
    required this.allVisibleSelected,
    required this.onSelectAll,
    required this.onClear,
    required this.onSetCategory,
    required this.onSetSupplier,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _SelectionToggleButton(
            allVisibleSelected: allVisibleSelected,
            onTap: allVisibleSelected ? onClear : onSelectAll,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count selected',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _BulkActionChip(
                    icon: Icons.category_outlined,
                    label: 'Category',
                    onTap: onSetCategory,
                  ),
                  const SizedBox(width: 8),
                  _BulkActionChip(
                    icon: Icons.storefront_outlined,
                    label: 'Supplier',
                    onTap: onSetSupplier,
                  ),
                  const SizedBox(width: 8),
                  _BulkActionChip(
                    icon: Icons.delete_outline,
                    label: 'Delete',
                    onTap: onDelete,
                    destructive: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionToggleButton extends StatelessWidget {
  final bool allVisibleSelected;
  final VoidCallback onTap;

  const _SelectionToggleButton({
    required this.allVisibleSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: allVisibleSelected ? 'Clear selection' : 'Select all visible',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            allVisibleSelected
                ? Icons.deselect_rounded
                : Icons.select_all_rounded,
            color: Colors.white,
            size: 17,
          ),
        ),
      ),
    );
  }
}

class _BulkActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _BulkActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = destructive ? AppColors.error : AppColors.navy;
    return ActionChip(
      onPressed: onTap,
      avatar: Icon(icon, size: 16, color: foreground),
      label: Text(label),
      labelStyle: TextStyle(color: foreground, fontWeight: FontWeight.w800),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: destructive
            ? AppColors.error.withValues(alpha: 0.25)
            : Colors.white,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _ProductSuggestionList extends StatelessWidget {
  final List<Product> products;
  final Map<int, ProductPurchaseSummary> summaries;
  final ValueChanged<Product> onSelected;

  const _ProductSuggestionList({
    required this.products,
    required this.summaries,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.creamDark),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: products.length,
        separatorBuilder: (_, index) =>
            Divider(height: 1, indent: 56, color: AppColors.creamDark),
        itemBuilder: (_, index) {
          final product = products[index];
          final summary = product.id == null ? null : summaries[product.id];
          final lastDate = summary?.lastPurchaseDate == null
              ? 'No purchase date'
              : 'Last ${_formatFullDate(summary!.lastPurchaseDate!)}';
          return ListTile(
            dense: true,
            leading: const CircleAvatar(
              radius: 17,
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              child: Icon(Icons.inventory_2_outlined, size: 17),
            ),
            title: Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            subtitle: Text(
              [
                product.quantityLabel,
                lastDate,
                if (product.productCode != null) 'Code ${product.productCode}',
                if (product.barcode != null) 'Barcode ${product.barcode}',
                '₹${product.purchasePrice.toStringAsFixed(2)}',
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: const Icon(Icons.add_box_outlined),
            onTap: () => onSelected(product),
          );
        },
      ),
    );
  }
}

class _ImportPreviewTable extends StatelessWidget {
  final List<Product> products;

  const _ImportPreviewTable({required this.products});

  @override
  Widget build(BuildContext context) {
    final visible = products.take(12).toList();
    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.creamDark),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 720,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(10),
            children: [
              const _ImportPreviewRow(
                name: 'Product',
                code: 'Code',
                barcode: 'Barcode',
                quantity: 'Qty',
                purchase: 'Purchase',
                selling: 'Selling',
                header: true,
              ),
              const Divider(height: 12),
              ...visible.map(
                (product) => _ImportPreviewRow(
                  name: product.name,
                  code: product.productCode ?? '-',
                  barcode: product.barcode ?? '-',
                  quantity: product.quantityLabel,
                  purchase: '₹${product.purchasePrice.toStringAsFixed(2)}',
                  selling: product.priceLabel,
                ),
              ),
              if (products.length > visible.length)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${products.length - visible.length} more rows',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportPreviewRow extends StatelessWidget {
  final String name;
  final String code;
  final String barcode;
  final String quantity;
  final String purchase;
  final String selling;
  final bool header;

  const _ImportPreviewRow({
    required this.name,
    required this.code,
    required this.barcode,
    required this.quantity,
    required this.purchase,
    required this.selling,
    this.header = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: header ? AppColors.navy : AppColors.textDark,
      fontSize: 12,
      fontWeight: header ? FontWeight.w900 : FontWeight.w600,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          _cell(name, 180, style),
          _cell(code, 90, style),
          _cell(barcode, 120, style),
          _cell(quantity, 72, style, alignEnd: true),
          _cell(purchase, 88, style, alignEnd: true),
          _cell(selling, 110, style, alignEnd: true),
        ],
      ),
    );
  }

  Widget _cell(
    String text,
    double width,
    TextStyle style, {
    bool alignEnd = false,
  }) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        style: style,
      ),
    );
  }
}

class _StockMovementHistorySheet extends StatelessWidget {
  final Product product;
  final List<StockMovement> movements;

  const _StockMovementHistorySheet({
    required this.product,
    required this.movements,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.82,
        ),
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
            Text(
              'Stock History',
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${product.name} • Current ${product.quantityLabel}',
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: movements.isEmpty
                  ? const Center(
                      child: Text(
                        'No stock movement yet',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: movements.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, color: AppColors.creamDark),
                      itemBuilder: (_, index) =>
                          _StockMovementRow(movement: movements[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockMovementRow extends StatelessWidget {
  final StockMovement movement;

  const _StockMovementRow({required this.movement});

  @override
  Widget build(BuildContext context) {
    final positive = movement.quantityDelta >= 0;
    final color = positive ? AppColors.success : AppColors.error;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              positive ? Icons.add_rounded : Icons.remove_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _movementLabel(movement.movementType),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    _formatFullDate(movement.createdAt),
                    if (movement.sourceType != null) movement.sourceType!,
                    if (movement.unitCost != null)
                      '₹${movement.unitCost!.toStringAsFixed(2)}',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${_formatQuantityInput(movement.quantityDelta)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  String _movementLabel(String type) {
    switch (type) {
      case StockMovementType.purchase:
        return 'Purchase / Restock';
      case StockMovementType.sale:
        return 'Sale';
      case StockMovementType.adjustment:
        return 'Adjustment';
      case StockMovementType.returnIn:
        return 'Return';
      case StockMovementType.voidSale:
        return 'Bill void';
      default:
        return type;
    }
  }
}

// ── Product Card (Professional Design) ──
class _ProductCard extends StatelessWidget {
  final Product product;
  final ProductPurchaseSummary? purchaseSummary;
  final int lowStockThreshold;
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onHistory;
  final VoidCallback onDelete;

  const _ProductCard({
    required this.product,
    this.purchaseSummary,
    required this.lowStockThreshold,
    required this.selectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onHistory,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isLowStock = product.quantity <= lowStockThreshold;
    final isOutOfStock = product.quantity == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.navy.withValues(alpha: 0.06)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: isSelected
            ? Border.all(color: AppColors.navy, width: 1.4)
            : isOutOfStock
            ? Border.all(color: AppColors.error.withValues(alpha: 0.3))
            : null,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: category badge + source + delete
              Row(
                children: [
                  if (selectionMode) ...[
                    Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 22,
                      color: isSelected ? AppColors.navy : AppColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                  ],
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
                  if (!selectionMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: onHistory,
                          icon: const Icon(Icons.history_rounded, size: 18),
                          tooltip: 'Stock history',
                          visualDensity: VisualDensity.compact,
                        ),
                        IconButton(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          tooltip: 'Delete',
                          color: AppColors.textMuted.withValues(alpha: 0.5),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
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
              if (product.productCode != null || product.barcode != null) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (product.productCode != null)
                      _InfoChip(
                        icon: Icons.tag_outlined,
                        label: product.productCode!,
                      ),
                    if (product.barcode != null)
                      _InfoChip(
                        icon: Icons.qr_code_scanner_rounded,
                        label: product.barcode!,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              if (purchaseSummary?.lastPurchaseDate != null) ...[
                Row(
                  children: [
                    Icon(
                      Icons.event_available_outlined,
                      size: 14,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Last purchase ${_formatFullDate(purchaseSummary!.lastPurchaseDate!)}',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
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

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.cream,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textMuted),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
