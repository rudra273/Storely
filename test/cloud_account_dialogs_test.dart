import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/screens/shared/cloud_account_dialogs.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/cloud/account_actions.dart';
import 'package:storely/services/cloud_service.dart';

class FakeActions implements AccountActions {
  final log = <String>[];

  /// What each call to signIn does, in order: null = succeed, else throw it.
  final signInScript = <Object?>[];
  Object? verifyError;
  Object? mfaError;
  Object? resetError;
  bool lastSyncFlag = true;

  @override
  Future<void> signIn(
    String email,
    String password, {
    bool syncAfterAuth = true,
  }) async {
    log.add('signIn $email');
    lastSyncFlag = syncAfterAuth;
    final next = signInScript.isEmpty ? null : signInScript.removeAt(0);
    if (next != null) throw next;
  }

  @override
  Future<void> completeMfa(String code, {bool syncAfterAuth = true}) async {
    log.add('mfa $code');
    lastSyncFlag = syncAfterAuth;
    if (mfaError != null) throw mfaError!;
  }

  @override
  Future<void> verifyEmail(String email, String code) async {
    log.add('verify $email $code');
    if (verifyError != null) throw verifyError!;
  }

  @override
  Future<void> resendVerificationCode(String email) async =>
      log.add('resend $email');

  @override
  Future<void> forgotPassword(String email) async => log.add('forgot $email');

  @override
  Future<void> resetPassword(String email, String code, String pw) async {
    log.add('reset $email $code');
    if (resetError != null) throw resetError!;
  }
}

const wrongCode = ApiException(
  400,
  'invalid_code',
  'That code is wrong or has expired.',
);

/// Opens [open] from a button and records what it returned.
Future<void> pumpOpener(
  WidgetTester tester,
  Future<Object?> Function(BuildContext) open,
  List<Object?> results,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => results.add(await open(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> typeCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(const Key('account-code-field')), code);
  await tester.pump();
}

void main() {
  group('email code dialog', () {
    testWidgets('a short code is refused without asking the server', (
      tester,
    ) async {
      final actions = FakeActions();
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showEmailCodeDialog(c, email: 'a@b.com', actions: actions),
        results,
      );
      await typeCode(tester, '123');
      await tester.tap(find.byKey(const Key('account-code-verify')));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter the 6-digit code from the email.'),
        findsOneWidget,
      );
      expect(actions.log, isEmpty);
      expect(results, isEmpty); // still open
    });

    testWidgets('a wrong code shows the server\'s message and stays open', (
      tester,
    ) async {
      final actions = FakeActions()..verifyError = wrongCode;
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showEmailCodeDialog(c, email: 'a@b.com', actions: actions),
        results,
      );
      await typeCode(tester, '000000');
      await tester.tap(find.byKey(const Key('account-code-verify')));
      await tester.pumpAndSettle();

      expect(find.text('That code is wrong or has expired.'), findsOneWidget);
      expect(results, isEmpty);
    });

    testWidgets('the right code confirms and closes with true', (tester) async {
      final actions = FakeActions();
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showEmailCodeDialog(c, email: 'a@b.com', actions: actions),
        results,
      );
      await typeCode(tester, '123456');
      await tester.tap(find.byKey(const Key('account-code-verify')));
      await tester.pumpAndSettle();

      expect(actions.log, ['verify a@b.com 123456']);
      expect(results, [true]);
    });

    testWidgets('only digits are accepted, at most six', (tester) async {
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showEmailCodeDialog(c, email: 'a@b.com', actions: FakeActions()),
        results,
      );
      await typeCode(tester, '12ab34567890');
      final field = tester.widget<TextField>(
        find.byKey(const Key('account-code-field')),
      );
      expect(field.controller!.text, '123456');
    });

    testWidgets('asking for a new code says what to expect', (tester) async {
      final actions = FakeActions();
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showEmailCodeDialog(c, email: 'a@b.com', actions: actions),
        results,
      );
      await tester.tap(find.byKey(const Key('account-code-resend')));
      await tester.pumpAndSettle();

      expect(actions.log, ['resend a@b.com']);
      expect(find.textContaining('a new one is on its way'), findsOneWidget);
    });

    testWidgets('cancel closes with false', (tester) async {
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showEmailCodeDialog(c, email: 'a@b.com', actions: FakeActions()),
        results,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });
  });

  group('two-step dialog', () {
    testWidgets(
      'accepts an authenticator or a recovery code and passes the sync flag',
      (tester) async {
        final actions = FakeActions();
        final results = <Object?>[];
        await pumpOpener(
          tester,
          (c) => showMfaDialog(c, syncAfterAuth: false, actions: actions),
          results,
        );
        await typeCode(tester, 'abcde-fghjk');
        await tester.tap(find.byKey(const Key('account-code-verify')));
        await tester.pumpAndSettle();

        expect(actions.log, ['mfa abcde-fghjk']);
        expect(actions.lastSyncFlag, isFalse);
        expect(results, [true]);
      },
    );

    testWidgets('a wrong code is explained and the dialog stays', (
      tester,
    ) async {
      final actions = FakeActions()
        ..mfaError = const ApiException(
          401,
          'invalid_mfa_code',
          'That code is wrong or has expired.',
        );
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showMfaDialog(c, actions: actions),
        results,
      );
      await typeCode(tester, '000000');
      await tester.tap(find.byKey(const Key('account-code-verify')));
      await tester.pumpAndSettle();
      expect(find.text('That code is wrong or has expired.'), findsOneWidget);
      expect(results, isEmpty);
    });
  });

  group('reset password dialog', () {
    testWidgets('asks for an email first, then the code and a new password', (
      tester,
    ) async {
      final actions = FakeActions();
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showResetPasswordDialog(c, email: 'a@b.com', actions: actions),
        results,
      );
      expect(find.byKey(const Key('reset-password-field')), findsNothing);
      await tester.tap(find.byKey(const Key('account-dialog-submit')));
      await tester.pumpAndSettle();
      expect(actions.log, ['forgot a@b.com']);
      expect(find.byKey(const Key('reset-password-field')), findsOneWidget);

      await typeCode(tester, '654321');
      await tester.enterText(
        find.byKey(const Key('reset-password-field')),
        'a-brand-new-passphrase',
      );
      await tester.tap(find.byKey(const Key('account-dialog-submit')));
      await tester.pumpAndSettle();

      expect(actions.log.last, 'reset a@b.com 654321');
      expect(results, [true]);
    });

    testWidgets('an email without an @ is not sent anywhere', (tester) async {
      final actions = FakeActions();
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showResetPasswordDialog(c, email: 'nonsense', actions: actions),
        results,
      );
      await tester.tap(find.byKey(const Key('account-dialog-submit')));
      await tester.pumpAndSettle();
      expect(actions.log, isEmpty);
      expect(find.byKey(const Key('account-dialog-error')), findsOneWidget);
    });

    testWidgets('a weak new password shows the server\'s advice', (
      tester,
    ) async {
      final actions = FakeActions()
        ..resetError = const ApiException(
          422,
          'weak_password',
          'This is a top-10 common password. Try a longer, less common phrase.',
        );
      final results = <Object?>[];
      await pumpOpener(
        tester,
        (c) => showResetPasswordDialog(c, email: 'a@b.com', actions: actions),
        results,
      );
      await tester.tap(find.byKey(const Key('account-dialog-submit')));
      await tester.pumpAndSettle();
      await typeCode(tester, '654321');
      await tester.enterText(
        find.byKey(const Key('reset-password-field')),
        'password123',
      );
      await tester.tap(find.byKey(const Key('account-dialog-submit')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Try a longer, less common phrase'),
        findsOneWidget,
      );
      expect(results, isEmpty);
    });
  });

  group('signing in through the challenges', () {
    Future<(List<Object?>, FakeActions)> run(
      WidgetTester tester,
      FakeActions actions,
    ) async {
      final results = <Object?>[];
      await pumpOpener(tester, (c) async {
        try {
          return await signInWithChallenges(
            c,
            email: 'a@b.com',
            password: 'pw',
            syncAfterAuth: false,
            actions: actions,
          );
        } catch (error) {
          return error;
        }
      }, results);
      return (results, actions);
    }

    testWidgets('a plain account signs straight in, no dialogs', (
      tester,
    ) async {
      final (results, actions) = await run(tester, FakeActions());
      expect(results, [true]);
      expect(actions.log, ['signIn a@b.com']);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('two-step: asks for the code, then is signed in', (
      tester,
    ) async {
      final actions = FakeActions()..signInScript.add(const CloudMfaRequired());
      await run(tester, actions);
      expect(find.text('Two-step verification'), findsOneWidget);
      await typeCode(tester, '123456');
      await tester.tap(find.byKey(const Key('account-code-verify')));
      await tester.pumpAndSettle();
      expect(actions.log, ['signIn a@b.com', 'mfa 123456']);
    });

    testWidgets('backing out of two-step means not signed in', (tester) async {
      final actions = FakeActions()..signInScript.add(const CloudMfaRequired());
      final (results, _) = await run(tester, actions);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
    });

    testWidgets('an unconfirmed address: confirm it, then sign in again', (
      tester,
    ) async {
      final actions = FakeActions()
        ..signInScript.add(const CloudEmailNotVerified('a@b.com'));
      final (results, _) = await run(tester, actions);
      expect(find.text('Confirm your email'), findsOneWidget);
      await typeCode(tester, '123456');
      await tester.tap(find.byKey(const Key('account-code-verify')));
      await tester.pumpAndSettle();

      expect(actions.log, [
        'signIn a@b.com',
        'verify a@b.com 123456',
        'signIn a@b.com',
      ]);
      expect(results, [true]);
    });

    testWidgets('declining to confirm the address means not signed in', (
      tester,
    ) async {
      final actions = FakeActions()
        ..signInScript.add(const CloudEmailNotVerified('a@b.com'));
      final (results, _) = await run(tester, actions);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(results, [false]);
      expect(actions.log, ['signIn a@b.com']);
    });

    testWidgets(
      'it never loops: still unconfirmed after confirming is an error',
      (tester) async {
        final actions = FakeActions()
          ..signInScript.addAll([
            const CloudEmailNotVerified('a@b.com'),
            const CloudEmailNotVerified('a@b.com'),
          ]);
        final (results, _) = await run(tester, actions);
        await typeCode(tester, '123456');
        await tester.tap(find.byKey(const Key('account-code-verify')));
        await tester.pumpAndSettle();
        expect(results.single, isA<CloudEmailNotVerified>());
      },
    );

    testWidgets('a wrong password is passed up for the screen to show', (
      tester,
    ) async {
      final actions = FakeActions()
        ..signInScript.add(
          const ApiException(
            401,
            'invalid_credentials',
            'Email or password is incorrect.',
          ),
        );
      final (results, _) = await run(tester, actions);
      expect(results.single, isA<ApiException>());
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
