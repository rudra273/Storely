import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/purchase_document.dart';
import 'package:storely/models/supplier.dart';
import 'package:storely/screens/purchase_history_screen.dart';
import 'package:storely/screens/supplier_payments_screen.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/purchase_api_sync_backend.dart';
import 'package:storely/services/api/server_capabilities.dart';
import 'package:storely/services/api/token_store.dart';

Map<String, dynamic> _sampleReceiptJson({
  required String uuid,
  required String supplierUuid,
  String supplierName = 'Acme Distributors',
  String invoiceNumber = 'INV-100',
  String purchaseDate = '2026-04-10',
  String subtotal = '100.00',
  String? total = '100.00',
  String? balanceDue = '100.00',
  String paymentStatus = 'unpaid',
  String? reversedAt,
  String? reversalReason,
  String returnedTotal = '0.00',
  List<Map<String, dynamic>> returns = const [],
  List<Map<String, dynamic>> payments = const [],
  String returnedQuantity = '0',
  String returnableQuantity = '10',
}) => {
  'uuid': uuid,
  'purchase_date': purchaseDate,
  'created_at': '2026-04-10T10:00:00Z',
  'origin': 'web',
  'supplier_uuid': supplierUuid,
  'supplier_name': supplierName,
  'invoice_number': invoiceNumber,
  'subtotal': subtotal,
  'total': total,
  'balance_due': balanceDue,
  'payment_status': paymentStatus,
  'reversed_at': reversedAt,
  'reversal_reason': reversalReason,
  'returned_total': returnedTotal,
  'returns': returns,
  'payments': payments,
  'items': [
    {
      'uuid': 'item-$uuid',
      'movement_uuid': 'mov-$uuid',
      'product_uuid': 'prod-1',
      'product_name': 'Basmati Rice',
      'unit_name': 'kg',
      'quantity': '10',
      'unit_cost': '10',
      'amount': '100.00',
      'returned_quantity': returnedQuantity,
      'returnable_quantity': returnableQuantity,
    },
  ],
};

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    DatabaseHelper.databaseFileName = 'e04-1-parity-test.db';
    await deleteDatabase(
      p.join(await getDatabasesPath(), DatabaseHelper.databaseFileName),
    );
  });

  tearDown(() async {
    db.isAdminMutationAllowed = null;
    await db.close();
    await deleteDatabase(
      p.join(await getDatabasesPath(), DatabaseHelper.databaseFileName),
    );
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  group('PurchaseDocument model & ServerCapabilities', () {
    test(
      'parses reversed_at, returned_total, returns[], and item return quantities',
      () {
        final doc = PurchaseDocument.fromJson(
          _sampleReceiptJson(
            uuid: 'r-1',
            supplierUuid: 'sup-1',
            balanceDue: '80.00',
            returnedTotal: '20.00',
            returnedQuantity: '2',
            returnableQuantity: '8',
            returns: [
              {
                'uuid': 'ret-1',
                'purchase_uuid': 'r-1',
                'supplier_uuid': 'sup-1',
                'supplier_name': 'Acme Distributors',
                'return_number': 'DN/2627/0001',
                'return_date': '2026-04-12',
                'reason': 'Damaged bags',
                'subtotal': '20.00',
                'tax_amount': '0.00',
                'total': '20.00',
                'payable_credit': '20.00',
                'refund_amount': '0.00',
                'refund_method': null,
                'created_at': '2026-04-12T10:00:00Z',
                'items': [
                  {
                    'uuid': 'ri-1',
                    'purchase_item_uuid': 'item-r-1',
                    'product_uuid': 'prod-1',
                    'product_name': 'Basmati Rice',
                    'unit_name': 'kg',
                    'quantity': '2',
                    'unit_cost': '10',
                    'amount': '20.00',
                    'movement_uuid': 'mov-ret-1',
                  },
                ],
              },
            ],
          ),
        );

        expect(doc.isReversed, isFalse);
        expect(doc.isNotRecorded, isFalse);
        expect(doc.hasReturnableItems, isTrue);
        expect(doc.canReverse, isTrue);
        expect(doc.canRecordPaymentTerms, isFalse);
        expect(doc.canPaySupplier, isTrue);
        expect(doc.returnedTotal, '20.00');
        expect(doc.returns, hasLength(1));
        expect(doc.returns.first.returnNumber, 'DN/2627/0001');
        expect(doc.returns.first.items.single.quantity, '2');
        expect(doc.lineItems.single.returnedQuantity, '2');
        expect(doc.lineItems.single.returnableQuantity, '8');

        final reversedDoc = PurchaseDocument.fromJson(
          _sampleReceiptJson(
            uuid: 'r-2',
            supplierUuid: 'sup-1',
            reversedAt: '2026-04-15T12:00:00Z',
            reversalReason: 'Duplicate invoice entry',
          ),
        );
        expect(reversedDoc.isReversed, isTrue);
        expect(reversedDoc.reversalReason, 'Duplicate invoice entry');
        expect(reversedDoc.canReverse, isFalse);
        expect(reversedDoc.hasReturnableItems, isFalse);
        expect(reversedDoc.canPaySupplier, isFalse);
        expect(reversedDoc.canRecordPaymentTerms, isFalse);

        final unrecordedDoc = PurchaseDocument.fromJson(
          _sampleReceiptJson(
            uuid: 'r-3',
            supplierUuid: 'sup-1',
            paymentStatus: 'not_recorded',
            total: null,
            balanceDue: null,
          ),
        );
        expect(unrecordedDoc.isNotRecorded, isTrue);
        expect(unrecordedDoc.canRecordPaymentTerms, isTrue);
      },
    );

    test('ServerCapabilities parses purchase_returns feature flag', () async {
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.test'),
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/login') {
            return http.Response(
              jsonEncode({
                'access_token': 'a',
                'refresh_token': 'r',
                'expires_in': 900,
              }),
              200,
            );
          }
          if (request.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({'id': 'u1', 'email': 'owner@test.com'}),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'contract_version': 1,
              'shop_id': 'shop-1',
              'role': 'owner',
              'features': {'purchase_returns': 1},
            }),
            200,
          );
        }),
      );
      await api.login('owner@test.com', 'pw');
      final caps = await ServerCapabilities.load(api, 'shop-1');
      expect(caps, isNotNull);
      expect(caps!.supportsPurchaseReturns, isTrue);
    });
  });

  group('PurchaseApiSyncBackend online operations', () {
    test('routes all E04.1 endpoints and forwards payment metadata', () async {
      final calls = <(String, String, Map<String, dynamic>?)>[];
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.test'),
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/login') {
            return http.Response(
              jsonEncode({
                'access_token': 'a',
                'refresh_token': 'r',
                'expires_in': 900,
              }),
              200,
            );
          }
          if (request.url.path == '/v1/me') {
            return http.Response(
              jsonEncode({'id': 'u1', 'email': 'owner@test.com'}),
              200,
            );
          }
          final body = request.body.isEmpty
              ? null
              : jsonDecode(request.body) as Map<String, dynamic>;
          calls.add((request.method, request.url.path, body));
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
      );
      await api.login('owner@test.com', 'pw');
      final backend = PurchaseApiSyncBackend(api);

      await backend.reversePurchase('s1', 'r1', reason: 'Wrong entry');
      await backend.recordPaymentTerms('s1', 'r1', {'payment_status': 'unpaid'});
      await backend.previewPurchaseTerms('s1', {'subtotal': '100.00'});
      await backend.createPurchaseReturn('s1', 'r1', {'reason': 'Damaged'});
      await backend.reverseSupplierPayment(
        's1',
        'sup1',
        'pay1',
        reason: 'Bounced cheque',
      );
      await backend.fetchSupplierStatement('s1', 'sup1');
      await backend.publishSupplierPayment('s1', 'sup1', {
        'request_key': 'k1',
        'amount': '50.00',
        'payment_date': '2026-04-12',
        'payment_method': 'upi',
        'purchase_uuid': 'r1',
        'reference': 'UTR-123',
        'notes': 'Part payment',
      });

      expect(calls.map((c) => '${c.$1} ${c.$2}').toList(), [
        'POST /v1/shops/s1/purchase-receipts/r1/reverse',
        'POST /v1/shops/s1/purchase-receipts/r1/payment-terms',
        'POST /v1/shops/s1/purchase-receipts/preview',
        'POST /v1/shops/s1/purchase-receipts/r1/returns',
        'POST /v1/shops/s1/suppliers/sup1/payments/pay1/reverse',
        'GET /v1/shops/s1/suppliers/sup1/statement',
        'POST /v1/shops/s1/suppliers/sup1/payments',
      ]);
      expect(calls.last.$3?['purchase_uuid'], 'r1');
      expect(calls.last.$3?['reference'], 'UTR-123');
      expect(calls.last.$3?['notes'], 'Part payment');
    });
  });

  group('D07 & D08 DB balance projection and queued payment metadata', () {
    test(
      'excludes reversed receipts, separates confirmed vs pending vs projected, counts unrecorded/failed, and converges on sync',
      () async {
        final supplierUuid = 'sup-d08';
        final shopId = await db.currentShopId();
        final rawDb = await db.database;
        await rawDb.insert('suppliers', {
          'uuid': supplierUuid,
          'shop_id': shopId,
          'name': 'Acme Distributors',
          'created_at': '2026-04-01T00:00:00Z',
          'updated_at': '2026-04-01T00:00:00Z',
        });

        // 1. Open receipt: 100.00 balance due
        await db.importPurchaseDocument(
          _sampleReceiptJson(
            uuid: 'r-open',
            supplierUuid: supplierUuid,
            balanceDue: '100.00',
          ),
          shopId: shopId,
        );
        // 2. Reversed receipt: must be excluded from confirmed balance
        await db.importPurchaseDocument(
          _sampleReceiptJson(
            uuid: 'r-rev',
            supplierUuid: supplierUuid,
            balanceDue: '250.00',
            reversedAt: '2026-04-11T00:00:00Z',
            reversalReason: 'Duplicate',
          ),
          shopId: shopId,
        );
        // 3. Unrecorded receipt: counted in unrecordedReceiptsCount
        await db.importPurchaseDocument(
          _sampleReceiptJson(
            uuid: 'r-unrec',
            supplierUuid: supplierUuid,
            paymentStatus: 'not_recorded',
            total: null,
            balanceDue: null,
          ),
          shopId: shopId,
        );

        // Queue a targeted payment with reference and notes (D07)
        await db.queueSupplierPayment(
          supplierUuid,
          '40.00',
          'upi',
          '2026-04-12',
          purchaseUuid: 'r-open',
          reference: 'UTR-9988',
          notes: 'First installment',
        );

        // Insert a failed payment in queue to verify failedPaymentsCount
        await rawDb.insert('supplier_payment_queue', {
          'request_key': 'failed-key-1',
          'shop_id': shopId,
          'supplier_uuid': supplierUuid,
          'payload': jsonEncode({
            'request_key': 'failed-key-1',
            'amount': '10.00',
            'payment_date': '2026-04-12',
            'payment_method': 'cash',
          }),
          'sync_state': 'error',
          'command_state': 'rejected',
          'last_error': 'Balance changed',
          'created_at': '2026-04-12T10:00:00Z',
        });

        final accounting = await db.supplierAccounting(supplierUuid);
        final summary = accounting['summary'] as SupplierBalanceSummary;
        expect(summary.confirmedBalance, '100.00');
        expect(summary.pendingPaymentsTotal, '40.00');
        expect(summary.projectedBalance, '60.00');
        expect(summary.unrecordedReceiptsCount, 1);
        expect(summary.failedPaymentsCount, 1);

        // Verify D07 stored fields in queue payload
        final queueRows = accounting['queue'] as List<Map<String, Object?>>;
        final queuedRow = queueRows.firstWhere(
          (r) => r['sync_state'] == 'pending',
        );
        final payload =
            jsonDecode(queuedRow['payload'] as String) as Map<String, dynamic>;
        expect(payload['purchase_uuid'], 'r-open');
        expect(payload['reference'], 'UTR-9988');
        expect(payload['notes'], 'First installment');

        // Simulate server confirming the payment & updated receipt arriving
        final requestKey = queuedRow['request_key'] as String;
        await db.beginSupplierPaymentAttempt(requestKey, shopId: shopId);
        await db.setSupplierPaymentSync(
          requestKey,
          shopId: shopId,
          cloudUuid: 'cloud-pay-1',
        );
        await db.importPurchaseDocument(
          _sampleReceiptJson(
            uuid: 'r-open',
            supplierUuid: supplierUuid,
            paymentStatus: 'partial',
            balanceDue: '60.00',
            payments: [
              {
                'uuid': 'cloud-pay-1',
                'payment_date': '2026-04-12',
                'amount': '40.00',
                'payment_method': 'upi',
                'reference': 'UTR-9988',
                'notes': 'First installment',
              },
            ],
          ),
          shopId: shopId,
        );

        final syncedSummary = await db.supplierBalanceSummary(supplierUuid);
        expect(syncedSummary.confirmedBalance, '60.00');
        expect(syncedSummary.pendingPaymentsTotal, '0.00');
        expect(syncedSummary.projectedBalance, '60.00');
      },
    );
  });

  group('D06, D07, D08 Widget parity tests', () {
    testWidgets(
      'PurchaseDetails shows Pay supplier, Return items, Reverse purchase, and Record payment terms appropriately',
      (tester) async {
        final supplierUuid = 'sup-ui-1';
        await tester.runAsync(() async {
          final shopId = await db.currentShopId();
          await db.importPurchaseDocument(
            _sampleReceiptJson(
              uuid: 'r-ui-open',
              supplierUuid: supplierUuid,
              supplierName: 'Open Supplier',
              invoiceNumber: 'INV-OPEN',
              balanceDue: '100.00',
            ),
            shopId: shopId,
          );
          await db.importPurchaseDocument(
            _sampleReceiptJson(
              uuid: 'r-ui-unrec',
              supplierUuid: supplierUuid,
              supplierName: 'Unrecorded Supplier',
              invoiceNumber: 'INV-UNREC',
              paymentStatus: 'not_recorded',
              total: null,
              balanceDue: null,
            ),
            shopId: shopId,
          );
        });

        await tester.pumpWidget(
          const MaterialApp(
            home: PurchaseHistoryScreen(isCloudLinkedOverride: true),
          ),
        );
        for (
          var i = 0;
          i < 20 && find.text('Open Supplier').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }

        // Open the unpaid receipt -> shows Pay supplier, Return items, Reverse purchase
        await tester.tap(find.text('Open Supplier'));
        await tester.pumpAndSettle();

        expect(find.text('Pay supplier'), findsOneWidget);
        expect(find.text('Return items'), findsOneWidget);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await tester.pumpAndSettle();
        expect(find.text('Reverse purchase'), findsOneWidget);
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();

        // Go back, finish pop animation & refresh, then open unrecorded receipt
        await tester.pageBack();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        for (
          var i = 0;
          i < 20 && find.text('Unrecorded Supplier').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await tester.tap(find.text('Unrecorded Supplier'));
        await tester.pumpAndSettle();

        expect(find.text('Record payment terms'), findsOneWidget);
        expect(find.text('Return items'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'SupplierPaymentsScreen displays D08 confirmed/pending/projected balances and D07 allocation selector',
      (tester) async {
        final supplierUuid = 'sup-ui-2';
        await tester.runAsync(() async {
          final shopId = await db.currentShopId();
          final rawDb = await db.database;
          await rawDb.insert('suppliers', {
            'uuid': supplierUuid,
            'shop_id': shopId,
            'name': 'Beta Traders',
            'created_at': '2026-04-01T00:00:00Z',
            'updated_at': '2026-04-01T00:00:00Z',
          });
          await db.importPurchaseDocument(
            _sampleReceiptJson(
              uuid: 'r-beta-1',
              supplierUuid: supplierUuid,
              supplierName: 'Beta Traders',
              invoiceNumber: 'INV-B1',
              balanceDue: '100.00',
              payments: [
                {
                  'uuid': 'pay-confirmed-1',
                  'payment_date': '2026-04-11',
                  'amount': '20.00',
                  'payment_method': 'cash',
                },
              ],
            ),
            shopId: shopId,
          );
          await db.queueSupplierPayment(
            supplierUuid,
            '30.00',
            'upi',
            '2026-04-12',
            purchaseUuid: 'r-beta-1',
            reference: 'UTR-77',
          );
        });

        await tester.pumpWidget(
          MaterialApp(
            home: SupplierPaymentsScreen(
              supplier: SupplierProfile(
                uuid: supplierUuid,
                name: 'Beta Traders',
              ),
              isCloudLinkedOverride: true,
            ),
          ),
        );
        for (
          var i = 0;
          i < 20 && find.textContaining('Confirmed balance').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }

        expect(find.text('Confirmed balance: ₹100.00'), findsOneWidget);
        expect(find.text('Pending on this device: ₹30.00'), findsOneWidget);
        expect(
          find.text('Projected balance after sync: ₹70.00'),
          findsOneWidget,
        );
        expect(find.text('Oldest unpaid bills (FIFO)'), findsOneWidget);
        expect(find.text('Reference (optional)'), findsOneWidget);
        expect(find.text('Notes (optional)'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });
}
