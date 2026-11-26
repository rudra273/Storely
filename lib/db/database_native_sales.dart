part of 'database_helper.dart';

const _nativeSaleScopeKey = 'native_sale_scope';
const nativeSalePostingEnabled = bool.fromEnvironment(
  'STORELY_NATIVE_SALE_POSTING',
);

const _nativeSaleTables = {
  'bills',
  'bill_items',
  'bill_payments',
  'stock_movements',
  'audit_log',
  'held_bills',
};

Future<Map<String, dynamic>?> _selectNativeSale(
  DatabaseExecutor txn,
  String shopId,
  String? owner,
  String deviceId,
  String snapshot,
) async {
  if (!nativeSalePostingEnabled || owner == null) return null;
  final scope = await txn.query(
    'cloud_sync_state',
    columns: ['value'],
    where: 'key = ? AND value = ?',
    whereArgs: [
      _nativeSaleScopeKey,
      jsonEncode([shopId, owner, deviceId, 1]),
    ],
  );
  return scope.isEmpty ? null : nativeSaleRequest(snapshot);
}

/// A durable upload reservation for an accepted checkout.
class PendingNativeSale {
  final String attemptId;
  final String billUuid;
  final String request;
  final String state;
  final String postingSnapshot;

  PendingNativeSale(Map<String, Object?> row)
    : attemptId = row['attempt_id'] as String,
      billUuid = row['bill_uuid'] as String,
      request = row['native_sale_request'] as String,
      state = row['native_sale_state'] as String,
      postingSnapshot = row['posting_snapshot'] as String;

  Map<String, dynamic> get decodedRequest =>
      Map<String, dynamic>.from(jsonDecode(request) as Map);

  String get invoiceNumber {
    try {
      return (decodedRequest['invoice_number'] ?? '').toString();
    } on Object {
      return '';
    }
  }

  String get totalAmount {
    try {
      return (decodedRequest['total_amount'] ?? '').toString();
    } on Object {
      return '';
    }
  }
}

/// Summary of local post-issue edits compared to a reserved sale's
/// `posting_snapshot`.
class NativeSaleLocalDiff {
  final List<String> changedBillFields;
  final bool cancelledLocally;
  final int addedPaymentsCount;
  final int addedCreditNotesCount;
  final bool itemsOrMovementsChanged;

  const NativeSaleLocalDiff({
    this.changedBillFields = const [],
    this.cancelledLocally = false,
    this.addedPaymentsCount = 0,
    this.addedCreditNotesCount = 0,
    this.itemsOrMovementsChanged = false,
  });

  bool get hasEdits =>
      changedBillFields.isNotEmpty ||
      cancelledLocally ||
      addedPaymentsCount > 0 ||
      addedCreditNotesCount > 0 ||
      itemsOrMovementsChanged;

  List<String> get summaryLines {
    final lines = <String>[];
    if (cancelledLocally) {
      lines.add('Invoice cancelled locally');
    }
    const customerFields = {
      'customer_uuid',
      'customer_name',
      'customer_phone',
      'customer_gstin',
      'customer_gst_legal_name',
      'customer_gst_trade_name',
      'customer_address_snapshot',
      'place_of_supply_state_code',
    };
    const cancellationFields = {
      'lifecycle_status',
      'cancelled_at',
      'cancelled_by',
      'cancellation_reason',
      'deleted_at',
    };
    const paymentFields = {
      'paid_amount',
      'balance_due',
      'payment_method',
      'payment_status',
    };
    final changedSet = changedBillFields.toSet();
    if (changedSet.any(customerFields.contains)) {
      lines.add('Customer details changed');
    }
    if (addedPaymentsCount > 0) {
      lines.add(
        '$addedPaymentsCount ${addedPaymentsCount == 1 ? 'payment' : 'payments'} added after checkout',
      );
    } else if (changedSet.any(paymentFields.contains)) {
      lines.add('Payment details changed');
    }
    if (addedCreditNotesCount > 0) {
      lines.add(
        '$addedCreditNotesCount ${addedCreditNotesCount == 1 ? 'credit note' : 'credit notes'} added after checkout',
      );
    }
    if (itemsOrMovementsChanged) {
      lines.add('Invoice items or stock movements changed');
    }
    final otherFields = changedBillFields
        .where(
          (f) =>
              f != 'updated_at' &&
              !customerFields.contains(f) &&
              !cancellationFields.contains(f) &&
              !paymentFields.contains(f),
        )
        .toList();
    if (otherFields.isNotEmpty) {
      lines.add('Invoice fields changed (${otherFields.join(', ')})');
    }
    if (hasEdits && lines.isEmpty) {
      lines.add('Local invoice record changed');
    }
    return lines;
  }
}

extension DatabaseNativeSales on DatabaseHelper {
  Future<void> clearNativeSaleScope() =>
      clearCloudSyncState(_nativeSaleScopeKey);

  Future<void> updateNativeSaleScope(
    CheckoutScope scope, {
    required bool supported,
    required bool Function() isCurrent,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      final identity = [scope.shopId, scope.owner, scope.deviceId];
      final value = jsonEncode([...identity, 1]);
      if (!supported) {
        await txn.delete(
          'cloud_sync_state',
          where: 'key = ? AND value IN (?, ?)',
          whereArgs: [_nativeSaleScopeKey, jsonEncode(identity), value],
        );
        return;
      }
      await txn.insert('cloud_sync_state', {
        'key': _nativeSaleScopeKey,
        'value': value,
        'updated_at': _nowIso(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<PendingNativeSale>> pendingNativeSales(
    CheckoutScope scope,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      return (await txn.query(
        'checkout_acceptances',
        where:
            "shop_id = ? AND owner = ? AND native_sale_state IN ('pending', 'reconcile')",
        whereArgs: [scope.shopId, scope.owner],
        orderBy: 'bill_id ASC',
      )).map(PendingNativeSale.new).toList();
    });
  }

  Future<PendingNativeSale?> pendingNativeSaleForBill(
    CheckoutScope scope,
    String billUuid,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      final rows = await txn.query(
        'checkout_acceptances',
        where:
            "shop_id = ? AND owner = ? AND bill_uuid = ? AND native_sale_state IN ('pending', 'reconcile')",
        whereArgs: [scope.shopId, scope.owner, billUuid],
        limit: 1,
      );
      return rows.isEmpty ? null : PendingNativeSale(rows.single);
    });
  }

  Future<NativeSaleLocalDiff> inspectLocalNativeSaleEdits(
    CheckoutScope scope,
    PendingNativeSale sale,
  ) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      final snapshot = jsonDecode(sale.postingSnapshot) as Map;
      final invoice = snapshot['invoice'] as Map;
      final billRows = await txn.query(
        'bills',
        where: 'shop_id = ? AND uuid = ?',
        whereArgs: [scope.shopId, invoice['uuid']],
      );
      final changedBillFields = <String>[];
      var cancelledLocally = false;
      if (billRows.isEmpty) {
        changedBillFields.add('uuid');
        cancelledLocally = true;
      } else {
        final current = billRows.single;
        for (final entry in invoice.entries) {
          if (current[entry.key] != entry.value) {
            changedBillFields.add(entry.key.toString());
          }
        }
        cancelledLocally =
            current['lifecycle_status'] == 'cancelled' ||
            current['cancelled_at'] != null ||
            current['deleted_at'] != null;
      }

      var itemsOrMovementsChanged = false;
      final snapshotItems = (snapshot['items'] as List).cast<Map>();
      final snapshotPayments = (snapshot['payments'] as List).cast<Map>();
      final snapshotMovements = (snapshot['movements'] as List).cast<Map>();

      for (final entry in <String, List<Map>>{
        'bill_items': snapshotItems,
        'bill_payments': snapshotPayments,
        'stock_movements': snapshotMovements,
      }.entries) {
        for (final effect in entry.value) {
          final rows = await txn.query(
            entry.key,
            where: 'shop_id = ? AND uuid = ?',
            whereArgs: [scope.shopId, effect['uuid']],
          );
          if (rows.isEmpty ||
              effect.entries.any(
                (field) => rows.single[field.key] != field.value,
              )) {
            itemsOrMovementsChanged = true;
            break;
          }
        }
        if (itemsOrMovementsChanged) break;
      }

      if (!itemsOrMovementsChanged) {
        final itemUuids = snapshotItems.map((row) => row['uuid']).toSet();
        final currentItems = await txn.query(
          'bill_items',
          columns: ['uuid'],
          where: 'shop_id = ? AND bill_uuid = ? AND deleted_at IS NULL',
          whereArgs: [scope.shopId, sale.billUuid],
        );
        if (currentItems.any((row) => !itemUuids.contains(row['uuid']))) {
          itemsOrMovementsChanged = true;
        }
      }

      if (!itemsOrMovementsChanged) {
        final movementUuids = snapshotMovements
            .map((row) => row['uuid'])
            .toSet();
        final currentMovements = await txn.query(
          'stock_movements',
          columns: ['uuid'],
          where:
              "shop_id = ? AND source_document_type = 'bill' AND source_document_uuid = ? AND movement_type = 'sale' AND deleted_at IS NULL",
          whereArgs: [scope.shopId, sale.billUuid],
        );
        if (currentMovements.any(
          (row) => !movementUuids.contains(row['uuid']),
        )) {
          itemsOrMovementsChanged = true;
        }
      }

      final snapshotPaymentUuids = snapshotPayments
          .map((row) => row['uuid'])
          .toSet();
      final currentPayments = await txn.query(
        'bill_payments',
        columns: ['uuid'],
        where: 'shop_id = ? AND bill_uuid = ? AND deleted_at IS NULL',
        whereArgs: [scope.shopId, sale.billUuid],
      );
      final addedPaymentsCount = currentPayments
          .where((row) => !snapshotPaymentUuids.contains(row['uuid']))
          .length;

      final creditNotes = await txn.query(
        'bills',
        columns: ['uuid'],
        where: 'shop_id = ? AND original_bill_uuid = ? AND deleted_at IS NULL',
        whereArgs: [scope.shopId, sale.billUuid],
      );

      return NativeSaleLocalDiff(
        changedBillFields: changedBillFields,
        cancelledLocally: cancelledLocally,
        addedPaymentsCount: addedPaymentsCount,
        addedCreditNotesCount: creditNotes.length,
        itemsOrMovementsChanged: itemsOrMovementsChanged,
      );
    });
  }

  /// Release a reserved native sale after the server confirmed the original
  /// invoice (either via replay/already_committed or explicit reconciliation).
  /// Clears `sync_dirty` ONLY for rows that still exactly match
  /// `posting_snapshot`, leaving any post-issue local edits dirty so they sync
  /// cleanly on top of the committed cloud invoice.
  Future<void> acknowledgeReconciledNativeSale(
    CheckoutScope scope,
    PendingNativeSale sale, {
    required bool Function() isCurrent,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      final rows = await txn.query(
        'checkout_acceptances',
        where: 'attempt_id = ? AND shop_id = ? AND owner = ? AND bill_uuid = ?',
        whereArgs: [sale.attemptId, scope.shopId, scope.owner, sale.billUuid],
      );
      if (rows.isEmpty) {
        throw StateError('The reserved sale record could not be found.');
      }
      final accepted = rows.single;
      if (accepted['native_sale_request'] != sale.request) {
        throw StateError('The reserved sale request changed.');
      }
      final state = accepted['native_sale_state'];
      if (state != 'pending' && state != 'reconcile') {
        throw StateError(
          'The reserved sale is no longer pending reconciliation.',
        );
      }

      final snapshot =
          jsonDecode(accepted['posting_snapshot'] as String) as Map;
      final effects = <String, List>{
        'bills': [snapshot['invoice']],
        'bill_items': snapshot['items'] as List,
        'bill_payments': snapshot['payments'] as List,
        'stock_movements': snapshot['movements'] as List,
      };
      final postReconcileUpdatedAt = DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 5))
          .toIso8601String();
      for (final entry in effects.entries) {
        for (final effect in entry.value.cast<Map>()) {
          final currentRows = await txn.query(
            entry.key,
            where: 'shop_id = ? AND uuid = ?',
            whereArgs: [scope.shopId, effect['uuid']],
          );
          if (currentRows.isEmpty) continue;
          final current = currentRows.single;
          final unchanged = !effect.entries.any(
            (field) => current[field.key] != field.value,
          );
          if (unchanged) {
            await txn.update(
              entry.key,
              {'sync_dirty': 0},
              where: 'shop_id = ? AND uuid = ?',
              whereArgs: [scope.shopId, effect['uuid']],
            );
          } else {
            // Preserve post-issue local edits against the cloud's commit
            // timestamp (which may be newer than an offline pre-send edit or
            // ahead by minor device clock skew) so the next sync pushes them.
            final existingStamp = current['updated_at']?.toString();
            final nextStamp = _cloudIsNewer(
              existingStamp,
              postReconcileUpdatedAt,
            )
                ? postReconcileUpdatedAt
                : existingStamp ?? postReconcileUpdatedAt;
            await txn.update(
              entry.key,
              {'sync_dirty': 1, 'updated_at': nextStamp},
              where: 'shop_id = ? AND uuid = ?',
              whereArgs: [scope.shopId, effect['uuid']],
            );
          }
        }
      }
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      await txn.update(
        'checkout_acceptances',
        {'native_sale_state': 'posted'},
        where: 'attempt_id = ?',
        whereArgs: [sale.attemptId],
      );
    });
  }

  Future<bool> hasReservedNativeSales(String shopId) async {
    final db = await database;
    return (await db.query(
      'checkout_acceptances',
      columns: ['attempt_id'],
      where: "shop_id = ? AND native_sale_state IN ('pending', 'reconcile')",
      whereArgs: [shopId],
      limit: 1,
    )).isNotEmpty;
  }

  /// Check the local invoice before sending and again before releasing the
  /// reservation. A local edit keeps the entire group out of row sync.
  Future<bool> checkNativeSale(
    CheckoutScope scope,
    PendingNativeSale sale, {
    required bool Function() isCurrent,
    bool acknowledged = false,
  }) async {
    final db = await database;
    return db.transaction((txn) async {
      await _assertCheckoutScope(txn, scope);
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      final accepted = (await txn.query(
        'checkout_acceptances',
        where: 'attempt_id = ? AND shop_id = ? AND owner = ? AND bill_uuid = ?',
        whereArgs: [sale.attemptId, scope.shopId, scope.owner, sale.billUuid],
      )).single;
      if (accepted['native_sale_request'] != sale.request) {
        throw StateError('The reserved sale request changed.');
      }
      if (accepted['native_sale_state'] != 'pending') return false;

      final snapshot =
          jsonDecode(accepted['posting_snapshot'] as String) as Map;
      final effects = <String, List>{
        'bills': [snapshot['invoice']],
        'bill_items': snapshot['items'] as List,
        'bill_payments': snapshot['payments'] as List,
        'stock_movements': snapshot['movements'] as List,
      };
      final matches = await _matchesNativeSale(txn, scope.shopId, effects);
      if (!isCurrent()) throw StateError('Account changed during sale sync.');
      if (matches && !acknowledged) return true;

      if (matches) {
        for (final entry in effects.entries) {
          for (final effect in entry.value.cast<Map>()) {
            await txn.update(
              entry.key,
              {'sync_dirty': 0},
              where: 'shop_id = ? AND uuid = ?',
              whereArgs: [scope.shopId, effect['uuid']],
            );
          }
        }
      }
      await txn.update(
        'checkout_acceptances',
        {'native_sale_state': matches ? 'posted' : 'reconcile'},
        where: 'attempt_id = ?',
        whereArgs: [sale.attemptId],
      );
      return matches;
    });
  }
}

const _derivedBillPaymentFields = {
  'paid_amount',
  'balance_due',
  'payment_status',
  'is_paid',
  'payment_method',
};

Future<bool> _matchesNativeSale(
  Transaction txn,
  String shopId,
  Map<String, List> effects,
) async {
  for (final entry in effects.entries) {
    for (final effect in entry.value.cast<Map>()) {
      final rows = await txn.query(
        entry.key,
        where: 'shop_id = ? AND uuid = ?',
        whereArgs: [shopId, effect['uuid']],
      );
      if (rows.isEmpty) return false;
      var allowDerivedPaymentShift = false;
      if (entry.key == 'bills') {
        final followUps = await txn.query(
          'native_billing_commands',
          columns: ['command_id'],
          where:
              "shop_id = ? AND bill_uuid = ? AND state = 'pending' AND command_type IN ('payment', 'credit_note')",
          whereArgs: [shopId, effect['uuid']],
          limit: 1,
        );
        allowDerivedPaymentShift = followUps.isNotEmpty;
      }
      if (effect.entries.any(
        (field) =>
            !(allowDerivedPaymentShift &&
                _derivedBillPaymentFields.contains(field.key)) &&
            rows.single[field.key] != field.value,
      )) {
        return false;
      }
    }
  }
  return true;
}

class _ReservedSaleRows {
  final bills = <Object?>{};
  final carts = <Object?>{};
  final uuids = <Object?>{};

  bool contains(String table, Map<String, Object?> row) {
    if (uuids.contains(row['uuid'])) return true;
    return switch (table) {
      'bills' =>
        bills.contains(row['uuid']) ||
            bills.contains(row['original_bill_uuid']),
      'bill_items' || 'bill_payments' => bills.contains(row['bill_uuid']),
      'stock_movements' =>
        row['source_document_type'] == 'bill' &&
            bills.contains(row['source_document_uuid']),
      'audit_log' =>
        row['entity_type'] == 'bill' && bills.contains(row['entity_uuid']),
      'held_bills' => carts.contains(row['uuid']),
      _ => false,
    };
  }
}

Future<_ReservedSaleRows> _reservedSaleRows(
  DatabaseExecutor txn,
  String table,
  String shopId,
) async {
  final reserved = _ReservedSaleRows();
  if (!_nativeSaleTables.contains(table)) return reserved;
  if (_nativeBillingCommandReservedTables.contains(table)) {
    final commandRows = await txn.query(
      'native_billing_commands',
      columns: ['reserved_uuids_json'],
      where: "shop_id = ? AND state = 'pending'",
      whereArgs: [shopId],
    );
    for (final row in commandRows) {
      final decoded = jsonDecode(row['reserved_uuids_json'] as String) as Map;
      final list = decoded[table];
      if (list is List) {
        reserved.uuids.addAll(list);
      }
    }
  }
  final rows = await txn.query(
    'checkout_acceptances',
    columns: ['bill_uuid', 'posting_snapshot'],
    where: "shop_id = ? AND native_sale_state IN ('pending', 'reconcile')",
    whereArgs: [shopId],
  );
  if (rows.isEmpty) return reserved;
  if (table == 'held_bills') {
    for (final row in rows) {
      final snapshot = jsonDecode(row['posting_snapshot'] as String) as Map;
      reserved.carts.addAll(
        snapshot['consumed_cart_uuids'] as List? ?? const [],
      );
    }
  } else {
    reserved.bills.addAll(rows.map((row) => row['bill_uuid']));
    final notes = await txn.rawQuery(
      """
      SELECT b.uuid FROM bills b
      JOIN checkout_acceptances a
        ON a.shop_id = b.shop_id AND a.bill_uuid = b.original_bill_uuid
      WHERE b.shop_id = ? AND a.native_sale_state IN ('pending', 'reconcile')
    """,
      [shopId],
    );
    reserved.bills.addAll(notes.map((row) => row['uuid']));
  }
  return reserved;
}
