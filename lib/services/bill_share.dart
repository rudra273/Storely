import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/bill_settings.dart';
import '../models/checkout_settlement.dart';
import '../models/shop_profile.dart';
import '../utils/bill_pdf_generator.dart';
import '../utils/money.dart';

/// Sharing a bill as a PDF, WhatsApp-ready PNG image, or formatted text
/// through the system share sheet, using the shop's current invoice settings.
class BillShare {
  static Future<void> sharePdf(Bill bill, {String? paperSizeOverride}) async {
    final db = DatabaseHelper.instance;
    final bytes = await BillPdfGenerator.generate(
      bill: bill,
      shop: await db.getShopProfile(),
      settings: await db.getBillSettings(),
      paperSizeOverride: paperSizeOverride,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: BillPdfGenerator.filename(bill),
    );
  }

  /// Rasterizes the generated invoice PDF to PNG and opens the system share
  /// sheet (ideal for quick WhatsApp image sharing).
  static Future<void> shareImage(Bill bill, {String? paperSizeOverride}) async {
    final db = DatabaseHelper.instance;
    final bytes = await BillPdfGenerator.generate(
      bill: bill,
      shop: await db.getShopProfile(),
      settings: await db.getBillSettings(),
      paperSizeOverride: paperSizeOverride,
    );
    final page = await Printing.raster(bytes, dpi: 200).first;
    final png = await page.toPng();
    final baseName = BillPdfGenerator.filename(
      bill,
    ).replaceAll(RegExp(r'\.pdf$'), '');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(png, name: '$baseName.png', mimeType: 'image/png'),
        ],
        title: 'Invoice ${bill.billNumber}',
      ),
    );
  }

  /// Plain-text WhatsApp summary aligned with Web `shareMessage` + E03.3 controls.
  static String buildWhatsAppMessage(Bill bill, ShopProfile? shop) {
    final displayId =
        bill.billNumber.isNotEmpty && !bill.billNumber.startsWith('SHOP-LOCAL-')
        ? bill.billNumber
        : 'Bill #${bill.id ?? ''}';
    final buffer = StringBuffer()..writeln(shop?.name ?? 'Storely');
    if (bill.isCancelled) {
      final reason = (bill.cancelReason ?? '').trim();
      buffer.writeln(
        reason.isEmpty ? 'VOID $displayId' : 'VOID $displayId ($reason)',
      );
    } else {
      buffer.writeln(displayId);
    }
    buffer
      ..writeln('Customer: ${bill.customerName}')
      ..writeln(
        'Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt)}',
      );
    if (shop?.gstin != null && shop!.gstin!.trim().isNotEmpty) {
      buffer.writeln('GSTIN: ${shop.gstin}');
    }
    if (shop?.address != null && shop!.address!.trim().isNotEmpty) {
      buffer.writeln(shop.address);
    }
    buffer
      ..writeln('')
      ..writeln('Items:');
    for (final item in bill.items) {
      final discNote = item.discountAmount > 0.005
          ? ' (Disc: ${rupees(item.discountAmount)})'
          : '';
      buffer.writeln(
        '- ${item.productName} ${item.quantityLabel} x ${item.priceLabel}: '
        '${rupees(item.subtotal)}$discNote',
      );
    }
    buffer
      ..writeln('')
      ..writeln('Subtotal: ${rupees(bill.subtotalAmount)}');
    if (bill.discountAmount > 0.005) {
      final discLabel =
          bill.discountMode == Bill.discountModeAmount && bill.discountValue > 0
          ? 'Discount (${rupees(bill.discountValue)} off)'
          : 'Discount (${bill.discountPercent.toStringAsFixed(bill.discountPercent == bill.discountPercent.roundToDouble() ? 0 : 2)}%)';
      buffer.writeln('$discLabel: -${rupees(bill.discountAmount)}');
    }
    if (bill.roundOffAmount.abs() > 0.004) {
      buffer.writeln('Round off: ${signedRupees(bill.roundOffAmount)}');
    }
    buffer.writeln('Total: ${rupees(bill.totalAmount)}');
    if (bill.isCancelled) {
      buffer.writeln('Status: Voided');
    } else {
      buffer
        ..writeln('Paid: ${rupees(bill.paidAmount)}')
        ..writeln('Balance: ${rupees(bill.balanceDue)}');
      if (bill.paidAmount > 0.005) {
        buffer.writeln('Payment: ${paymentMethodLabel(bill.paymentMethod)}');
      }
    }
    final notes = (bill.notes ?? '').trim();
    if (notes.isNotEmpty) {
      buffer.writeln('Notes: $notes');
    }
    return buffer.toString();
  }

  /// Unified share chooser (PDF / Image / WhatsApp text) with optional paper override.
  static Future<void> showShareSheet(
    BuildContext context,
    Bill bill, {
    VoidCallback? onWhatsApp,
  }) async {
    final settings = await DatabaseHelper.instance.getBillSettings();
    if (!context.mounted) return;
    String paper = settings.paperSize;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Share ${bill.billNumber.isNotEmpty ? bill.billNumber : 'invoice'}',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: BillSettings.paperA4, label: Text('A4')),
                    ButtonSegment(value: BillSettings.paperA5, label: Text('A5')),
                    ButtonSegment(
                      value: BillSettings.paper80mm,
                      label: Text('80mm'),
                    ),
                    ButtonSegment(
                      value: BillSettings.paper58mm,
                      label: Text('58mm'),
                    ),
                  ],
                  selected: {paper},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) =>
                      setSheetState(() => paper = v.first),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.picture_as_pdf_outlined),
                  title: const Text('Share as PDF'),
                  subtitle: Text('Paper: ${paper.toUpperCase()}'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    sharePdf(bill, paperSizeOverride: paper);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: const Text('Share as image (WhatsApp-ready)'),
                  subtitle: Text('PNG · ${paper.toUpperCase()}'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    shareImage(bill, paperSizeOverride: paper);
                  },
                ),
                if (onWhatsApp != null)
                  ListTile(
                    leading: const Icon(Icons.chat_outlined),
                    title: const Text('Send WhatsApp text summary'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      onWhatsApp();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
