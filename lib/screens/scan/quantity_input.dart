part of '../scan_screen.dart';

/// Editable cart quantity. Owns its controller so typing keeps focus; the
/// text is only rewritten when the quantity changes from outside (the +/-
/// buttons, or a stock clamp) and no longer matches what the user typed.
class _QuantityInput extends StatefulWidget {
  final double quantity;
  final ValueChanged<double> onChanged;

  const _QuantityInput({
    super.key,
    required this.quantity,
    required this.onChanged,
  });

  @override
  State<_QuantityInput> createState() => _QuantityInputState();
}

class _QuantityInputState extends State<_QuantityInput> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatQuantityInput(widget.quantity),
    );
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _QuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final typed = double.tryParse(_controller.text);
    final matches = typed != null && (typed - widget.quantity).abs() < 1e-9;
    if (matches || (typed == null && _focusNode.hasFocus)) return;
    final text = _formatQuantityInput(widget.quantity);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onFocusChange() {
    // Leaving the field with an empty/rejected value (e.g. "0") restores the
    // real quantity.
    if (_focusNode.hasFocus) return;
    final typed = double.tryParse(_controller.text);
    if (typed == null || (typed - widget.quantity).abs() >= 1e-9) {
      _controller.text = _formatQuantityInput(widget.quantity);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
      ],
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        border: InputBorder.none,
      ),
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      onChanged: (value) {
        final quantity = double.tryParse(value);
        if (quantity != null) widget.onChanged(quantity);
      },
    );
  }
}
