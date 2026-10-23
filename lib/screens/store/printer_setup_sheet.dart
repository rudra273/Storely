import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../../services/thermal/receipt_builder.dart';
import '../../services/thermal/thermal_printer_service.dart';
import '../../theme/app_theme.dart';

/// Choose this phone's Bluetooth receipt printer (paired in Android
/// Bluetooth settings first), set the paper width and test it.
class PrinterSetupSheet extends StatefulWidget {
  const PrinterSetupSheet({super.key});

  @override
  State<PrinterSetupSheet> createState() => _PrinterSetupSheetState();
}

class _PrinterSetupSheetState extends State<PrinterSetupSheet> {
  final _printer = ThermalPrinterService.instance;
  List<BluetoothInfo>? _paired;
  late ReceiptPaper _paper = _printer.paper;
  bool _busy = false;
  String? _message;

  Future<void> _findPrinters() async {
    await _run(() async {
      final paired = await _printer.pairedPrinters();
      if (!mounted) return;
      setState(() {
        _paired = paired;
        _message = paired.isEmpty
            ? 'No paired devices. Pair the printer in Android Bluetooth '
                  'settings first, then try again.'
            : null;
      });
    });
  }

  Future<void> _choose(BluetoothInfo device) async {
    await _printer.choose(
      mac: device.macAdress,
      name: device.name,
      paper: _paper,
    );
    if (mounted) setState(() => _paired = null);
  }

  Future<void> _setPaper(ReceiptPaper paper) async {
    setState(() => _paper = paper);
    await _printer.setPaper(paper);
  }

  Future<void> _test() async {
    await _run(() async {
      await _printer.testPrint();
      if (mounted) setState(() => _message = 'Test receipt sent.');
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } on PrinterException catch (error) {
      if (mounted) setState(() => _message = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Printer not reachable. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final paired = _paired;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Receipt printer', style: AppText.title),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _printer.isConfigured
                    ? 'Printing to ${_printer.printerName}'
                    : 'Pair your Bluetooth thermal printer in Android '
                          'settings, then choose it here.',
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<ReceiptPaper>(
                segments: const [
                  ButtonSegment(
                    value: ReceiptPaper.mm58,
                    label: Text('58 mm (2")'),
                  ),
                  ButtonSegment(
                    value: ReceiptPaper.mm80,
                    label: Text('80 mm (3")'),
                  ),
                ],
                selected: {_paper},
                showSelectedIcon: false,
                onSelectionChanged: (value) => _setPaper(value.first),
              ),
              const SizedBox(height: AppSpacing.md),
              if (paired != null)
                for (final device in paired)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.print_outlined),
                    title: Text(device.name),
                    subtitle: Text(device.macAdress),
                    onTap: () => _choose(device),
                  ),
              if (_busy) const LinearProgressIndicator(minHeight: 2),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(_message!, style: AppText.caption),
                ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _busy ? null : _findPrinters,
                icon: const Icon(Icons.bluetooth_searching_rounded),
                label: Text(
                  _printer.isConfigured ? 'Change printer' : 'Choose printer',
                ),
              ),
              if (_printer.isConfigured) ...[
                const SizedBox(height: AppSpacing.sm),
                FilledButton.icon(
                  onPressed: _busy ? null : _test,
                  icon: const Icon(Icons.receipt_long_rounded),
                  label: const Text('Test print'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          await _printer.forget();
                          if (mounted) setState(() {});
                        },
                  child: const Text('Forget printer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
