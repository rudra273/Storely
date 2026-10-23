import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../db/database_helper.dart';
import '../../models/bill.dart';
import 'receipt_builder.dart';
import 'receipt_image.dart';

/// A printer problem worth showing to the shopkeeper as is.
class PrinterException implements Exception {
  final String message;

  const PrinterException(this.message);

  @override
  String toString() => message;
}

/// The device's Bluetooth receipt printer (per phone, not synced).
/// Printers are paired in Android Bluetooth settings first; this lists the
/// paired ones, remembers the chosen one and prints to it.
class ThermalPrinterService extends ChangeNotifier {
  static final ThermalPrinterService instance = ThermalPrinterService._();

  ThermalPrinterService._();

  static const _macKey = 'printer_mac';
  static const _nameKey = 'printer_name';
  static const _paperKey = 'printer_paper';

  String? _mac;
  String? _name;
  ReceiptPaper _paper = ReceiptPaper.mm58;
  bool _busy = false;

  bool get isConfigured => _mac != null;
  String? get printerName => _name;
  ReceiptPaper get paper => _paper;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mac = prefs.getString(_macKey);
    _name = prefs.getString(_nameKey);
    _paper = prefs.getString(_paperKey) == ReceiptPaper.mm80.name
        ? ReceiptPaper.mm80
        : ReceiptPaper.mm58;
  }

  Future<void> choose({
    required String mac,
    required String name,
    required ReceiptPaper paper,
  }) async {
    _mac = mac;
    _name = name;
    _paper = paper;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_macKey, mac);
    await prefs.setString(_nameKey, name);
    await prefs.setString(_paperKey, paper.name);
    notifyListeners();
  }

  Future<void> setPaper(ReceiptPaper paper) async {
    _paper = paper;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paperKey, paper.name);
    notifyListeners();
  }

  Future<void> forget() async {
    _mac = null;
    _name = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_macKey);
    await prefs.remove(_nameKey);
    if (await PrintBluetoothThermal.connectionStatus) {
      await PrintBluetoothThermal.disconnect;
    }
    notifyListeners();
  }

  /// Printers already paired in Android Bluetooth settings.
  Future<List<BluetoothInfo>> pairedPrinters() async {
    if (!await PrintBluetoothThermal.isPermissionBluetoothGranted) {
      throw const PrinterException(
        'Allow "Nearby devices" for Storely to use a Bluetooth printer.',
      );
    }
    if (!await PrintBluetoothThermal.bluetoothEnabled) {
      throw const PrinterException('Turn on Bluetooth to find your printer.');
    }
    return PrintBluetoothThermal.pairedBluetooths;
  }

  Future<void> printBill(Bill bill) async {
    final db = DatabaseHelper.instance;
    final shop = await db.getShopProfile();
    final settings = await db.getBillSettings();
    final profile = await CapabilityProfile.load();
    final bytes = ReceiptBuilder.needsImageMode(bill, shop)
        ? await ReceiptImage.build(
            bill: bill,
            shop: shop,
            settings: settings,
            paper: _paper,
            profile: profile,
          )
        : ReceiptBuilder.build(
            bill: bill,
            shop: shop,
            settings: settings,
            paper: _paper,
            profile: profile,
          );
    await _send(bytes);
  }

  Future<void> testPrint() async {
    final shop = await DatabaseHelper.instance.getShopProfile();
    final profile = await CapabilityProfile.load();
    final gen = Generator(_paper.size, profile);
    await _send([
      ...gen.reset(),
      ...gen.text(
        'Storely test print',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
      ...gen.text(
        shop?.name ?? '',
        styles: const PosStyles(align: PosAlign.center),
      ),
      ...gen.text(
        '${_paper == ReceiptPaper.mm58 ? '58' : '80'} mm paper',
        styles: const PosStyles(align: PosAlign.center),
      ),
      ...gen.hr(),
      ...gen.text('If you can read this, printing works.'),
      ...gen.feed(3),
      ...gen.cut(),
    ]);
  }

  Future<void> _send(List<int> bytes) async {
    final mac = _mac;
    if (mac == null) {
      throw const PrinterException('Choose a receipt printer first.');
    }
    if (_busy) throw const PrinterException('Already printing.');
    _busy = true;
    try {
      if (!await PrintBluetoothThermal.connectionStatus) {
        final connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: mac,
        );
        if (!connected) {
          throw PrinterException(
            'Could not connect to ${_name ?? 'the printer'}. Check that it '
            'is on, charged and near the phone.',
          );
        }
      }
      if (!await PrintBluetoothThermal.writeBytes(bytes)) {
        throw const PrinterException('Printing failed. Try again.');
      }
    } finally {
      _busy = false;
    }
  }
}

/// Short label for settings rows.
String printerLabel(ThermalPrinterService printer) => printer.isConfigured
    ? '${printer.printerName ?? 'Printer'} · '
          '${printer.paper == ReceiptPaper.mm58 ? '58' : '80'} mm'
    : 'Not set';
