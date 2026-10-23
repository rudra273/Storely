import 'package:printing/printing.dart';

import '../db/database_helper.dart';
import '../models/bill.dart';
import '../utils/bill_pdf_generator.dart';

/// Sharing a bill as a PDF through the system share sheet (WhatsApp, email,
/// Drive, print...), using the shop's current invoice settings.
class BillShare {
  static Future<void> sharePdf(Bill bill) async {
    final db = DatabaseHelper.instance;
    final bytes = await BillPdfGenerator.generate(
      bill: bill,
      shop: await db.getShopProfile(),
      settings: await db.getBillSettings(),
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: BillPdfGenerator.filename(bill),
    );
  }
}
