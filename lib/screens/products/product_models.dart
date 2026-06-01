part of '../products_screen.dart';

enum _ProductSortMode {
  lastAdded('Last Added'),
  firstAdded('First Added'),
  nameAsc('A to Z'),
  nameDesc('Z to A');

  final String label;
  const _ProductSortMode(this.label);
}

/// A staged purchase line item, not yet written to the DB. Collected on the
/// New Purchase screen and committed in one pass on Confirm.
class _PurchaseDraft {
  /// Fully-built draft product (mrp = computed selling price).
  final Product product;

  /// Quantity entered: delta for a restock, initial stock for a new product.
  final double quantityAdded;

  /// Non-null => this item restocks an existing catalog product.
  final Product? restockTarget;

  const _PurchaseDraft({
    required this.product,
    required this.quantityAdded,
    this.restockTarget,
  });

  String get name => product.name;
  bool get isRestock => restockTarget != null;
}
