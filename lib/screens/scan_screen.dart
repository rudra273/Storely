import '../l10n/l10n.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../db/database_helper.dart';
import '../services/app_settings_service.dart';
import '../services/app_log.dart';
import '../services/bill_share.dart';
import '../services/cloud_service.dart';
import '../services/thermal/thermal_printer_service.dart';
import '../models/bill.dart';
import '../models/checkout_settlement.dart';
import '../utils/decimal_text.dart';
import 'package:uuid/uuid.dart';
import '../models/bill_totals.dart';
import '../models/customer.dart';
import '../models/held_bill.dart';
import '../models/product.dart';
import '../models/sale_quantity.dart';
import '../utils/money.dart';
import '../utils/checkout_code.dart';
import 'products_screen.dart' show showCheckoutQuickAdd;
import 'shared/bill_quick_sheet.dart' show showBillQuickSheet;

part 'scan/manual_product_widgets.dart';
part 'scan/customer_suggestion_list.dart';
part 'scan/bill_summary_widgets.dart';
part 'scan/bill_draft.dart';
part 'scan/bill_checkout_sheet.dart';
part 'scan/quantity_input.dart';
part 'scan/party_bar.dart';

enum BillingEntryMode { scan, manual }

class ScanScreen extends StatefulWidget {
  /// Null opens the mode the shop used last (Scan or Search).
  final BillingEntryMode? initialMode;
  final Bill? duplicateFromBill;

  const ScanScreen({super.key, this.initialMode, this.duplicateFromBill});
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _scanCooldown = Duration(seconds: 1);
  static const _invalidScanCooldown = Duration(seconds: 2);
  // The scanner reports a code ~every 250ms while it stays in frame. The same
  // code only counts again once it has been out of view for this long, so a
  // product held under the camera is added once, not once per cooldown.
  static const _sameCodeHoldWindow = Duration(milliseconds: 1500);

  final _productSearchCtrl = TextEditingController();
  final List<BillItem> _items = [];
  late final Future<CheckoutScope> _checkoutScope;
  CheckoutCart? _checkoutCart;
  Map<String, dynamic> _checkoutState = const {};
  Future<void> _checkoutWrites = Future<void>.value();

  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  Map<int, int> _saleCounts = const {};
  late BillingEntryMode _entryMode;
  bool _isProcessing = false;
  bool _isSavingBill = false;
  bool _isOpeningBillSheet = false;
  bool _isSendingHandoff = false;
  bool _isLoadingProducts = true;
  bool _showAddedStatus = false;
  bool _duplicateConsumed = false;
  bool _canUseCloudHandoff =
      CloudService.instance.state.value.canUseDraftHandoff;
  int _cloudHandoffCount = 0;
  String? _lastScanned;
  DateTime? _lastScannedSeenAt;

  Bill? get _effectiveDuplicateFromBill =>
      _duplicateConsumed ? null : widget.duplicateFromBill;

  double get _subtotal => _items.fold(0, (sum, i) => sum + i.subtotal);
  int get _itemCount =>
      _items.fold<double>(0, (sum, i) => sum + i.quantity).round();

  @override
  void initState() {
    super.initState();
    _checkoutScope = DatabaseHelper.instance.captureCheckoutScope();
    _entryMode = widget.duplicateFromBill != null
        ? BillingEntryMode.manual
        : widget.initialMode ??
              (AppSettingsService.instance.billingSearchFirst
                  ? BillingEntryMode.manual
                  : BillingEntryMode.scan);
    if (widget.duplicateFromBill != null) {
      _items.addAll(widget.duplicateFromBill!.items.map(_copyItemForNewBill));
      _draftReady = true;
    } else {
      _restoreDraft();
    }
    _productSearchCtrl.addListener(_applyProductSearch);
    CloudService.instance.state.addListener(_onCloudStateChanged);
    _loadProducts();
    _loadHeldCount();
    if (_canUseCloudHandoff) {
      unawaited(_loadCloudHandoffCount());
    }
  }

  void _onCloudStateChanged() {
    final enabled = CloudService.instance.state.value.canUseDraftHandoff;
    if (enabled == _canUseCloudHandoff) return;
    if (!mounted) return;
    setState(() {
      _canUseCloudHandoff = enabled;
      if (!enabled) _cloudHandoffCount = 0;
    });
    if (enabled) unawaited(_loadCloudHandoffCount());
  }

  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // Billing snackbars (e.g. "Restored your unsaved bill") belong to this
    // screen; the app-wide messenger would otherwise keep showing them.
    final messenger = _messenger;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (messenger?.mounted ?? false) messenger!.removeCurrentSnackBar();
    });
    _draftTimer?.cancel();
    _scanCooldownTimer?.cancel();
    if (_draftReady) _saveDraftNow();
    _productSearchCtrl.removeListener(_applyProductSearch);
    CloudService.instance.state.removeListener(_onCloudStateChanged);
    _productSearchCtrl.dispose();
    super.dispose();
  }

  // ── Auto-saved cart and held bills ──
  //
  // Every rebuild checks whether the cart changed and, if so, saves it
  // (debounced) so an app kill or a call mid-bill never loses the cart.

  Timer? _draftTimer;
  Timer? _scanCooldownTimer;
  bool _draftReady = false;
  String _savedDraft = HeldBill.encodeItems(const []);
  int _heldCount = 0;

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    if (!_draftReady) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 400), _saveDraftNow);
  }

  Future<void>? _draftWrite;
  Object? _lastDraftError;

  Future<void> _saveDraftNow() async {
    final pending = _draftWrite;
    if (pending != null) await pending;
    final write = _writeDraftNow();
    _draftWrite = write;
    try {
      await write;
    } finally {
      if (identical(_draftWrite, write)) _draftWrite = null;
    }
    await _commitPendingParty();
  }

  // ── Customer / party bar ──
  //
  // The party is kept in the checkout raw fields (the same durable draft the
  // checkout sheet edits), so held carts, restores and checkout review see it.
  // A party picked before the cart has a durable row waits in [_pendingParty]
  // and is written as soon as the cart is saved.

  Map<String, dynamic>? _pendingParty;

  Map<String, dynamic> get _partyFields {
    final pending = _pendingParty;
    if (pending != null) return pending;
    final raw = _checkoutState['raw'];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  Map<String, dynamic> _stateWithParty(Map<String, dynamic> fields) {
    final raw = _checkoutState['raw'];
    return {
      ..._checkoutState,
      'version': 1,
      'raw': {...(raw is Map ? Map<String, dynamic>.from(raw) : {}), ...fields},
    };
  }

  Future<void> _commitPendingParty() async {
    final fields = _pendingParty;
    if (fields == null ||
        _checkoutCart == null ||
        _checkoutState['pending'] != null) {
      return;
    }
    try {
      await _persistCheckoutState(_stateWithParty(fields));
      if (identical(_pendingParty, fields)) _pendingParty = null;
    } catch (error, stack) {
      AppLog.error('Save bill party', error, stack);
    }
  }

  Future<void> _pickParty() async {
    if (_pendingCheckoutBlocksEdit()) return;
    final customers = await DatabaseHelper.instance.getAllCustomers();
    if (!mounted) return;
    final fields = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PartyPickerSheet(
        customers: customers,
        currentName: _partyFields['name']?.toString() ?? '',
      ),
    );
    if (fields == null || !mounted) return;
    if (_pendingCheckoutBlocksEdit()) return;
    setState(() => _pendingParty = fields);
    await _commitPendingParty();
    if (mounted) setState(() {});
  }

  Future<void> _writeDraftNow() async {
    final encoded = HeldBill.encodeItems(_items);
    if (encoded == _savedDraft) return;
    final previous = _savedDraft;
    _savedDraft = encoded;
    try {
      _checkoutCart = await DatabaseHelper.instance.saveCartDraft(
        HeldBill.decodeItems(encoded),
        expectedScope: await _checkoutScope,
        expectedCart: _checkoutCart,
      );
      if (_checkoutCart == null && _checkoutState.isNotEmpty) {
        // Emptying the cart drops its durable checkout row; keep the chosen
        // party for the next item instead of silently reverting to walk-in.
        final raw = _checkoutState['raw'];
        if (raw is Map &&
            (raw['name']?.toString().trim().isNotEmpty ?? false)) {
          _pendingParty ??= {
            for (final key in _walkInPartyFields().keys)
              if (raw.containsKey(key)) key: raw[key],
          };
        }
        _checkoutState = const {};
      }
      _lastDraftError = null;
    } catch (error, stack) {
      _lastDraftError = error;
      if (_savedDraft == encoded) _savedDraft = previous;
      AppLog.error('Save cart draft', error, stack);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save your draft: $error')),
      );
    }
  }

  Future<void> _flushCart() async {
    await _saveDraftNow();
    if (_lastDraftError != null) {
      throw StateError('Could not keep the cart: $_lastDraftError');
    }
    await _checkoutWrites;
  }

  void _showCheckoutSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool _pendingCheckoutBlocksEdit() {
    if (_checkoutState['pending'] == null) return false;
    _showCheckoutSnackBar(
      'Recover the pending checkout before changing, holding or discarding its cart.',
    );
    return true;
  }

  Future<void> _restoreDraft() async {
    try {
      final cart = await DatabaseHelper.instance.loadCheckoutCart(
        await _checkoutScope,
      );
      _checkoutCart = cart;
      _checkoutState = cart?.state ?? const {};
      final draft = cart?.cart.items ?? const <BillItem>[];
      if (!mounted) return;
      _savedDraft = HeldBill.encodeItems(draft);
      _draftReady = true;
      if (draft.isEmpty || _items.isNotEmpty) return;
      // Do not mutate the saved revision used for the next compare-and-save.
      setState(() => _items.addAll(HeldBill.decodeItems(_savedDraft)));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Restored your unsaved bill (${draft.length} '
            'item${draft.length == 1 ? '' : 's'})',
          ),
          action: SnackBarAction(
            label: context.l10n.discard,
            onPressed: () {
              if (mounted && !_pendingCheckoutBlocksEdit()) {
                setState(() => _items.clear());
              }
            },
          ),
        ),
      );
    } catch (error) {
      _lastDraftError = error;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not restore checkout: $error')),
      );
    }
  }

  Future<void> _persistCheckoutState(Map<String, dynamic> state) {
    final snapshot = jsonDecode(jsonEncode(state)) as Map<String, dynamic>;
    final identity = _checkoutCart?.cart.uuid;
    final previous = _checkoutWrites;
    final next = () async {
      await previous;
      final cart = _checkoutCart;
      if (cart == null || cart.cart.uuid != identity) {
        throw StateError('Checkout cart is no longer active.');
      }
      final updated = await DatabaseHelper.instance.writeCheckoutState(
        cart,
        snapshot,
      );
      _checkoutCart = updated;
      _checkoutState = snapshot;
    }();
    // Keep the sequencing chain usable after an observed failure; callers still receive it.
    _checkoutWrites = next.catchError((Object _) {});
    return next;
  }

  Future<void> _loadHeldCount() async {
    final held = await DatabaseHelper.instance.getHeldBills();
    if (mounted) setState(() => _heldCount = held.length);
  }

  Future<void> _loadCloudHandoffCount() async {
    if (!_canUseCloudHandoff) return;
    try {
      final list = await CloudService.instance.listDraftHandoffs();
      if (mounted) setState(() => _cloudHandoffCount = list.length);
    } on Object {
      // Offline or unavailable: keep local billing unaffected.
    }
  }

  Future<void> _sendDraftHandoff() async {
    if (_items.isEmpty || _isSendingHandoff || !_canUseCloudHandoff) return;
    if (_pendingCheckoutBlocksEdit()) return;
    setState(() => _isSendingHandoff = true);
    try {
      await _flushCart();
      final items = List<BillItem>.of(_items);
      final first = items.first.productName;
      final label =
          '${DateFormat('hh:mm a').format(DateTime.now())} · $first'
          '${items.length > 1 ? ' +${items.length - 1}' : ''}';
      final serializedItems = [
        for (final item in items)
          {
            ...item.toMap(0),
            if (item.draftQuantityInput != null)
              'draft_quantity_input': item.draftQuantityInput,
          },
      ];
      final metadata = Map<String, dynamic>.from(_checkoutState)
        ..remove('pending');
      await CloudService.instance.publishDraftHandoff(
        items: serializedItems,
        label: label,
        metadata: metadata,
      );
      await DatabaseHelper.instance.saveCartDraft(
        const [],
        expectedScope: await _checkoutScope,
        expectedCart: _checkoutCart,
      );
      _checkoutCart = null;
      _checkoutState = const {};
      _pendingParty = null;
      _savedDraft = HeldBill.encodeItems(const []);
      if (!mounted) return;
      setState(() {
        _items.clear();
        _cloudHandoffCount++;
      });
      _showCheckoutSnackBar('Sent to another device: $label');
    } catch (error) {
      if (!mounted) return;
      _showCheckoutSnackBar(error.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _isSendingHandoff = false);
    }
  }

  Future<void> _hydrateClaimedHandoff(DraftHandoff claimed) async {
    if (_pendingCheckoutBlocksEdit()) return;
    try {
      await _flushCart();
      final scope = await _checkoutScope;
      if (_items.isNotEmpty && _checkoutCart != null) {
        final first = _items.first.productName;
        final parkLabel =
            '${DateFormat('hh:mm a').format(DateTime.now())} · $first'
            '${_items.length > 1 ? ' +${_items.length - 1}' : ''}';
        await DatabaseHelper.instance.parkCheckoutCart(
          _checkoutCart!,
          parkLabel,
        );
        _checkoutCart = null;
        _checkoutState = const {};
        _pendingParty = null;
      }
      final byUuid = {
        for (final product in _allProducts)
          if (product.uuid.isNotEmpty) product.uuid: product,
      };
      final hydratedItems = [
        for (final item in claimed.toBillItems())
          if (item.productUuid != null && byUuid.containsKey(item.productUuid))
            BillItem.fromMap({
              ...item.toMap(0),
              'product_id': byUuid[item.productUuid]!.id,
            })..draftQuantityInput = item.draftQuantityInput
          else
            item,
      ];
      var nextCart = await DatabaseHelper.instance.saveCartDraft(
        hydratedItems,
        expectedScope: scope,
        expectedCart: _checkoutCart,
      );
      final sanitizedMetadata = Map<String, dynamic>.from(claimed.metadata)
        ..remove('pending');
      if (sanitizedMetadata.isNotEmpty && nextCart != null) {
        nextCart = await DatabaseHelper.instance.writeCheckoutState(
          nextCart,
          sanitizedMetadata,
        );
      }
      if (!mounted) return;
      _checkoutCart = nextCart;
      _checkoutState = nextCart?.state ?? sanitizedMetadata;
      _savedDraft = HeldBill.encodeItems(hydratedItems);
      setState(() {
        _items
          ..clear()
          ..addAll(hydratedItems);
      });
      await _loadHeldCount();
      await _loadCloudHandoffCount();
      if (!mounted) return;
      _showCheckoutSnackBar('Took over cart from ${claimed.sourceDeviceLabel}');
    } catch (error) {
      if (!mounted) return;
      _showCheckoutSnackBar(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  /// Parks the cart so the next customer can be billed.
  Future<void> _holdCart() async {
    if (_items.isEmpty) return;
    final items = List<BillItem>.of(_items);
    final first = items.first.productName;
    final label =
        '${DateFormat('hh:mm a').format(DateTime.now())} · $first'
        '${items.length > 1 ? ' +${items.length - 1}' : ''}';
    if (_pendingCheckoutBlocksEdit()) return;
    try {
      await _flushCart();
      final cart = _checkoutCart;
      if (cart == null) {
        throw StateError('The current cart is no longer available.');
      }
      await DatabaseHelper.instance.parkCheckoutCart(cart, label);
      _checkoutCart = null;
      _checkoutState = const {};
      _pendingParty = null;
      _savedDraft = HeldBill.encodeItems(const []);
      if (!mounted) return;
      setState(() {
        _items.clear();
        _heldCount++;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Held: $label')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _openHeldBills() async {
    final held = await DatabaseHelper.instance.getHeldBills();
    if (!mounted) return;
    final selection = await showModalBottomSheet<_HeldSheetSelection>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceOf(context),
      builder: (_) => _HeldBillsSheet(
        held: held,
        onDelete: (bill) async {
          await DatabaseHelper.instance.deleteHeldBill(bill.id);
          await _loadHeldCount();
        },
        showCloudHandoffs: _canUseCloudHandoff,
        onLoadCloudHandoffs: _canUseCloudHandoff
            ? () async {
                final list = await CloudService.instance.listDraftHandoffs();
                if (mounted) setState(() => _cloudHandoffCount = list.length);
                return list;
              }
            : null,
        onClaimCloudHandoff: _canUseCloudHandoff
            ? (handoff) => CloudService.instance.claimDraftHandoff(handoff.uuid)
            : null,
        onDiscardCloudHandoff: _canUseCloudHandoff
            ? (handoff) async {
                await CloudService.instance.discardDraftHandoff(handoff.uuid);
                if (mounted && _cloudHandoffCount > 0) {
                  setState(() => _cloudHandoffCount--);
                }
              }
            : null,
      ),
    );
    if (selection == null || !mounted) return;
    if (selection is _ClaimedDraftHandoff) {
      await _hydrateClaimedHandoff(selection.handoff);
      return;
    }
    final chosen = (selection as _ResumeHeldBill).bill;
    // Swap: the cart being billed is held, so nothing is lost.
    if (_pendingCheckoutBlocksEdit()) return;
    CheckoutCart resumed;
    try {
      await _flushCart();
      final active = _checkoutCart;
      resumed = await DatabaseHelper.instance.resumeCheckoutCart(
        await _checkoutScope,
        chosen.id,
        active: active,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
      return;
    }
    if (!mounted) return;
    _checkoutCart = resumed;
    _checkoutState = resumed.state;
    _savedDraft = HeldBill.encodeItems(resumed.cart.items);
    setState(() {
      _items.clear();
      _items.addAll(
        HeldBill.decodeItems(HeldBill.encodeItems(resumed.cart.items)),
      );
    });
    await _loadHeldCount();
  }

  Future<void> _loadProducts() async {
    final products = await DatabaseHelper.instance.getAllProducts();
    final saleCounts = await DatabaseHelper.instance.getProductSaleCounts();
    if (!mounted) return;
    // Frequently sold items first, so the usual items are one tap away.
    products.sort((a, b) {
      final byCount = (saleCounts[b.id] ?? 0).compareTo(saleCounts[a.id] ?? 0);
      return byCount != 0
          ? byCount
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    setState(() {
      _allProducts = products;
      _saleCounts = saleCounts;
      _isLoadingProducts = false;
    });
    _applyProductSearch();
  }

  List<Product> _matchingCatalogProducts(String normalizedQuery) {
    return _allProducts.where((product) {
      return product.name.toLowerCase().contains(normalizedQuery) ||
          (product.itemCode?.toLowerCase().contains(normalizedQuery) ??
              false) ||
          (product.barcode?.toLowerCase().contains(normalizedQuery) ?? false) ||
          (product.category?.toLowerCase().contains(normalizedQuery) ??
              false) ||
          (product.supplier?.toLowerCase().contains(normalizedQuery) ?? false);
    }).toList();
  }

  void _applyProductSearch() {
    final query = _productSearchCtrl.text.trim().toLowerCase();
    if (!mounted) return;
    setState(() {
      final products = query.isEmpty
          ? _allProducts
          : _matchingCatalogProducts(query);
      _filteredProducts = products.take(40).toList();
    });
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null || barcode.rawValue == null) return;

    final raw = barcode.rawValue!;
    final now = DateTime.now();
    final lastSeenAt = _lastScannedSeenAt;
    final sameCodeStillInView =
        raw == _lastScanned &&
        lastSeenAt != null &&
        now.difference(lastSeenAt) < _sameCodeHoldWindow;
    if (raw == _lastScanned) _lastScannedSeenAt = now;
    if (sameCodeStillInView || _isProcessing) return;

    setState(() => _isProcessing = true);
    _lastScanned = raw;
    _lastScannedSeenAt = now;

    try {
      await _handleScannedCode(raw);
    } catch (_) {
      if (!mounted) return;
      setState(() => _showAddedStatus = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Could not read this code. Try again.'),
            duration: _invalidScanCooldown,
          ),
        );
      _allowNextScanAfter(_invalidScanCooldown);
    }
  }

  bool _recoveringCode = false;

  void _scheduleScanCooldown(bool fromManualSearch, Duration duration) {
    if (!fromManualSearch) _allowNextScanAfter(duration);
  }

  Future<void> _submitExactCode(String raw) async {
    if (_isProcessing ||
        _recoveringCode ||
        _isSavingBill ||
        _isOpeningBillSheet) {
      return;
    }
    _scanCooldownTimer?.cancel();
    setState(() => _isProcessing = true);
    try {
      await _handleScannedCode(raw, fromManualSearch: true);
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? 'Item not found. Search the catalog for this label.'
          : error.toString().replaceFirst('Bad state: ', '');
      _showCheckoutSnackBar(message);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleScannedCode(
    String raw, {
    bool fromManualSearch = false,
  }) async {
    if (_pendingCheckoutBlocksEdit()) {
      _scheduleScanCooldown(fromManualSearch, _invalidScanCooldown);
      return;
    }
    final scope = await _checkoutScope;
    final db = DatabaseHelper.instance;
    final Product? product;
    try {
      product = await db.resolveCheckoutProduct(raw, scope);
    } on FormatException {
      if (!mounted) return;
      _showCheckoutSnackBar(
        'Item not found. Search the catalog for this label.',
      );
      _scheduleScanCooldown(fromManualSearch, _invalidScanCooldown);
      return;
    }
    if (!mounted) return;
    if (product != null) {
      final item = await db.buildBillItemForProduct(product);
      await db.captureCheckoutScope().then((current) {
        if (current.shopId != scope.shopId ||
            current.owner != scope.owner ||
            current.deviceId != scope.deviceId) {
          throw StateError('Checkout shop or account changed.');
        }
      });
      if (!mounted) return;
      _addBillItem(item);
      HapticFeedback.mediumImpact();
      _scheduleScanCooldown(fromManualSearch, _scanCooldown);
      return;
    }
    if (fromManualSearch) {
      final trimmed = raw.trim();
      final query = trimmed.toLowerCase();
      final matches = query.isEmpty
          ? const <Product>[]
          : _matchingCatalogProducts(query);
      if (matches.isNotEmpty) {
        _showCheckoutSnackBar(
          '${matches.length} products match "$trimmed". Choose one from the list.',
        );
        _scheduleScanCooldown(fromManualSearch, _invalidScanCooldown);
        return;
      }
    }
    final code = checkoutBarcodeCandidate(raw);
    if (code == null) {
      _showCheckoutSnackBar(
        'Item not found. Search the catalog for this label.',
      );
      _scheduleScanCooldown(fromManualSearch, _invalidScanCooldown);
      return;
    }
    final canCreate =
        DatabaseHelper.instance.isAdminMutationAllowed == null ||
        DatabaseHelper.instance.isAdminMutationAllowed!();
    if (!canCreate) {
      _showCheckoutSnackBar(
        'No product matches "$code". Only a shop owner or admin can add new products.',
      );
      _scheduleScanCooldown(fromManualSearch, _invalidScanCooldown);
      return;
    }
    if (_recoveringCode) return;
    _recoveringCode = true;
    try {
      await _flushCart();
      if (!mounted) return;
      final add = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Item not found'),
          content: Text(
            'No item matches "$code". Add it without losing the current bill?',
          ),
          actions: [
            TextButton(
              key: const ValueKey('checkout-code-cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep billing'),
            ),
            FilledButton(
              key: const ValueKey('checkout-create-product'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add item'),
            ),
          ],
        ),
      );
      if (add != true || !mounted) return;
      final saved = await showCheckoutQuickAdd(
        context,
        barcode: code,
        scope: scope,
      );
      if (saved == null || !mounted) return;
      final current = await db.productForCheckoutReturn(saved.uuid, scope);
      if (!mounted) return;
      if (current.trackStock && current.quantity <= 0) {
        await _loadProducts();
        if (!mounted) return;
        _showCheckoutSnackBar(
          'Item saved. Add stock before adding it to this bill.',
        );
        return;
      }
      final item = await db.buildBillItemForProduct(current);
      await db.productForCheckoutReturn(saved.uuid, scope);
      if (!mounted) return;
      _addBillItem(item);
      await _flushCart();
      if (!mounted) return;
      _productSearchCtrl.clear();
      await _loadProducts();
    } finally {
      _recoveringCode = false;
      _scheduleScanCooldown(fromManualSearch, _scanCooldown);
    }
  }

  Future<void> _addProductToBill(Product product) async {
    final item = await DatabaseHelper.instance.buildBillItemForProduct(product);
    if (!mounted) return;
    _addBillItem(item);
    HapticFeedback.selectionClick();
    // Ready for the next item: clear the search after an add.
    if (_productSearchCtrl.text.isNotEmpty) _productSearchCtrl.clear();
  }

  BillItem _copyItemForNewBill(BillItem item) {
    return BillItem(
      productId: item.productId,
      productUuid: item.productUuid,
      productName: item.productName,
      hsnCodeSnapshot: item.hsnCodeSnapshot,
      hsnTypeSnapshot: item.hsnTypeSnapshot,
      mrp: item.mrp,
      unit: item.unit,
      purchasePriceSnapshot: item.purchasePriceSnapshot,
      sellingPriceSnapshot: item.sellingPriceSnapshot,
      costSnapshot: item.costSnapshot,
      profitSnapshot: item.profitSnapshot,
      commissionSnapshot: item.commissionSnapshot,
      gstSnapshot: item.gstSnapshot,
      gstPercentSnapshot: item.gstPercentSnapshot,
      taxableValueSnapshot: item.taxableValueSnapshot,
      cgstAmountSnapshot: item.cgstAmountSnapshot,
      sgstAmountSnapshot: item.sgstAmountSnapshot,
      igstAmountSnapshot: item.igstAmountSnapshot,
      itemTypeSnapshot: item.itemTypeSnapshot,
      taxTypeSnapshot: item.taxTypeSnapshot,
      cessPercentSnapshot: item.cessPercentSnapshot,
      cessAmountSnapshot: item.cessAmountSnapshot,
      wasDirectPrice: item.wasDirectPrice,
      quantity: item.quantity,
      discountMode: item.discountMode,
      discountValue: item.discountValue,
      discountAmount: item.discountAmount,
      taxMode: item.taxMode,
      mrpSnapshot: item.mrpSnapshot,
    );
  }

  void _addBillItem(BillItem item) {
    if (_pendingCheckoutBlocksEdit()) return;
    final existing = _items.indexWhere(
      (existingItem) =>
          (item.productId != null &&
              existingItem.productId == item.productId) ||
          (item.productId == null &&
              existingItem.productName.toLowerCase() ==
                  item.productName.toLowerCase()),
    );
    final quantity = existing < 0
        ? saleQuantityValue(item.quantity.toString())
        : _items[existing].draftQuantityInput == null
        ? adjustSaleQuantity(_items[existing].quantity, 1)
        : null;
    if (quantity == null) {
      _showCheckoutSnackBar(saleQuantityGuidance);
      return;
    }
    final available = _availableStockForItem(item);
    if (available != null && exceedsStock(quantity, available)) {
      _showStockLimitMessage(item.productName, available);
    }

    setState(() {
      if (existing >= 0) {
        _items[existing].quantity = quantity;
        _items[existing].unit ??= item.unit;
      } else {
        _items.add(item);
      }
      _showAddedStatus = _entryMode == BillingEntryMode.scan;
    });
  }

  double? _availableStockForItem(BillItem item) {
    final productId = item.productId;
    if (productId == null) return null;
    for (final product in _allProducts) {
      if (product.id == productId) {
        return product.trackStock ? product.quantity : null;
      }
    }
    return null;
  }

  /// Selling past the recorded stock is allowed (counts often lag the
  /// shelf); this only warns, and stock goes negative.
  void _showStockLimitMessage(String productName, double available) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            available <= stockQuantityEpsilon
                ? '"$productName" shows no stock. Added anyway.'
                : 'Only ${_formatQuantityInput(available)} in stock for '
                      '"$productName". Added anyway.',
          ),
        ),
      );
  }

  void _allowNextScanAfter(Duration duration) {
    if (!mounted) return;
    _scanCooldownTimer?.cancel();
    _scanCooldownTimer = Timer(duration, () {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _showAddedStatus = false;
      });
    });
  }

  Future<void> _openBillSheet() async {
    if (_items.isEmpty || _isOpeningBillSheet || _isSavingBill) return;
    _isOpeningBillSheet = true;
    try {
      await _runBillCheckout();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      _isOpeningBillSheet = false;
    }
  }

  Future<void> _runBillCheckout() async {
    _draftTimer?.cancel();
    await _flushCart();
    if (_checkoutCart == null) {
      throw StateError('Checkout cart is no longer available.');
    }
    _checkoutState = _checkoutCart!.state;
    if (_checkoutState['pending'] == null &&
        _items.any(
          (item) =>
              item.draftQuantityInput != null ||
              saleQuantityThousandths(item.quantity.toString()) == null,
        )) {
      _showCheckoutSnackBar(saleQuantityGuidance);
      return;
    }
    final device = (await _checkoutScope).deviceId;
    var baseline = await DatabaseHelper.instance.captureSettingsEditBaseline();
    final owner = await DatabaseHelper.instance.getCloudSyncState(
      'preference_owner',
    );
    var shop = await DatabaseHelper.instance.getShopProfile();
    final customers = await DatabaseHelper.instance.getAllCustomers();
    var settings = await DatabaseHelper.instance.getBillSettings();
    if (!mounted) return;
    final cartItems = List<BillItem>.of(_items);
    if (_checkoutState['pending'] == null &&
        _checkoutState['raw'] is Map &&
        (jsonEncode(_checkoutState['reviewed_context']) !=
                jsonEncode(baseline.toLocalMap()) ||
            _checkoutState['reviewed_items'] !=
                HeldBill.encodeItems(cartItems))) {
      _checkoutState = {
        ..._checkoutState,
        'raw': {
          ...Map<String, dynamic>.from(_checkoutState['raw'] as Map),
          'settlement': null,
          'consent': false,
        },
      };
    }
    final maxFixedDiscount = BillTotals.calculate(
      cartItems,
      gstRegistered: false,
      interState: false,
      roundOffMode: Bill.roundOffNone,
    ).totals.netAmount;

    BillTotals totalsFor({
      required String discountMode,
      required double discountValue,
      required String taxMode,
      required String roundOffMode,
      required double roundOffIncrement,
      String? placeOfSupplyStateCode,
      String? customerGstin,
    }) {
      final gstRegistered = shop?.gstRegistered ?? false;
      final shopStateCode = _stateCodeFromGstin(shop?.gstin);
      final supplyStateCode =
          _cleanStateCode(placeOfSupplyStateCode) ??
          _stateCodeFromGstin(customerGstin);
      final interState =
          gstRegistered &&
          shopStateCode != null &&
          supplyStateCode != null &&
          shopStateCode != supplyStateCode;
      return BillTotals.forCart(
        cartItems,
        discountMode: discountMode,
        discountValue: discountValue,
        taxMode: taxMode,
        gstRegistered: gstRegistered,
        interState: interState,
        roundOffMode: roundOffMode,
        roundOffIncrement: roundOffIncrement,
      );
    }

    var attemptId = const Uuid().v4();
    Bill? frozenBill;
    List<BillItem>? frozenItems;
    BillTotals? frozenTotals;
    final pending = _checkoutState['pending'];
    if (pending != null) {
      final saved = Map<String, dynamic>.from(pending as Map);
      attemptId = saved['attempt_id'] as String;
      baseline = SettingsEditBaseline.fromLocalMap(
        Map<String, dynamic>.from(saved['baseline'] as Map),
      );
      frozenItems = [
        for (final item in saved['items'] as List)
          BillItem.fromMap(Map<String, dynamic>.from(item as Map)),
      ];
      frozenBill = Bill.fromMap({
        ...Map<String, dynamic>.from(saved['bill'] as Map),
        'transaction_reference': saved['reference'],
      }, frozenItems);
      frozenTotals = BillTotals.fromTaxedItems(
        frozenItems,
        roundOff: saved['round_off'] as bool? ?? true,
        roundOffMode:
            saved['round_off_mode'] as String? ?? frozenBill.roundOffMode,
        roundOffIncrement:
            (saved['round_off_increment'] as num?)?.toDouble() ??
            frozenBill.roundOffIncrement,
        billTaxMode: saved['tax_mode'] as String? ?? frozenBill.taxMode,
      );
      if (attemptId.isEmpty ||
          frozenBill.uuid.isEmpty ||
          frozenBill.shopId != baseline.shopId ||
          baseline.shopId != (await _checkoutScope).shopId) {
        throw const FormatException(
          'Unreadable pending checkout identity. Keep a backup before recovery.',
        );
      }
    }
    Future<({int id, BillTotals totals})> save(_BillDraft draft) async {
      if (_isSavingBill) throw StateError('Checkout save already in progress.');
      if (mounted) setState(() => _isSavingBill = true);
      try {
        if (frozenBill == null) {
          final customerName = draft.customerName;
          final customerPhone = draft.customerPhone;
          final billType = draft.billType;
          final customerGstin = draft.customerGstin;
          final customerGstLegalName = draft.customerGstLegalName;
          final customerGstTradeName = draft.customerGstTradeName;
          final customerAddress = draft.customerAddress;
          final placeOfSupplyStateCode = draft.placeOfSupplyStateCode;
          final discountPercent = draft.discountPercent;
          final discountMode = draft.discountMode;
          final discountValue = draft.discountValue;
          final taxMode = draft.taxMode;
          final roundOffMode = draft.roundOffMode;
          final roundOffIncrement = draft.roundOffIncrement;
          final paidAmount = draft.paidAmount;
          final paymentMethod = draft.paymentMethod;
          final transactionReference = draft.transactionReference;
          final gstRegistered = shop?.gstRegistered ?? false;
          final shopStateCode = _stateCodeFromGstin(shop?.gstin);
          final supplyStateCode =
              _cleanStateCode(placeOfSupplyStateCode) ??
              _stateCodeFromGstin(customerGstin);
          final interState =
              gstRegistered &&
              shopStateCode != null &&
              supplyStateCode != null &&
              shopStateCode != supplyStateCode;
          final calculated = BillTotals.calculate(
            cartItems,
            discountMode: discountMode,
            discountValue: discountValue,
            taxMode: taxMode,
            gstRegistered: gstRegistered,
            interState: interState,
            roundOffMode: roundOffMode,
            roundOffIncrement: roundOffIncrement,
          );
          final itemCopies = calculated.items;
          final totals = calculated.totals;
          final total = totals.grandTotal;
          final received = paidAmount;

          final bill = Bill(
            uuid: const Uuid().v4(),
            shopId: baseline.shopId,
            billType: billType,
            customerName: customerName.trim().isEmpty
                ? 'Walk-in Customer'
                : customerName.trim(),
            customerPhone: _cleanOptionalText(customerPhone),
            customerGstin: _cleanOptionalText(customerGstin)?.toUpperCase(),
            customerGstLegalName: _cleanOptionalText(customerGstLegalName),
            customerGstTradeName: _cleanOptionalText(customerGstTradeName),
            customerAddressSnapshot: _cleanOptionalText(customerAddress),
            placeOfSupplyStateCode: supplyStateCode,
            subtotalAmount: totals.subtotal,
            discountPercent: discountMode == Bill.discountModePercent
                ? discountPercent
                : 0,
            discountMode: discountMode,
            discountValue: discountValue,
            discountAmount: totals.discountAmount,
            taxMode: taxMode,
            taxableAmount: totals.taxableAmount,
            cgstAmount: totals.cgstAmount,
            sgstAmount: totals.sgstAmount,
            igstAmount: totals.igstAmount,
            cessAmount: totals.cessAmount,
            roundOffAmount: totals.roundOffAmount,
            roundOffMode: roundOffMode,
            roundOffIncrement: roundOffIncrement,
            totalAmount: total,
            itemCount: _itemCount,
            isPaid: received >= total - 0.005,
            paymentMethod: paymentMethod,
            paidAmount: received,
            transactionReference: transactionReference,
            notes: _cleanOptionalText(draft.notes),
            createdAt: draft.billDate,
            duplicatedFromBillUuid:
                _checkoutState['source_bill_uuid'] as String? ??
                _effectiveDuplicateFromBill?.uuid,
          );

          final previewTotals = totalsFor(
            discountMode: discountMode,
            discountValue: discountValue,
            taxMode: taxMode,
            roundOffMode: roundOffMode,
            roundOffIncrement: roundOffIncrement,
            placeOfSupplyStateCode: placeOfSupplyStateCode,
            customerGstin: customerGstin,
          );
          if (decimalScaledInteger(total.toStringAsFixed(2), scale: 2) !=
              decimalScaledInteger(
                previewTotals.grandTotal.toStringAsFixed(2),
                scale: 2,
              )) {
            throw StateError(
              'Reviewed total changed. Return to the cart and review checkout again.',
            );
          }
          frozenBill = bill;
          frozenItems = itemCopies;
          frozenTotals = totals;
        }
        await _checkoutWrites;
        if (_checkoutState['pending'] == null) {
          await _persistCheckoutState({
            ..._checkoutState,
            'version': 1,
            'pending': {
              'attempt_id': attemptId,
              'baseline': baseline.toLocalMap(),
              'bill': frozenBill!.toMap(),
              'reference': frozenBill!.transactionReference,
              'items': frozenItems!.map((item) => item.toMap(0)).toList(),
              'round_off': frozenBill!.roundOffMode != Bill.roundOffNone,
              'round_off_mode': frozenBill!.roundOffMode,
              'round_off_increment': frozenBill!.roundOffIncrement,
              'tax_mode': frozenBill!.taxMode,
              'draft': draft.toMap(),
            },
          });
        }
        final id = await DatabaseHelper.instance.insertReviewedCheckout(
          attemptId: attemptId,
          expectedShopId: baseline.shopId,
          expectedOwner: owner,
          baseline: baseline,
          cartSnapshot: HeldBill.encodeItems(cartItems),
          originDeviceId: device,
          bill: frozenBill!,
          items: frozenItems!,
          expectedCart: _checkoutCart,
        );
        return (id: id, totals: frozenTotals!);
      } finally {
        if (mounted) setState(() => _isSavingBill = false);
      }
    }

    if (!mounted) return;
    try {
      await _persistCheckoutState({
        ..._checkoutState,
        'version': 1,
        'source_bill_uuid':
            _checkoutState['source_bill_uuid'] ??
            _effectiveDuplicateFromBill?.uuid,
        'step': 'checkout',
      });
      if (!mounted) return;
      final completed =
          await showModalBottomSheet<
            ({_BillDraft draft, int id, BillTotals totals})
          >(
            context: context,
            isScrollControlled: true,
            enableDrag: false,
            isDismissible: false,
            useSafeArea: true,
            backgroundColor: AppColors.surfaceOf(context),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            builder: (_) => _BillCheckoutSheet(
              customers: customers,
              initialState: _checkoutState,
              onRawChanged: (raw) => _persistCheckoutState({
                ..._checkoutState,
                'version': 1,
                'step': 'checkout',
                'source_bill_uuid':
                    _checkoutState['source_bill_uuid'] ??
                    _effectiveDuplicateFromBill?.uuid,
                'raw': raw,
                'reviewed_items': HeldBill.encodeItems(cartItems),
                'reviewed_context': baseline.toLocalMap(),
              }),
              onSave: save,
              onReview: () async {
                final next = await DatabaseHelper.instance
                    .captureSettingsEditBaseline();
                if (next.shopId != baseline.shopId ||
                    await DatabaseHelper.instance.getCloudSyncState(
                          'preference_owner',
                        ) !=
                        owner) {
                  throw StateError(
                    'Return to the original shop and account before reviewing.',
                  );
                }
                final nextShop = await DatabaseHelper.instance.getShopProfile();
                final nextSettings = await DatabaseHelper.instance
                    .getBillSettings();
                baseline = next;
                shop = nextShop;
                settings = nextSettings;
                await _persistCheckoutState({
                  ..._checkoutState,
                  'pending': null,
                });
                frozenBill = null;
                frozenItems = null;
                frozenTotals = null;
                attemptId = const Uuid().v4();
              },
              totalsFor: totalsFor,
              defaultTaxMode: settings.defaultTaxMode,
              defaultRoundOffMode: settings.roundOffMode,
              defaultRoundOffIncrement: settings.roundOffIncrement,
              maxFixedDiscount: maxFixedDiscount,
              itemCount: _itemCount,
              canBackdate:
                  DatabaseHelper.instance.isAdminMutationAllowed == null ||
                  DatabaseHelper.instance.isAdminMutationAllowed!(),
              initialBill: _effectiveDuplicateFromBill,
            ),
          );
      if (completed == null) {
        await _checkoutWrites;
        if (mounted && _checkoutCart != null) {
          await _persistCheckoutState({
            ..._checkoutState,
            'version': 1,
            'step': 'items',
          });
        }
        return;
      }
      if (!mounted) return;
      final draft = completed.draft;
      final saved = completed;
      final totalAmount = saved.totals.grandTotal;
      final itemCount = _itemCount;
      // The bill is saved: empty the cart and consume duplicate lineage now so
      // no path back to this screen (or New Bill) can carry it forward.
      _checkoutCart = null;
      _checkoutState = const {};
      _pendingParty = null;
      _savedDraft = HeldBill.encodeItems(const []);
      _duplicateConsumed = true;
      setState(() => _items.clear());
      final startNewBill = await _showBillCreatedDialog(
        billId: saved.id,
        customerName: draft.customerName.trim().isEmpty
            ? 'Walk-in Customer'
            : draft.customerName.trim(),
        totalAmount: totalAmount,
        paidAmount: draft.paidAmount,
        expectedBillUuid: frozenBill!.uuid,
        expectedScope: await _checkoutScope,
        itemCount: itemCount,
      );
      if (!mounted) return;
      if (startNewBill) {
        _duplicateConsumed = true;
        _loadProducts(); // stock changed
      } else if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        _loadProducts();
      }
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Bad state: ', '');
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// Returns true when the user wants to start another bill right away.
  Future<bool> _showBillCreatedDialog({
    required int billId,
    required String customerName,
    required double totalAmount,
    required double paidAmount,
    required String expectedBillUuid,
    required CheckoutScope expectedScope,
    required int itemCount,
  }) async {
    Future<void> assertCompletionOwnership() async {
      final current = await DatabaseHelper.instance.captureCheckoutScope();
      if (current.shopId != expectedScope.shopId ||
          current.owner != expectedScope.owner ||
          current.deviceId != expectedScope.deviceId) {
        throw StateError(
          'Invoice saved. Return to the original shop and account to view it.',
        );
      }
    }

    await assertCompletionOwnership();
    final bill = await DatabaseHelper.instance.getBillById(billId);
    await assertCompletionOwnership();
    if (bill != null &&
        (bill.uuid != expectedBillUuid ||
            bill.shopId != expectedScope.shopId)) {
      throw StateError(
        'The saved invoice identity changed. Reopen it from the original shop history.',
      );
    }
    final billLabel = bill?.billNumber.isNotEmpty == true
        ? bill!.billNumber
        : 'Bill #$billId';
    final effectiveTotal = bill?.totalAmount ?? totalAmount;
    final effectivePaid = bill?.paidAmount ?? paidAmount;
    final status =
        bill?.paymentStatus ??
        (effectivePaid <= 0.005
            ? Bill.statusUnpaid
            : effectivePaid + 0.005 >= effectiveTotal
            ? Bill.statusPaid
            : Bill.statusPartial);
    final statusLabel = switch (status) {
      Bill.statusPaid => 'Paid',
      Bill.statusPartial => 'Partial',
      _ => 'Unpaid',
    };
    final methodSuffix = effectivePaid > 0.005 && bill != null
        ? ' · ${paymentMethodLabel(bill.paymentMethod)}'
        : '';
    if (!mounted) return false;
    final action = await showDialog<_BillCreatedAction>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _BillCreatedDialog(
        bill: bill,
        totalAmount: effectiveTotal,
        paidAmount: effectivePaid,
        summary:
            '$customerName\n$billLabel • $itemCount item${itemCount != 1 ? 's' : ''} • $statusLabel$methodSuffix',
      ),
    );
    if (action == _BillCreatedAction.viewInvoice && bill != null && mounted) {
      await assertCompletionOwnership();
      if (!mounted) return false;
      await showBillQuickSheet(context, bill);
      return false;
    }
    return action == _BillCreatedAction.newBill;
  }

  void _updateQty(int index, int delta) {
    if (_pendingCheckoutBlocksEdit()) return;
    if (_items[index].draftQuantityInput != null) {
      _showCheckoutSnackBar(saleQuantityGuidance);
      return;
    }
    final next = adjustSaleQuantity(_items[index].quantity, delta);
    if (next == null) {
      _showCheckoutSnackBar(saleQuantityGuidance);
      return;
    }
    if (delta > 0) {
      final available = _availableStockForItem(_items[index]);
      if (available != null && exceedsStock(next, available)) {
        _showStockLimitMessage(_items[index].productName, available);
      }
    }
    setState(() {
      _items[index].quantity = next;
      if (_items[index].quantity <= 0) _items.removeAt(index);
    });
  }

  void _setQty(int index, String input) {
    if (_pendingCheckoutBlocksEdit()) return;
    final item = _items[index];
    final quantity = saleQuantityValue(input);
    if (quantity == null) {
      setState(() => item.draftQuantityInput = input);
      return;
    }
    final available = _availableStockForItem(_items[index]);
    if (available != null && exceedsStock(quantity, available)) {
      _showStockLimitMessage(_items[index].productName, available);
    }
    setState(() {
      item.draftQuantityInput = null;
      item.quantity = quantity;
    });
  }

  String? _cleanOptionalText(String? value) {
    final trimmed = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed == null || trimmed.isEmpty || trimmed == '+91') return null;
    return trimmed;
  }

  String? _stateCodeFromGstin(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.length < 2) return null;
    final code = trimmed.substring(0, 2);
    return RegExp(r'^\d{2}$').hasMatch(code) ? code : null;
  }

  String? _cleanStateCode(String? value) {
    final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits == null || digits.isEmpty) return null;
    return digits.padLeft(2, '0').substring(0, 2);
  }

  Widget _buildModeSelector() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SegmentedButton<BillingEntryMode>(
        segments: [
          ButtonSegment(
            value: BillingEntryMode.scan,
            icon: Icon(Icons.qr_code_scanner_rounded),
            label: Text(context.l10n.navScan),
          ),
          ButtonSegment(
            value: BillingEntryMode.manual,
            icon: Icon(Icons.search_rounded),
            label: Text(context.l10n.search),
          ),
        ],
        selected: {_entryMode},
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.isDark(context)
              ? AppColors.darkSurfaceRaised
              : AppColors.navyLight,
          selectedBackgroundColor: AppColors.amber,
          foregroundColor: Colors.white,
          selectedForegroundColor: Colors.white,
        ),
        onSelectionChanged: (selection) {
          setState(() {
            _entryMode = selection.first;
            _showAddedStatus = false;
          });
          AppSettingsService.instance.setBillingSearchFirst(
            selection.first == BillingEntryMode.manual,
          );
        },
      ),
    );
  }

  Widget _buildEntryPanel(double height) {
    return _entryMode == BillingEntryMode.scan
        ? _buildScanPanel(height)
        : _buildManualPanel(height);
  }

  Widget _buildScanPanel(double height) {
    return Container(
      height: height,
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
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error, _) => _ScannerUnavailable(
              message:
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Camera permission is off. Allow it in Settings, or add '
                        'items by search.'
                  : 'Camera is not available. Add items by search.',
              onUseSearch: () {
                setState(() => _entryMode = BillingEntryMode.manual);
                AppSettingsService.instance.setBillingSearchFirst(true);
              },
            ),
          ),
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
                  child: Text(
                    context.l10n.itemAdded,
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
    );
  }

  Widget _buildManualPanel(double height) {
    return Container(
      height: height,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceOf(context),
        borderRadius: AppRadius.lgRadius,
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Column(
        children: [
          TextField(
            key: const ValueKey('checkout-product-search'),
            controller: _productSearchCtrl,
            onSubmitted: _submitExactCode,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              labelText: context.l10n.searchProducts,
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
          if (checkoutBarcodeCandidate(_productSearchCtrl.text) != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const ValueKey('checkout-use-exact-code'),
                onPressed: _isProcessing || _recoveringCode
                    ? null
                    : () => _submitExactCode(_productSearchCtrl.text),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Use exact code'),
              ),
            ),
          if (_productSearchCtrl.text.isEmpty && _saleCounts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  context.l10n.frequentlySold,
                  style: AppText.caption,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: _isLoadingProducts
                ? const Center(child: CircularProgressIndicator())
                : _allProducts.isEmpty
                ? _ManualEmptyState(
                    icon: Icons.inventory_2_outlined,
                    message: context.l10n.addProductsFirst,
                  )
                : _filteredProducts.isEmpty
                ? _ManualEmptyState(
                    icon: Icons.search_off_rounded,
                    message: context.l10n.noMatchingProducts,
                  )
                : ListView.separated(
                    itemCount: _filteredProducts.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final product = _filteredProducts[index];
                      return _ManualProductTile(
                        product: product,
                        onAdd: () => _addProductToBill(product),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _entryHintText() {
    if (_entryMode == BillingEntryMode.scan) {
      return _items.isEmpty
          ? context.l10n.pointCamera
          : '${_items.length} item${_items.length != 1 ? 's' : ''} added';
    }
    if (_items.isNotEmpty) {
      return context.l10n.itemsInBill(_items.length);
    }
    return 'Search by item name, code, category or supplier';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppColors.isDark(context);
    final headerSurface = isDark ? AppColors.darkBg : AppColors.navy;
    return PopScope(
      canPop: _items.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final action = await _confirmExit();
        if (action == null || !context.mounted) return;
        try {
          if (action == 'discard') {
            if (_pendingCheckoutBlocksEdit()) return;
            await _flushCart();
            await DatabaseHelper.instance.saveCartDraft(
              const [],
              expectedScope: await _checkoutScope,
              expectedCart: _checkoutCart,
            );
            _checkoutCart = null;
            _checkoutState = const {};
            _pendingParty = null;
            _savedDraft = HeldBill.encodeItems(const []);
            if (!mounted) return;
            setState(() => _items.clear());
          } else {
            await _flushCart();
          }
          if (!context.mounted) return;
          Navigator.pop(context);
        } catch (error) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      },
      child: Scaffold(
        backgroundColor: headerSurface,
        appBar: AppBar(
          title: Text(
            _effectiveDuplicateFromBill != null
                ? context.l10n.duplicateBill
                : _entryMode == BillingEntryMode.scan
                ? 'Scan & Bill'
                : context.l10n.manualBill,
          ),
          backgroundColor: headerSurface,
          foregroundColor: Colors.white,
          actions: [
            AppInfoAction(
              title: 'Billing Help',
              intro:
                  'Build the bill first, then complete checkout with customer and payment details.',
              sections: [
                AppInfoSection(
                  title: context.l10n.addItems,
                  points: [
                    'Scan mode reads Storely product labels and barcode values.',
                    'Manual mode lets you search by product name, code, category, or supplier.',
                    'Use quantity controls on each bill row before completing the bill.',
                  ],
                ),
                AppInfoSection(
                  title: context.l10n.completeBill,
                  points: [
                    'Before Generate Bill, this screen is your editable draft.',
                    'Complete Bill opens checkout for customer, discount, and payment details.',
                    'Saved bills keep price, GST, and profit snapshots from the moment of billing.',
                    'For corrections after saving, cancel the old bill and duplicate it as a new bill.',
                    'Selling more than the recorded stock shows a warning; stock then goes negative.',
                  ],
                ),
              ],
            ),
            if (_heldCount > 0 || _canUseCloudHandoff)
              TextButton.icon(
                key: const ValueKey('checkout-held-list'),
                onPressed: _openHeldBills,
                icon: const Icon(
                  Icons.inventory_rounded,
                  color: AppColors.amber,
                ),
                label: Text(
                  _heldCount + _cloudHandoffCount > 0
                      ? context.l10n.heldCount(_heldCount + _cloudHandoffCount)
                      : context.l10n.heldBills,
                  style: const TextStyle(color: AppColors.amber),
                ),
              ),
            if (_items.isNotEmpty)
              IconButton(
                key: const ValueKey('checkout-hold'),
                tooltip: context.l10n.holdBill,
                onPressed: _holdCart,
                icon: const Icon(
                  Icons.pause_circle_outline_rounded,
                  color: AppColors.amber,
                ),
              ),
            if (_items.isNotEmpty)
              TextButton(
                onPressed: _clearWithUndo,
                child: Text(
                  context.l10n.clear,
                  style: TextStyle(color: AppColors.amber),
                ),
              ),
          ],
        ),
        body: Column(
          children: [
            _PartyBar(
              name: _partyFields['name']?.toString() ?? '',
              phone: _partyFields['phone']?.toString() ?? '',
              onTap: _pickParty,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxHeight < 520;
                  final panelHeight = (constraints.maxHeight * 0.42).clamp(
                    180.0,
                    280.0,
                  );

                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildModeSelector(),
                      _buildEntryPanel(panelHeight),
                      if (!compact) ...[
                        const SizedBox(height: 8),
                        Text(
                          _entryHintText(),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else
                        const SizedBox(height: 8),
                      Expanded(child: _buildBillItemsPanel()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
        // ── Bottom Total + Complete Button ──
        bottomNavigationBar: _items.isNotEmpty
            ? Container(
                color: AppColors.bgOf(context),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.isDark(context)
                          ? AppColors.darkSurfaceRaised
                          : AppColors.navy,
                      borderRadius: AppRadius.lgRadius,
                    ),
                    child: Row(
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.l10n.total,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              rupees(_subtotal),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        TestKeys.tag(
                          TestKeys.scanBillBtn,
                          FilledButton.icon(
                            onPressed: _openBillSheet,
                            icon: const Icon(Icons.receipt_long_rounded),
                            label: Text(
                              _checkoutState['pending'] != null
                                  ? 'Recover pending checkout'
                                  : context.l10n.bill,
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
                          button: true,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Future<String?> _confirmExit() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Keep this bill for later?'),
        content: Text(
          'Keep the cart and checkout entries on this device, or discard them explicitly.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('checkout-keep-exit'),
            onPressed: () => Navigator.pop(ctx, 'keep'),
            child: const Text('Keep and exit'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.keepBilling),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(context.l10n.discard),
          ),
        ],
      ),
    );
    return action;
  }

  void _clearWithUndo() {
    if (_pendingCheckoutBlocksEdit()) return;
    final removed = List<BillItem>.of(_items);
    setState(() => _items.clear());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Cleared ${removed.length} item${removed.length == 1 ? '' : 's'}',
          ),
          action: SnackBarAction(
            label: context.l10n.undo,
            onPressed: () {
              if (!mounted || _items.isNotEmpty) return;
              setState(() => _items.addAll(removed));
            },
          ),
        ),
      );
  }

  Future<void> _showLineControlsSheet(int index) async {
    if (_pendingCheckoutBlocksEdit()) return;
    final item = _items[index];
    final result =
        await showModalBottomSheet<
          ({String mode, double value, String? taxMode})
        >(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppColors.surfaceOf(context),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (_) => _LineControlsSheet(
            productName: item.productName,
            lineSubtotal: item.subtotal,
            initialMode: item.discountMode,
            initialValue: item.discountValue,
            initialTaxMode: item.taxMode,
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      item.discountMode = result.mode;
      item.discountValue = result.value;
      item.taxMode = result.taxMode;
    });
  }

  String? _lineControlsBadge(BillItem item) {
    final parts = <String>[];
    if (item.discountValue > 0) {
      final val = item.discountValue
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'\.?0+$'), '');
      parts.add(
        item.discountMode == Bill.discountModeAmount
            ? '₹$val off'
            : '$val% off',
      );
    }
    if (item.taxMode == Bill.taxModeInclusive) {
      parts.add('Incl.');
    } else if (item.taxMode == Bill.taxModeExclusive) {
      parts.add('Excl.');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _buildBillItemsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.lg),
        ),
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
                    context.l10n.noItemsYet,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                if (_canUseCloudHandoff)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        key: const ValueKey('checkout-send-handoff'),
                        onPressed: _isSendingHandoff ? null : _sendDraftHandoff,
                        icon: _isSendingHandoff
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.devices_rounded, size: 18),
                        label: const Text('Send to another device'),
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final item = _items[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceOf(context),
                          borderRadius: AppRadius.mdRadius,
                          border: Border.all(
                            color: AppColors.borderOf(context),
                          ),
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
                                      color: AppColors.inkMutedOf(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (_lineControlsBadge(item)
                                      case final badge?)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        badge,
                                        style: TextStyle(
                                          color: AppColors.amber,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (item.draftQuantityInput != null ||
                                      saleQuantityThousandths(
                                            item.quantity.toString(),
                                          ) ==
                                          null)
                                    Text(
                                      saleQuantityGuidance,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            // Qty controls
                            Container(
                              decoration: BoxDecoration(
                                color: AppColors.softBgOf(context),
                                borderRadius: AppRadius.smRadius,
                              ),
                              child: Row(
                                children: [
                                  IconButton(
                                    onPressed: () => _updateQty(i, -1),
                                    icon: const Icon(Icons.remove, size: 18),
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 44,
                                    child: _QuantityInput(
                                      key: ObjectKey(item),
                                      quantity: item.quantity,
                                      invalidInput: item.draftQuantityInput,
                                      enabled:
                                          _checkoutState['pending'] == null,
                                      onChanged: (quantity) =>
                                          _setQty(i, quantity),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _updateQty(i, 1),
                                    icon: const Icon(Icons.add, size: 18),
                                    constraints: const BoxConstraints(
                                      minWidth: 48,
                                      minHeight: 48,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              key: ValueKey('cart-item-edit-$i'),
                              tooltip: 'Line discount & tax',
                              onPressed: _checkoutState['pending'] == null
                                  ? () => _showLineControlsSheet(i)
                                  : null,
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              constraints: const BoxConstraints(
                                minWidth: 36,
                                minHeight: 36,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Subtotal
                            Text(
                              rupees(item.subtotal),
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
              ],
            ),
    );
  }
}

class _LineControlsSheet extends StatefulWidget {
  final String productName;
  final double lineSubtotal;
  final String initialMode;
  final double initialValue;
  final String? initialTaxMode;

  const _LineControlsSheet({
    required this.productName,
    required this.lineSubtotal,
    required this.initialMode,
    required this.initialValue,
    required this.initialTaxMode,
  });

  @override
  State<_LineControlsSheet> createState() => _LineControlsSheetState();
}

class _LineControlsSheetState extends State<_LineControlsSheet> {
  late String _mode;
  String? _taxMode;
  late final TextEditingController _valueCtrl;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _taxMode = widget.initialTaxMode;
    _valueCtrl = TextEditingController(
      text: widget.initialValue > 0
          ? widget.initialValue
                .toStringAsFixed(2)
                .replaceFirst(RegExp(r'\.?0+$'), '')
          : '',
    );
  }

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.productName,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('line-discount-value'),
                    controller: _valueCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        return RegExp(
                              r'^\d*\.?\d{0,2}$',
                            ).hasMatch(newValue.text)
                            ? newValue
                            : oldValue;
                      }),
                    ],
                    decoration: InputDecoration(
                      labelText: _mode == Bill.discountModePercent
                          ? 'Line discount (%)'
                          : 'Line discount (₹)',
                      prefixText: _mode == Bill.discountModeAmount
                          ? '₹ '
                          : null,
                      suffixText: _mode == Bill.discountModePercent
                          ? '%'
                          : null,
                      errorText: _errorText,
                    ),
                    onChanged: (_) => setState(() => _errorText = null),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  key: const ValueKey('line-discount-mode'),
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: Bill.discountModePercent,
                      label: Text('%'),
                    ),
                    ButtonSegment(
                      value: Bill.discountModeAmount,
                      label: Text('₹'),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (sel) => setState(() {
                    _mode = sel.first;
                    _errorText = null;
                  }),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Line tax mode', style: AppText.caption),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                key: const ValueKey('line-tax-mode'),
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'default', label: Text('Bill default')),
                  ButtonSegment(
                    value: Bill.taxModeInclusive,
                    label: Text('Incl.'),
                  ),
                  ButtonSegment(
                    value: Bill.taxModeExclusive,
                    label: Text('Excl.'),
                  ),
                ],
                selected: {_taxMode ?? 'default'},
                onSelectionChanged: (sel) => setState(() {
                  _taxMode = sel.first == 'default' ? null : sel.first;
                }),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const ValueKey('line-controls-apply'),
                onPressed: () {
                  final parsed = double.tryParse(_valueCtrl.text.trim()) ?? 0;
                  if (_mode == Bill.discountModePercent && parsed > 100) {
                    setState(() => _errorText = 'Percent must be 0 to 100');
                    return;
                  }
                  if (_mode == Bill.discountModeAmount &&
                      parsed > widget.lineSubtotal + 1e-6) {
                    setState(() => _errorText = 'Cannot exceed line subtotal');
                    return;
                  }
                  Navigator.pop(context, (
                    mode: _mode,
                    value: parsed,
                    taxMode: _taxMode,
                  ));
                },
                child: const Text('Apply'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
