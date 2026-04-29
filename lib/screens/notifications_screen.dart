import 'package:flutter/material.dart';
import '../main.dart';
import '../db/database_helper.dart';

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
    
    // Group by customer
    Map<String, double> debitsMap = {};
    for (var bill in bills) {
      final name = bill.customerName.trim().isNotEmpty ? bill.customerName.trim() : 'Unknown';
      final phone = bill.customerPhone?.trim() ?? '';
      final key = '$name|__|$phone';
      
      debitsMap[key] = (debitsMap[key] ?? 0) + bill.totalAmount;
    }

    // Convert to list
    final debitsList = debitsMap.entries.map((e) {
      final parts = e.key.split('|__|');
      return {
        'name': parts[0],
        'phone': parts[1].isNotEmpty ? parts[1] : 'No phone provided',
        'amount': e.value,
      };
    }).toList();

    // Sort descending by amount
    debitsList.sort((a, b) => (b['amount'] as double).compareTo(a['amount'] as double));

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
      backgroundColor: AppColors.cream,
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _customerDebits.isEmpty
              ? const Center(
                  child: Text(
                    'No notifications are there.',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _customerDebits.length,
                  itemBuilder: (context, index) {
                    final data = _customerDebits[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.error.withValues(alpha: 0.1),
                          child: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
                        ),
                        title: Text(
                          data['name'],
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          data['phone'],
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text(
                              'Pending Due',
                              style: TextStyle(fontSize: 10, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '₹${(data['amount'] as double).toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: AppColors.error,
                              ),
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
