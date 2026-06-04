import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/product.dart';
import '../models/product_purchase.dart';
import '../models/pricing.dart';
import '../utils/csv_importer.dart';
import 'qr_sheet_screen.dart';

part 'products/product_models.dart';
part 'products/product_formatters.dart';
part 'products/product_filter_widgets.dart';
part 'products/new_purchase_screen.dart';
part 'products/product_editor_widgets.dart';
part 'products/product_bulk_actions.dart';
part 'products/product_import_widgets.dart';
part 'products/stock_history_sheet.dart';
part 'products/product_cards.dart';

class ProductsScreen extends StatefulWidget {
  final int refreshToken;
  final bool isActiveMainTab;
  final int openPurchaseFlowToken;
  final VoidCallback? onPurchaseFlowComplete;
  final VoidCallback? onBackToHome;

  const ProductsScreen({
    super.key,
    this.refreshToken = 0,
    this.isActiveMainTab = true,
    this.openPurchaseFlowToken = 0,
    this.onPurchaseFlowComplete,
    this.onBackToHome,
  });

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
  bool _isOpeningRequestedPurchaseFlow = false;
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
    if (oldWidget.openPurchaseFlowToken != widget.openPurchaseFlowToken) {
      _openRequestedPurchaseFlow();
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

  void _openRequestedPurchaseFlow() {
    if (_isOpeningRequestedPurchaseFlow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _isOpeningRequestedPurchaseFlow) return;
      _isOpeningRequestedPurchaseFlow = true;
      try {
        await _loadProducts();
        if (!mounted) return;
        await _showNewPurchaseFlow();
      } finally {
        _isOpeningRequestedPurchaseFlow = false;
        widget.onPurchaseFlowComplete?.call();
      }
    });
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
            color: AppColors.surfaceOf(ctx),
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
                    color: AppColors.borderStrongOf(ctx),
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
                      ? Icon(Icons.check_rounded, color: AppColors.brandOf(ctx))
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
            color: AppColors.surfaceOf(ctx),
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
                    color: AppColors.borderStrongOf(ctx),
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
  /// Picks a file and parses it into products. Shows a loading spinner over
  /// [dialogContext] (defaults to the screen). Returns null on cancel/empty/
  /// error (an error is surfaced via snackbar/dialog).
  Future<List<Product>?> _pickAndParseImport([
    BuildContext? dialogContext,
  ]) async {
    final ctx = dialogContext ?? context;
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt', 'xlsx'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;

    // Show loading
    if (ctx.mounted) {
      showDialog(
        context: ctx,
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

      if (ctx.mounted) Navigator.pop(ctx); // dismiss loading

      if (products.isEmpty) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('No products found in file')),
          );
        }
        return null;
      }
      return products;
    } catch (e) {
      if (ctx.mounted) Navigator.pop(ctx); // dismiss loading
      _showImportError(e);
      return null;
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
            color: AppColors.surfaceOf(ctx),
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Scan Barcode',
                        style: TextStyle(
                          color: AppColors.inkOf(ctx),
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
              color: AppColors.surfaceOf(ctx),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrongOf(ctx),
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
                        backgroundColor: AppColors.brandOf(ctx),
                        foregroundColor: AppColors.isDark(ctx)
                            ? Colors.black
                            : Colors.white,
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

  // ── New Purchase (step 1: date + supplier) ──
  Future<void> _showNewPurchaseFlow() async {
    var purchaseDate = DateTime.now();
    String? selectedSupplier;

    final proceed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          return SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceOf(ctx),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: AppColors.isDark(ctx)
                    ? Border.all(color: AppColors.borderOf(ctx))
                    : null,
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ProductSheetHeader(
                    title: 'New Purchase',
                    onClose: () => Navigator.pop(ctx, false),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _EditorSection(
                          title: 'Purchase Details',
                          icon: Icons.receipt_long_outlined,
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
                              _OptionDropdown(
                                label: 'Supplier',
                                value: selectedSupplier,
                                options: _suppliers,
                                onChanged: (value) =>
                                    setSheet(() => selectedSupplier = value),
                                onAdd: () async {
                                  final value = await _showAddOptionDialog(
                                    'Supplier',
                                  );
                                  if (value == null ||
                                      !mounted ||
                                      !ctx.mounted) {
                                    return;
                                  }
                                  await DatabaseHelper.instance
                                      .addSupplierOption(value);
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Next'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (proceed != true || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _NewPurchaseScreen(
          purchaseDate: purchaseDate,
          supplier: selectedSupplier,
          addProduct: (stagedNames) => _showAddEditSheet(
            stageOnly: true,
            initialPurchaseDate: purchaseDate,
            initialSupplier: selectedSupplier,
            stagedNames: stagedNames,
          ),
          editProduct: (draft, stagedNames) => _showAddEditSheet(
            product: draft.product,
            stageOnly: true,
            initialPurchaseDate: purchaseDate,
            initialSupplier: selectedSupplier,
            stagedNames: stagedNames,
            stagedRestockTarget: draft.restockTarget,
          ),
          pickAndParseImport: _pickAndParseImport,
          matchExisting: _matchExistingByName,
          commitBatch: _commitPurchaseBatch,
        ),
      ),
    );
    if (mounted) _loadProducts();
  }

  /// Finds an existing catalog product whose name matches [name]
  /// (case-insensitive), or null. Used to mark imported/edited drafts as
  /// restocks.
  Product? _matchExistingByName(String name) {
    final lower = name.trim().toLowerCase();
    for (final p in _allProducts) {
      if (p.name.toLowerCase() == lower) return p;
    }
    return null;
  }

  /// Commits a staged purchase batch in one database transaction: restock
  /// matches, insert the rest. Returns the number of items committed.
  Future<int> _commitPurchaseBatch(
    List<_PurchaseDraft> drafts,
    DateTime purchaseDate,
  ) async {
    final commits = drafts.map((draft) {
      final target = draft.restockTarget ?? _matchExistingByName(draft.name);
      return ProductPurchaseCommit(
        product: draft.product,
        quantityAdded: draft.quantityAdded,
        restockTarget: target,
      );
    }).toList();
    return DatabaseHelper.instance.commitProductPurchaseBatch(
      commits,
      purchaseDate: purchaseDate,
    );
  }

  // ── Add/Edit Sheet ──
  // When [stageOnly] is true, saving does NOT touch the DB; it returns a
  // [_PurchaseDraft] for the caller (the batch staging screen) to commit later.
  // [stagedNames] are names already in the current batch, blocked as duplicates.
  Future<_PurchaseDraft?> _showAddEditSheet({
    Product? product,
    DateTime? initialPurchaseDate,
    String? initialSupplier,
    bool stageOnly = false,
    Set<String> stagedNames = const {},
    Product? stagedRestockTarget,
  }) async {
    final isCatalogEditing = product != null && !stageOnly;
    final isEditing = product != null;
    final db = DatabaseHelper.instance;
    final globalPricing = await db.getGlobalPricingSettings();
    var selectedCategoryPricing = product?.category == null
        ? null
        : await db.getCategoryPricing(product!.category!);
    if (!mounted) return null;

    final nameCtrl = TextEditingController(text: product?.name ?? '');
    final productCodeCtrl = TextEditingController(
      text: product?.productCode ?? '',
    );
    final barcodeCtrl = TextEditingController(text: product?.barcode ?? '');
    final hsnCtrl = TextEditingController(text: product?.hsnCode ?? '');
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
    String? selectedSupplier = product?.supplier ?? initialSupplier;
    String? selectedUnit = product?.unit;
    Product? selectedExistingProduct = stagedRestockTarget;
    final lockedRestockTarget = stageOnly && stagedRestockTarget != null;
    var purchaseDate = initialPurchaseDate ?? DateTime.now();
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
        shopId: product?.shopId ?? '',
        productCode: productCodeCtrl.text,
        barcode: barcodeCtrl.text,
        name: nameCtrl.text.trim().isEmpty ? 'Product' : nameCtrl.text.trim(),
        hsnCode: hsnCtrl.text,
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

    final draft =
        await showModalBottomSheet<_PurchaseDraft>(
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
                      !isCatalogEditing && selectedExistingProduct != null;

                  // In staging mode, block a name already in this batch (unless it's
                  // the same staged item being edited).
                  if (stageOnly && stagedNames.contains(name.toLowerCase())) {
                    if (ctx.mounted) {
                      setSheet(() {
                        nameError = '"$name" is already in this batch';
                        isSaving = false;
                      });
                    }
                    return;
                  }

                  // For a normal (non-staging) save we hard-block duplicate catalog
                  // names. In staging mode a catalog match just becomes a restock on
                  // confirm, so we don't block it here.
                  final unique =
                      stageOnly ||
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
                      hsnCode: _optionalControllerText(hsnCtrl),
                      name: name,
                      categoryId: existing.categoryId,
                      category: selectedCategory,
                      supplierId: existing.supplierId,
                      supplier: selectedSupplier,
                      unitId: existing.unitId,
                      unit: selectedUnit,
                      mrp: preview.sellingPrice,
                      purchasePrice: double.parse(purchaseCtrl.text),
                      gstPercent: gstCustom
                          ? double.tryParse(gstCtrl.text)
                          : null,
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
                    final quantityAdded = double.parse(qtyCtrl.text);
                    if (stageOnly) {
                      hasUserEdited = false;
                      if (ctx.mounted) {
                        Navigator.pop(
                          ctx,
                          _PurchaseDraft(
                            // Carry the added qty on the product so re-editing the
                            // staged row shows it; restockProduct recomputes the
                            // real total at commit, so this value is display-only.
                            product: updated.copyWith(quantity: quantityAdded),
                            quantityAdded: quantityAdded,
                            restockTarget: existing,
                          ),
                        );
                      }
                      return;
                    }
                    await DatabaseHelper.instance.restockProduct(
                      updated,
                      quantityAdded: quantityAdded,
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
                    shopId: product?.shopId ?? '',
                    productCode: _optionalControllerText(productCodeCtrl),
                    barcode: _optionalControllerText(barcodeCtrl),
                    hsnCode: _optionalControllerText(hsnCtrl),
                    name: name,
                    categoryId: product?.categoryId,
                    category: selectedCategory,
                    supplierId: product?.supplierId,
                    supplier: selectedSupplier,
                    unitId: product?.unitId,
                    unit: selectedUnit,
                    mrp: preview.sellingPrice,
                    purchasePrice: double.parse(purchaseCtrl.text),
                    gstPercent: gstCustom
                        ? double.tryParse(gstCtrl.text)
                        : null,
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
                  if (stageOnly) {
                    hasUserEdited = false;
                    if (ctx.mounted) {
                      Navigator.pop(
                        ctx,
                        _PurchaseDraft(
                          product: p,
                          quantityAdded: double.parse(qtyCtrl.text),
                        ),
                      );
                    }
                    return;
                  }
                  if (isEditing) {
                    await DatabaseHelper.instance.updateProduct(p);
                  } else {
                    await DatabaseHelper.instance.insertProduct(
                      p,
                      purchaseDate: purchaseDate,
                    );
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
                    decoration: BoxDecoration(
                      color: AppColors.surfaceOf(ctx),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                      border: AppColors.isDark(ctx)
                          ? Border.all(color: AppColors.borderOf(ctx))
                          : null,
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
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                10,
                                14,
                                14,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!isEditing)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 10,
                                      ),
                                      child: _PurchaseContextBar(
                                        date: purchaseDate,
                                        supplier: selectedSupplier,
                                      ),
                                    ),
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
                                                : 'In-app',
                                            imported:
                                                product?.isImported ?? false,
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
                                            if (!lockedRestockTarget) {
                                              selectedExistingProduct = null;
                                            }
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
                                                setFieldText(
                                                  nameCtrl,
                                                  match.name,
                                                );
                                                setFieldText(
                                                  productCodeCtrl,
                                                  match.productCode ?? '',
                                                );
                                                setFieldText(
                                                  barcodeCtrl,
                                                  match.barcode ?? '',
                                                );
                                                setFieldText(
                                                  hsnCtrl,
                                                  match.hsnCode ?? '',
                                                );
                                                setFieldText(
                                                  purchaseCtrl,
                                                  match.purchasePrice
                                                      .toStringAsFixed(2),
                                                );
                                                setFieldText(
                                                  manualPriceCtrl,
                                                  (match.manualPrice ??
                                                          match.mrp)
                                                      .toStringAsFixed(2),
                                                );
                                                setFieldText(qtyCtrl, '');
                                                setFieldText(totalCtrl, '');
                                                selectedCategory =
                                                    match.category;
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
                                                    TextCapitalization
                                                        .characters,
                                                decoration:
                                                    const InputDecoration(
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
                                                keyboardType:
                                                    TextInputType.text,
                                                decoration: InputDecoration(
                                                  labelText: 'Barcode',
                                                  prefixIcon: const Icon(
                                                    Icons
                                                        .qr_code_scanner_rounded,
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
                                                    FocusScope.of(
                                                      ctx,
                                                    ).unfocus(),
                                                onChanged: (_) {
                                                  markEdited();
                                                  setSheet(() {});
                                                },
                                                onFieldSubmitted: (_) =>
                                                    FocusScope.of(
                                                      ctx,
                                                    ).unfocus(),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        TextFormField(
                                          controller: hsnCtrl,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                            LengthLimitingTextInputFormatter(8),
                                          ],
                                          decoration: const InputDecoration(
                                            labelText: 'HSN/SAC Code',
                                            prefixIcon: Icon(
                                              Icons.numbers_outlined,
                                              size: 18,
                                            ),
                                          ),
                                          onChanged: (_) {
                                            markEdited();
                                            setSheet(() {});
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        _OptionDropdown(
                                          label: 'Category',
                                          value: selectedCategory,
                                          options: _categories,
                                          onChanged: (value) {
                                            markEdited();
                                            updateCategoryPricing(
                                              value,
                                              setSheet,
                                            );
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
                                            if (!mounted || !ctx.mounted) {
                                              return;
                                            }
                                            setState(() {
                                              if (!_categories.contains(
                                                value,
                                              )) {
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
                                              Icons.inventory_2_outlined,
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
                                        const SizedBox(height: 10),
                                        _OptionDropdown(
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
                                                  (a, b) =>
                                                      a.toLowerCase().compareTo(
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
                                                decoration:
                                                    const InputDecoration(
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
                                                decoration:
                                                    const InputDecoration(
                                                      labelText:
                                                          'Stock Value (₹)',
                                                      prefixIcon: Icon(
                                                        Icons
                                                            .calculate_outlined,
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
                                  const SizedBox(height: 10),
                                  _EditorSection(
                                    title: 'Selling Price',
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
                                              formulaMarginText =
                                                  marginCtrl.text;
                                            }
                                            directPrice = value;
                                            if (directPrice) {
                                              updateMarginFromDirectPrice();
                                            } else {
                                              restoreFormulaMargin();
                                            }
                                          }),
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
                                              labelText:
                                                  'Direct Selling Price *',
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
                                              return number == null ||
                                                      number <= 0
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
                                            selectedCategoryPricing
                                                    ?.gstPercent !=
                                                null,
                                          ),
                                          overheadSourceHint: sourceHint(
                                            overheadCustom,
                                            selectedCategoryPricing
                                                    ?.overheadCost !=
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
                                              effectiveOverhead()
                                                  .toStringAsFixed(2),
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
    return draft;
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
      canPop:
          !widget.isActiveMainTab ||
          (!_selectionMode && widget.onBackToHome == null),
      onPopInvokedWithResult: (didPop, result) {
        if (!widget.isActiveMainTab) return;
        if (didPop) return;
        if (_selectionMode) {
          _clearProductSelection();
          return;
        }
        widget.onBackToHome?.call();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: _selectionMode
              ? Text('${_selectedProductIds.length} selected')
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
              : const Text('Products'),
          actions: [
            if (_selectionMode) ...[
              IconButton(
                onPressed: _clearProductSelection,
                icon: const Icon(Icons.close_rounded),
                tooltip: 'Clear selection',
              ),
            ] else ...[
              if (_allProducts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Center(
                    child: StatusPill(
                      label: '${_allProducts.length}',
                      variant: PillVariant.info,
                    ),
                  ),
                ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _searchOpen = !_searchOpen;
                    if (!_searchOpen) _searchCtrl.clear();
                  });
                },
                icon: Icon(_searchOpen ? Icons.close : Icons.search),
              ),
              IconButton(
                onPressed: _openQrSheet,
                icon: const Icon(Icons.qr_code_2),
                tooltip: 'Product labels',
              ),
              const AppInfoAction(
                title: 'Products Help',
                intro:
                    'Products are managed through purchases so stock, supplier, and date stay accurate.',
                sections: [
                  AppInfoSection(
                    title: 'Add stock',
                    points: [
                      'Use New Purchase to select date and supplier, then add or import products.',
                      'If a product name already exists, the purchase becomes a restock for that product.',
                      'Product import is inside New Purchase; it is not a separate catalog action.',
                    ],
                  ),
                  AppInfoSection(
                    title: 'Find and manage products',
                    points: [
                      'Search by name, product code, barcode, category, unit, supplier, or source.',
                      'Long press products to select multiple rows for bulk category, supplier, or delete actions.',
                      'Product labels opens QR or barcode sheets for printing.',
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 8),
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
                  FloatingActionButton(
                    heroTag: 'add',
                    onPressed: _showNewPurchaseFlow,
                    child: const Icon(Icons.add_rounded),
                  ),
                ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: AppRadius.lgRadius,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 36,
                color: AppColors.inkFaint,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No products yet', style: AppText.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a purchase, then add or import products',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: _showNewPurchaseFlow,
              icon: const Icon(Icons.add_shopping_cart_rounded),
              label: const Text('New Purchase'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: _ProductFilterButton(
                  count: _activeFilterCount,
                  onTap: _showProductFilters,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: AppCard(
              color: AppColors.amber.withValues(alpha: 0.08),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: AppSpacing.sm),
                  Text('Updating prices...', style: AppText.body),
                ],
              ),
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
                  child: Text('No matching products', style: AppText.caption),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    120,
                  ),
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
