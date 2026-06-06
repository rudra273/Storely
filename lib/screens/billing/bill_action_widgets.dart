part of '../bills_screen.dart';

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  const _AmountRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: AppText.caption),
          const Spacer(),
          Text(
            value,
            style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final Color color;

  const _ActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: 0.5,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label, overflow: TextOverflow.ellipsis),
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _EditBuyerDetailsSheet extends StatelessWidget {
  final bool isB2b;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController gstinCtrl;
  final TextEditingController legalNameCtrl;
  final TextEditingController tradeNameCtrl;
  final TextEditingController addressCtrl;
  final TextEditingController stateCodeCtrl;

  const _EditBuyerDetailsSheet({
    required this.isB2b,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.gstinCtrl,
    required this.legalNameCtrl,
    required this.tradeNameCtrl,
    required this.addressCtrl,
    required this.stateCodeCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(24),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrongOf(context),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Edit Buyer Details',
                  style: AppText.title.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  'Only buyer details can be changed. Items, amounts, and GST stay locked.',
                  style: AppText.caption,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Customer Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                if (isB2b) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: gstinCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'GSTIN',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: legalNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'GST Legal Name',
                      prefixIcon: Icon(Icons.business_center_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: tradeNameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'GST Trade Name',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: addressCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: stateCodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Place of Supply (State Code)',
                      prefixIcon: Icon(Icons.map_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  final String status;
  const _PaymentChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final isPaid = status == Bill.statusPaid;
    final isPartial = status == Bill.statusPartial;
    return StatusPill(
      label: _paymentStatusLabel(status),
      variant: isPaid
          ? PillVariant.paid
          : isPartial
          ? PillVariant.warning
          : PillVariant.unpaid,
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String method;
  const _MethodChip({required this.method});

  @override
  Widget build(BuildContext context) {
    final online = method == 'online';
    return StatusPill(
      label: _paymentMethodLabel(method),
      variant: online ? PillVariant.info : PillVariant.warning,
    );
  }
}
