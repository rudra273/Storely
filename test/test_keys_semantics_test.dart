import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/utils/test_keys.dart';

/// Verifies that [TestKeys.tag] actually publishes a semantics `identifier`
/// (the value that surfaces to external UI test tools as Android `resource-id`
/// / iOS `accessibilityIdentifier`) and that it can be located with
/// `find.bySemanticsIdentifier`, the same finder integration tests use.
void main() {
  // Enabling semantics mirrors what an accessibility service / test tool does
  // at runtime; without it the semantics tree is not built.
  late SemanticsHandle handle;

  setUp(() {
    handle = TestWidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  });

  tearDown(() => handle.dispose());

  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('tag exposes a button identifier findable by test tools', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      wrap(
        TestKeys.tag(
          TestKeys.createBillBtn,
          FilledButton(
            onPressed: () => tapped = true,
            child: const Text('New Bill'),
          ),
          button: true,
        ),
      ),
    );

    // Found by its stable identifier, independent of the visible label.
    expect(find.bySemanticsIdentifier(TestKeys.createBillBtn), findsOneWidget);

    // And it is still the real, tappable button.
    await tester.tap(find.bySemanticsIdentifier(TestKeys.createBillBtn));
    expect(tapped, isTrue);
  });

  testWidgets('tag exposes a text-field identifier', (tester) async {
    await tester.pumpWidget(
      wrap(
        TestKeys.tag(
          TestKeys.productSearchField,
          const TextField(),
          textField: true,
        ),
      ),
    );

    expect(
      find.bySemanticsIdentifier(TestKeys.productSearchField),
      findsOneWidget,
    );
  });

  testWidgets('dynamic per-row identifiers are unique and findable', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: [
            TestKeys.tag(TestKeys.productRow(1), const Text('Item 1')),
            TestKeys.tag(TestKeys.productRow(2), const Text('Item 2')),
          ],
        ),
      ),
    );

    expect(find.bySemanticsIdentifier('product_row_1'), findsOneWidget);
    expect(find.bySemanticsIdentifier('product_row_2'), findsOneWidget);
    expect(find.bySemanticsIdentifier('product_row_3'), findsNothing);
  });

  test('id constants follow the expected naming convention', () {
    expect(TestKeys.navHome, 'nav_home');
    expect(TestKeys.productRow(42), 'product_row_42');
    expect(TestKeys.billRow('INV-9'), 'bill_row_INV-9');
  });
}
