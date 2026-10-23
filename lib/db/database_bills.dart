part of 'database_helper.dart';

mixin DatabaseBills {
  Future<Database> get database;
  Future<void> syncCustomersFromBills(DatabaseExecutor executor);
  Future<void> _seedDefaultInvoiceSeries(DatabaseExecutor executor);
  Future<BillSettings> getBillSettings();
  Future<void> _syncProductQuantityCache(
    DatabaseExecutor executor,
    int productId,
  );

  Future<int> insertBill(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) => _insertBillTxn(txn, bill, items));
  }

  Future<int> _insertBillTxn(
    Transaction txn,
    Bill bill,
    List<BillItem> items,
  ) async {
    {
      final shopId = await _activeShopId(txn);
      final billUuid = bill.uuid.isEmpty ? _newUuid() : bill.uuid;
      final billNumber = bill.billNumber.isEmpty
          ? await _allocateBillNumber(txn, bill.createdAt, shopId: shopId)
          : _BillNumberAllocation(
              number: bill.billNumber,
              seriesUuid: bill.invoiceSeriesUuid,
            );
      final customerInfo = await _upsertCustomerForBill(txn, bill);
      final billMap = {
        ...bill.toMap(),
        'uuid': billUuid,
        'shop_id': bill.shopId.isEmpty || bill.shopId == _legacyShopId
            ? shopId
            : bill.shopId,
        'bill_number': billNumber.number,
        'invoice_series_uuid': billNumber.seriesUuid,
        'customer_id': customerInfo?.id,
        'customer_uuid': customerInfo?.uuid,
        'created_at': _localIso(bill.createdAt),
        'updated_at': _nowIso(),
      };
      final billId = await txn.insert('bills', billMap..remove('id'));
      for (final item in items) {
        final itemMap = {
          ...item.toMap(billId, billUuid: billUuid),
          'uuid': item.uuid.isEmpty ? _newUuid() : item.uuid,
          'shop_id': item.shopId.isEmpty || item.shopId == _legacyShopId
              ? shopId
              : item.shopId,
          'bill_uuid': billUuid,
          'created_at': _localIso(bill.createdAt),
          'updated_at': _nowIso(),
        };
        await txn.insert('bill_items', itemMap..remove('id'));
        await _applySaleStockMovement(
          txn,
          item: item,
          billId: billId,
          billUuid: billUuid,
          createdAt: bill.createdAt,
        );
      }
      if (bill.paidAmount > 0) {
        await txn.insert('bill_payments', {
          'uuid': _newUuid(),
          'shop_id': bill.shopId.isEmpty || bill.shopId == _legacyShopId
              ? shopId
              : bill.shopId,
          'bill_uuid': billUuid,
          'amount': bill.paidAmount.clamp(0, bill.totalAmount).toDouble(),
          'payment_method': bill.paymentMethod,
          'payment_reference': _normaliseName(bill.transactionReference),
          'received_at': _localIso(bill.createdAt),
          'created_at': bill.createdAt.toIso8601String(),
          'updated_at': _nowIso(),
        });
        await _updateBillPaymentSummary(txn, billId, billUuid);
      }
      notifyDatabaseChanged();
      return billId;
    }
  }

  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
    );
    final itemsByBillId = await _itemsByBillId(
      db,
      billMaps,
      includeDeleted: false,
    );
    final refByBillUuid = await _latestPaymentRefByBillUuid(db, billMaps);
    return [
      for (final map in billMaps)
        Bill.fromMap({
          ...map,
          'transaction_reference': refByBillUuid[map['uuid']],
        }, itemsByBillId[map['id']] ?? const []),
    ];
  }

  /// Bills dated [from]..[to] (yyyy-MM-dd, inclusive), oldest first, with
  /// their items. Cancelled bills come back too when [includeCancelled]
  /// (their items are left out).
  Future<List<Bill>> getBillsBetween(
    String from,
    String to, {
    bool includeCancelled = false,
  }) async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where:
          'shop_id = ? AND substr(created_at, 1, 10) BETWEEN ? AND ?'
          '${includeCancelled ? '' : ' AND deleted_at IS NULL'}',
      whereArgs: [await _activeShopId(db), from, to],
      orderBy: 'created_at ASC, id ASC',
    );
    final itemsByBillId = await _itemsByBillId(
      db,
      billMaps,
      includeDeleted: false,
    );
    return [
      for (final map in billMaps)
        Bill.fromMap(map, itemsByBillId[map['id']] ?? const []),
    ];
  }

  // ── Held bills and the auto-saved cart (device-local) ──

  Future<int> holdBill(String label, List<BillItem> items) async {
    final db = await database;
    final now = _localIso();
    return db.insert('held_bills', {
      'shop_id': await _activeShopId(db),
      'kind': 'held',
      'label': label,
      'items_json': HeldBill.encodeItems(items),
      'created_at': now,
      'updated_at': now,
    });
  }

  Future<List<HeldBill>> getHeldBills() async {
    final db = await database;
    final rows = await db.query(
      'held_bills',
      where: "kind = 'held' AND shop_id = ?",
      whereArgs: [await _activeShopId(db)],
      orderBy: 'created_at DESC',
    );
    return rows.map(HeldBill.fromMap).toList();
  }

  Future<void> deleteHeldBill(int id) async {
    final db = await database;
    await db.delete('held_bills', where: 'id = ?', whereArgs: [id]);
  }

  /// Saves the cart being billed so it survives the app being closed.
  /// An empty cart clears the draft.
  Future<void> saveCartDraft(List<BillItem> items) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    await db.transaction((txn) async {
      await txn.delete(
        'held_bills',
        where: "kind = 'draft' AND shop_id = ?",
        whereArgs: [shopId],
      );
      if (items.isEmpty) return;
      final now = _localIso();
      await txn.insert('held_bills', {
        'shop_id': shopId,
        'kind': 'draft',
        'label': 'Unsaved bill',
        'items_json': HeldBill.encodeItems(items),
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  Future<List<BillItem>> loadCartDraft() async {
    final db = await database;
    final rows = await db.query(
      'held_bills',
      where: "kind = 'draft' AND shop_id = ?",
      whereArgs: [await _activeShopId(db)],
      limit: 1,
    );
    return rows.isEmpty
        ? const []
        : HeldBill.decodeItems(rows.single['items_json'] as String);
  }

  // ── Credit notes (sales returns) ──

  static const creditNoteSettleRefund = 'refund';
  static const creditNoteSettleAdjust = 'adjust';

  /// Quantity still returnable per invoice line (sold minus already
  /// returned on active credit notes), keyed by the invoice line uuid.
  Future<Map<String, double>> returnableQuantities(int billId) async {
    final db = await database;
    return _returnableQuantities(db, billId);
  }

  Future<Map<String, double>> _returnableQuantities(
    DatabaseExecutor executor,
    int billId,
  ) async {
    final rows = await executor.rawQuery(
      '''
      SELECT bi.uuid AS uuid, bi.quantity AS sold,
        COALESCE((
          SELECT -SUM(cni.quantity)
          FROM bill_items cni
          JOIN bills cn ON cn.id = cni.bill_id
          WHERE cni.original_item_uuid = bi.uuid
            AND cni.deleted_at IS NULL AND cn.deleted_at IS NULL
        ), 0) AS returned
      FROM bill_items bi
      WHERE bi.bill_id = ? AND bi.deleted_at IS NULL
      ''',
      [billId],
    );
    return {
      for (final row in rows)
        row['uuid'] as String: roundMoney(
          (row['sold'] as num).toDouble() - (row['returned'] as num).toDouble(),
        ),
    };
  }

  /// Issues a credit note returning [quantities] (invoice line uuid ->
  /// quantity) of invoice [billId]. Returned stock goes back to inventory.
  /// [settlement] is [creditNoteSettleRefund] (money paid back by
  /// [refundMethod]) or [creditNoteSettleAdjust] (reduces what the customer
  /// still owes on the invoice). Returns the credit note's bill id.
  Future<int> createCreditNote({
    required int billId,
    required Map<String, double> quantities,
    required String settlement,
    String refundMethod = 'cash',
    String? reason,
    DateTime? createdAt,
  }) async {
    await _requireAdminMutation();
    final when = createdAt ?? DateTime.now();
    final db = await database;
    final settings = await getBillSettings();
    return db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [billId],
        limit: 1,
      );
      if (rows.isEmpty) throw StateError('Bill not found or cancelled');
      final original = Bill.fromMap(rows.single);
      if (original.isCreditNote) {
        throw StateError('A credit note cannot be returned');
      }
      final itemRows = await txn.query(
        'bill_items',
        where: 'bill_id = ? AND deleted_at IS NULL',
        whereArgs: [billId],
      );
      final returnable = await _returnableQuantities(txn, billId);
      final lines = <BillItem>[];
      for (final row in itemRows) {
        final item = BillItem.fromMap(row);
        final qty = quantities[item.uuid] ?? 0;
        if (qty <= 0) continue;
        if (qty > (returnable[item.uuid] ?? 0) + stockQuantityEpsilon) {
          throw ArgumentError(
            'Only ${_formatDbQuantity(returnable[item.uuid] ?? 0)} of '
            '"${item.productName}" can be returned',
          );
        }
        lines.add(
          BillItem(
            uuid: _newUuid(),
            productId: item.productId,
            productUuid: item.productUuid,
            productName: item.productName,
            hsnCodeSnapshot: item.hsnCodeSnapshot,
            hsnTypeSnapshot: item.hsnTypeSnapshot,
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
            wasDirectPrice: item.wasDirectPrice,
            quantity: -qty,
            originalItemUuid: item.uuid,
            createdAt: when,
          ),
        );
      }
      if (lines.isEmpty) throw ArgumentError('Choose at least one item');

      final totals = BillTotals.fromTaxedItems(
        lines,
        roundOff: settings.roundOffTotal,
      );
      final refund = -totals.grandTotal; // positive amount owed back
      if (settlement == creditNoteSettleAdjust &&
          refund > original.balanceDue + 0.005) {
        throw ArgumentError(
          'Adjustment is more than the ${rupees(original.balanceDue)} due on '
          'this bill. Refund instead.',
        );
      }

      final shopId = await _activeShopId(txn);
      final number = await _allocateCreditNoteNumber(txn, when, shopId);
      final creditNoteId = await _insertBillTxn(
        txn,
        Bill(
          billNumber: number,
          billType: original.billType,
          customerName: original.customerName,
          customerPhone: original.customerPhone,
          customerGstin: original.customerGstin,
          customerGstLegalName: original.customerGstLegalName,
          customerGstTradeName: original.customerGstTradeName,
          customerAddressSnapshot: original.customerAddressSnapshot,
          placeOfSupplyStateCode: original.placeOfSupplyStateCode,
          subtotalAmount: totals.subtotal,
          discountPercent: original.discountPercent,
          discountAmount: totals.discountAmount,
          taxableAmount: totals.taxableAmount,
          cgstAmount: totals.cgstAmount,
          sgstAmount: totals.sgstAmount,
          igstAmount: totals.igstAmount,
          roundOffAmount: totals.roundOffAmount,
          totalAmount: totals.grandTotal,
          itemCount: lines.length,
          isPaid: false,
          paidAmount: 0,
          documentType: Bill.documentCreditNote,
          originalBillUuid: original.uuid,
          originalBillNumber: original.billNumber,
          cancelReason: _normaliseName(reason),
          createdAt: when,
        ),
        lines,
      );
      final creditNote = (await txn.query(
        'bills',
        where: 'id = ?',
        whereArgs: [creditNoteId],
        limit: 1,
      )).single;

      // Returned goods back to stock.
      for (final line in lines) {
        if (line.productId == null || line.productUuid == null) continue;
        await _insertBillStockMovement(
          txn,
          productId: line.productId!,
          productUuid: line.productUuid!,
          movementType: StockMovementType.returnIn,
          quantityDelta: -line.quantity,
          sourceType: 'credit_note',
          sourceDocumentType: 'bill',
          sourceDocumentId: creditNoteId,
          sourceDocumentUuid: creditNote['uuid'] as String,
          createdAt: when,
        );
        await _syncProductQuantityCache(txn, line.productId!);
      }

      // Settle: refund money, or reduce what is owed on the invoice. The
      // two adjustment rows cancel out in 'collected', since no cash moves.
      if (refund > 0.005) {
        final isAdjust = settlement == creditNoteSettleAdjust;
        await _insertPayment(
          txn,
          billId: creditNoteId,
          bill: creditNote,
          amount: -refund,
          paymentMethod: isAdjust ? 'credit_note' : refundMethod,
          paymentReference: isAdjust ? original.billNumber : null,
          notes: isAdjust ? 'Adjusted against invoice' : 'Refund',
          receivedAt: when,
        );
        if (isAdjust) {
          await _insertPayment(
            txn,
            billId: billId,
            bill: rows.single,
            amount: refund,
            paymentMethod: 'credit_note',
            paymentReference: number,
            notes: 'Credit note',
            receivedAt: when,
          );
        }
      }
      await syncCustomersFromBills(txn);
      notifyDatabaseChanged();
      return creditNoteId;
    });
  }

  /// CN/{FY}/{SEQ} with this device's letter; its own per-device counter.
  Future<String> _allocateCreditNoteNumber(
    DatabaseExecutor executor,
    DateTime createdAt,
    String shopId,
  ) async {
    final deviceCode = await _deviceCodeFor(executor, shopId);
    final resetKey = InvoiceNumbering.resetKey(createdAt, 'financial_year');
    final counterKey = 'credit_note_seq:$shopId:$resetKey';
    final stored = await executor.query(
      'cloud_sync_state',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [counterKey],
      limit: 1,
    );
    var sequence = stored.isEmpty
        ? 1
        : int.tryParse(stored.single['value']?.toString() ?? '') ?? 1;
    String format(int seq) => InvoiceNumbering.format(
      template: 'CN/{FY}/{SEQ}',
      date: createdAt,
      sequence: seq,
      padding: 4,
      deviceCode: deviceCode,
    );
    var number = format(sequence);
    while (await _billNumberExists(executor, shopId, number)) {
      sequence++;
      number = format(sequence);
    }
    await executor.insert('cloud_sync_state', {
      'key': counterKey,
      'value': '${sequence + 1}',
      'updated_at': _nowIso(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return number;
  }

  /// One bill with its items (including a cancelled one), or null.
  Future<Bill?> getBillById(int id) async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (billMaps.isEmpty) return null;
    final items = await _itemsByBillId(db, billMaps, includeDeleted: true);
    final refs = await _latestPaymentRefByBillUuid(db, billMaps);
    final map = billMaps.single;
    return Bill.fromMap({
      ...map,
      'transaction_reference': refs[map['uuid']],
    }, items[map['id']] ?? const []);
  }

  /// How many bills each product appeared on in the last [days] days, for
  /// putting frequently sold items first while billing.
  Future<Map<int, int>> getProductSaleCounts({int days = 60}) async {
    final db = await database;
    final since = DateTime.now()
        .subtract(Duration(days: days))
        .toIso8601String()
        .substring(0, 10);
    final rows = await db.rawQuery(
      '''
      SELECT bi.product_id AS product_id, COUNT(DISTINCT bi.bill_id) AS n
      FROM bill_items bi
      WHERE bi.deleted_at IS NULL AND bi.product_id IS NOT NULL
        AND substr(bi.created_at, 1, 10) >= ?
      GROUP BY bi.product_id
      ''',
      [since],
    );
    return {
      for (final row in rows)
        row['product_id'] as int: (row['n'] as num).toInt(),
    };
  }

  /// Cancelled bills are soft-deleted (deleted_at is set) so they stay out of
  /// every sales/KPI/ledger aggregate, but their lifecycle record is preserved.
  /// This surfaces them for reference/audit, newest first.
  Future<List<Bill>> getCancelledBills() async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'lifecycle_status = ?',
      whereArgs: [Bill.lifecycleCancelled],
      orderBy: 'cancelled_at DESC, created_at DESC',
    );
    final itemsByBillId = await _itemsByBillId(
      db,
      billMaps,
      includeDeleted: true,
    );
    final refByBillUuid = await _latestPaymentRefByBillUuid(db, billMaps);
    return [
      for (final map in billMaps)
        Bill.fromMap({
          ...map,
          'transaction_reference': refByBillUuid[map['uuid']],
        }, itemsByBillId[map['id']] ?? const []),
    ];
  }

  /// Loads the most recent non-empty `payment_reference` for each bill in
  /// [billMaps], keyed by bill uuid. Batched (chunked IN-list) to avoid N+1
  /// queries, mirroring [_itemsByBillId].
  Future<Map<String, String>> _latestPaymentRefByBillUuid(
    DatabaseExecutor executor,
    List<Map<String, Object?>> billMaps,
  ) async {
    final uuids = [
      for (final map in billMaps)
        if ((map['uuid'] as String?)?.isNotEmpty == true) map['uuid'] as String,
    ];
    if (uuids.isEmpty) return const {};
    final result = <String, String>{};
    const chunkSize = 500;
    for (var start = 0; start < uuids.length; start += chunkSize) {
      final chunk = uuids.sublist(
        start,
        start + chunkSize > uuids.length ? uuids.length : start + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await executor.query(
        'bill_payments',
        columns: ['bill_uuid', 'payment_reference'],
        where:
            'bill_uuid IN ($placeholders) AND deleted_at IS NULL '
            "AND payment_reference IS NOT NULL AND payment_reference != ''",
        whereArgs: chunk,
        orderBy: 'received_at DESC, id DESC',
      );
      for (final row in rows) {
        final uuid = row['bill_uuid'] as String;
        // First row per bill wins (ordered newest-first), so don't overwrite.
        result.putIfAbsent(uuid, () => row['payment_reference'] as String);
      }
    }
    return result;
  }

  /// Loads the bill_items for every bill in [billMaps] in a single batched query
  /// (grouped by bill_id in memory) instead of one query per bill. Avoids the
  /// N+1 round-trips that made bill lists scale linearly with bill count.
  Future<Map<int, List<BillItem>>> _itemsByBillId(
    DatabaseExecutor executor,
    List<Map<String, Object?>> billMaps, {
    required bool includeDeleted,
  }) async {
    final billIds = [
      for (final map in billMaps)
        if (map['id'] != null) map['id'] as int,
    ];
    if (billIds.isEmpty) return const {};
    final deletedClause = includeDeleted ? '' : 'deleted_at IS NULL AND ';
    final grouped = <int, List<BillItem>>{};
    // Chunk the IN-list so we never exceed SQLite's bound-variable limit
    // (~999) on shops with very large bill counts.
    const chunkSize = 500;
    for (var start = 0; start < billIds.length; start += chunkSize) {
      final chunk = billIds.sublist(
        start,
        start + chunkSize > billIds.length ? billIds.length : start + chunkSize,
      );
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final itemMaps = await executor.query(
        'bill_items',
        where: '${deletedClause}bill_id IN ($placeholders)',
        whereArgs: chunk,
      );
      for (final m in itemMaps) {
        final billId = m['bill_id'] as int;
        (grouped[billId] ??= <BillItem>[]).add(BillItem.fromMap(m));
      }
    }
    return grouped;
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    await syncCustomersFromBills(db);
    final maps = await db.query(
      'customers',
      where: 'deleted_at IS NULL',
      orderBy: 'total_purchase_amount DESC, updated_at DESC',
    );
    return maps.map((map) => Customer.fromMap(map)).toList();
  }

  Future<void> saveCustomerProfile(Customer customer) async {
    final db = await database;
    final name = _normaliseName(customer.name) ?? 'Walk-in Customer';
    final phone = _normaliseCustomerPhone(customer.phone);
    final now = _nowIso();

    await db.transaction((txn) async {
      final shopId = await _activeShopId(txn);
      if (phone != null) {
        final duplicate = await txn.query(
          'customers',
          columns: ['id'],
          where: customer.id == null
              ? 'deleted_at IS NULL AND shop_id = ? AND phone = ?'
              : 'deleted_at IS NULL AND shop_id = ? AND phone = ? AND id != ?',
          whereArgs: customer.id == null
              ? [shopId, phone]
              : [shopId, phone, customer.id],
          limit: 1,
        );
        if (duplicate.isNotEmpty) {
          throw ArgumentError('Phone number already exists');
        }
      }

      final map =
          customer
              .copyWith(
                uuid: customer.uuid.isEmpty ? _newUuid() : customer.uuid,
                shopId:
                    customer.shopId.isEmpty || customer.shopId == _legacyShopId
                    ? shopId
                    : customer.shopId,
                name: name,
                phone: phone ?? '',
                updatedAt: DateTime.parse(now),
              )
              .toMap()
            ..remove('id');

      if (customer.id == null) {
        map['created_at'] = now;
        map['updated_at'] = now;
        await txn.insert('customers', map);
        return;
      }

      await txn.update(
        'customers',
        map,
        where: 'id = ?',
        whereArgs: [customer.id],
      );
      await syncCustomersFromBills(txn);
    });
  }

  Future<int> cancelBill(int id, {required String reason}) async {
    await _requireAdminMutation();
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        columns: ['uuid', 'customer_id', 'total_amount', 'deleted_at'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['deleted_at'] != null) return 0;
      final now = _nowIso();
      final billUuid = rows.single['uuid'] as String;
      final activeCreditNotes = await txn.query(
        'bills',
        columns: ['bill_number'],
        where: 'original_bill_uuid = ? AND deleted_at IS NULL',
        whereArgs: [billUuid],
      );
      if (activeCreditNotes.isNotEmpty) {
        throw StateError(
          'This bill has credit note '
          '${activeCreditNotes.map((r) => r['bill_number']).join(', ')}. '
          'Cancel the credit note first.',
        );
      }
      // Cancelling a credit note also undoes its adjustment on the invoice.
      final creditNoteNumber = await txn.query(
        'bills',
        columns: ['bill_number', 'original_bill_uuid'],
        where: "id = ? AND document_type = 'credit_note'",
        whereArgs: [id],
        limit: 1,
      );
      if (creditNoteNumber.isNotEmpty) {
        final originalUuid =
            creditNoteNumber.single['original_bill_uuid'] as String?;
        await txn.update(
          'bill_payments',
          {'deleted_at': now, 'updated_at': now},
          where:
              "bill_uuid = ? AND payment_method = 'credit_note' "
              'AND payment_reference = ? AND deleted_at IS NULL',
          whereArgs: [originalUuid, creditNoteNumber.single['bill_number']],
        );
        final original = await txn.query(
          'bills',
          columns: ['id'],
          where: 'uuid = ?',
          whereArgs: [originalUuid],
          limit: 1,
        );
        if (original.isNotEmpty) {
          await _updateBillPaymentSummary(
            txn,
            original.single['id'] as int,
            originalUuid!,
          );
        }
      }
      final customerId = rows.single['customer_id'] as int?;
      final totalAmount =
          (rows.single['total_amount'] as num?)?.toDouble() ?? 0;
      final itemRows = await txn.query(
        'bill_items',
        where: 'deleted_at IS NULL AND bill_id = ?',
        whereArgs: [id],
      );
      for (final row in itemRows) {
        final item = BillItem.fromMap(row);
        if (item.productId != null && item.productUuid != null) {
          await _insertBillStockMovement(
            txn,
            // Same id on every device: if two phones cancel the same bill,
            // sync keeps one stock return instead of restoring it twice.
            uuid: 'void-$billUuid-${item.uuid}',
            productId: item.productId!,
            productUuid: item.productUuid!,
            movementType: StockMovementType.voidSale,
            quantityDelta: item.quantity,
            sourceType: 'bill_void',
            sourceDocumentType: 'bill',
            sourceDocumentId: id,
            sourceDocumentUuid: billUuid,
          );
          await _syncProductQuantityCache(txn, item.productId!);
        }
      }
      await txn.update(
        'bill_items',
        {'deleted_at': now, 'updated_at': now},
        where: 'bill_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'bill_payments',
        {'deleted_at': now, 'updated_at': now},
        where: 'bill_uuid = ?',
        whereArgs: [billUuid],
      );
      final count = await txn.update(
        'bills',
        {
          'lifecycle_status': Bill.lifecycleCancelled,
          'cancelled_at': now,
          'cancel_reason': _normaliseName(reason) ?? 'Cancelled',
          'deleted_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (customerId != null) {
        await _adjustCustomerLedger(
          txn,
          customerId: customerId,
          amountDelta: -totalAmount,
          billCountDelta: -1,
        );
        await syncCustomersFromBills(txn);
      }
      notifyDatabaseChanged();
      return count;
    });
  }

  Future<int> deleteBill(int id) {
    return cancelBill(id, reason: 'Deleted');
  }

  Future<int> updateBillPaidStatus(
    int id,
    bool isPaid, {
    String? paymentMethod,
    String? paymentReference,
  }) async {
    // Marking unpaid voids every recorded payment on the bill, so it is an
    // admin-only correction like cancelling a bill.
    if (!isPaid) await _requireAdminMutation();
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        columns: ['uuid', 'shop_id', 'total_amount', 'balance_due'],
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      final bill = rows.single;
      final billUuid = bill['uuid'] as String;
      final shopId = bill['shop_id'] as String? ?? await _activeShopId(txn);
      final total = (bill['total_amount'] as num).toDouble();
      final balance = (bill['balance_due'] as num?)?.toDouble() ?? total;
      final now = _nowIso();
      if (!isPaid) {
        await txn.update(
          'bill_payments',
          {'deleted_at': now, 'updated_at': now},
          where: 'bill_uuid = ? AND deleted_at IS NULL',
          whereArgs: [billUuid],
        );
      } else if (balance > 0.005) {
        await txn.insert('bill_payments', {
          'uuid': _newUuid(),
          'shop_id': shopId,
          'bill_uuid': billUuid,
          'amount': balance,
          'payment_method': paymentMethod ?? 'cash',
          'payment_reference': _normaliseName(paymentReference),
          'received_at': _localIso(),
          'created_at': now,
          'updated_at': now,
        });
      }
      await _updateBillPaymentSummary(txn, id, billUuid);
      notifyDatabaseChanged();
      return 1;
    });
  }

  Future<int> recordBillPayment(
    int billId, {
    required double amount,
    String paymentMethod = 'cash',
    String? paymentReference,
    String? notes,
    DateTime? receivedAt,
  }) async {
    if (amount <= 0) throw ArgumentError('Payment amount must be positive');
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        columns: ['uuid', 'shop_id', 'balance_due', 'deleted_at'],
        where: 'id = ?',
        whereArgs: [billId],
        limit: 1,
      );
      if (rows.isEmpty || rows.single['deleted_at'] != null) return 0;
      final balance = (rows.single['balance_due'] as num?)?.toDouble() ?? 0;
      if (amount > balance + 0.005) {
        throw ArgumentError('Payment cannot exceed balance due');
      }
      await _insertPayment(
        txn,
        billId: billId,
        bill: rows.single,
        amount: amount,
        paymentMethod: paymentMethod,
        paymentReference: paymentReference,
        notes: notes,
        receivedAt: receivedAt,
      );
      notifyDatabaseChanged();
      return 1;
    });
  }

  /// One payment from a customer settled against their unpaid bills, oldest
  /// first, in a single transaction. Returns how many bills it touched.
  /// Throws if [amount] is more than they owe on [billIds].
  Future<int> recordCustomerPayment({
    required List<int> billIds,
    required double amount,
    String paymentMethod = 'cash',
    String? paymentReference,
    DateTime? receivedAt,
  }) async {
    if (amount <= 0) throw ArgumentError('Payment amount must be positive');
    if (billIds.isEmpty) return 0;
    final db = await database;
    return db.transaction((txn) async {
      final rows = await txn.query(
        'bills',
        columns: ['id', 'uuid', 'shop_id', 'balance_due'],
        where:
            'deleted_at IS NULL AND balance_due > 0.005 '
            'AND id IN (${List.filled(billIds.length, '?').join(',')})',
        whereArgs: billIds,
        orderBy: 'created_at ASC, id ASC',
      );
      final totalDue = rows.fold<double>(
        0,
        (sum, row) => sum + (row['balance_due'] as num).toDouble(),
      );
      if (amount > totalDue + 0.005) {
        throw ArgumentError('Payment cannot exceed the amount due');
      }
      var remaining = amount;
      var touched = 0;
      for (final row in rows) {
        if (remaining <= 0.005) break;
        final balance = (row['balance_due'] as num).toDouble();
        final part = roundMoney(remaining < balance ? remaining : balance);
        await _insertPayment(
          txn,
          billId: row['id'] as int,
          bill: row,
          amount: part,
          paymentMethod: paymentMethod,
          paymentReference: paymentReference,
          notes: 'Customer payment',
          receivedAt: receivedAt,
        );
        remaining = roundMoney(remaining - part);
        touched++;
      }
      notifyDatabaseChanged();
      return touched;
    });
  }

  Future<void> _insertPayment(
    DatabaseExecutor txn, {
    required int billId,
    required Map<String, Object?> bill,
    required double amount,
    required String paymentMethod,
    String? paymentReference,
    String? notes,
    DateTime? receivedAt,
  }) async {
    final now = _nowIso();
    final billUuid = bill['uuid'] as String;
    await txn.insert('bill_payments', {
      'uuid': _newUuid(),
      'shop_id': bill['shop_id'] as String? ?? await _activeShopId(txn),
      'bill_uuid': billUuid,
      'amount': amount,
      'payment_method': paymentMethod,
      'payment_reference': _normaliseName(paymentReference),
      'notes': _normaliseName(notes),
      'received_at': _localIso(receivedAt),
      'created_at': now,
      'updated_at': now,
    });
    await _updateBillPaymentSummary(txn, billId, billUuid);
  }

  Future<int> updateBillProfitCommissionPercent(int id, double percent) async {
    await _requireAdminMutation();
    final db = await database;
    final count = await db.update(
      'bills',
      {
        'profit_commission_percent': percent.clamp(0, 100).toDouble(),
        'updated_at': _nowIso(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyDatabaseChanged();
    return count;
  }

  /// Updates only the buyer/customer snapshot fields on a finalized bill.
  /// Amounts, items, GST, and totals are intentionally left untouched — those
  /// snapshots are immutable. GST fields are ignored for non-B2B bills.
  Future<int> updateBillCustomerDetails(
    int id, {
    required String customerName,
    String? customerPhone,
    String? customerGstin,
    String? customerGstLegalName,
    String? customerGstTradeName,
    String? customerAddressSnapshot,
    String? placeOfSupplyStateCode,
    required bool isB2b,
  }) async {
    await _requireAdminMutation();
    final db = await database;
    final values = <String, Object?>{
      'customer_name': _normaliseName(customerName) ?? 'Walk-in Customer',
      'customer_phone': _normaliseCustomerPhone(customerPhone),
      'updated_at': _nowIso(),
    };
    if (isB2b) {
      // Reuse the Bill constructor's canonical cleaning for the GST snapshot
      // fields (GSTIN upper-casing, state-code padding, whitespace collapse).
      final cleaned = Bill(
        totalAmount: 0,
        itemCount: 0,
        customerGstin: customerGstin,
        customerGstLegalName: customerGstLegalName,
        customerGstTradeName: customerGstTradeName,
        customerAddressSnapshot: customerAddressSnapshot,
        placeOfSupplyStateCode: placeOfSupplyStateCode,
      );
      values['customer_gstin'] = cleaned.customerGstin;
      values['customer_gst_legal_name'] = cleaned.customerGstLegalName;
      values['customer_gst_trade_name'] = cleaned.customerGstTradeName;
      values['customer_address_snapshot'] = cleaned.customerAddressSnapshot;
      values['place_of_supply_state_code'] = cleaned.placeOfSupplyStateCode;
    }
    final count = await db.update(
      'bills',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyDatabaseChanged();
    return count;
  }

  Future<int> getBillCount() async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) as c FROM bills WHERE deleted_at IS NULL "
      "AND document_type <> 'credit_note'",
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<double> getTodaySales() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      'SELECT COALESCE(SUM(total_amount),0) as s FROM bills WHERE deleted_at IS NULL AND created_at LIKE ?',
      ['$today%'],
    );
    return (r.first['s'] as num).toDouble();
  }

  Future<double> getTodayCollected() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      '''
      SELECT COALESCE(SUM(p.amount), 0) AS s
      FROM bill_payments p
      JOIN bills b ON b.uuid = p.bill_uuid
      WHERE p.deleted_at IS NULL
        AND b.deleted_at IS NULL
        AND p.received_at LIKE ?
      ''',
      ['$today%'],
    );
    return (r.first['s'] as num).toDouble();
  }

  Future<int> getTodayBillCount() async {
    final db = await database;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final r = await db.rawQuery(
      "SELECT COUNT(*) as c FROM bills WHERE deleted_at IS NULL "
      "AND document_type <> 'credit_note' AND created_at LIKE ?",
      ['$today%'],
    );
    return Sqflite.firstIntValue(r) ?? 0;
  }

  Future<List<Bill>> getUnpaidBills({int? limit}) async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'deleted_at IS NULL AND is_paid = ?',
      whereArgs: [0],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    final bills = <Bill>[];
    for (final map in billMaps) {
      final itemMaps = await db.query(
        'bill_items',
        where: 'deleted_at IS NULL AND bill_id = ?',
        whereArgs: [map['id']],
      );
      final items = itemMaps.map((m) => BillItem.fromMap(m)).toList();
      bills.add(Bill.fromMap(map, items));
    }
    return bills;
  }

  Future<_BillNumberAllocation> _allocateBillNumber(
    DatabaseExecutor executor,
    DateTime createdAt, {
    required String shopId,
  }) async {
    var rows = await executor.query(
      'invoice_series',
      where:
          'shop_id = ? AND deleted_at IS NULL AND is_active = 1 AND is_default = 1',
      whereArgs: [shopId],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) {
      await _seedDefaultInvoiceSeries(executor);
      rows = await executor.query(
        'invoice_series',
        where:
            'shop_id = ? AND deleted_at IS NULL AND is_active = 1 AND is_default = 1',
        whereArgs: [shopId],
        orderBy: 'id ASC',
        limit: 1,
      );
    }
    if (rows.isEmpty) {
      throw StateError('No active invoice series is configured');
    }

    final series = rows.single;
    final resetKey = InvoiceNumbering.resetKey(
      createdAt,
      series['reset_period']?.toString(),
    );
    final storedKey = series['last_sequence_key']?.toString();
    var sequence = storedKey == resetKey
        ? (series['next_sequence'] as num?)?.toInt() ?? 1
        : 1;

    final template =
        series['format_template']?.toString() ??
        InvoiceNumbering.defaultTemplate;
    final padding = (series['sequence_padding'] as num?)?.toInt() ?? 4;
    final deviceCode = await _deviceCodeFor(executor, shopId);
    String format(int seq) => InvoiceNumbering.format(
      template: template,
      date: createdAt,
      sequence: seq,
      padding: padding,
      deviceCode: deviceCode,
    );

    // A sequence reset can land on a number that already exists, e.g. a
    // pattern without date tokens on a daily reset, or a pulled bill from
    // another device. The unique (shop_id, bill_number) index covers
    // cancelled bills too, so a collision would fail the insert and roll the
    // sequence back, blocking every later bill. Skip forward to a free number.
    var number = format(sequence);
    var attempts = 0;
    while (await _billNumberExists(executor, shopId, number)) {
      if (++attempts > 100000) {
        throw StateError(
          'Could not find a free bill number. Check the bill number pattern '
          'in Bill Settings.',
        );
      }
      sequence++;
      number = format(sequence);
    }

    await executor.update(
      'invoice_series',
      // This device's own counter (its numbers carry its device letter), so
      // it is local-only: not synced and no updated_at bump.
      {'next_sequence': sequence + 1, 'last_sequence_key': resetKey},
      where: 'id = ?',
      whereArgs: [series['id']],
    );
    return _BillNumberAllocation(
      number: number,
      seriesUuid: series['uuid']?.toString(),
    );
  }

  Future<bool> _billNumberExists(
    DatabaseExecutor executor,
    String shopId,
    String billNumber,
  ) async {
    final rows = await executor.query(
      'bills',
      columns: ['id'],
      where: 'shop_id = ? AND bill_number = ?',
      whereArgs: [shopId, billNumber],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> _updateBillPaymentSummary(
    DatabaseExecutor executor,
    int billId,
    String billUuid,
  ) async {
    final billRows = await executor.query(
      'bills',
      columns: ['total_amount'],
      where: 'id = ?',
      whereArgs: [billId],
      limit: 1,
    );
    if (billRows.isEmpty) return;
    final total = (billRows.single['total_amount'] as num).toDouble();
    final paymentRows = await executor.rawQuery(
      '''
      SELECT COALESCE(SUM(amount), 0) AS paid
      FROM bill_payments
      WHERE bill_uuid = ? AND deleted_at IS NULL
      ''',
      [billUuid],
    );
    final paid = (paymentRows.single['paid'] as num?)?.toDouble() ?? 0;
    // Credit notes are negative (money owed back); compare magnitudes and
    // keep the sign, so an unrefunded credit note is never 'unpaid' dues.
    final sign = total < 0 ? -1.0 : 1.0;
    final totalAbs = total * sign;
    final paidAbs = paid * sign;
    final dueAbs = (totalAbs - paidAbs) <= 0.005 ? 0.0 : totalAbs - paidAbs;
    final due = dueAbs * sign;
    final status = paidAbs <= 0.005
        ? Bill.statusUnpaid
        : dueAbs <= 0.005
        ? Bill.statusPaid
        : Bill.statusPartial;
    await executor.update(
      'bills',
      {
        'paid_amount': paid,
        'balance_due': due,
        'payment_status': status,
        'is_paid': status == Bill.statusPaid ? 1 : 0,
        'payment_method': status == Bill.statusUnpaid
            ? 'cash'
            : await _latestPaymentMethod(executor, billUuid),
        // Derived from bill_payments (which sync on their own), so it does not
        // bump updated_at: a payment on one phone must not overwrite another
        // phone's edit or cancellation of the bill row.
      },
      where: 'id = ?',
      whereArgs: [billId],
    );
  }

  Future<String> _latestPaymentMethod(
    DatabaseExecutor executor,
    String billUuid,
  ) async {
    final rows = await executor.query(
      'bill_payments',
      columns: ['payment_method'],
      where: 'bill_uuid = ? AND deleted_at IS NULL',
      whereArgs: [billUuid],
      orderBy: 'received_at DESC, id DESC',
      limit: 1,
    );
    return rows.isEmpty ? 'cash' : rows.single['payment_method'] as String;
  }

  Future<void> _applySaleStockMovement(
    DatabaseExecutor executor, {
    required BillItem item,
    required int billId,
    required String billUuid,
    required DateTime createdAt,
  }) async {
    if (item.quantity <= 0 || item.productId == null) return;
    final productRows = await executor.query(
      'products',
      columns: ['uuid'],
      where: 'id = ?',
      whereArgs: [item.productId],
      limit: 1,
    );
    if (productRows.isEmpty) {
      throw StateError('Product "${item.productName}" no longer exists');
    }
    // Selling more than the recorded stock is allowed (the count is often
    // behind the shelf); billing warns first and stock goes negative.
    final productUuid =
        item.productUuid ?? productRows.single['uuid'] as String;
    await _insertBillStockMovement(
      executor,
      productId: item.productId!,
      productUuid: productUuid,
      movementType: StockMovementType.sale,
      quantityDelta: -item.quantity,
      sourceType: 'bill',
      sourceDocumentType: 'bill',
      sourceDocumentId: billId,
      sourceDocumentUuid: billUuid,
      createdAt: createdAt,
    );
    await _syncProductQuantityCache(executor, item.productId!);
  }

  Future<void> _insertBillStockMovement(
    DatabaseExecutor executor, {
    String? uuid,
    required int productId,
    required String productUuid,
    required String movementType,
    required double quantityDelta,
    String? sourceType,
    String? sourceDocumentType,
    int? sourceDocumentId,
    String? sourceDocumentUuid,
    DateTime? createdAt,
  }) async {
    final now = DateTime.now().toUtc();
    final shopId = await _activeShopId(executor);
    await executor.insert('stock_movements', {
      'uuid': uuid ?? _newUuid(),
      'shop_id': shopId,
      'product_id': productId,
      'product_uuid': productUuid,
      'movement_type': movementType,
      'quantity_delta': quantityDelta,
      'source_type': sourceType,
      'source_document_type': sourceDocumentType,
      'source_document_id': sourceDocumentId,
      'source_document_uuid': sourceDocumentUuid,
      'created_at': _localIso(createdAt),
      'updated_at': now.toIso8601String(),
    });
  }

  Future<_CustomerRef?> _upsertCustomerForBill(
    DatabaseExecutor executor,
    Bill bill,
  ) async {
    final phone = _normaliseCustomerPhone(bill.customerPhone);
    if (phone == null) return null;
    final name = _normaliseName(bill.customerName) ?? 'Walk-in Customer';
    return _upsertCustomerLedger(
      executor,
      name: name,
      phone: phone,
      gstin: bill.customerGstin,
      gstLegalName: bill.customerGstLegalName,
      gstTradeName: bill.customerGstTradeName,
      address: bill.customerAddressSnapshot,
      placeOfSupplyStateCode: bill.placeOfSupplyStateCode,
      amountDelta: bill.totalAmount,
      billCountDelta: 1,
      purchaseAt: bill.createdAt.toIso8601String(),
    );
  }
}

String _formatDbQuantity(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
}

class _BillNumberAllocation {
  final String number;
  final String? seriesUuid;

  const _BillNumberAllocation({required this.number, required this.seriesUuid});
}

class _CustomerRef {
  final int id;
  final String uuid;

  const _CustomerRef({required this.id, required this.uuid});
}

Future<_CustomerRef> _upsertCustomerLedger(
  DatabaseExecutor executor, {
  required String name,
  required String phone,
  String? gstin,
  String? gstLegalName,
  String? gstTradeName,
  String? address,
  String? placeOfSupplyStateCode,
  required double amountDelta,
  required int billCountDelta,
  required String purchaseAt,
}) async {
  final shopId = await _activeShopId(executor);
  final existing = await executor.query(
    'customers',
    columns: ['id', 'uuid', 'name'],
    where: 'shop_id = ? AND phone = ? AND deleted_at IS NULL',
    whereArgs: [shopId, phone],
    limit: 1,
  );
  final now = _nowIso();
  if (existing.isEmpty) {
    final uuid = _newUuid();
    final id = await executor.insert('customers', {
      'uuid': uuid,
      'shop_id': shopId,
      'name': name,
      'phone': phone,
      'gstin': gstin,
      'gst_legal_name': gstLegalName,
      'gst_trade_name': gstTradeName,
      'address': address,
      'gst_source': gstin == null ? null : 'manual',
      'gst_verified_at': gstin == null ? null : _nowIso(),
      'place_of_supply_state_code': placeOfSupplyStateCode,
      'total_purchase_amount': amountDelta,
      'bill_count': billCountDelta,
      'last_purchase_at': purchaseAt,
      'created_at': now,
      'updated_at': now,
    });
    return _CustomerRef(id: id, uuid: uuid);
  }

  final id = existing.single['id'] as int;
  final uuid = existing.single['uuid'] as String;
  final updateName = name.trim().isNotEmpty && name != 'Walk-in Customer';
  await executor.rawUpdate(
    '''
    UPDATE customers
    SET
      name = CASE WHEN ? THEN ? ELSE name END,
      gstin = COALESCE(?, gstin),
      gst_legal_name = COALESCE(?, gst_legal_name),
      gst_trade_name = COALESCE(?, gst_trade_name),
      address = COALESCE(?, address),
      gst_source = CASE WHEN ? IS NOT NULL THEN 'manual' ELSE gst_source END,
      gst_verified_at = CASE WHEN ? IS NOT NULL THEN ? ELSE gst_verified_at END,
      place_of_supply_state_code = COALESCE(?, place_of_supply_state_code),
      total_purchase_amount = MAX(total_purchase_amount + ?, 0),
      bill_count = MAX(bill_count + ?, 0),
      last_purchase_at = ?,
      updated_at = ?
    WHERE id = ?
    ''',
    [
      updateName ? 1 : 0,
      name,
      gstin,
      gstLegalName,
      gstTradeName,
      address,
      gstin,
      gstin,
      gstin == null ? null : now,
      placeOfSupplyStateCode,
      amountDelta,
      billCountDelta,
      purchaseAt,
      now,
      id,
    ],
  );
  return _CustomerRef(id: id, uuid: uuid);
}

Future<void> _adjustCustomerLedger(
  DatabaseExecutor executor, {
  required int customerId,
  required double amountDelta,
  required int billCountDelta,
}) async {
  // Customer totals are derived: no updated_at bump (see sync tracking).
  await executor.rawUpdate(
    '''
    UPDATE customers
    SET
      total_purchase_amount = MAX(total_purchase_amount + ?, 0),
      bill_count = MAX(bill_count + ?, 0)
    WHERE id = ?
    ''',
    [amountDelta, billCountDelta, customerId],
  );
}

String? _normaliseCustomerPhone(Object? value) {
  final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == null || digits.isEmpty || digits == '91') return null;
  if (digits.length == 10) return '91$digits';
  return digits;
}
