part of 'database_helper.dart';

mixin DatabaseBills {
  Future<Database> get database;
  Future<void> syncCustomersFromBills(DatabaseExecutor executor);
  Future<void> _seedDefaultInvoiceSeries(DatabaseExecutor executor);
  Future<void> _syncProductQuantityCache(
    DatabaseExecutor executor,
    int productId,
  );

  Future<int> insertBill(Bill bill, List<BillItem> items) async {
    final db = await database;
    return db.transaction((txn) async {
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
          'created_at': bill.createdAt.toIso8601String(),
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
          'received_at': bill.createdAt.toIso8601String(),
          'created_at': bill.createdAt.toIso8601String(),
          'updated_at': _nowIso(),
        });
        await _updateBillPaymentSummary(txn, billId, billUuid);
      }
      notifyDatabaseChanged();
      return billId;
    });
  }

  Future<List<Bill>> getAllBills() async {
    final db = await database;
    final billMaps = await db.query(
      'bills',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at DESC',
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
      await txn.update(
        'bills',
        {
          'customer_name': name,
          'customer_phone': phone,
          'customer_gstin': customer.gstin,
          'customer_gst_legal_name': customer.gstLegalName,
          'customer_gst_trade_name': customer.gstTradeName,
          'customer_address_snapshot': customer.address,
          'place_of_supply_state_code': customer.placeOfSupplyStateCode,
          'bill_type': customer.gstin == null ? Bill.typeB2c : Bill.typeB2b,
          'updated_at': now,
        },
        where: 'deleted_at IS NULL AND customer_id = ?',
        whereArgs: [customer.id],
      );
      await syncCustomersFromBills(txn);
    });
  }

  Future<int> deleteBill(int id) async {
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
        {'deleted_at': now, 'updated_at': now},
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
      }
      notifyDatabaseChanged();
      return count;
    });
  }

  Future<int> updateBillPaidStatus(
    int id,
    bool isPaid, {
    String? paymentMethod,
  }) async {
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
          'received_at': now,
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
      final now = _nowIso();
      await txn.insert('bill_payments', {
        'uuid': _newUuid(),
        'shop_id':
            rows.single['shop_id'] as String? ?? await _activeShopId(txn),
        'bill_uuid': rows.single['uuid'] as String,
        'amount': amount,
        'payment_method': paymentMethod,
        'payment_reference': _normaliseName(paymentReference),
        'notes': _normaliseName(notes),
        'received_at': (receivedAt ?? DateTime.now()).toIso8601String(),
        'created_at': now,
        'updated_at': now,
      });
      await _updateBillPaymentSummary(
        txn,
        billId,
        rows.single['uuid'] as String,
      );
      notifyDatabaseChanged();
      return 1;
    });
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

  Future<int> getBillCount() async {
    final db = await database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as c FROM bills WHERE deleted_at IS NULL',
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
      'SELECT COUNT(*) as c FROM bills WHERE deleted_at IS NULL AND created_at LIKE ?',
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
    final resetKey = _invoiceResetKey(
      createdAt,
      series['reset_period']?.toString(),
    );
    final storedKey = series['last_sequence_key']?.toString();
    final sequence = storedKey == resetKey
        ? (series['next_sequence'] as num?)?.toInt() ?? 1
        : 1;
    final nextSequence = sequence + 1;
    final now = _nowIso();
    await executor.update(
      'invoice_series',
      {
        'next_sequence': nextSequence,
        'last_sequence_key': resetKey,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [series['id']],
    );

    final template =
        series['format_template']?.toString() ??
        'SHOP-LOCAL-{DEVICE}-{YYYY}{MM}{DD}-{SEQ}';
    final padding = (series['sequence_padding'] as num?)?.toInt() ?? 4;
    final deviceId = series['device_id']?.toString() ?? 'local';
    final number = _formatInvoiceNumber(
      template: template,
      createdAt: createdAt,
      sequence: sequence,
      padding: padding,
      deviceId: deviceId,
    );
    return _BillNumberAllocation(
      number: number,
      seriesUuid: series['uuid']?.toString(),
    );
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
    final due = (total - paid) <= 0.005 ? 0.0 : total - paid;
    final status = paid <= 0.005
        ? Bill.statusUnpaid
        : due <= 0.005
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
        'updated_at': _nowIso(),
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
      columns: ['uuid', 'name', 'quantity_cache'],
      where: 'id = ?',
      whereArgs: [item.productId],
      limit: 1,
    );
    if (productRows.isEmpty) {
      throw StateError('Product "${item.productName}" no longer exists');
    }
    final available =
        (productRows.single['quantity_cache'] as num?)?.toDouble() ?? 0;
    if (item.quantity > available) {
      final name = productRows.single['name']?.toString() ?? item.productName;
      throw StateError(
        'Only ${_formatDbQuantity(available)} available for "$name"',
      );
    }
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
      'uuid': _newUuid(),
      'shop_id': shopId,
      'product_id': productId,
      'product_uuid': productUuid,
      'movement_type': movementType,
      'quantity_delta': quantityDelta,
      'source_type': sourceType,
      'source_document_type': sourceDocumentType,
      'source_document_id': sourceDocumentId,
      'source_document_uuid': sourceDocumentUuid,
      'created_at': (createdAt ?? now).toIso8601String(),
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

String _invoiceResetKey(DateTime createdAt, String? resetPeriod) {
  final year = createdAt.year.toString().padLeft(4, '0');
  final month = createdAt.month.toString().padLeft(2, '0');
  final day = createdAt.day.toString().padLeft(2, '0');
  switch (resetPeriod) {
    case 'never':
      return 'all';
    case 'monthly':
      return '$year$month';
    case 'financial_year':
      final startYear = createdAt.month >= 4
          ? createdAt.year
          : createdAt.year - 1;
      return 'FY$startYear-${(startYear + 1).toString().substring(2)}';
    case 'daily':
    default:
      return '$year$month$day';
  }
}

String _formatInvoiceNumber({
  required String template,
  required DateTime createdAt,
  required int sequence,
  required int padding,
  required String deviceId,
}) {
  final year = createdAt.year.toString().padLeft(4, '0');
  final month = createdAt.month.toString().padLeft(2, '0');
  final day = createdAt.day.toString().padLeft(2, '0');
  return template
      .replaceAll('{DEVICE}', deviceId)
      .replaceAll('{YYYY}', year)
      .replaceAll('{YY}', year.substring(2))
      .replaceAll('{MM}', month)
      .replaceAll('{DD}', day)
      .replaceAll('{SEQ}', sequence.toString().padLeft(padding, '0'));
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
  final now = _nowIso();
  await executor.rawUpdate(
    '''
    UPDATE customers
    SET
      total_purchase_amount = MAX(total_purchase_amount + ?, 0),
      bill_count = MAX(bill_count + ?, 0),
      updated_at = ?
    WHERE id = ?
    ''',
    [amountDelta, billCountDelta, now, customerId],
  );
}

String? _normaliseCustomerPhone(Object? value) {
  final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == null || digits.isEmpty || digits == '91') return null;
  if (digits.length == 10) return '91$digits';
  return digits;
}
