import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/shop_profile.dart';
import '../services/cloud_service.dart';
import '../utils/bill_pdf_generator.dart';
import 'scan_screen.dart';

class BillsScreen extends StatefulWidget {
  final int refreshToken;

  const BillsScreen({super.key, this.refreshToken = 0});
  @override
  State<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends State<BillsScreen> {
  List<Bill> _bills = [];
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadBills();
  }

  @override
  void didUpdateWidget(covariant BillsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _loadBills();
  }

  Future<void> _loadBills() async {
    final bills = await DatabaseHelper.instance.getAllBills();
    if (mounted) {
      setState(() {
        _bills = bills;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteBill(Bill bill) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline, color: AppColors.error, size: 32),
        title: const Text('Delete Bill'),
        content: Text('Delete ${_billDisplayId(bill)}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseHelper.instance.deleteBill(bill.id!);
      _loadBills();
    }
  }

  Future<void> _updateBillStatus(Bill bill, bool isPaid, {String? paymentMethod}) async {
    if (bill.id == null) return;
    await DatabaseHelper.instance.updateBillPaidStatus(
      bill.id!,
      isPaid,
      paymentMethod: paymentMethod,
    );
    await _loadBills();
  }

  Future<void> _recordPayment(Bill bill) async {
    if (bill.id == null || bill.balanceDue <= 0) return;
    final amountCtrl = TextEditingController(
      text: bill.balanceDue.toStringAsFixed(2),
    );
    var method = 'cash';
    try {
      final amount = await showDialog<double>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Record Payment'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount received',
                    prefixText: '₹ ',
                    helperText: 'Balance: ₹${bill.balanceDue.toStringAsFixed(2)}',
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'cash',
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Cash'),
                    ),
                    ButtonSegment(
                      value: 'online',
                      icon: Icon(Icons.account_balance_wallet_outlined),
                      label: Text('Online'),
                    ),
                  ],
                  selected: {method},
                  onSelectionChanged: (value) =>
                      setDialogState(() => method = value.first),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(amountCtrl.text) ?? 0;
                  Navigator.pop(ctx, value);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );
      if (amount == null || amount <= 0) return;
      await DatabaseHelper.instance.recordBillPayment(
        bill.id!,
        amount: amount,
        paymentMethod: method,
      );
      await _loadBills();
    } finally {
      amountCtrl.dispose();
    }
  }

  Future<void> _openBillCreator(BillingEntryMode mode) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanScreen(initialMode: mode)),
    );
    await _loadBills();
  }

  Future<void> _sendBillOnWhatsApp(Bill bill) async {
    final phone = _whatsAppPhone(bill.customerPhone);
    if (phone == null) return;
    final uri = Uri.https('wa.me', '/$phone', {
      'text': _buildBillMessage(bill, await DatabaseHelper.instance.getShopProfile()),
    });
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp')),
      );
    }
  }

  Future<void> _shareBillPdf(Bill bill) async {
    final shop = await DatabaseHelper.instance.getShopProfile();
    final bytes = await BillPdfGenerator.generate(bill: bill, shop: shop);
    await Printing.sharePdf(bytes: bytes, filename: BillPdfGenerator.filename(bill));
  }

  String? _whatsAppPhone(String? value) {
    final phone = value?.replaceAll(RegExp(r'[^0-9]'), '');
    if (phone == null || phone.isEmpty || phone == '91') return null;
    if (phone.length == 10) return '91$phone';
    return phone;
  }

  String _buildBillMessage(Bill bill, ShopProfile? shop) {
    final buffer = StringBuffer()
      ..writeln(shop?.name ?? 'Storely')
      ..writeln(_billDisplayId(bill))
      ..writeln('Customer: ${bill.customerName}')
      ..writeln('Date: ${DateFormat('dd MMM yyyy, hh:mm a').format(bill.createdAt)}');
    if (shop?.gstin != null) buffer.writeln('GSTIN: ${shop!.gstin}');
    if (shop?.address != null) buffer.writeln(shop!.address);
    buffer..writeln('')..writeln('Items:');
    for (final item in bill.items) {
      buffer.writeln(
        '- ${item.productName} ${item.quantityLabel} x ${item.priceLabel}: ₹${item.subtotal.toStringAsFixed(2)}',
      );
    }
    buffer
      ..writeln('')
      ..writeln('Subtotal: ₹${bill.subtotalAmount.toStringAsFixed(2)}');
    if (bill.discountAmount > 0) {
      buffer.writeln(
        'Discount (${bill.discountPercent.toStringAsFixed(2)}%): -₹${bill.discountAmount.toStringAsFixed(2)}',
      );
    }
    buffer
      ..writeln('Total: ₹${bill.totalAmount.toStringAsFixed(2)}')
      ..writeln('Paid: ₹${bill.paidAmount.toStringAsFixed(2)}')
      ..writeln('Balance: ₹${bill.balanceDue.toStringAsFixed(2)}')
      ..writeln('Status: ${_paymentStatusLabel(bill.paymentStatus)}');
    if (bill.paidAmount > 0) {
      buffer.writeln('Payment: ${_paymentMethodLabel(bill.paymentMethod)}');
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        color: AppColors.amber,
        onRefresh: _loadBills,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: AppScreenHeaderDelegate(
                title: 'Bills',
                topPadding: MediaQuery.paddingOf(context).top,
              ),
            ),
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_bills.isEmpty)
              SliverFillRemaining(child: _buildEmpty())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  96,
                ),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SearchBar(
                        controller: _searchCtrl,
                        query: _searchQuery,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim().toLowerCase()),
                        onClear: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_searchQuery.isEmpty) ...[
                        _UnpaidSummary(bills: _bills),
                      ],
                      ..._buildGroupedBillCards(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _isLoading || _bills.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openBillCreator(BillingEntryMode.manual),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('New Bill'),
            ),
    );
  }

  List<Widget> _buildGroupedBillCards() {
    final widgets = <Widget>[];
    String? currentGroup;

    final filtered = _bills.where((b) {
      if (_searchQuery.isEmpty) return true;
      final nameMatches = b.customerName.toLowerCase().contains(_searchQuery);
      final numMatches = b.billNumber.toLowerCase().contains(_searchQuery);
      final dateMatches =
          DateFormat('dd MMM yyyy').format(b.createdAt).toLowerCase().contains(_searchQuery);
      return nameMatches || numMatches || dateMatches;
    }).toList();

    for (final bill in filtered) {
      final group = _dateGroupTitle(bill.createdAt);
      if (group != currentGroup) {
        currentGroup = group;
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: AppSpacing.xl));
        widgets.add(_DateLabel(title: group));
        widgets.add(const SizedBox(height: AppSpacing.sm));
      }
      widgets.add(
        _BillCard(
          bill: bill,
          onDelete: () => _deleteBill(bill),
          onStatusChanged: (isPaid, method) =>
              _updateBillStatus(bill, isPaid, paymentMethod: method),
          onRecordPayment: () => _recordPayment(bill),
          onSendWhatsApp: () => _sendBillOnWhatsApp(bill),
          onSharePdf: () => _shareBillPdf(bill),
        ),
      );
    }
    return widgets;
  }

  String _dateGroupTitle(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final billDate = DateTime(date.year, date.month, date.day);
    final daysAgo = today.difference(billDate).inDays;
    if (daysAgo == 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    return DateFormat('dd MMM yyyy').format(date);
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: AppRadius.lgRadius,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 36,
                color: AppColors.inkFaint,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('No bills yet', style: AppText.title),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create your first bill to get started',
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => _openBillCreator(BillingEntryMode.manual),
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text('Create Bill'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Search bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search by name, bill # or date...',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: query.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 18),
                onPressed: onClear,
              )
            : null,
      ),
    );
  }
}

// ── Unpaid summary (collapsible) ──────────────────────────────────────────────

class _UnpaidSummary extends StatelessWidget {
  final List<Bill> bills;
  const _UnpaidSummary({required this.bills});

  @override
  Widget build(BuildContext context) {
    final unpaid = bills.where((b) => !b.isPaid).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (unpaid.isEmpty) return const SizedBox.shrink();

    final customerTotals = <String, double>{};
    for (final b in unpaid) {
      final name = b.customerName.trim().isEmpty ? 'Walk-in' : b.customerName.trim();
      customerTotals[name] = (customerTotals[name] ?? 0) + b.totalAmount;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            leading: const LeadingIconChip(
              icon: Icons.warning_amber_rounded,
              color: AppColors.error,
            ),
            title: Text(
              'Unpaid Bills Summary',
              style: AppText.subtitle.copyWith(color: AppColors.error),
            ),
            subtitle: Text(
              '${unpaid.length} pending bill${unpaid.length != 1 ? 's' : ''}',
              style: AppText.caption,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg,
            ),
            children: [
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
              Text(
                'TOTAL DUE BY CUSTOMER',
                style: AppText.label.copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...customerTotals.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: AppText.body)),
                      Text(
                        '₹${e.value.toStringAsFixed(2)}',
                        style: AppText.subtitle.copyWith(color: AppColors.error),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'ALL UNPAID BILLS',
                style: AppText.label.copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...unpaid.map(
                (b) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 44,
                        child: Text(
                          DateFormat('dd MMM').format(b.createdAt),
                          style: AppText.caption,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              b.customerName,
                              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              '#${b.billNumber.length > 4 ? b.billNumber.substring(b.billNumber.length - 4) : b.billNumber}',
                              style: AppText.caption,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${b.totalAmount.toStringAsFixed(0)}',
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Date label ────────────────────────────────────────────────────────────────

class _DateLabel extends StatelessWidget {
  final String title;
  const _DateLabel({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title.toUpperCase(),
      style: AppText.label,
    );
  }
}

// ── Bill card ─────────────────────────────────────────────────────────────────

class _BillCard extends StatefulWidget {
  final Bill bill;
  final VoidCallback onDelete;
  final VoidCallback onSendWhatsApp;
  final VoidCallback onSharePdf;
  final void Function(bool isPaid, String? paymentMethod) onStatusChanged;
  final VoidCallback onRecordPayment;

  const _BillCard({
    required this.bill,
    required this.onDelete,
    required this.onSendWhatsApp,
    required this.onSharePdf,
    required this.onStatusChanged,
    required this.onRecordPayment,
  });

  @override
  State<_BillCard> createState() => _BillCardState();
}

class _BillCardState extends State<_BillCard> {
  bool _expanded = false;

  Future<void> _togglePaidStatus() async {
    final bill = widget.bill;
    if (bill.isPaid) {
      widget.onStatusChanged(false, null);
    } else {
      final method = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Payment Method'),
          content: const Text('How was this bill paid?'),
          actions: [
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'cash'),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Cash'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'online'),
              icon: const Icon(Icons.account_balance_wallet_outlined),
              label: const Text('Online'),
            ),
          ],
        ),
      );
      if (method != null) widget.onStatusChanged(true, method);
    }
  }

  Future<void> _showProfitSummary() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BillProfitSheet(bill: widget.bill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final dateStr = DateFormat('hh:mm a').format(bill.createdAt);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: AppRadius.mdRadius,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    const LeadingIconChip(
                      icon: Icons.receipt_outlined,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            bill.customerName.isEmpty ? 'Walk-in' : bill.customerName,
                            style: AppText.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_billDisplayId(bill)} · $dateStr · ${bill.itemCount} item${bill.itemCount != 1 ? 's' : ''}',
                            style: AppText.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _PaymentChip(status: bill.paymentStatus),
                            if (bill.paidAmount > 0) ...[
                              const SizedBox(width: 4),
                              _MethodChip(method: bill.paymentMethod),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${bill.totalAmount.toStringAsFixed(2)}',
                          style: AppText.subtitle.copyWith(fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      color: AppColors.inkFaint,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  children: [
                    if (bill.customerPhone != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          children: [
                            Icon(Icons.phone_outlined, size: 15, color: AppColors.inkMuted),
                            const SizedBox(width: AppSpacing.sm),
                            Text(bill.customerPhone!, style: AppText.caption),
                          ],
                        ),
                      ),
                    ...bill.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(item.productName, style: AppText.body),
                            ),
                            Text(
                              '${item.quantityLabel} × ${item.priceLabel}',
                              style: AppText.caption,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Text(
                              '₹${item.subtotal.toStringAsFixed(2)}',
                              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: AppSpacing.lg),
                    if (bill.discountAmount > 0) ...[
                      _AmountRow(
                        label: 'Subtotal',
                        value: '₹${bill.subtotalAmount.toStringAsFixed(2)}',
                      ),
                      _AmountRow(
                        label: 'Discount ${bill.discountPercent.toStringAsFixed(2)}%',
                        value: '−₹${bill.discountAmount.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: AppText.subtitle),
                        Text(
                          '₹${bill.totalAmount.toStringAsFixed(2)}',
                          style: AppText.subtitle.copyWith(color: AppColors.navy),
                        ),
                      ],
                    ),
                    if (bill.paidAmount > 0 || bill.balanceDue > 0) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _AmountRow(
                        label: 'Paid',
                        value: '₹${bill.paidAmount.toStringAsFixed(2)}',
                      ),
                      _AmountRow(
                        label: 'Balance',
                        value: '₹${bill.balanceDue.toStringAsFixed(2)}',
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(height: 1),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      children: [
                        if (CloudService.instance.state.value.isAdmin)
                          _ActionButton(
                            onPressed: widget.onDelete,
                            icon: Icons.delete_outline,
                            label: 'Delete',
                            color: AppColors.error,
                          ),
                        _ActionButton(
                          onPressed: _togglePaidStatus,
                          icon: bill.isPaid
                              ? Icons.pending_actions_outlined
                              : Icons.check_circle_outline,
                          label: bill.isPaid ? 'Mark Unpaid' : 'Mark Paid',
                          color: bill.isPaid ? AppColors.inkMuted : AppColors.success,
                        ),
                        if (bill.balanceDue > 0)
                          _ActionButton(
                            onPressed: widget.onRecordPayment,
                            icon: Icons.payments_outlined,
                            label: 'Record Payment',
                            color: AppColors.amber,
                          ),
                        if (bill.customerPhone != null)
                          _ActionButton(
                            onPressed: widget.onSendWhatsApp,
                            icon: Icons.send_outlined,
                            label: 'WhatsApp',
                            color: AppColors.success,
                          ),
                        _ActionButton(
                          onPressed: widget.onSharePdf,
                          icon: Icons.ios_share_rounded,
                          label: 'Share',
                          color: AppColors.navy,
                        ),
                        _ActionButton(
                          onPressed: _showProfitSummary,
                          icon: Icons.trending_up_rounded,
                          label: 'View Profit',
                          color: AppColors.navy,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Profit sheet ──────────────────────────────────────────────────────────────

class _BillProfitSheet extends StatefulWidget {
  final Bill bill;
  const _BillProfitSheet({required this.bill});

  @override
  State<_BillProfitSheet> createState() => _BillProfitSheetState();
}

class _BillProfitSheetState extends State<_BillProfitSheet> {
  late final TextEditingController _commissionCtrl;
  late double _commissionPercent;

  @override
  void initState() {
    super.initState();
    _commissionPercent = widget.bill.profitCommissionPercent;
    _commissionCtrl = TextEditingController(
      text: _commissionPercent == 0 ? '' : _commissionPercent.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _commissionCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveCommission() async {
    final billId = widget.bill.id;
    if (billId == null) return;
    await DatabaseHelper.instance.updateBillProfitCommissionPercent(
      billId,
      _commissionPercent,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Commission saved for this bill')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    final revenue = bill.items.fold(0.0, (sum, item) => sum + item.subtotal);
    final cost = bill.items.fold(0.0, (sum, item) => sum + item.totalCost);
    final profit = bill.items.fold(0.0, (sum, item) => sum + item.totalProfit);
    final commission = profit > 0 ? profit * _commissionPercent / 100 : 0.0;
    final gst = bill.items.fold(0.0, (sum, item) => sum + item.totalGst);
    final net = profit - commission;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, 0, AppSpacing.md, AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.lgRadius,
          border: Border.all(color: AppColors.border),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: AppRadius.pillRadius,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('${_billDisplayId(bill)} Profit', style: AppText.title),
              const SizedBox(height: AppSpacing.lg),
              AppCard(
                color: AppColors.bg,
                child: Column(
                  children: [
                    _ProfitRow('Total Revenue', revenue),
                    _ProfitRow('Purchase Cost', cost),
                    _ProfitRow('Overhead', 0.0),
                    if (gst > 0) _ProfitRow('GST', gst),
                    const Divider(height: AppSpacing.lg),
                    _ProfitRow('Gross Profit', profit,
                        isBold: true, color: AppColors.success),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Text(
                          'Partner Commission %',
                          style: AppText.caption.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 80,
                          height: 36,
                          child: TextField(
                            controller: _commissionCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              contentPadding: EdgeInsets.zero,
                              suffixText: '%',
                              border: OutlineInputBorder(
                                borderRadius: AppRadius.smRadius,
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: AppRadius.smRadius,
                                borderSide: const BorderSide(color: AppColors.border),
                              ),
                              filled: true,
                              fillColor: AppColors.surface,
                            ),
                            onChanged: (value) => setState(() {
                              _commissionPercent =
                                  (double.tryParse(value) ?? 0).clamp(0, 100).toDouble();
                            }),
                          ),
                        ),
                      ],
                    ),
                    if (commission > 0) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _ProfitRow('Commission Payable', -commission,
                          color: AppColors.error),
                    ],
                    const Divider(height: AppSpacing.xl),
                    _ProfitRow('Net Profit', net, isBold: true, fontSize: 18),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: _saveCommission,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save Commission'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────────

class _ProfitRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isBold;
  final Color? color;
  final double fontSize;

  const _ProfitRow(
    this.label,
    this.value, {
    this.isBold = false,
    this.color,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: color ?? AppColors.inkMuted,
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          Text(
            '${value < 0 ? '−' : ''}₹${value.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w600,
              fontSize: fontSize,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

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
          Text(value, style: AppText.caption.copyWith(fontWeight: FontWeight.w600)),
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

String _paymentStatusLabel(String status) => switch (status) {
      Bill.statusPaid => 'Paid',
      Bill.statusPartial => 'Partial',
      _ => 'Unpaid',
    };

String _paymentMethodLabel(String method) => method == 'online' ? 'Online' : 'Cash';

String _billDisplayId(Bill bill) {
  if (bill.billNumber.isEmpty) return 'Bill #${bill.id}';
  return bill.billNumber.replaceFirst(RegExp(r'^SHOP-LOCAL-local-'), 'INV-');
}
