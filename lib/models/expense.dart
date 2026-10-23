/// Money spent running the shop (rent, salary, tea, transport...).
class Expense {
  static const categories = [
    'Rent',
    'Salary',
    'Electricity',
    'Transport',
    'Tea & snacks',
    'Repairs',
    'Phone & internet',
    'Other',
  ];

  final int? id;
  final String uuid;

  /// Business day, local time (yyyy-MM-ddTHH:mm:ss).
  final DateTime date;
  final double amount;
  final String category;

  /// 'cash', 'upi', 'card' or 'bank' — only cash affects the closing cash.
  final String paymentMethod;
  final String? notes;

  const Expense({
    this.id,
    this.uuid = '',
    required this.date,
    required this.amount,
    this.category = 'Other',
    this.paymentMethod = 'cash',
    this.notes,
  });

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
    id: map['id'] as int?,
    uuid: map['uuid'] as String? ?? '',
    date: DateTime.parse(map['expense_date'] as String),
    amount: (map['amount'] as num).toDouble(),
    category: map['category'] as String? ?? 'Other',
    paymentMethod: map['payment_method'] as String? ?? 'cash',
    notes: map['notes'] as String?,
  );
}
