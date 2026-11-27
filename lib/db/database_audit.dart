part of 'database_helper.dart';

/// One change recorded in the audit trail.
class AuditEntry {
  final String entityType;
  final String entityUuid;
  final String action;
  final String? details;
  final String actor;
  final DateTime at;

  const AuditEntry({
    this.entityType = 'bill',
    this.entityUuid = '',
    required this.action,
    required this.details,
    required this.actor,
    required this.at,
  });

  String get label => switch (action) {
    AuditAction.cancelled => 'Cancelled',
    AuditAction.payment => 'Payment recorded',
    AuditAction.markedUnpaid => 'Marked unpaid (payments reversed)',
    AuditAction.edited => 'Bill details edited',
    AuditAction.commission => 'Commission changed',
    AuditAction.creditNote => 'Credit note issued',
    AuditAction.created =>
      entityType == 'product' ? 'Product created' : 'Created',
    AuditAction.updated =>
      entityType == 'product' ? 'Product updated' : 'Updated',
    AuditAction.deleted =>
      entityType == 'product' ? 'Product deleted' : 'Deleted',
    AuditAction.stockAdjusted => 'Stock adjusted',
    _ => action,
  };
}

class AuditAction {
  static const cancelled = 'cancelled';
  static const payment = 'payment';
  static const markedUnpaid = 'marked_unpaid';
  static const edited = 'edited';
  static const commission = 'commission';
  static const creditNote = 'credit_note';
  static const created = 'created';
  static const updated = 'updated';
  static const deleted = 'deleted';
  static const stockAdjusted = 'stock_adjusted';
}

Future<void> _createAuditTables(DatabaseExecutor executor) async {
  await executor.execute('''
    CREATE TABLE IF NOT EXISTS audit_log(
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uuid TEXT NOT NULL UNIQUE,
      shop_id TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_uuid TEXT NOT NULL,
      action TEXT NOT NULL,
      details TEXT,
      actor TEXT,
      device_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )
  ''');
  await executor.execute('''
    CREATE INDEX IF NOT EXISTS idx_audit_log_entity
    ON audit_log(entity_uuid, created_at)
  ''');
  await executor.execute('''
    CREATE INDEX IF NOT EXISTS idx_audit_log_shop_created
    ON audit_log(shop_id, created_at)
  ''');
}

/// Records a shop audit event inside the caller's executor/transaction.
Future<void> _logAuditEvent(
  DatabaseExecutor executor, {
  required String entityType,
  required String entityUuid,
  required String action,
  String? details,
}) async {
  final now = _nowIso();
  final actor = DatabaseHelper.instance.auditActor?.call();
  await executor.insert('audit_log', {
    'uuid': _newUuid(),
    'shop_id': await _activeShopId(executor),
    'entity_type': entityType,
    'entity_uuid': entityUuid,
    'action': action,
    'details': details,
    'actor': actor == null || actor.trim().isEmpty ? null : actor.trim(),
    'created_at': _localIso(),
    'updated_at': now,
  });
}

/// Records a change to a bill. Runs inside the caller's transaction so the
/// entry exists exactly when the change does.
Future<void> _logBillAudit(
  DatabaseExecutor executor, {
  required String billUuid,
  required String action,
  String? details,
}) => _logAuditEvent(
  executor,
  entityType: 'bill',
  entityUuid: billUuid,
  action: action,
  details: details,
);

mixin DatabaseAudit {
  Future<Database> get database;

  /// Records a shop-wide audit event.
  Future<void> logAuditEvent({
    required String entityType,
    required String entityUuid,
    required String action,
    String? details,
  }) async {
    final db = await database;
    await _logAuditEvent(
      db,
      entityType: entityType,
      entityUuid: entityUuid,
      action: action,
      details: details,
    );
  }

  /// The bill's history, oldest first.
  Future<List<AuditEntry>> getBillAudit(String billUuid) async {
    final db = await database;
    final rows = await db.query(
      'audit_log',
      where: 'entity_uuid = ? AND deleted_at IS NULL',
      whereArgs: [billUuid],
      orderBy: 'created_at ASC, id ASC',
    );
    return [
      for (final r in rows)
        AuditEntry(
          entityType: r['entity_type'] as String? ?? 'bill',
          entityUuid: r['entity_uuid'] as String? ?? billUuid,
          action: r['action'] as String,
          details: r['details'] as String?,
          actor: r['actor'] as String? ?? 'This phone',
          at: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }

  /// Shop-wide audit log, newest first, with optional entity type, search
  /// query, date range, and pagination.
  Future<List<AuditEntry>> getShopAuditLog({
    String? entityType,
    String? query,
    DateTime? from,
    DateTime? to,
    int limit = 100,
    int offset = 0,
  }) async {
    final db = await database;
    final shopId = await _activeShopId(db);
    final clauses = <String>['shop_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[shopId];

    final cleanType = entityType?.trim();
    if (cleanType != null && cleanType.isNotEmpty) {
      clauses.add('entity_type = ?');
      args.add(cleanType);
    }

    final cleanQuery = query?.trim().toLowerCase();
    if (cleanQuery != null && cleanQuery.isNotEmpty) {
      final like = '%$cleanQuery%';
      clauses.add(
        "(LOWER(COALESCE(details, '')) LIKE ? OR LOWER(action) LIKE ? "
        "OR LOWER(COALESCE(actor, '')) LIKE ? OR LOWER(entity_type) LIKE ?)",
      );
      args.addAll([like, like, like, like]);
    }

    if (from != null) {
      clauses.add('substr(created_at, 1, 10) >= ?');
      args.add(_dateOnly(from));
    }
    if (to != null) {
      clauses.add('substr(created_at, 1, 10) <= ?');
      args.add(_dateOnly(to));
    }

    final rows = await db.query(
      'audit_log',
      where: clauses.join(' AND '),
      whereArgs: args,
      orderBy: 'created_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return [
      for (final r in rows)
        AuditEntry(
          entityType: r['entity_type'] as String? ?? 'bill',
          entityUuid: r['entity_uuid'] as String? ?? '',
          action: r['action'] as String,
          details: r['details'] as String?,
          actor: r['actor'] as String? ?? 'This phone',
          at: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }
}
