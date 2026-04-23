import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../models/product.dart';
import '../utils/pdf_generator.dart';

class QrSheetScreen extends StatefulWidget {
  final List<Product> products;

  const QrSheetScreen({super.key, required this.products});

  @override
  State<QrSheetScreen> createState() => _QrSheetScreenState();
}

class _QrSheetScreenState extends State<QrSheetScreen> {
  int _columns = 3;
  int _rows = 8;

  int get _itemsPerPage => _columns * _rows;
  int get _pageCount => PdfGenerator.pageCount(
    widget.products.length,
    columns: _columns,
    rows: _rows,
  );

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'QR Code Sheet',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // ── Layout configuration card ──
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.grid_view_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Layout',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    // Page info chip
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$_pageCount page${_pageCount != 1 ? 's' : ''} · ${widget.products.length} items',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Columns control
                    Expanded(
                      child: _StepperControl(
                        label: 'Columns',
                        value: _columns,
                        min: 1,
                        max: 6,
                        onChanged: (v) => setState(() => _columns = v),
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Rows control
                    Expanded(
                      child: _StepperControl(
                        label: 'Rows',
                        value: _rows,
                        min: 1,
                        max: 12,
                        onChanged: (v) => setState(() => _rows = v),
                        colorScheme: colorScheme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Per-page indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Text(
                            '$_itemsPerPage',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colorScheme.tertiary,
                            ),
                          ),
                          Text(
                            'per page',
                            style: TextStyle(
                              fontSize: 10,
                              color: colorScheme.onTertiaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ── PDF Preview ──
          Expanded(
            child: PdfPreview(
              key: ValueKey('${_columns}_$_rows'),
              build: (format) => PdfGenerator.generate(
                widget.products,
                columns: _columns,
                rows: _rows,
              ),
              allowPrinting: false,
              allowSharing: true,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              pdfFileName: 'storely_qr_codes.pdf',
              loadingWidget: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      'Generating QR codes...',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact +/- stepper widget for grid configuration
class _StepperControl extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final ColorScheme colorScheme;

  const _StepperControl({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _circleButton(
                icon: Icons.remove,
                enabled: value > min,
                onTap: () => onChanged(value - 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  '$value',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              _circleButton(
                icon: Icons.add,
                enabled: value < max,
                onTap: () => onChanged(value + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: enabled
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }
}
