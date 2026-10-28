import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/cloud/account_actions.dart';
import '../../services/cloud_service.dart';
import '../../theme/app_theme.dart';

/// Turns an exception into a sentence for the person using the app.
String accountErrorText(Object error) => error
    .toString()
    .replaceFirst('Exception: ', '')
    .replaceFirst('Bad state: ', '')
    .replaceFirst('Invalid argument(s): ', '')
    .trim();

AccountActions _defaultActions() => CloudService.instance;

/// Asks for the 6-digit code that was emailed, and confirms the address.
/// Returns true once the address is confirmed.
Future<bool> showEmailCodeDialog(
  BuildContext context, {
  required String email,
  AccountActions? actions,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) =>
        EmailCodeDialog(email: email, actions: actions ?? _defaultActions()),
  );
  return confirmed ?? false;
}

/// Asks for an authenticator (or recovery) code to finish signing in.
Future<bool> showMfaDialog(
  BuildContext context, {
  bool syncAfterAuth = true,
  AccountActions? actions,
}) async {
  final done = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => MfaDialog(
      syncAfterAuth: syncAfterAuth,
      actions: actions ?? _defaultActions(),
    ),
  );
  return done ?? false;
}

/// Emails a reset code, then sets a new password. Returns true when changed.
Future<bool> showResetPasswordDialog(
  BuildContext context, {
  String email = '',
  AccountActions? actions,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ResetPasswordDialog(
      initialEmail: email,
      actions: actions ?? _defaultActions(),
    ),
  );
  return changed ?? false;
}

/// Signs in, and walks through whatever the account needs first: confirming the
/// email address, or a second-factor code. Returns true when signed in, false if
/// the person backed out. Any other failure is thrown for the caller to show.
Future<bool> signInWithChallenges(
  BuildContext context, {
  required String email,
  required String password,
  bool syncAfterAuth = true,
  AccountActions? actions,
}) async {
  final account = actions ?? _defaultActions();
  var confirmedOnce = false;
  while (true) {
    try {
      await account.signIn(email, password, syncAfterAuth: syncAfterAuth);
      return true;
    } on CloudMfaRequired {
      if (!context.mounted) return false;
      return showMfaDialog(
        context,
        syncAfterAuth: syncAfterAuth,
        actions: account,
      );
    } on CloudEmailNotVerified catch (needsCode) {
      if (confirmedOnce || !context.mounted) rethrow;
      final confirmed = await showEmailCodeDialog(
        context,
        email: needsCode.email,
        actions: account,
      );
      if (!confirmed) return false;
      confirmedOnce = true; // then sign in again with the confirmed address
    }
  }
}

class EmailCodeDialog extends StatefulWidget {
  final String email;
  final AccountActions actions;

  const EmailCodeDialog({
    super.key,
    required this.email,
    required this.actions,
  });

  @override
  State<EmailCodeDialog> createState() => _EmailCodeDialogState();
}

class _EmailCodeDialogState extends State<EmailCodeDialog> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.actions.verifyEmail(widget.email, code);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountErrorText(error);
      });
    }
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      await widget.actions.resendVerificationCode(widget.email);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _info =
            'If the last code is more than a minute old, a new one is on its way.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountErrorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm your email'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('We sent a 6-digit code to ${widget.email}.'),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('account-code-field'),
            controller: _codeCtrl,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: 'Code',
              prefixIcon: const Icon(Icons.pin_outlined),
              errorText: _error,
              helperText: _info,
              helperMaxLines: 3,
            ),
            onSubmitted: (_) => _busy ? null : _verify(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('account-code-resend'),
          onPressed: _busy ? null : _resend,
          child: const Text('Send a new code'),
        ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('account-code-verify'),
          onPressed: _busy ? null : _verify,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class MfaDialog extends StatefulWidget {
  final bool syncAfterAuth;
  final AccountActions actions;

  const MfaDialog({
    super.key,
    required this.syncAfterAuth,
    required this.actions,
  });

  @override
  State<MfaDialog> createState() => _MfaDialogState();
}

class _MfaDialogState extends State<MfaDialog> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Enter the code from your authenticator app.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.actions.completeMfa(
        code,
        syncAfterAuth: widget.syncAfterAuth,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountErrorText(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Two-step verification'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the 6-digit code from your authenticator app, or one of '
            'your recovery codes.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('account-code-field'),
            controller: _codeCtrl,
            autofocus: true,
            enabled: !_busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            inputFormatters: [LengthLimitingTextInputFormatter(12)],
            decoration: InputDecoration(
              labelText: 'Code',
              prefixIcon: const Icon(Icons.verified_user_outlined),
              errorText: _error,
            ),
            onSubmitted: (_) => _busy ? null : _verify(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('account-code-verify'),
          onPressed: _busy ? null : _verify,
          child: const Text('Verify'),
        ),
      ],
    );
  }
}

class ResetPasswordDialog extends StatefulWidget {
  final String initialEmail;
  final AccountActions actions;

  const ResetPasswordDialog({
    super.key,
    required this.initialEmail,
    required this.actions,
  });

  @override
  State<ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<ResetPasswordDialog> {
  late final _emailCtrl = TextEditingController(text: widget.initialEmail);
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = accountErrorText(error);
      });
    }
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter the email address of your account.');
      return;
    }
    await _run(() async {
      await widget.actions.forgotPassword(email);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _change() async {
    if (_codeCtrl.text.trim().length != 6) {
      setState(() => _error = 'Enter the 6-digit code from the email.');
      return;
    }
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Choose a new password.');
      return;
    }
    await _run(() async {
      await widget.actions.resetPassword(
        _emailCtrl.text.trim(),
        _codeCtrl.text.trim(),
        _passwordCtrl.text,
      );
      if (mounted) Navigator.pop(context, true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Reset your password'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _codeSent
                ? 'If that email has an account, a code is on its way. Enter it '
                      'with your new password.'
                : 'We will email you a 6-digit code.',
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('reset-email-field'),
            controller: _emailCtrl,
            enabled: !_busy && !_codeSent,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline_rounded),
            ),
          ),
          if (_codeSent) ...[
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('account-code-field'),
              controller: _codeCtrl,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                labelText: 'Code',
                prefixIcon: Icon(Icons.pin_outlined),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('reset-password-field'),
              controller: _passwordCtrl,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                prefixIcon: Icon(Icons.lock_outline_rounded),
                helperText: 'At least 8 characters.',
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              key: const Key('account-dialog-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('account-dialog-submit'),
          onPressed: _busy ? null : (_codeSent ? _change : _sendCode),
          child: Text(_codeSent ? 'Change password' : 'Send code'),
        ),
      ],
    );
  }
}
