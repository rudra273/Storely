import 'dart:convert';

import '../../db/database_helper.dart';
import 'native_sale_sync_backend.dart';
import 'sync_backend.dart';
import 'purchase_sync_backend.dart';

/// How a device's existing local data is handled on its first sync.
enum FirstSyncMode { uploadExisting, startFresh }

/// Result of inspecting a reserved native sale against both the cloud server
/// and local post-issue edits.
class NativeSaleReconciliationReport {
  final PendingNativeSale sale;
  final String serverStatus;
  final bool operationCommitted;
  final Map<String, dynamic>? committedBill;
  final List<Map<String, dynamic>> stockShortages;
  final List<Map<String, dynamic>> termsMismatches;
  final List<Map<String, dynamic>> snapshotMismatches;
  final List<String> identityConflicts;
  final List<String> blockingReasons;
  final bool canReconcile;
  final NativeSaleLocalDiff localDiff;

  const NativeSaleReconciliationReport({
    required this.sale,
    required this.serverStatus,
    required this.operationCommitted,
    required this.committedBill,
    required this.stockShortages,
    required this.termsMismatches,
    required this.snapshotMismatches,
    required this.identityConflicts,
    required this.blockingReasons,
    required this.canReconcile,
    required this.localDiff,
  });

  bool get hasStockShortages => stockShortages.isNotEmpty;

  bool get hasSnapshotOrTermsMismatches =>
      termsMismatches.isNotEmpty || snapshotMismatches.isNotEmpty;
}

/// Outcome of a sync attempt.
///
/// [syncedAt] is non-null only when a real sync ran. [needsRegistration] means
/// the user belongs to no shop yet. [needsFirstSyncChoice] means this is the
/// first sync and the device has existing local data, so the user must choose
/// whether to upload it or start fresh. [conflicts] are rows that could not be
/// applied or uploaded; everything else synced.
class CloudSyncResult {
  final DateTime? syncedAt;
  final bool needsRegistration;
  final bool needsFirstSyncChoice;
  final List<SyncConflict> conflicts;

  const CloudSyncResult.synced(
    DateTime this.syncedAt, {
    this.conflicts = const [],
  }) : needsRegistration = false,
       needsFirstSyncChoice = false;
  const CloudSyncResult.needsRegistration()
    : syncedAt = null,
      needsRegistration = true,
      needsFirstSyncChoice = false,
      conflicts = const [];
  const CloudSyncResult.needsFirstSyncChoice()
    : syncedAt = null,
      needsRegistration = false,
      needsFirstSyncChoice = true,
      conflicts = const [];
}

/// Two-way sync between the local database and the cloud.
///
/// Pull: per table, pages of rows changed after a cursor on the *server*
/// clock (server_updated_at), re-reading a short overlap so rows from
/// transactions that commit slightly out of order are never skipped. Pulled
/// rows are applied idempotently, so re-reading is harmless.
///
/// Push: exactly the rows marked changed on this device (sync_dirty), in
/// parent-before-child table order and in chunks. A chunk the server refuses
/// is retried row by row so one bad row is reported as a conflict instead of
/// blocking the table. Conflict rules (latest edit wins, deletions win) are
/// enforced by the server, so pull-before-push races cannot lose data.
class CloudSyncEngine {
  final SyncBackend backend;
  final DatabaseHelper database;

  /// Locally-known admin status (e.g. right after registering a shop), which
  /// skips the is_shop_admin round-trip that can lag behind registration.
  final bool? knownIsAdmin;

  /// Rows per pull page (smaller in tests to exercise paging).
  final int pageSize;
  final Future<void> Function(bool restoring)? prepareUserData;
  final Future<void> Function()? applyUserData;
  final bool Function()? isUserDataScopeCurrent;

  CloudSyncEngine({
    required this.backend,
    required this.database,
    this.knownIsAdmin,
    this.pageSize = defaultPageSize,
    this.prepareUserData,
    this.applyUserData,
    this.isUserDataScopeCurrent,
  });

  static const purchaseCursorStateKey = 'purchase_document_sequence';
  static const nativeSaleConflictTable = 'native_sale_postings';
  static const nativeBillingCommandConflictTable = 'native_billing_commands';
  static const lastSyncStateKey = 'last_successful_cloud_sync_at';
  static const defaultPageSize = 500;
  static const pushChunkSize = 200;
  static const pullOverlap = Duration(minutes: 2);

  static const _adminManagedTables = {
    'shops',
    'app_settings',
    'bill_settings',
    'categories',
    'units',
    'suppliers',
    'products',
    'invoice_series',
    'expenses',
  };

  static const syncedTables = ['shops', ...storelyCloudTables];

  static String _cursorKey(String table) => 'pull_cursor:$table';

  /// Gives up on this phone's version of one row that keeps failing to
  /// sync: it is no longer uploaded, and its table is pulled again from the
  /// start so the cloud's version (if any) replaces it on the next sync.
  static Future<void> useCloudCopy(
    DatabaseHelper database,
    SyncConflict conflict,
  ) async {
    if (conflict.table == 'supplier_payment_queue') {
      throw StateError(
        'Review this payment in Suppliers. The saved request is preserved.',
      );
    }
    if (conflict.table == 'purchase_documents') {
      throw StateError(
        'Review this purchase in Purchase history. Stock and pending documents are preserved.',
      );
    }
    if (conflict.table == nativeSaleConflictTable) {
      throw StateError(
        'The original sale is reserved for atomic sync. Its local records are preserved.',
      );
    }
    if (conflict.table == nativeBillingCommandConflictTable) {
      throw StateError(
        'This billing follow-up is reserved for atomic sync. Its local records are preserved.',
      );
    }
    await database.markRowSynced(conflict.table, conflict.key);
    await database.clearCloudSyncState(_cursorKey(conflict.table));
    final remaining = [
      for (final c in await database.getSyncConflicts())
        if (c.table != conflict.table || c.key != conflict.key) c,
    ];
    await database.saveSyncConflicts(remaining);
  }

  /// Forget sync progress so the next sync is a first sync again.
  static Future<void> resetProgress(DatabaseHelper database) async {
    await database.clearCloudSyncState(lastSyncStateKey);
    await database.clearCloudSyncState(purchaseCursorStateKey);
    await database.clearNativeSaleScope();
    await database.clearNativeBillingCommandsScope();
    for (final table in syncedTables) {
      await database.clearCloudSyncState(_cursorKey(table));
    }
    await database.saveSyncConflicts(const []);
  }

  Future<CloudSyncResult> sync({FirstSyncMode? firstSyncMode}) async {
    var shopId = await database.currentShopId();
    final hadLocalData = await database.hasLocalBusinessDataForCloud();

    // Resolve which shop (if any) this user belongs to. Joining a shop the
    // user was invited to also happens here.
    final memberShopId = await backend.resolveMembershipShopId();
    if (memberShopId == null) {
      return const CloudSyncResult.needsRegistration();
    }
    if (memberShopId != shopId) {
      if (await database.hasLocalBusinessDataForCloud()) {
        throw StateError(
          'This user belongs to a different cloud shop, but this device '
          'already has local business data. Export or clear local data '
          'before joining that shop.',
        );
      }
      await database.adoptCloudShopId(memberShopId);
      shopId = memberShopId;
    }

    // Each device gets its own bill-number letter before it bills for the
    // shop, so phones billing offline never issue the same number.
    if (!await database.hasDeviceCode(shopId)) {
      final code = await backend.registerDevice(
        shopId,
        await database.localDeviceId(),
      );
      await database.setDeviceCode(shopId, code);
    }

    final lastSync = await database.getCloudSyncState(lastSyncStateKey);
    final canPushAdminTables =
        knownIsAdmin ?? await backend.isShopAdmin(shopId);
    final firstSync = lastSync == null;

    // First sync on a device that already has local data: the user decides
    // whether to upload it or start fresh. Staff joining an existing shop
    // never upload catalog data, so they are not asked.
    if (firstSync &&
        firstSyncMode == null &&
        canPushAdminTables &&
        await database.hasLocalBusinessDataForCloud()) {
      return const CloudSyncResult.needsFirstSyncChoice();
    }

    await prepareUserData?.call(firstSync && !hadLocalData);
    if (firstSync &&
        firstSyncMode == FirstSyncMode.startFresh &&
        (await database.hasReservedNativeSales(shopId) ||
            await database.hasReservedNativeBillingCommands(shopId))) {
      throw StateError(
        'Retry the reserved sales and billing commands before starting fresh.',
      );
    }
    final saleBackend = backend;
    final saleScope =
        (saleBackend is NativeSaleSyncBackend ||
            saleBackend is NativeBillingCommandSyncBackend)
        ? await database.captureCheckoutScope()
        : null;
    final conflicts = <SyncConflict>[];
    for (final table in syncedTables) {
      conflicts.addAll(await _pull(table, shopId));
    }

    if (firstSync) {
      if (firstSyncMode == FirstSyncMode.startFresh) {
        await database.markAllCloudRowsClean();
        await database.keepPendingPurchasesLocal();
      }
    }

    for (final table in syncedTables) {
      if (_adminManagedTables.contains(table) && !canPushAdminTables) continue;
      if (table == 'audit_log' &&
          saleScope?.owner != null &&
          saleScope!.shopId == shopId) {
        if (saleBackend is NativeSaleSyncBackend) {
          conflicts.addAll(
            await _syncNativeSales(
              saleBackend as NativeSaleSyncBackend,
              saleScope,
            ),
          );
        }
        if (saleBackend is NativeBillingCommandSyncBackend) {
          conflicts.addAll(
            await _syncNativeBillingCommands(
              saleBackend as NativeBillingCommandSyncBackend,
              saleScope,
            ),
          );
        }
      }
      conflicts.addAll(await _push(table));
    }

    final purchaseBackend = backend;
    if (canPushAdminTables && purchaseBackend is PurchaseSyncBackend) {
      conflicts.addAll(
        await _syncPurchaseDocuments(
          purchaseBackend as PurchaseSyncBackend,
          shopId,
        ),
      );
    }
    await applyUserData?.call();
    if (nativeSalePostingEnabled &&
        saleScope?.owner != null &&
        saleScope!.shopId == shopId) {
      if (saleBackend is NativeSaleSyncBackend) {
        final supported = await (saleBackend as NativeSaleSyncBackend)
            .supportsNativeSale(saleScope);
        await database.updateNativeSaleScope(
          saleScope,
          supported: supported,
          isCurrent: _nativeSaleScopeCurrent,
        );
      }
      if (saleBackend is NativeBillingCommandSyncBackend) {
        final supported = await (saleBackend as NativeBillingCommandSyncBackend)
            .supportsNativeBillingCommands(saleScope);
        await database.updateNativeBillingCommandsScope(
          saleScope,
          supported: supported,
          isCurrent: _nativeSaleScopeCurrent,
        );
      }
    }
    final syncedAt = DateTime.now().toUtc();
    await database.setCloudSyncState(
      lastSyncStateKey,
      syncedAt.toIso8601String(),
    );
    await database.saveSyncConflicts(conflicts);
    return CloudSyncResult.synced(syncedAt, conflicts: conflicts);
  }

  bool _nativeSaleScopeCurrent() => isUserDataScopeCurrent?.call() != false;

  Future<NativeSaleReconciliationReport> inspectReservedNativeSale(
    NativeSaleSyncBackend transport,
    CheckoutScope scope,
    String billUuid,
  ) async {
    if (!_nativeSaleScopeCurrent()) {
      throw StateError('Account changed during sale reconciliation.');
    }
    final sale = await database.pendingNativeSaleForBill(scope, billUuid);
    if (sale == null) {
      throw StateError('No reserved native sale found for this invoice.');
    }
    final request = Map<String, dynamic>.from(jsonDecode(sale.request) as Map);
    if (request['invoice_uuid'] != sale.billUuid ||
        request['device_id'] != scope.deviceId) {
      throw const FormatException('Saved sale identity or device differs.');
    }
    final localDiff = await database.inspectLocalNativeSaleEdits(scope, sale);
    if (!_nativeSaleScopeCurrent()) {
      throw StateError('Account changed during sale reconciliation.');
    }
    final raw = await transport.inspectNativeSaleReconciliation(
      scope,
      sale.attemptId,
      request,
    );
    if (!_nativeSaleScopeCurrent()) {
      throw StateError('Account changed during sale reconciliation.');
    }

    List<Map<String, dynamic>> mapList(Object? value) => value is List
        ? [for (final item in value) Map<String, dynamic>.from(item as Map)]
        : const [];
    List<String> stringList(Object? value) =>
        value is List ? [for (final item in value) item.toString()] : const [];

    return NativeSaleReconciliationReport(
      sale: sale,
      serverStatus: (raw['status'] ?? '').toString(),
      operationCommitted: raw['operation_committed'] == true,
      committedBill: raw['committed_bill'] is Map
          ? Map<String, dynamic>.from(raw['committed_bill'] as Map)
          : null,
      stockShortages: mapList(raw['stock_shortages']),
      termsMismatches: mapList(raw['terms_mismatches']),
      snapshotMismatches: mapList(raw['snapshot_mismatches']),
      identityConflicts: stringList(raw['identity_conflicts']),
      blockingReasons: stringList(raw['blocking_reasons']),
      canReconcile: raw['can_reconcile'] == true,
      localDiff: localDiff,
    );
  }

  Future<void> resolveReservedNativeSale(
    NativeSaleSyncBackend transport,
    CheckoutScope scope,
    NativeSaleReconciliationReport report, {
    bool allowStockShortage = false,
    bool acceptRecordedSnapshot = false,
    bool postOriginalBeforeLocalEdits = false,
    String? reason,
  }) async {
    if (!_nativeSaleScopeCurrent()) {
      throw StateError('Account changed during sale reconciliation.');
    }
    final sale = report.sale;
    final request = Map<String, dynamic>.from(jsonDecode(sale.request) as Map);
    if (request['invoice_uuid'] != sale.billUuid ||
        request['device_id'] != scope.deviceId) {
      throw const FormatException('Saved sale identity or device differs.');
    }

    if (report.serverStatus == 'already_committed') {
      final receipt = report.committedBill;
      if (receipt == null || !_matchesNativeSaleReceipt(request, receipt)) {
        throw const FormatException(
          'The server did not confirm the saved sale identities.',
        );
      }
      if (!_matchesNativeSaleSnapshot(request, receipt)) {
        throw const FormatException(
          'The server did not confirm the saved invoice item snapshots.',
        );
      }
      if (!_nativeSaleScopeCurrent()) {
        throw StateError('Account changed during sale reconciliation.');
      }
      await database.acknowledgeReconciledNativeSale(
        scope,
        sale,
        isCurrent: _nativeSaleScopeCurrent,
      );
    } else if (allowStockShortage || acceptRecordedSnapshot) {
      final trimmedReason = (reason ?? '').trim();
      if (trimmedReason.length < 3) {
        throw ArgumentError(
          'Enter a reconciliation reason (at least 3 characters).',
        );
      }
      if (report.localDiff.hasEdits && !postOriginalBeforeLocalEdits) {
        throw StateError(
          'Confirm posting the original invoice before syncing local edits.',
        );
      }
      if (!_nativeSaleScopeCurrent()) {
        throw StateError('Account changed during sale reconciliation.');
      }
      final receipt = await transport.reconcileNativeSale(
        scope,
        sale.attemptId,
        request,
        allowStockShortage: allowStockShortage,
        acceptRecordedSnapshot: acceptRecordedSnapshot,
        reason: trimmedReason,
      );
      if (!_nativeSaleScopeCurrent()) {
        throw StateError('Account changed during sale reconciliation.');
      }
      if (!_matchesNativeSaleReceipt(request, receipt)) {
        throw const FormatException(
          'The server did not confirm the saved sale identities.',
        );
      }
      if (!_matchesNativeSaleSnapshot(request, receipt)) {
        throw const FormatException(
          'The server did not confirm the saved invoice item snapshots.',
        );
      }
      await database.acknowledgeReconciledNativeSale(
        scope,
        sale,
        isCurrent: _nativeSaleScopeCurrent,
      );
    } else if (report.serverStatus == 'ready' &&
        (!report.localDiff.hasEdits || postOriginalBeforeLocalEdits)) {
      if (!_nativeSaleScopeCurrent()) {
        throw StateError('Account changed during sale reconciliation.');
      }
      final receipt = await transport.postNativeSale(
        scope,
        sale.attemptId,
        request,
      );
      if (!_nativeSaleScopeCurrent()) {
        throw StateError('Account changed during sale reconciliation.');
      }
      if (!_matchesNativeSaleReceipt(request, receipt)) {
        throw const FormatException(
          'The server did not confirm the saved sale identities.',
        );
      }
      if (!_matchesNativeSaleSnapshot(request, receipt)) {
        throw const FormatException(
          'The server did not confirm the saved invoice item snapshots.',
        );
      }
      await database.acknowledgeReconciledNativeSale(
        scope,
        sale,
        isCurrent: _nativeSaleScopeCurrent,
      );
    } else {
      throw StateError(
        'Select the required reconciliation options before continuing.',
      );
    }

    final remaining = [
      for (final c in await database.getSyncConflicts())
        if (c.table != nativeSaleConflictTable || c.key != sale.billUuid) c,
    ];
    await database.saveSyncConflicts(remaining);
  }

  Future<List<SyncConflict>> _syncNativeSales(
    NativeSaleSyncBackend transport,
    CheckoutScope scope,
  ) async {
    final conflicts = <SyncConflict>[];
    for (final sale in await database.pendingNativeSales(scope)) {
      String? problem;
      try {
        final unchanged = await database.checkNativeSale(
          scope,
          sale,
          isCurrent: _nativeSaleScopeCurrent,
        );
        if (!unchanged) {
          problem =
              'The invoice changed on this device and needs reconciliation.';
        } else {
          final request = jsonDecode(sale.request) as Map<String, dynamic>;
          if (request['invoice_uuid'] != sale.billUuid ||
              request['device_id'] != scope.deviceId) {
            throw const FormatException(
              'Saved sale identity or device differs.',
            );
          }
          final receipt = await transport.postNativeSale(
            scope,
            sale.attemptId,
            request,
          );
          if (!_matchesNativeSaleReceipt(request, receipt)) {
            throw const FormatException(
              'The server did not confirm the saved sale identities.',
            );
          }
          if (!_matchesNativeSaleSnapshot(request, receipt)) {
            throw const FormatException(
              'The server did not confirm the saved invoice item snapshots.',
            );
          }
          if (!await database.checkNativeSale(
            scope,
            sale,
            isCurrent: _nativeSaleScopeCurrent,
            acknowledged: true,
          )) {
            problem =
                'The server accepted the sale and local changes need reconciliation.';
          }
        }
      } on SyncRowRejected catch (error) {
        problem = error.message;
      } on FormatException catch (error) {
        problem = error.message;
      }
      if (problem != null) {
        conflicts.add(
          SyncConflict(
            table: nativeSaleConflictTable,
            key: sale.billUuid,
            message: problem,
          ),
        );
        // Keep checkout order when an earlier sale could have changed stock
        // available to a later sale on this device.
        break;
      }
    }
    return conflicts;
  }

  Future<List<SyncConflict>> _syncNativeBillingCommands(
    NativeBillingCommandSyncBackend transport,
    CheckoutScope scope,
  ) async {
    final conflicts = <SyncConflict>[];
    for (final cmd in await database.pendingNativeBillingCommands(scope)) {
      String? problem;
      try {
        final request = cmd.decodedRequest;
        if (request['device_id'] != scope.deviceId) {
          throw const FormatException('Saved billing command device differs.');
        }
        final Map<String, dynamic> receipt;
        switch (cmd.commandType) {
          case 'payment':
            receipt = await transport.postNativePayment(
              scope,
              cmd.commandId,
              cmd.billUuid,
              request,
            );
            if (!_matchesNativePaymentReceipt(cmd, receipt)) {
              throw const FormatException(
                'The server did not confirm the saved payment identity.',
              );
            }
          case 'cancel':
            receipt = await transport.postNativeCancel(
              scope,
              cmd.commandId,
              cmd.billUuid,
              request,
            );
            if (!_matchesNativeCancelReceipt(cmd, receipt)) {
              throw const FormatException(
                'The server did not confirm the bill cancellation.',
              );
            }
          case 'credit_note':
            receipt = await transport.postNativeCreditNote(
              scope,
              cmd.commandId,
              cmd.billUuid,
              request,
            );
            if (!_matchesNativeCreditNoteReceipt(cmd, request, receipt)) {
              throw const FormatException(
                'The server did not confirm the saved credit note identities.',
              );
            }
          default:
            throw FormatException(
              'Unsupported billing command type: ${cmd.commandType}',
            );
        }
        await database.acknowledgeNativeBillingCommand(
          scope,
          cmd,
          isCurrent: _nativeSaleScopeCurrent,
        );
      } on SyncRowRejected catch (error) {
        problem = error.message;
      } on FormatException catch (error) {
        problem = error.message;
      }
      if (problem != null) {
        await database.recordNativeBillingCommandError(cmd.commandId, problem);
        conflicts.add(
          SyncConflict(
            table: nativeBillingCommandConflictTable,
            key: cmd.commandId,
            message: problem,
          ),
        );
        // Keep creation order so later follow-up commands on the same bill or
        // stock do not overtake an earlier rejected command.
        break;
      }
    }
    return conflicts;
  }

  static bool _matchesNativePaymentReceipt(
    PendingNativeBillingCommand cmd,
    Map<String, dynamic> receipt,
  ) {
    final bill = receipt['bill'];
    final payments = receipt['payments'];
    if (bill is! Map || bill['uuid'] != cmd.billUuid) return false;
    if (payments is! List) return false;
    return payments.any((p) => p is Map && p['uuid'] == cmd.targetUuid);
  }

  static bool _matchesNativeCancelReceipt(
    PendingNativeBillingCommand cmd,
    Map<String, dynamic> receipt,
  ) {
    final bill = receipt['bill'];
    return bill is Map &&
        bill['uuid'] == cmd.billUuid &&
        bill['cancelled'] == true;
  }

  static bool _matchesNativeCreditNoteReceipt(
    PendingNativeBillingCommand cmd,
    Map<String, dynamic> request,
    Map<String, dynamic> receipt,
  ) {
    final bill = receipt['bill'];
    final items = receipt['items'];
    if (bill is! Map ||
        bill['uuid'] != cmd.targetUuid ||
        bill['bill_number'] != request['credit_note_number']) {
      return false;
    }
    if (items is! List) return false;
    final returnedIds = items
        .map((item) => item is Map ? item['uuid'] : null)
        .toSet();
    final expectedIds = (request['lines'] as List)
        .map((line) => (line as Map)['line_uuid'])
        .toList();
    return expectedIds.isNotEmpty && returnedIds.containsAll(expectedIds);
  }

  static bool _matchesNativeSaleReceipt(
    Map<String, dynamic> request,
    Map<String, dynamic> receipt,
  ) {
    bool sameIds(Object? rows, Iterable<Object?> expected) {
      if (rows is! List || rows.length != expected.length) return false;
      final ids = rows.map((row) => row is Map ? row['uuid'] : null).toSet();
      return ids.length == rows.length && ids.containsAll(expected);
    }

    final invoice = receipt['bill'];
    return invoice is Map &&
        invoice['uuid'] == request['invoice_uuid'] &&
        invoice['bill_number'] == request['invoice_number'] &&
        sameIds(
          receipt['items'],
          (request['lines'] as List).map((line) => (line as Map)['line_uuid']),
        ) &&
        sameIds(receipt['payments'], [?request['payment_uuid']]);
  }

  static bool _matchesNativeSaleSnapshot(
    Map<String, dynamic> request,
    Map<String, dynamic> receipt,
  ) {
    final lines = (request['lines'] as List).cast<Map>();
    // An earlier app can have reserved a command before snapshot proof existed.
    if (lines.every((line) => line['snapshot'] == null)) return true;
    final proof = receipt['native_sale_snapshot_verified'];
    if (proof is! int || proof != 1) return false;
    final items = {
      for (final item in (receipt['items'] as List).cast<Map>())
        item['uuid']: item,
    };
    return lines.every((line) {
      final snapshot = line['snapshot'];
      final item = items[line['line_uuid']]!;
      return snapshot is Map &&
          item.containsKey('hsn_code') &&
          item['hsn_code'] == snapshot['hsn_code_snapshot'] &&
          item.containsKey('unit') &&
          item['unit'] == snapshot['unit_name'];
    });
  }

  Future<List<SyncConflict>> _syncPurchaseDocuments(
    PurchaseSyncBackend transport,
    String shopId,
  ) async {
    final conflicts = <SyncConflict>[];
    for (final receipt in await database.pendingPurchaseDocuments()) {
      if (!await database.purchaseStockUploaded(receipt)) {
        const message =
            'Purchase stock is still waiting to upload. The document is kept pending.';
        conflicts.add(
          SyncConflict(
            table: 'purchase_documents',
            key: receipt.uuid,
            message: message,
          ),
        );
        continue;
      }
      try {
        final cloud = await transport.publishNativePurchase(
          shopId,
          receipt.toJson(),
        );
        final conflict = await database.importPurchaseDocument(
          cloud,
          shopId: shopId,
        );
        if (conflict != null) conflicts.add(conflict);
      } on SyncRowRejected catch (error) {
        await database.setPurchaseSyncError(receipt.uuid, error.message);
        conflicts.add(
          SyncConflict(
            table: 'purchase_documents',
            key: receipt.uuid,
            message: error.message,
          ),
        );
      }
    }
    if (transport is SupplierPaymentSyncBackend) {
      final payments = transport as SupplierPaymentSyncBackend;
      for (final payment in await database.pendingSupplierPayments(
        shopId: shopId,
      )) {
        final key = payment['request_key'] as String;
        final previouslyUnknown = payment['command_state'] == 'unknown';
        if (!await database.beginSupplierPaymentAttempt(key, shopId: shopId)) {
          continue;
        }
        try {
          final supplierId = payment['supplier_uuid'] as String;
          final payload = Map<String, dynamic>.from(
            jsonDecode(payment['payload'] as String) as Map,
          );
          if (payment['shop_id'] != shopId ||
              supplierId.trim().isEmpty ||
              payload['request_key'] != key) {
            throw const FormatException(
              'Saved payment identity does not match its queue record',
            );
          }
          String? recoveredUuid;
          if (previouslyUnknown &&
              payload['purchase_uuid'] != null &&
              transport is! SupplierPaymentRecoveryBackend) {
            throw StateError(
              'This server cannot verify the selected purchase for this saved payment.',
            );
          }
          if (previouslyUnknown &&
              transport is SupplierPaymentRecoveryBackend) {
            final recovery = await (transport as SupplierPaymentRecoveryBackend)
                .recoverSupplierPayment(shopId, supplierId, payload);
            if (recovery.status == SupplierPaymentRecoveryStatus.unsupported &&
                payload['purchase_uuid'] != null) {
              throw StateError(
                'This server cannot verify the selected purchase for this saved payment.',
              );
            }
            if (recovery.status == SupplierPaymentRecoveryStatus.committed) {
              recoveredUuid = recovery.uuid;
              if (recoveredUuid == null ||
                  recoveredUuid.trim().isEmpty ||
                  recoveredUuid != recoveredUuid.trim()) {
                throw const FormatException(
                  'Missing recovered payment identity',
                );
              }
            }
          }
          final result = recoveredUuid == null
              ? await payments.publishSupplierPayment(
                  shopId,
                  supplierId,
                  payload,
                )
              : {'uuid': recoveredUuid};
          await database.setSupplierPaymentSync(
            key,
            shopId: shopId,
            cloudUuid: result['uuid'] as String,
          );
        } on SyncRowRejected catch (error) {
          // A retry denied after a lost response cannot prove that the first
          // attempt did not commit. Keep the reservation and original identity.
          if (previouslyUnknown) {
            await database.markSupplierPaymentUncertain(key, shopId: shopId);
          } else {
            await database.setSupplierPaymentSync(
              key,
              shopId: shopId,
              error: error.message,
              isConflict: error.isConflict,
            );
          }
          conflicts.add(
            SyncConflict(
              table: 'supplier_payment_queue',
              key: key,
              message: error.message,
            ),
          );
        } catch (_) {
          await database.markSupplierPaymentUncertain(key, shopId: shopId);
          rethrow;
        }
      }
    }
    var sequence =
        int.tryParse(
          await database.getCloudSyncState(purchaseCursorStateKey) ?? '',
        ) ??
        0;
    final limit = pageSize > 100 ? 100 : pageSize;
    while (true) {
      final page = await transport.pullPurchaseDocuments(
        shopId,
        afterSequence: sequence,
        limit: limit,
      );
      if (page.isEmpty) break;
      for (final row in page) {
        final next = (row['change_sequence'] as num).toInt();
        if (next <= sequence) {
          throw StateError('Purchase feed did not advance.');
        }
        final conflict = await database.importPurchaseDocument(
          row,
          shopId: shopId,
        );
        if (conflict != null) conflicts.add(conflict);
        sequence = next;
      }
      await database.setCloudSyncState(purchaseCursorStateKey, '$sequence');
      if (page.length < limit) break;
    }
    return conflicts;
  }

  void _assertPreferenceTransport() {
    if (isUserDataScopeCurrent?.call() == false) {
      throw StateError('Account changed during preference sync.');
    }
  }

  Future<List<SyncConflict>> _pull(String table, String shopId) async {
    final conflicts = <SyncConflict>[];
    if (table == 'user_preferences') _assertPreferenceTransport();
    final preferenceScope = table == 'user_preferences'
        ? await database.ensurePortablePreferenceCursorScope(shopId)
        : null;
    final stored = DateTime.tryParse(
      await database.getCloudSyncState(_cursorKey(table)) ?? '',
    );
    var afterTs = stored == null
        ? DateTime.utc(1970)
        : stored.subtract(pullOverlap);
    var afterKey = '';
    DateTime? newest = stored;
    var skippedReservedSale = false;
    final keyColumn = table == 'app_settings' ? 'key' : 'uuid';

    while (true) {
      if (preferenceScope != null) _assertPreferenceTransport();
      final page = await backend.pullPage(
        table,
        shopId: shopId,
        afterTs: afterTs,
        afterKey: afterKey,
        limit: pageSize,
      );
      if (preferenceScope != null) _assertPreferenceTransport();
      if (page.isEmpty) break;
      if (preferenceScope != null) {
        await database.assertPortablePreferenceCursorScope(preferenceScope);
      }
      conflicts.addAll(
        await database.cloudImportRows(
          table,
          page,
          onReservedSale: () => skippedReservedSale = true,
        ),
      );
      final last = page.last;
      afterTs = DateTime.parse(last['server_updated_at'].toString());
      afterKey = last[keyColumn]?.toString() ?? '';
      if (newest == null || afterTs.isAfter(newest)) newest = afterTs;
      if (page.length < pageSize) break;
    }

    // Keep the last cursor until reserved rows can be applied after replay.
    if (newest != null && newest != stored && !skippedReservedSale) {
      if (preferenceScope != null) {
        await database.assertPortablePreferenceCursorScope(preferenceScope);
      }
      if (preferenceScope != null) {
        await database.savePortablePreferenceCursor(
          preferenceScope,
          newest.toUtc().toIso8601String(),
          isTransportCurrent: isUserDataScopeCurrent,
        );
      } else {
        await database.setCloudSyncState(
          _cursorKey(table),
          newest.toUtc().toIso8601String(),
        );
      }
    }
    return conflicts;
  }

  Future<List<SyncConflict>> _push(String table) async {
    if (table == 'user_preferences') _assertPreferenceTransport();
    final conflicts = <SyncConflict>[];
    final rows = await database.cloudDirtyRows(table);
    for (var start = 0; start < rows.length; start += pushChunkSize) {
      if (table == 'user_preferences') _assertPreferenceTransport();
      final chunk = rows.sublist(
        start,
        start + pushChunkSize < rows.length
            ? start + pushChunkSize
            : rows.length,
      );
      try {
        await backend.upsert(table, chunk);
        await database.markCloudRowsClean(table, chunk);
      } on SyncRowRejected {
        // Find the bad rows; upload the rest.
        for (final row in chunk) {
          try {
            await backend.upsert(table, [row]);
            await database.markCloudRowsClean(table, [row]);
          } on SyncRowRejected catch (error) {
            conflicts.add(
              SyncConflict(
                table: table,
                key: (row['uuid'] ?? row['key'])?.toString() ?? '',
                message: error.message,
              ),
            );
          }
        }
      }
    }
    return conflicts;
  }
}
