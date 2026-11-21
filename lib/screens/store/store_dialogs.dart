part of '../store_screen.dart';

class _MoneyField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String>? onChanged;

  const _MoneyField({
    required this.controller,
    required this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _NameDialog extends StatefulWidget {
  final String title;
  final String label;
  final String? initialValue;

  const _NameDialog({
    required this.title,
    required this.label,
    this.initialValue,
  });

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final value = _controller.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(labelText: widget.label),
          validator: (value) =>
              value == null || value.trim().isEmpty ? 'Required' : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

class _NumberDialog extends StatefulWidget {
  final String title;
  final String label;
  final double initialValue;
  final Future<void> Function(double) onSave;

  const _NumberDialog({
    required this.title,
    required this.label,
    required this.initialValue,
    required this.onSave,
  });

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  bool _saving = false;
  String? _saveError;
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: lowStockThresholdText(widget.initialValue),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final value = LowStockThreshold.parse(_controller.text)!.value;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.pop(context, value);
    } catch (error) {
      if (mounted) {
        setState(
          () => _saveError = error is FormatException
              ? error.message
              : friendlyError(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _formKey,
          child: TextFormField(
            key: const ValueKey('low-stock-threshold-input'),
            enabled: !_saving,
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: widget.label,
              errorText: _saveError,
              suffixText: 'units',
            ),
            validator: (value) {
              return LowStockThreshold.parse(value) == null
                  ? 'Enter a value from 0 to 999999999 with up to 4 decimal places'
                  : null;
            },
            onFieldSubmitted: (_) => _submit(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('low-stock-threshold-save'),
            onPressed: _saving ? null : _submit,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
