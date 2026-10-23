import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:pdf/widgets.dart' as pw;

/// Fonts for Storely PDFs: Noto Sans (Latin + ₹) with a Noto Sans
/// Devanagari fallback so Hindi/Marathi names render.
Future<pw.ThemeData> storelyPdfTheme() async {
  WidgetsFlutterBinding.ensureInitialized();
  Future<pw.Font> font(String name) async =>
      pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  return pw.ThemeData.withFont(
    base: await font('NotoSans-Regular'),
    bold: await font('NotoSans-Bold'),
    fontFallback: [
      await font('NotoSansDevanagari-Regular'),
      await font('NotoSansDevanagari-Bold'),
    ],
  );
}
