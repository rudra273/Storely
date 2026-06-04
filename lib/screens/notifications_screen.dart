import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _customerDebits = [];

  @override
  void initState() {
    super.initState();
    _loadDebits();
  }

  Future<void> _loadDebits() async {
    final bills = await DatabaseHelper.instance.getUnpaidBills();
    final debitsList = buildCustomerDebitRows(bills);

    if (mounted) {
      setState(() {
        _customerDebits = debitsList;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Notifications')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _customerDebits.isEmpty
          ? Center(child: Text('No pending dues', style: AppText.caption))
          : ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: _customerDebits.length,
              itemBuilder: (context, index) {
                final data = _customerDebits[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        const LeadingIconChip(
                          icon: Icons.warning_amber_rounded,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['name'] as String,
                                style: AppText.subtitle,
                              ),
                              Text(
                                data['phone'] as String,
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('PENDING', style: AppText.label),
                            Text(
                              '₹${(data['amount'] as double).toStringAsFixed(2)}',
                              style: AppText.subtitle.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

List<Map<String, dynamic>> buildCustomerDebitRows(List<Bill> bills) {
  final debitsMap = <String, double>{};
  for (final bill in bills) {
    final name = bill.customerName.trim().isNotEmpty
        ? bill.customerName.trim()
        : 'Unknown';
    final phone = bill.customerPhone?.trim() ?? '';
    final key = '$name|__|$phone';

    debitsMap[key] = (debitsMap[key] ?? 0) + bill.balanceDue;
  }

  final debitsList = debitsMap.entries.map((e) {
    final parts = e.key.split('|__|');
    return {
      'name': parts[0],
      'phone': parts[1].isNotEmpty ? parts[1] : 'No phone provided',
      'amount': e.value,
    };
  }).toList();

  debitsList.sort(
    (a, b) => (b['amount'] as double).compareTo(a['amount'] as double),
  );
  return debitsList;
}
