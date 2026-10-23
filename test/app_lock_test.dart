import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storely/screens/app_lock_gate.dart';
import 'package:storely/services/app_settings_service.dart';

void main() {
  final navigatorKey = GlobalKey<NavigatorState>();
  var taps = 0;

  Widget app() => MaterialApp(
    navigatorKey: navigatorKey,
    builder: (context, child) =>
        AppLockGate(navigatorKey: navigatorKey, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('Customer profits'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('Open customers'),
          ),
        ),
      ),
    ),
  );

  setUp(() async {
    taps = 0;
    SharedPreferences.setMockInitialValues({});
    await AppSettingsService.instance.load();
    await AppSettingsService.instance.setAppLockEnabled(false);
  });

  testWidgets('lock covers pushed screens and keeps them for after unlock', (
    tester,
  ) async {
    await tester.pumpWidget(app());
    await tester.tap(find.text('Open customers'));
    await tester.pumpAndSettle();
    expect(find.text('Customer profits'), findsOneWidget);

    await AppSettingsService.instance.setAppLockEnabled(true);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    // Frames resume (and the lock first shows) when the app comes back.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    // The biometric prompt is pending (spinner), so pump a fixed time.
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Storely Locked'), findsOneWidget);
    // The screen underneath cannot be used while locked.
    await tester.tap(find.text('Customer profits'), warnIfMissed: false);
    expect(taps, 0);

    // Android back does not pop the hidden screen.
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 300));

    // Unlock (here by turning the lock off; on a device via biometrics).
    await AppSettingsService.instance.setAppLockEnabled(false);
    await tester.pumpAndSettle();
    expect(find.text('Storely Locked'), findsNothing);
    expect(find.text('Customer profits'), findsOneWidget);
    await tester.tap(find.text('Customer profits'));
    expect(taps, 1);
  });
}
