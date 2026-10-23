part of 'database_helper.dart';

/// One change recorded in the audit trail.
class AuditEntry {
  final String action;
  final String? details;
  final String actor;
  final DateTime at;

  const AuditEntry({
    required this.action,
    required this.details,
    required this.actor,
    required this.at,
  });

  String get label => switch (action) {
    AuditAction.cancelled => 'Cancelled',
    AuditAction.payment => 'Payment recorded',
    AuditAction.markedUnpaid => 'Marked unpaid (payments reversed)',
    AuditAction.edited => 'Customer details edited',
    AuditAction.commission => 'Commission changed',
    AuditAction.creditNote => 'Credit note issued',
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
}

/// Records a change to a bill. Runs inside the caller's transaction so the
/// entry exists exactly when the change does.
Future<void> _logBillAudit(
  DatabaseExecutor executor, {
  required String billUuid,
  required String action,
  String? details,
}) async {
  final now = _nowIso();
  final actor = DatabaseHelper.instance.auditActor?.call();
  await executor.insert('audit_log', {
    'uuid': _newUuid(),
    'shop_id': await _activeShopId(executor),
    'entity_type': 'bill',
    'entity_uuid': billUuid,
    'action': action,
    'details': details,
    'actor': actor == null || actor.trim().isEmpty ? null : actor.trim(),
    'created_at': _localIso(),
    'updated_at': now,
  });
}

mixin DatabaseAudit {
  Future<Database> get database;

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
          action: r['action'] as String,
          details: r['details'] as String?,
          actor: r['actor'] as String? ?? 'This phone',
          at: DateTime.parse(r['created_at'] as String),
        ),
    ];
  }
}
