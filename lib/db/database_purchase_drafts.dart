part of 'database_helper.dart';

mixin DatabasePurchaseDrafts {
  Future<Database> get database;

  Future<PurchaseComposerDraft> openPurchaseDraft() async {
    await _requirePurchaseDraftAccess();
    final db = await database;
    return db.transaction((txn) async {
      final shop = await _activeShopId(txn);
      final rows = await txn.query(
        'purchase_drafts',
        where: "shop_id = ? AND status = 'editing'",
        whereArgs: [shop],
      );
      if (rows.isNotEmpty) return _composerFromRow(rows.single);
      final today = DateTime.now().toUtc().add(
        const Duration(hours: 5, minutes: 30),
      );
      final draft = PurchaseComposerDraft(
        uuid: _newUuid(),
        shopId: shop,
        revision: 0,
        date: DateTime(today.year, today.month, today.day),
      );
      await txn.insert('purchase_drafts', {
        'uuid': draft.uuid,
        'shop_id': shop,
        'revision': 0,
        'status': 'editing',
        'payload': jsonEncode(draft.toJson()),
        'updated_at': _nowIso(),
      });
      return draft;
    });
  }

  Future<PurchaseComposerDraft> savePurchaseDraft(
    PurchaseComposerDraft draft,
  ) async {
    await _requirePurchaseDraftAccess();
    if (draft.lines.length > 200) {
      throw ArgumentError('Use up to 200 purchase rows.');
    }
    final db = await database;
    return db.transaction((txn) async {
      if (draft.shopId != await _activeShopId(txn)) {
        throw StateError('The active shop changed. Your draft is preserved.');
      }
      final changed = await txn.update(
        'purchase_drafts',
        {
          'revision': draft.revision + 1,
          'payload': jsonEncode(draft.toJson()),
          'updated_at': _nowIso(),
        },
        where:
            "uuid = ? AND shop_id = ? AND revision = ? AND status = 'editing'",
        whereArgs: [draft.uuid, draft.shopId, draft.revision],
      );
      if (changed != 1) {
        throw StateError(
          'This draft changed or was already posted. Reopen Add purchase.',
        );
      }
      return draft.copyWith(revision: draft.revision + 1);
    });
  }

  Future<void> discardPurchaseDraft(PurchaseComposerDraft draft) async {
    await _requirePurchaseDraftAccess();
    final db = await database;
    if (draft.shopId != await _activeShopId(db)) {
      throw StateError('The active shop changed.');
    }
    final changed = await db.delete(
      'purchase_drafts',
      where: "uuid = ? AND shop_id = ? AND revision = ? AND status = 'editing'",
      whereArgs: [draft.uuid, draft.shopId, draft.revision],
    );
    if (changed != 1) {
      throw StateError('This draft changed. Reopen Add purchase.');
    }
  }
}

PurchaseComposerDraft _composerFromRow(Map<String, Object?> row) =>
    PurchaseComposerDraft.fromRow(
      Map<String, dynamic>.from(row),
      Map<String, dynamic>.from(jsonDecode(row['payload'] as String) as Map),
    );

Future<void> _requirePurchaseDraftAccess() async {
  await _requireAdminMutation();
  if (!_canMutateAsAdmin()) {
    throw StateError('Purchases are available to owners and admins only.');
  }
}
