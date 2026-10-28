import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/config/cloud_defaults.dart';
import 'package:storely/l10n/app_localizations.dart';
import 'package:storely/screens/welcome_screen.dart';

void main() {
  testWidgets(
    'cloud onboarding cannot enable cloud in the default offline build',
    (tester) async {
      expect(CloudDefaults.isAvailable, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: WelcomeScreen(onComplete: () {}),
        ),
      );
      await tester.tap(find.text('Join Existing Shop'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You can use Storely offline.'),
        findsOneWidget,
      );
      final signIn = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Sign In and Join'),
      );
      expect(signIn.onPressed, isNull);
      expect(find.byType(TextField), findsNWidgets(2)); // email/password only
    },
  );
}
