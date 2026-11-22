part of '../scan_screen.dart';

/// Editable cart quantity. Owns its controller so typing keeps focus; the
/// text is only rewritten when the quantity changes from outside (the +/-
/// buttons, or a stock clamp) and no longer matches what the user typed.
class _QuantityInput extends StatefulWidget {
  final double quantity;
  final String? invalidInput;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _QuantityInput({
    super.key,
    required this.quantity,
    required this.invalidInput,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<_QuantityInput> createState() => _QuantityInputState();
}

class _QuantityInputState extends State<_QuantityInput> {
  late final TextEditingController _controller;

  String get _display =>
      widget.invalidInput ??
      widget.quantity.toString().replaceFirst(RegExp(r'\.0$'), '');

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _display);
  }

  @override
  void didUpdateWidget(covariant _QuantityInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = _display;
    if (_controller.text == text ||
        (widget.invalidInput == null &&
            saleQuantityValue(_controller.text) == widget.quantity)) {
      return;
    }
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: const ValueKey('sale-quantity-input'),
      controller: _controller,
      enabled: widget.enabled,
      textAlign: TextAlign.center,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        isDense: true,
        filled: false,
        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        border: InputBorder.none,
      ),
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color:
            widget.invalidInput == null && saleQuantityValue(_display) != null
            ? null
            : Theme.of(context).colorScheme.error,
      ),
      onChanged: widget.onChanged,
    );
  }
}
