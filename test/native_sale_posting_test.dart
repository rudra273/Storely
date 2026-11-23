import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/native_sale_posting.dart';

String id(int value) =>
    '00000000-0000-4000-8000-${value.toString().padLeft(12, '0')}';
Map<String, dynamic> capture({
  double quantity = 1,
  double discount = 0,
  double? paid,
}) {
  final created = DateTime(2026, 11, 22, 12, 34, 56, 123);
  final factor = 1 - discount / 100;
  final item = BillItem(
    uuid: id(2),
    shopId: 'shop',
    billUuid: id(1),
    productUuid: id(3),
    productName: 'Tea',
    sellingPriceSnapshot: 118,
    taxableValueSnapshot: 100 * factor,
    gstSnapshot: 18 * factor,
    cgstAmountSnapshot: 9 * factor,
    sgstAmountSnapshot: 9 * factor,
    quantity: quantity,
    createdAt: created,
  );
  final subtotal = item.subtotal;
  final total = item.lineAmount;
  final amountPaid = paid ?? total;
  return {
    'version': 1,
    'device_id': 'device-001',
    'invoice':
        Bill(
            uuid: id(1),
            shopId: 'shop',
            billNumber: 'INV-ORIGINAL',
            customerName: 'Original Customer',
            subtotalAmount: subtotal,
            discountPercent: discount,
            discountAmount: double.parse((subtotal - total).toStringAsFixed(2)),
            taxableAmount: item.totalTaxableValue,
            cgstAmount: item.totalCgst,
            sgstAmount: item.totalSgst,
            totalAmount: total,
            paidAmount: amountPaid,
            balanceDue: total - amountPaid,
            isPaid: amountPaid == total,
            itemCount: 1,
            createdAt: created,
            deviceId: 'device-001',
          ).toMap()
          ..remove('id')
          ..remove('customer_id'),
    'items': [
      item.toMap(1)
        ..remove('id')
        ..remove('bill_id')
        ..remove('product_id'),
    ],
    'payments': amountPaid > 0
        ? [
            {
              'uuid': id(5),
              'shop_id': 'shop',
              'bill_uuid': id(1),
              'amount': amountPaid,
              'payment_method': 'cash',
              'payment_reference': null,
              'received_at': created.toIso8601String(),
              'deleted_at': null,
            },
          ]
        : <dynamic>[],
    'movements': [
      {
        'uuid': id(4),
        'shop_id': 'shop',
        'product_uuid': id(3),
        'quantity_delta': -quantity,
        'movement_type': 'sale',
        'source_type': 'bill',
        'source_document_type': 'bill',
        'source_document_uuid': id(1),
        'deleted_at': null,
      },
    ],
  };
}

void main() {
  test(
    'maps original IDs, date, line tax snapshots and exact money strings',
    () {
      final raw = capture();
      final body = nativeSaleRequest(jsonEncode(raw))!;
      expect(body['invoice_uuid'], id(1));
      expect(body['invoice_number'], 'INV-ORIGINAL');
      expect(body['created_at'], '2026-11-22T12:34:56.123');
      expect(body['device_id'], 'device-001');
      expect(body['total_amount'], '118.00');
      expect(body['paid_amount'], '118.00');
      expect(body['balance_due'], '0.00');
      expect(body['settlement_choice'], 'full');
      expect(body['allow_unassigned_credit'], isFalse);
      expect(body['payment_uuid'], id(5));
      expect(body['payment'], {
        'amount': '118.00',
        'method': 'cash',
        'reference': null,
      });
      expect(body['lines'], [
        {
          'line_uuid': id(2),
          'movement_uuid': id(4),
          'product_uuid': id(3),
          'name': 'Tea',
          'quantity': '1',
          'subtotal': '118.00',
          'taxable_amount': '100.00',
          'tax_amount': '18.00',
          'total_amount': '118.00',
        },
      ]);
      expect(body['cart']['items'], [
        {'product_uuid': id(3), 'quantity': '1'},
      ]);
      expect(jsonEncode(raw), jsonEncode(capture()));
    },
  );
  test(
    'fractional and discounted lines use saved taxed values, never current prices',
    () {
      final fractional = nativeSaleRequest(
        jsonEncode(capture(quantity: 0.125)),
      )!;
      expect(fractional['lines'].single['taxable_amount'], '12.50');
      expect(fractional['lines'].single['tax_amount'], '2.25');
      expect(fractional['total_amount'], '14.75');
      final discounted = nativeSaleRequest(jsonEncode(capture(discount: 10)))!;
      expect(discounted['subtotal'], '118.00');
      expect(discounted['discount_amount'], '11.80');
      expect(discounted['total_amount'], '106.20');
      expect(discounted['cart']['discount_percent'], '10');
    },
  );
  test(
    'partial/unpaid requires saved customer identity and recognized phone',
    () {
      for (final paid in [0.0, 50.0]) {
        final raw = capture(paid: paid);
        expect(nativeSaleRequest(jsonEncode(raw)), isNull);
        raw['invoice']['customer_uuid'] = id(7);
        raw['invoice']['customer_phone'] = '9876543210';
        final body = nativeSaleRequest(jsonEncode(raw))!;
        expect(body['settlement_choice'], paid == 0 ? 'unpaid' : 'partial');
        expect(body['payment_uuid'], paid == 0 ? null : id(5));
        expect(body['allow_unassigned_credit'], isFalse);
      }
    },
  );
  test('noncash reference is preserved and exact retry body is stable', () {
    final raw = capture();
    raw['invoice']['payment_method'] = 'upi';
    raw['payments'].single['payment_method'] = 'upi';
    raw['payments'].single['payment_reference'] = 'ORIGINAL-REF';
    final text = jsonEncode(raw);
    expect(nativeSaleRequest(text)!['payment']['reference'], 'ORIGINAL-REF');
    expect(
      jsonEncode(nativeSaleRequest(text)),
      jsonEncode(nativeSaleRequest(text)),
    );
  });
  final unsupported = <String, void Function(Map<String, dynamic>)>{
    'future version': (r) => r['version'] = 2,
    'custom line': (r) => r['items'].single['product_uuid'] = null,
    'missing movement': (r) => r['movements'].clear(),
    'wrong stock quantity': (r) => r['movements'].single['quantity_delta'] = -2,
    'extra movement': (r) =>
        r['movements'].add({...r['movements'].single, 'uuid': id(8)}),
    'foreign movement': (r) => r['movements'].single['shop_id'] = 'foreign',
    'wrong stock source': (r) =>
        r['movements'].single['source_document_uuid'] = id(8),
    'deleted payment': (r) => r['payments'].single['deleted_at'] = '2026-11-23',
    'different payment': (r) => r['payments'].single['amount'] = 100,
    'wrong payment method': (r) =>
        r['payments'].single['payment_method'] = 'card',
    'multiple payments': (r) =>
        r['payments'].add({...r['payments'].single, 'uuid': id(8)}),
    'reused identity': (r) => r['payments'].single['uuid'] = id(2),
    'return': (r) => r['invoice']['document_type'] = 'credit_note',
    'cancelled': (r) => r['invoice']['cancelled_at'] = '2026-11-23',
    'duplicate lineage': (r) =>
        r['invoice']['duplicated_from_bill_uuid'] = id(8),
    'commission': (r) => r['invoice']['profit_commission_percent'] = 5,
    'unit commission': (r) => r['items'].single['commission_snapshot'] = 1,
    'bad money scale': (r) => r['invoice']['total_amount'] = '118.001',
    'bad quantity scale': (r) => r['items'].single['quantity'] = 0.0001,
    'invalid identity': (r) => r['invoice']['uuid'] = 'local-invoice',
    'offset time': (r) => r['invoice']['created_at'] = '2026-11-22T12:34:56Z',
    'changed subtotal': (r) => r['invoice']['subtotal_amount'] = 120,
    'foreign item': (r) => r['items'].single['shop_id'] = 'foreign',
    'cash reference': (r) =>
        r['payments'].single['payment_reference'] = 'stale-UPI',
    'duplicate product': (r) {
      r['items'].add({...r['items'].single, 'uuid': id(8)});
      r['movements'].add({...r['movements'].single, 'uuid': id(9)});
    },
  };
  for (final entry in unsupported.entries) {
    test('leaves unsupported ${entry.key} for review', () {
      final raw = jsonDecode(jsonEncode(capture())) as Map<String, dynamic>;
      entry.value(raw);
      expect(nativeSaleRequest(jsonEncode(raw)), isNull);
    });
  }
  test('malformed capture fails closed without throwing', () {
    for (final text in ['', 'null', '[]', '{}', '{"version":1}', '{bad']) {
      expect(nativeSaleRequest(text), isNull);
    }
  });
}
