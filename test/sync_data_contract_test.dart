import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/services/portable_preference_keys.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';

void main() {
  test('every SQLite business field has an explicit cloud/restore mapping', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final helper = DatabaseHelper.instance;
    await helper.close();
    DatabaseHelper.databaseFileName = 'sync-contract.db';
    final databasePath = await DatabaseHelper.databasePath();
    await deleteDatabase(databasePath);
    final tables = <String, dynamic>{};
    final db = await helper.database;
    final actualTables = (await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name <> 'android_metadata'",
    )).map((row) => row['name'] as String).toSet();
    expect(
      actualTables,
      {
        ...CloudSyncEngine.syncedTables,
        'cloud_sync_state',
        'purchase_documents',
      },
      reason:
          'A new persistent table needs an explicit cloud or device-only classification.',
    );
    for (final table in CloudSyncEngine.syncedTables) {
      final fields = <String, dynamic>{};
      for (final column in await db.rawQuery('PRAGMA table_info($table)')) {
        final name = column['name'] as String;
        String? wire = name;
        var kind = 'mirrored';
        var restore = 'Preserve the stored business value.';
        if (name == 'id') {
          wire = null;
          kind = 'local_identity';
          restore =
              'Allocate a new SQLite row ID; cloud UUID is the stable identity.';
        } else if (name == 'sync_dirty') {
          wire = null;
          kind = 'sync_runtime';
          restore =
              'Pulled rows start clean; never restore another device dirty state.';
        } else if ((table == 'products' &&
                {'category_id', 'supplier_id', 'unit_id'}.contains(name)) ||
            (table == 'bills' && name == 'customer_id')) {
          wire = name.replaceFirst('_id', '_uuid');
          kind = 'uuid_relationship';
          restore = 'Map UUID back to this SQLite database row ID.';
        } else if (table == 'bill_items' &&
            {'bill_id', 'product_id'}.contains(name)) {
          wire = name.replaceFirst('_id', '_uuid');
          kind = 'uuid_relationship';
          restore =
              'Resolve the already-stored UUID; allocate this device local ID.';
        } else if (table == 'stock_movements' &&
            {
              'product_id',
              'supplier_id',
              'source_document_id',
            }.contains(name)) {
          wire = name.replaceFirst('_id', '_uuid');
          kind = 'uuid_relationship';
          restore =
              'Resolve UUID; source_document_id is rebuilt for bill documents.';
        } else if (table == 'invoice_series' &&
            {'next_sequence', 'last_sequence_key'}.contains(name)) {
          kind = 'device_sequence_snapshot';
          restore =
              'Keep this device counter; register a new device letter on clean restore.';
        } else if (table == 'products' && name == 'quantity_cache') {
          kind = 'derived_snapshot';
          restore =
              'Rebuild from stock movements; do not trust another device cache.';
        } else if ((table == 'customers' &&
                {
                  'total_purchase_amount',
                  'bill_count',
                  'last_purchase_at',
                }.contains(name)) ||
            (table == 'bills' &&
                {
                  'paid_amount',
                  'balance_due',
                  'payment_status',
                  'is_paid',
                  'payment_method',
                }.contains(name))) {
          kind = 'derived_snapshot';
          restore = 'Reconcile from durable bills/payments on restore.';
        } else if (table == 'held_bills' && name == 'items_json') {
          kind = 'cart_snapshot';
          restore =
              'Preserve every line snapshot; export portable UUIDs and rebuild local product IDs.';
        }
        fields[name] = {'wire': wire, 'kind': kind, 'restore': restore};
      }
      tables[table] = {
        'fields': fields,
        'server_only': ['server_updated_at'],
      };
    }
    final documentFields = {
      'uuid': 'Stable document identity; preserve across retries and restore.',
      'shop_id': 'Scope to the active authenticated shop.',
      'payload':
          'Whole immutable header and line snapshots via purchase-receipts/native and purchase-receipts/changes; never post stock on import.',
      'origin': 'Preserve web/android origin from the document.',
      'sync_state':
          'Device runtime: pending/error/synced/local; downloaded documents start synced.',
      'last_error':
          'Device runtime: retain actionable rejection; never upload.',
      'created_at':
          'Document audit time; original phone time remains device_created_at in payload after acknowledgement.',
      'purchase_date':
          'Preserve the effective receipt date independently of sync order.',
      'deleted_at':
          'Reserved local tombstone; posted corrections require a future audited API.',
    };
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(purchase_documents)',
      )).map((column) => column['name']).toSet(),
      documentFields.keys.toSet(),
      reason:
          'Review new document fields and their whole-document restore policy.',
    );
    final result = {
      'version': 2,
      'document_tables': {
        'purchase_documents': {'fields': documentFields},
      },
      'tables': tables,
      'cart_item_fields': {
        for (final field in BillItem(
          productName: 'Contract',
          quantity: 1,
          mrp: 1,
        ).toMap(0).keys)
          field: {
            'wire': {'id', 'bill_id'}.contains(field)
                ? null
                : field == 'product_id'
                ? 'product_uuid'
                : field,
            'kind': field == 'product_id'
                ? 'uuid_relationship'
                : {'id', 'bill_id'}.contains(field)
                ? 'local_identity'
                : field == 'subtotal'
                ? 'derived_snapshot'
                : 'mirrored',
          },
      },
      'portable_preferences': (portablePreferenceKeys.toList()..sort()),
      'device_only_tables': ['cloud_sync_state'],
      'server_managed_public_tables': {
        'shop_members': 'Membership and roles via authenticated API',
        'shop_invites': 'Invitations via authenticated API',
        'shop_devices': 'Device registration and invoice letters via API',
        'invoice_counters': 'Atomic web invoice counters',
        'idempotency_keys': 'Durable web write retry keys',
        'alembic_version': 'Migration runtime state',
      },
      'device_only': [
        'cloud_sync_state',
        'app_lock_enabled',
        'printer_mac',
        'printer_name',
        'printer_paper',
        'last_backup_at',
        'cloud backend selection',
        'API refresh token',
        'premium request receipt',
      ],
      'cart_restore_policy':
          'Origin device owns resumable carts. Other devices retain read-only snapshots. Tombstones prevent resurrection.',
    };
    final file = File('docs/sync_data_contract.json');
    if (Platform.environment['STORELY_WRITE_CONTRACT'] == '1') {
      final apiFixture = File(
        '../storelyapi/tests/fixtures/sync_data_contract.json',
      );
      if (await apiFixture.parent.exists()) {
        await apiFixture.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(result)}\n',
        );
      }
      await file.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    }
    expect(
      jsonDecode(await file.readAsString()),
      result,
      reason:
          'New/changed fields require a reviewed cloud mapping; regenerate with STORELY_WRITE_CONTRACT=1.',
    );
    await helper.close();
    await deleteDatabase(databasePath);
    DatabaseHelper.databaseFileName = 'storely.db';
  });
}
