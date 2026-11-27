import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/held_bill.dart';

void main() {
  final db = DatabaseHelper.instance;
  late CheckoutScope scope;
  late CheckoutCart cart;
  final raw = {
    'version': 1,
    'raw': {
      'name': ' Asha ',
      'discount': 'bad input',
      'partial': '50.000',
      'settlement': 'partial',
      'consent': true,
      'method': 'online',
      'reference': 'KEEP ref',
    },
  };
  Future<CheckoutCart> state(
    CheckoutCart expected,
    Map<String, dynamic> data,
  ) => db.writeCheckoutState(expected, data);
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await db.close();
    DatabaseHelper.databaseFileName = 'checkout-drafts.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    scope = await db.captureCheckoutScope();
    await db.saveCartDraft([
      BillItem(productName: 'First', quantity: 1, sellingPriceSnapshot: 118),
    ]);
    cart = (await db.loadCheckoutCart(scope))!;
  });
  tearDown(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  test(
    'legacy cart has no metadata and raw invalid text survives reopen exactly',
    () async {
      expect(cart.state, isEmpty);
      cart = await state(cart, raw);
      await db.close();
      final reopened = (await db.loadCheckoutCart(scope))!;
      expect(reopened.state, raw);
      expect(reopened.revision, cart.revision);
      expect(
        HeldBill.encodeItems(reopened.cart.items),
        HeldBill.encodeItems(cart.cart.items),
      );
    },
  );
  test(
    'stale metadata writer cannot overwrite a newer editor even with identical items',
    () async {
      final newer = await state(cart, raw);
      await expectLater(
        state(cart, {
          'version': 1,
          'raw': {'name': 'stale'},
        }),
        throwsStateError,
      );
      expect((await db.loadCheckoutCart(scope))!.revision, newer.revision);
      expect((await db.loadCheckoutCart(scope))!.state, raw);
      await expectLater(
        db.saveCartDraft(
          cart.cart.items,
          expectedScope: scope,
          expectedCart: cart,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'delayed writes cannot adopt changed tenant account or device',
    () async {
      await db.setCloudSyncState('preference_owner', 'different-user');
      await expectLater(state(cart, raw), throwsStateError);
      await expectLater(
        db.saveCartDraft(
          cart.cart.items,
          expectedScope: scope,
          expectedCart: cart,
        ),
        throwsStateError,
      );
      await db.setCloudSyncState('preference_owner', null);
      await db.setCloudSyncState('device_id', 'different-device');
      await expectLater(state(cart, raw), throwsStateError);
      await expectLater(db.loadCheckoutCart(scope), throwsStateError);
    },
  );
  test(
    'park and resume transfer fields with original list wire and sticky tombstones',
    () async {
      cart = await state(cart, raw);
      final bytes = HeldBill.encodeItems(cart.cart.items);
      final held = await db.parkCheckoutCart(cart, 'Asha');
      expect(await db.loadCheckoutCart(scope), isNull);
      expect(held.state, raw);
      await expectLater(state(cart, raw), throwsStateError);
      final resumed = await db.resumeCheckoutCart(scope, held.cart.id);
      expect(resumed.state, raw);
      expect(HeldBill.encodeItems(resumed.cart.items), bytes);
      expect(resumed.cart.uuid, isNot(held.cart.uuid));
      await expectLater(
        db.resumeCheckoutCart(scope, held.cart.id),
        throwsStateError,
      );
      final sql = await db.database;
      expect(
        (await sql.query(
          'held_bills',
          where: 'uuid = ?',
          whereArgs: [cart.cart.uuid],
        )).single['deleted_at'],
        isNotNull,
      );
      expect(
        (await sql.query(
          'held_bills',
          where: 'uuid = ?',
          whereArgs: [held.cart.uuid],
        )).single['deleted_at'],
        isNotNull,
      );
    },
  );
  test('atomic swap preserves both carts and raw metadata', () async {
    final held = await db.parkCheckoutCart(await state(cart, raw), 'First');
    await db.saveCartDraft([
      BillItem(productName: 'Second', quantity: 2, sellingPriceSnapshot: 50),
    ]);
    final other = await state((await db.loadCheckoutCart(scope))!, {
      'version': 1,
      'raw': {'name': 'Second customer'},
    });
    final resumed = await db.resumeCheckoutCart(
      scope,
      held.cart.id,
      active: other,
    );
    expect(resumed.cart.items.single.productName, 'First');
    expect(resumed.state, raw);
    final parked = (await db.getHeldBills()).single;
    expect(parked.items.single.productName, 'Second');
    final second = await db.resumeCheckoutCart(
      scope,
      parked.id,
      active: resumed,
    );
    expect((second.state['raw'] as Map)['name'], 'Second customer');
  });
  test(
    'late resume failure rolls back active park and selected tombstone',
    () async {
      final held = await db.parkCheckoutCart(await state(cart, raw), 'First');
      await db.saveCartDraft([
        BillItem(productName: 'Second', quantity: 1, sellingPriceSnapshot: 50),
      ]);
      final active = (await db.loadCheckoutCart(scope))!;
      final sql = await db.database;
      await sql.execute(
        "CREATE TRIGGER fail_resume BEFORE INSERT ON held_bills WHEN NEW.kind = 'draft' BEGIN SELECT RAISE(ABORT, 'late resume failure'); END",
      );
      await expectLater(
        db.resumeCheckoutCart(scope, held.cart.id, active: active),
        throwsA(isA<DatabaseException>()),
      );
      expect((await db.loadCheckoutCart(scope))!.cart.uuid, active.cart.uuid);
      expect((await db.getHeldBills()).single.uuid, held.cart.uuid);
    },
  );
  test('failed park leaves active cart and metadata intact', () async {
    cart = await state(cart, raw);
    final sql = await db.database;
    await sql.execute(
      "CREATE TRIGGER fail_hold BEFORE INSERT ON held_bills WHEN NEW.kind = 'held' BEGIN SELECT RAISE(ABORT, 'hold failed'); END",
    );
    await expectLater(
      db.parkCheckoutCart(cart, 'First'),
      throwsA(isA<DatabaseException>()),
    );
    expect((await db.loadCheckoutCart(scope))!.state, raw);
    expect(await db.getHeldBills(), isEmpty);
  });
  test(
    'foreign origin held backup remains read only even with missing metadata',
    () async {
      final held = await db.parkCheckoutCart(cart, 'First');
      final sql = await db.database;
      await sql.update(
        'held_bills',
        {'origin_device_id': 'other-device'},
        where: 'id = ?',
        whereArgs: [held.cart.id],
      );
      expect((await db.getHeldBills()).single.readOnly, isTrue);
      await expectLater(
        db.resumeCheckoutCart(scope, held.cart.id),
        throwsStateError,
      );
    },
  );
  test(
    'frozen attempt cannot be held changed discarded or moved into another account',
    () async {
      cart = await state(cart, {
        ...raw,
        'pending': {'attempt_id': 'stable'},
      });
      await expectLater(db.parkCheckoutCart(cart, 'First'), throwsStateError);
      await expectLater(
        db.saveCartDraft(const [], expectedScope: scope, expectedCart: cart),
        throwsStateError,
      );
      await expectLater(db.bindCloudUserData('new-user'), throwsStateError);
      expect(await db.getCloudSyncState('preference_owner'), isNull);
      expect((await db.loadCheckoutCart(scope))!.state['pending'], isNotNull);
    },
  );
  test(
    'first account attachment promotes only its local metadata atomically and requires fresh settlement',
    () async {
      await state(cart, raw);
      await db.bindCloudUserData('first-user');
      final first = await db.captureCheckoutScope();
      final attached = (await db.loadCheckoutCart(first))!;
      expect((attached.state['raw'] as Map)['name'], ' Asha ');
      expect((attached.state['raw'] as Map)['settlement'], isNull);
      expect((attached.state['raw'] as Map)['consent'], isFalse);
      await db.bindCloudUserData('second-user');
      expect(
        await db.loadCheckoutCart(await db.captureCheckoutScope()),
        isNull,
      );
      await expectLater(state(attached, raw), throwsStateError);
    },
  );
  test(
    'old physical backup missing metadata table receives empty additive schema',
    () async {
      final sql = await db.database;
      await sql.execute('DROP TABLE checkout_draft_state');
      await sql.execute('PRAGMA user_version = 27');
      await db.close();
      expect((await db.loadCheckoutCart(scope))!.state, isEmpty);
      expect((await db.database).getVersion(), completion(29));
    },
  );
  test(
    'malformed metadata fails closed without overwriting the preserved payload',
    () async {
      cart = await state(cart, raw);
      final sql = await db.database;
      await sql.update('checkout_draft_state', {
        'payload': jsonEncode({'version': 99}),
      });
      await expectLater(db.loadCheckoutCart(scope), throwsFormatException);
      expect(
        jsonDecode(
          (await sql.query('checkout_draft_state')).single['payload'] as String,
        )['version'],
        99,
      );
    },
  );
  test('item ABA cannot revive stale editor revision', () async {
    cart = await state(cart, raw);
    final original = cart;
    final changed = await db.saveCartDraft(
      [BillItem(productName: 'Changed', quantity: 1, sellingPriceSnapshot: 20)],
      expectedScope: scope,
      expectedCart: cart,
    );
    final back = await db.saveCartDraft(
      original.cart.items,
      expectedScope: scope,
      expectedCart: changed,
    );
    expect(back!.revision, greaterThan(original.revision));
    await expectLater(state(original, raw), throwsStateError);
  });
  test(
    'another owner draft on same device is not included in scoped return query',
    () async {
      final sql = await db.database;
      await sql.insert('held_bills', {
        'uuid': 'foreign-account-cart',
        'shop_id': scope.shopId,
        'owner_user_id': 'other-user',
        'origin_device_id': scope.deviceId,
        'kind': 'draft',
        'label': 'Other',
        'items_json': HeldBill.encodeItems(cart.cart.items),
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      final updated = await db.saveCartDraft(
        [
          BillItem(
            productName: 'Edited own',
            quantity: 1,
            sellingPriceSnapshot: 25,
          ),
        ],
        expectedScope: scope,
        expectedCart: cart,
      );
      expect(updated!.cart.items.single.productName, 'Edited own');
    },
  );
  test(
    'delayed state writer cannot recreate consumed draft after explicit discard',
    () async {
      cart = await state(cart, raw);
      await db.saveCartDraft(
        const [],
        expectedScope: scope,
        expectedCart: cart,
      );
      await expectLater(state(cart, raw), throwsStateError);
      expect(await db.loadCheckoutCart(scope), isNull);
      expect(await (await db.database).query('checkout_draft_state'), isEmpty);
    },
  );
}
