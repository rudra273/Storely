import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/bill.dart';
import '../models/bill_totals.dart';
import '../models/gst_states.dart';
import '../models/shop_profile.dart';

/// GSTR-1 workbook for one month, laid out like the GST offline tool's
/// sheets (b2b, b2cl, b2cs, cdnr, hsn(b2b), hsn(b2c), docs) so a CA can
/// copy it in or upload it after review.
///
/// Simplifications: no cess, no exports/SEZ, no e-commerce operator, no
/// reverse charge. Credit notes to unregistered buyers are netted into
/// b2cs (the usual treatment for small B2C returns).
class Gstr1Export {
  /// Inter-state invoices to unregistered buyers above this go in b2cl.
  static const b2clLimit = 100000.0;

  final ShopProfile shop;
  final List<Bill> bills;
  final List<Bill> cancelled;

  Gstr1Export({required this.shop, required List<Bill> bills})
    : bills = bills.where((b) => b.deletedAt == null).toList(),
      cancelled = bills.where((b) => b.deletedAt != null).toList();

  String get _shopState => gstStateCode(shop.gstin) ?? '';

  static final _date = DateFormat('dd-MMM-yyyy');

  static double _r(double v) => roundMoney(v);

  String _pos(Bill b) {
    final code =
        b.placeOfSupplyStateCode ?? gstStateCode(b.customerGstin) ?? _shopState;
    final name = gstStateNames[code];
    return name == null ? code : '$code-$name';
  }

  static bool _registered(Bill b) =>
      (b.customerGstin ?? '').trim().length == 15;

  static bool _interState(Bill b) =>
      b.igstAmount.abs() > 0.004 ||
      b.items.any((i) => i.igstAmountSnapshot.abs() > 0.004);

  /// Taxable value per GST rate on one bill (signed: credit notes negative).
  static Map<double, double> _taxableByRate(Bill b) {
    final out = <double, double>{};
    for (final item in b.items) {
      final rate = item.gstPercentSnapshot ?? 0;
      out[rate] = (out[rate] ?? 0) + item.totalTaxableValue;
    }
    return out.map((k, v) => MapEntry(k, _r(v)));
  }

  List<Bill> get _invoices => bills.where((b) => !b.isCreditNote).toList();
  List<Bill> get _creditNotes => bills.where((b) => b.isCreditNote).toList();

  List<List<Object?>> b2b() => [
    [
      'GSTIN/UIN of Recipient',
      'Receiver Name',
      'Invoice Number',
      'Invoice date',
      'Invoice Value',
      'Place Of Supply',
      'Reverse Charge',
      'Applicable % of Tax Rate',
      'Invoice Type',
      'E-Commerce GSTIN',
      'Rate',
      'Taxable Value',
      'Cess Amount',
    ],
    for (final b in _invoices.where(_registered))
      for (final e in _taxableByRate(b).entries)
        [
          b.customerGstin!.trim().toUpperCase(),
          b.customerGstLegalName ?? b.customerName,
          b.billNumber,
          _date.format(b.createdAt),
          _r(b.totalAmount),
          _pos(b),
          'N',
          '',
          'Regular B2B',
          '',
          e.key,
          e.value,
          0,
        ],
  ];

  bool _isB2cl(Bill b) =>
      !_registered(b) && _interState(b) && b.totalAmount > b2clLimit;

  List<List<Object?>> b2cl() => [
    [
      'Invoice Number',
      'Invoice date',
      'Invoice Value',
      'Place Of Supply',
      'Applicable % of Tax Rate',
      'Rate',
      'Taxable Value',
      'Cess Amount',
      'E-Commerce GSTIN',
    ],
    for (final b in _invoices.where(_isB2cl))
      for (final e in _taxableByRate(b).entries)
        [
          b.billNumber,
          _date.format(b.createdAt),
          _r(b.totalAmount),
          _pos(b),
          '',
          e.key,
          e.value,
          0,
          '',
        ],
  ];

  /// Small B2C sales summed by place of supply and rate, net of B2C returns.
  List<List<Object?>> b2cs() {
    final sums = <(String, double), double>{};
    for (final b in bills.where((b) => !_registered(b) && !_isB2cl(b))) {
      for (final e in _taxableByRate(b).entries) {
        final key = (_pos(b), e.key);
        sums[key] = (sums[key] ?? 0) + e.value;
      }
    }
    final keys = sums.keys.toList()
      ..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$2.compareTo(b.$2);
      });
    return [
      [
        'Type',
        'Place Of Supply',
        'Applicable % of Tax Rate',
        'Rate',
        'Taxable Value',
        'Cess Amount',
        'E-Commerce GSTIN',
      ],
      for (final k in keys)
        if (sums[k]!.abs() > 0.004) ['OE', k.$1, '', k.$2, _r(sums[k]!), 0, ''],
    ];
  }

  List<List<Object?>> cdnr() => [
    [
      'GSTIN/UIN of Recipient',
      'Receiver Name',
      'Note Number',
      'Note Date',
      'Note Type',
      'Place Of Supply',
      'Reverse Charge',
      'Note Supply Type',
      'Note Value',
      'Applicable % of Tax Rate',
      'Rate',
      'Taxable Value',
      'Cess Amount',
    ],
    for (final b in _creditNotes.where(_registered))
      for (final e in _taxableByRate(b).entries)
        [
          b.customerGstin!.trim().toUpperCase(),
          b.customerGstLegalName ?? b.customerName,
          b.billNumber,
          _date.format(b.createdAt),
          'C',
          _pos(b),
          'N',
          'Regular B2B',
          _r(b.totalAmount.abs()),
          '',
          e.key,
          _r(e.value.abs()),
          0,
        ],
  ];

  /// HSN summary for registered ([b2b] true) or unregistered buyers.
  List<List<Object?>> hsn({required bool b2b}) {
    final rows = <(String, String, double), List<double>>{};
    final descriptions = <String, String>{};
    for (final b in bills.where((b) => _registered(b) == b2b)) {
      for (final i in b.items) {
        final code = (i.hsnCodeSnapshot ?? '').trim();
        final uqc = uqcFor(i.unit);
        final rate = i.gstPercentSnapshot ?? 0;
        final key = (code, uqc, rate);
        final taxable = i.totalTaxableValue;
        final igst = i.totalIgst;
        final cgst = i.totalCgst;
        final sgst = i.totalSgst;
        final sums = rows.putIfAbsent(key, () => [0, 0, 0, 0, 0, 0]);
        sums[0] += i.quantity;
        sums[1] += taxable + igst + cgst + sgst;
        sums[2] += taxable;
        sums[3] += igst;
        sums[4] += cgst;
        sums[5] += sgst;
        descriptions.putIfAbsent(code, () => i.productName);
      }
    }
    final keys = rows.keys.toList()
      ..sort((a, b) {
        final c = a.$1.compareTo(b.$1);
        return c != 0 ? c : a.$3.compareTo(b.$3);
      });
    return [
      [
        'HSN',
        'Description',
        'UQC',
        'Total Quantity',
        'Total Value',
        'Rate',
        'Taxable Value',
        'Integrated Tax Amount',
        'Central Tax Amount',
        'State/UT Tax Amount',
        'Cess Amount',
      ],
      for (final k in keys)
        [
          k.$1,
          descriptions[k.$1] ?? '',
          k.$2,
          double.parse(rows[k]![0].toStringAsFixed(3)),
          _r(rows[k]![1]),
          k.$3,
          _r(rows[k]![2]),
          _r(rows[k]![3]),
          _r(rows[k]![4]),
          _r(rows[k]![5]),
          0,
        ],
    ];
  }

  /// Number ranges issued this month, per document type.
  List<List<Object?>> docs() {
    List<Object?> range(String nature, List<Bill> issued, List<Bill> voided) {
      final all = [...issued, ...voided]
        ..sort((a, b) => a.billNumber.compareTo(b.billNumber));
      return [
        nature,
        all.isEmpty ? '' : all.first.billNumber,
        all.isEmpty ? '' : all.last.billNumber,
        all.length,
        voided.length,
      ];
    }

    return [
      [
        'Nature of Document',
        'Sr. No. From',
        'Sr. No. To',
        'Total Number',
        'Cancelled',
      ],
      if (_invoices.isNotEmpty || cancelled.any((b) => !b.isCreditNote))
        range(
          'Invoices for outward supply',
          _invoices,
          cancelled.where((b) => !b.isCreditNote).toList(),
        ),
      if (_creditNotes.isNotEmpty) range('Credit Note', _creditNotes, const []),
    ];
  }

  /// Tax totals for the month, shown before exporting.
  ({double taxable, double igst, double cgst, double sgst}) totals() {
    double taxable = 0, igst = 0, cgst = 0, sgst = 0;
    for (final b in bills) {
      taxable += b.taxableAmount;
      igst += b.igstAmount;
      cgst += b.cgstAmount;
      sgst += b.sgstAmount;
    }
    return (
      taxable: _r(taxable),
      igst: _r(igst),
      cgst: _r(cgst),
      sgst: _r(sgst),
    );
  }

  Map<String, List<List<Object?>>> sheets() => {
    'b2b': b2b(),
    'b2cl': b2cl(),
    'b2cs': b2cs(),
    'cdnr': cdnr(),
    'hsn(b2b)': hsn(b2b: true),
    'hsn(b2c)': hsn(b2b: false),
    'docs': docs(),
  };

  Uint8List toXlsx() {
    final book = xl.Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    for (final entry in sheets().entries) {
      final sheet = book[entry.key];
      for (final row in entry.value) {
        sheet.appendRow([
          for (final cell in row)
            cell is num
                ? xl.DoubleCellValue(cell.toDouble())
                : xl.TextCellValue('${cell ?? ''}'),
        ]);
      }
    }
    if (defaultSheet != null) book.delete(defaultSheet);
    return Uint8List.fromList(book.encode()!);
  }

  Future<void> share(DateTime month) async {
    final dir = await getTemporaryDirectory();
    final label = DateFormat('MMM-yyyy').format(month);
    final file = File('${dir.path}/GSTR1_${shop.gstin ?? 'shop'}_$label.xlsx');
    await file.writeAsBytes(toXlsx());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'GSTR-1 $label · ${shop.name}',
      ),
    );
  }

  /// GST unit quantity code for a Storely unit name.
  static String uqcFor(String? unit) =>
      switch ((unit ?? '').trim().toLowerCase()) {
        'pcs' || 'pc' || 'nos' => 'NOS',
        'kg' => 'KGS',
        'g' || 'gm' => 'GMS',
        'ltr' || 'l' => 'LTR',
        'ml' => 'MLT',
        'mtr' || 'm' => 'MTR',
        'box' => 'BOX',
        'dozen' => 'DOZ',
        'pkt' => 'PAC',
        'sqft' => 'SQF',
        '' => 'NOS',
        _ => 'OTH',
      };
}
