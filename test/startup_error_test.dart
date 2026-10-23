import 'package:flutter_test/flutter_test.dart';
import 'package:storely/screens/startup_error_screen.dart';

void main() {
  testWidgets('startup error offers retry and shows the error', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      StartupErrorApp(
        error: StateError('database disk image is malformed'),
        onRetry: () async => retries++,
      ),
    );
    expect(find.text('Storely could not start'), findsOneWidget);
    expect(find.textContaining('malformed'), findsOneWidget);
    expect(find.text('Save a copy of my data'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(retries, 1);
  });
}
