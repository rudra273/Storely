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
        'purchase_drafts',
        'supplier_payment_queue',
        'checkout_acceptances',
        'checkout_draft_state',
        'native_billing_commands',
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
    final draftFields = {
      'uuid':
          'Stable local draft and eventual native receipt UUID; never reuse after discard.',
      'shop_id':
          'Only the active shop on this device may open or change the draft.',
      'revision':
          'Optimistic local revision prevents stale editors overwriting or posting a newer draft.',
      'status':
          'editing/posted; posted marker commits with stock and prevents duplicate confirmation.',
      'payload':
          'Device-local header, product snapshots, target UUIDs and import rows. Never row-sync; full SQLite backup only.',
      'updated_at':
          'Device-local save time, independent of effective purchase date.',
    };
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(purchase_drafts)',
      )).map((c) => c['name']).toSet(),
      draftFields.keys.toSet(),
    );
    final paymentFields = {
      'request_key':
          'Stable idempotency key; preserve unchanged through retry and backup restore.',
      'shop_id':
          'Scope queued payments to the active shop; never upload after start fresh.',
      'supplier_uuid':
          'Supplier UUID submitted to the payment API after dependencies upload.',
      'payload':
          'Exact payment request via suppliers/payments; never row-sync. Full SQLite backup preserves pending requests.',
      'sync_state':
          'Local pending/synced/error/local state. Rejected requests require review and are never automatically resubmitted.',
      'command_state':
          'Local ready/sending/unknown/accepted/rejected/conflict/local lifecycle; never sent on wire.',
      'attempt_count':
          'Local durable send count; preserved through backup and retry.',
      'last_attempt_at':
          'Local last-send time; never changes the payment business date.',
      'cloud_uuid':
          'Acknowledged payment UUID; avoid double-counting when receipt feed arrives.',
      'last_error':
          'Actionable rejection or uncertain-send diagnostic retained on the originating device.',
      'created_at':
          'Local audit and deterministic upload order; never derived from business date.',
    };
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(supplier_payment_queue)',
      )).map((c) => c['name']).toSet(),
      paymentFields.keys.toSet(),
    );
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(checkout_acceptances)',
      )).map((column) => column['name']).toSet(),
      {
        'attempt_id',
        'shop_id',
        'owner',
        'request_fingerprint',
        'bill_id',
        'bill_uuid',
        'posting_snapshot',
        'native_sale_request',
        'native_sale_state',
      },
    );
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(checkout_draft_state)',
      )).map((column) => column['name']).toSet(),
      {'cart_uuid', 'shop_id', 'owner', 'device_id', 'revision', 'payload'},
    );
    expect(
      (await db.rawQuery(
        'PRAGMA table_info(native_billing_commands)',
      )).map((column) => column['name']).toSet(),
      {
        'command_id',
        'shop_id',
        'owner',
        'device_id',
        'command_type',
        'bill_uuid',
        'target_uuid',
        'request_json',
        'reserved_uuids_json',
        'state',
        'last_error',
        'created_at',
      },
    );
    final result = {
      'version': 10,
      'local_native_billing_commands': {
        'table': 'native_billing_commands',
        'policy':
            'Device-only durable queue for atomic billing follow-up commands (payments, cancellations, credit notes); never row-sync or portable restore. Reserved rows stay out of legacy row sync until acknowledged.',
        'fields': [
          'command_id',
          'shop_id',
          'owner',
          'device_id',
          'command_type',
          'bill_uuid',
          'target_uuid',
          'request_json',
          'reserved_uuids_json',
          'state',
          'last_error',
          'created_at',
        ],
      },
      'local_checkout_drafts': {
        'table': 'checkout_draft_state',
        'policy':
            'Device-only owner-scoped raw checkout and frozen local request; never row-sync. SQLite backups retain it with the exact original cart. Atomic park/swap transfers identity; acceptance or discard removes it.',
        'fields': [
          'cart_uuid',
          'shop_id',
          'owner',
          'device_id',
          'revision',
          'payload',
        ],
      },
      'local_checkout_acceptance': {
        'table': 'checkout_acceptances',
        'policy':
            'Device-only exact retry ledger, original sale effects and optional native delivery reservation; never row-sync or portable restore. Invoice, snapshot, reservation and matching origin cart tombstone commit atomically. Reserved effects stay out of legacy row sync until acknowledged.',
        'fields': [
          'attempt_id',
          'shop_id',
          'owner',
          'request_fingerprint',
          'bill_id',
          'bill_uuid',
          'posting_snapshot',
          'native_sale_request',
          'native_sale_state',
        ],
      },
      'local_payment_tables': {
        'supplier_payment_queue': {'fields': paymentFields},
      },
      'local_draft_tables': {
        'purchase_drafts': {'fields': draftFields},
      },
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
      'device_only_tables': [
        'cloud_sync_state',
        'purchase_drafts',
        'supplier_payment_queue',
        'checkout_acceptances',
        'checkout_draft_state',
        'native_billing_commands',
      ],
      'server_managed_public_tables': {
        'shop_members': 'Membership and roles via authenticated API',
        'shop_invites': 'Invitations via authenticated API',
        'shop_devices': 'Device registration and invoice letters via API',
        'invoice_counters': 'Atomic web invoice counters',
        'idempotency_keys': 'Durable web write retry keys',
        'purchase_document_items':
            'Receipt lines via purchase-receipts API; the phone stores whole document snapshots',
        'purchase_receipt_imports':
            'Server-side purchase import fingerprints; never stored on the device',
        'purchase_returns':
            'Debit notes / purchase returns via purchase-receipts returns API; receipt feed carries return snapshots',
        'purchase_return_items':
            'Purchase return line items via purchase-receipts returns API; receipt feed carries return snapshots',
        'supplier_payments':
            'Payment headers via supplier payment API; receipt feed carries allocations',
        'supplier_payment_allocations':
            'Allocated amounts via whole purchase document feed; never generic row-sync',
        'draft_handoffs':
            'Server-mediated single-consumer cross-device draft handoffs via REST API',
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
