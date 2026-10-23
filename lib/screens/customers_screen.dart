import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/customer.dart';
import '../services/cloud_service.dart';
import '../services/dues_reminder.dart';
import '../utils/statement_pdf_generator.dart';
import 'shared/record_payment_dialog.dart';
import 'customer_profile_sheet.dart';
import '../utils/money.dart';

/// The single Customers page, opened from both Home → Workspace and
/// Settings → Customers. Full-screen (not a bottom sheet) and dark-mode aware.
///
/// View-only for staff: the list is always visible, but Add/Edit are hidden when
/// the signed-in cloud user is not an owner/admin (those writes are admin-gated
/// in the DB layer).
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  List<Customer> _customers = [];
  List<Bill> _bills = [];
  Map<int, double> _pendingById = {};
  Map<String, double> _pendingByPhone = {};
  bool _isLoading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final customers = await DatabaseHelper.instance.getAllCustomers();
      final bills = await DatabaseHelper.instance.getAllBills();
      if (!mounted) return;
      final pending = _buildPendingMaps(bills);
      setState(() {
        _customers = customers;
        _bills = bills;
        _pendingById = pending.$1;
        _pendingByPhone = pending.$2;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load customers: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  List<Customer> get _filtered {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _customers;
    final digits = query.replaceAll(RegExp(r'[^0-9]'), '');
    return _customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          customer.phone.contains(digits.isEmpty ? query : digits) ||
          (customer.gstin?.toLowerCase().contains(query) ?? false) ||
          (customer.email?.toLowerCase().contains(query) ?? false) ||
          (customer.address?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  double _pendingAmount(Customer customer) {
    final byId = customer.id == null ? null : _pendingById[customer.id];
    if (byId != null) return byId;
    return _pendingByPhone[customer.phone] ?? 0;
  }

  List<Bill> _billsFor(Customer customer) {
    final phone = _normalisePhone(customer.phone);
    final matched = _bills.where((bill) {
      if (bill.lifecycleStatus == Bill.lifecycleCancelled) return false;
      if (customer.id != null && bill.customerId == customer.id) return true;
      if (phone == null) return false;
      return _normalisePhone(bill.customerPhone) == phone;
    }).toList();
    matched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matched;
  }

  Future<void> _addCustomer() async {
    final result = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CustomerProfileSheet(),
    );
    if (result == null) return;
    await _save(() => DatabaseHelper.instance.saveCustomerProfile(result));
  }

  Future<void> _editCustomer(Customer customer) async {
    final result = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CustomerProfileSheet(customer: customer),
    );
    if (result == null) return;
    await _save(() => DatabaseHelper.instance.saveCustomerProfile(result));
  }

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openDetail(Customer customer) async {
    final canManage = CloudService.instance.state.value.isAdmin;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CustomerDetailScreen(
          customer: customer,
          bills: _billsFor(customer),
          reloadBills: () async {
            await _load();
            return _billsFor(customer);
          },
          canManage: canManage,
          onEdit: canManage ? () => _editCustomer(customer) : null,
        ),
      ),
    );
    // An edit from the detail page may have changed data.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final customers = _filtered;
    // Listen to cloud state so Add actions appear the moment the user's role
    // resolves on startup — otherwise isAdmin is read once (null role → false)
    // and the buttons only show after a sync round-trip + reopening the page.
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, cloudState, _) {
        final canManage = cloudState.isAdmin;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: navyAppBar(title: 'Customers'),
          // Hidden when the list is truly empty — the centered empty-state
          // button is the single add action there. Shown once customers exist
          // (including when a search filters them all out, so adding stays
          // reachable).
          floatingActionButton: canManage && _customers.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _addCustomer,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Customer'),
                )
              : null,
          body: _isLoading
              ? const AppSkeletonList()
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.sm,
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Search customers',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    Expanded(
                      child: customers.isEmpty
                          ? _EmptyCustomers(
                              hasAny: _customers.isNotEmpty,
                              canManage: canManage,
                              onAdd: _addCustomer,
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                AppSpacing.sm,
                                AppSpacing.lg,
                                AppSpacing.xxxl * 2,
                              ),
                              itemCount: customers.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (_, index) {
                                final customer = customers[index];
                                return _CustomerSummaryRow(
                                  customer: customer,
                                  pendingAmount: _pendingAmount(customer),
                                  onTap: () => _openDetail(customer),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}

(Map<int, double>, Map<String, double>) _buildPendingMaps(List<Bill> bills) {
  final byId = <int, double>{};
  final byPhone = <String, double>{};
  for (final bill in bills) {
    if (bill.balanceDue <= 0) continue;
    final id = bill.customerId;
    if (id != null) byId[id] = (byId[id] ?? 0) + bill.balanceDue;
    final phone = _normalisePhone(bill.customerPhone);
    if (phone != null) byPhone[phone] = (byPhone[phone] ?? 0) + bill.balanceDue;
  }
  return (byId, byPhone);
}

String? _normalisePhone(String? value) {
  final digits = value?.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits == null || digits.isEmpty || digits == '91') return null;
  if (digits.length == 10) return '91$digits';
  return digits;
}

String _displayPhone(String phone) {
  if (phone.length == 12 && phone.startsWith('91')) {
    return '+91 ${phone.substring(2, 7)} ${phone.substring(7)}';
  }
  return phone;
}

class _EmptyCustomers extends StatelessWidget {
  final bool hasAny;
  final bool canManage;
  final VoidCallback onAdd;

  const _EmptyCustomers({
    required this.hasAny,
    required this.canManage,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline_rounded,
              size: 56,
              color: AppColors.inkMutedOf(context),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              hasAny ? 'No matching customers' : 'No customers yet',
              style: AppText.subtitle,
            ),
            if (!hasAny) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                canManage
                    ? 'Customers are saved automatically from bills, or add them here.'
                    : 'Your shop has not added any customers yet.',
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
              if (canManage) ...[
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Customer'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomerSummaryRow extends StatelessWidget {
  final Customer customer;
  final double pendingAmount;
  final VoidCallback? onTap;

  const _CustomerSummaryRow({
    required this.customer,
    required this.pendingAmount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          const LeadingIconChip(
            icon: Icons.person_outline_rounded,
            color: AppColors.success,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: AppText.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (customer.phone.isNotEmpty)
                      _displayPhone(customer.phone),
                    '${customer.billCount} purchase${customer.billCount != 1 ? 's' : ''}',
                  ].join(' · '),
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
              Text(
                rupees(customer.totalPurchaseAmount, decimals: 0),
                style: AppText.subtitle.copyWith(fontSize: 14),
              ),
              Text(
                pendingAmount > 0
                    ? 'Due ${rupees(pendingAmount, decimals: 0)}'
                    : 'No due',
                style: AppText.caption.copyWith(
                  color: pendingAmount > 0
                      ? AppColors.error
                      : AppColors.success,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Customer Detail (full page) ───────────────────────────────────────────────

class _CustomerDetailScreen extends StatefulWidget {
  final Customer customer;
  final List<Bill> bills;
  final Future<List<Bill>> Function() reloadBills;
  final bool canManage;
  final VoidCallback? onEdit;

  const _CustomerDetailScreen({
    required this.customer,
    required this.bills,
    required this.reloadBills,
    required this.canManage,
    this.onEdit,
  });

  @override
  State<_CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<_CustomerDetailScreen> {
  late List<Bill> bills = widget.bills;
  bool _busy = false;

  Customer get customer => widget.customer;
  bool get canManage => widget.canManage;
  VoidCallback? get onEdit => widget.onEdit;

  List<Bill> get _unpaid =>
      bills.where((b) => b.balanceDue > 0.005).toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  double get pendingAmount =>
      _unpaid.fold<double>(0, (sum, b) => sum + b.balanceDue);

  Future<void> _recordPayment() async {
    final unpaid = _unpaid;
    if (unpaid.isEmpty) return;
    final entry = await showDialog<PaymentEntry>(
      context: context,
      builder: (_) => RecordPaymentDialog(
        balanceDue: pendingAmount,
        title: 'Payment from ${customer.name}',
      ),
    );
    if (entry == null) return;
    await _run(() async {
      final touched = await DatabaseHelper.instance.recordCustomerPayment(
        billIds: [for (final b in unpaid) b.id!],
        amount: entry.amount,
        paymentMethod: entry.method,
        paymentReference: entry.reference,
      );
      final updated = await widget.reloadBills();
      if (!mounted) return;
      setState(() => bills = updated);
      _toast(
        '${rupees(entry.amount)} received, settled against '
        '$touched bill${touched == 1 ? '' : 's'} (oldest first)',
      );
    });
  }

  Future<void> _remind() async {
    await _run(() async {
      final db = DatabaseHelper.instance;
      final shop = await db.getShopProfile();
      final settings = await db.getBillSettings();
      final text = DuesReminder.message(
        customerName: customer.name,
        shopName: shop?.name ?? 'our shop',
        unpaidBills: _unpaid,
        upiId: settings.upiId,
      );
      final link = DuesReminder.whatsAppLink(customer.phone, text);
      if (link == null) {
        _toast('Add a phone number to send a reminder');
        return;
      }
      final opened = await launchUrl(
        link,
        mode: LaunchMode.externalApplication,
      );
      if (!opened) _toast('Unable to open WhatsApp');
    });
  }

  Future<void> _shareStatement() async {
    await _run(() async {
      final db = DatabaseHelper.instance;
      final bytes = await StatementPdfGenerator.generate(
        customerName: customer.name,
        customerPhone: customer.phone.isEmpty ? null : customer.phone,
        bills: bills,
        shop: await db.getShopProfile(),
        settings: await db.getBillSettings(),
      );
      final safeName = customer.name.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '-');
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'Statement-$safeName.pdf',
      );
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      _toast(
        error is ArgumentError
            ? '${error.message}'
            : 'Something went wrong. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<(IconData, String)> get _detailLines {
    final lines = <(IconData, String)>[];
    if (customer.gstin != null && customer.gstin!.isNotEmpty) {
      lines.add((Icons.badge_outlined, 'GSTIN ${customer.gstin}'));
    }
    if (customer.email != null && customer.email!.isNotEmpty) {
      lines.add((Icons.email_outlined, customer.email!));
    }
    if (customer.address != null && customer.address!.isNotEmpty) {
      lines.add((Icons.location_on_outlined, customer.address!));
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final totalBilled = bills.fold<double>(0, (sum, b) => sum + b.totalAmount);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: navyAppBar(
        title: 'Customer',
        actions: [
          if (canManage && onEdit != null)
            IconButton(
              onPressed: () {
                Navigator.of(context).pop();
                onEdit!();
              },
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit',
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Row(
            children: [
              const LeadingIconChip(
                icon: Icons.person_outline_rounded,
                color: AppColors.success,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: AppText.title.copyWith(
                        color: AppColors.inkOf(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (customer.phone.isNotEmpty)
                      Text(
                        _displayPhone(customer.phone),
                        style: AppText.caption,
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_detailLines.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            ..._detailLines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      line.$1,
                      size: 15,
                      color: AppColors.inkMutedOf(context),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(line.$2, style: AppText.caption)),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MiniStat(
                  label: 'Total billed',
                  value: rupees(totalBilled, decimals: 0),
                  color: AppColors.inkOf(context),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _MiniStat(
                  label: 'Pending',
                  value: pendingAmount > 0
                      ? rupees(pendingAmount, decimals: 0)
                      : '₹0',
                  color: pendingAmount > 0
                      ? AppColors.error
                      : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              if (pendingAmount > 0)
                FilledButton.icon(
                  onPressed: _busy ? null : _recordPayment,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Record payment'),
                ),
              if (pendingAmount > 0 && customer.phone.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _remind,
                  icon: const Icon(Icons.chat_outlined),
                  label: const Text('Remind'),
                ),
              if (bills.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _shareStatement,
                  icon: const Icon(Icons.description_outlined),
                  label: const Text('Statement'),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(title: 'Bills (${bills.length})'),
          const SizedBox(height: AppSpacing.sm),
          if (bills.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No bills for this customer yet',
                  style: AppText.caption,
                ),
              ),
            )
          else
            ...bills.map(
              (bill) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _CustomerBillRow(bill: bill),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppText.subtitle.copyWith(color: color, fontSize: 15),
          ),
        ],
      ),
    );
  }
}

class _CustomerBillRow extends StatelessWidget {
  final Bill bill;

  const _CustomerBillRow({required this.bill});

  StatusPill get _statusPill => switch (bill.paymentStatus) {
    Bill.statusPaid => StatusPill.paid(),
    Bill.statusPartial => StatusPill.partial(),
    _ => StatusPill.unpaid(),
  };

  @override
  Widget build(BuildContext context) {
    final date = bill.createdAt;
    final dateLabel =
        '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bill.billNumber.isNotEmpty ? bill.billNumber : 'No number',
                  style: AppText.subtitle.copyWith(fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$dateLabel · ${bill.itemCount} item${bill.itemCount != 1 ? 's' : ''}',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                rupees(bill.totalAmount, decimals: 0),
                style: AppText.subtitle.copyWith(fontSize: 14),
              ),
              const SizedBox(height: 4),
              _statusPill,
            ],
          ),
        ],
      ),
    );
  }
}
