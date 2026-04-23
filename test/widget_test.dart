import 'package:flutter_test/flutter_test.dart';
import 'package:storely/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const StorelyApp());
    expect(find.byType(StorelyApp), findsOneWidget);
  });
}
