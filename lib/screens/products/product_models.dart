part of '../products_screen.dart';

enum _ProductSortMode {
  lastAdded('Last Added'),
  firstAdded('First Added'),
  nameAsc('A to Z'),
  nameDesc('Z to A');

  final String label;
  const _ProductSortMode(this.label);
}

typedef _PurchaseDraft = PurchaseDraftLine;
