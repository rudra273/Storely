import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../utils/csv_importer.dart';
import 'product.dart';
import 'purchase_document.dart';

/// Local duplicate assistance. This namespace is intentionally distinct from
/// the server's import fingerprint until both platforms share a canonical parser.
String purchaseImportFingerprint(ImportParseResult parsed) {
  String optionalNumber(double? value) {
    if (value == null) return '';
    try {
      return purchaseDecimal(value);
    } catch (_) {
      return '#invalid:$value';
    }
  }

  String text(String? value) => value?.trim() ?? '';
  final signatures = <String>[];
  for (final p in parsed.products) {
    signatures.add(
      jsonEncode([
        text(p.productCode).toLowerCase(),
        text(p.barcode).toLowerCase(),
        text(p.name).toLowerCase(),
        text(p.category).toLowerCase(),
        text(p.unit).toLowerCase(),
        text(p.hsnCode),
        optionalNumber(p.gstPercent),
        optionalNumber(p.manualPrice),
        optionalNumber(p.quantity),
        optionalNumber(p.purchasePrice),
        optionalNumber(p.reorderLevel),
        optionalNumber(p.printedMrp),
        text(p.purchaseBatchNo),
        p.purchaseExpiry?.toIso8601String().substring(0, 10) ?? '',
      ]),
    );
  }
  signatures.sort();
  final errors = parsed.errors.map((e) => e.message).toList()..sort();
  return sha256
      .convert(utf8.encode(jsonEncode({'rows': signatures, 'errors': errors})))
      .toString();
}

/// Explicit selection for each valid imported row.
class PurchaseImportChoice {
  final int number;
  final Product product;
  final Product? existing;
  final String? newProductKey;
  const PurchaseImportChoice({
    required this.number,
    required this.product,
    this.existing,
    this.newProductKey,
  });
}

class ReviewedPurchaseImport {
  final String fingerprint;
  final List<PurchaseImportChoice> rows;
  final bool duplicateApproved;
  const ReviewedPurchaseImport({
    required this.fingerprint,
    required this.rows,
    required this.duplicateApproved,
  });
}
