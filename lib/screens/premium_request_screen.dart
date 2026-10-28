import 'package:flutter/material.dart';

import '../config/cloud_defaults.dart';
import '../db/database_helper.dart';
import '../services/cloud/premium_request_service.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';
import 'shared/cloud_account_dialogs.dart';

class PremiumRequestScreen extends StatefulWidget {
  const PremiumRequestScreen({
    super.key,
    this.requests,
    this.shopId,
    this.shopName,
  });
  final PremiumRequestService? requests;
  final String? shopId;
  final String? shopName;
  @override
  State<PremiumRequestScreen> createState() => _PremiumRequestScreenState();
}

class _PremiumRequestScreenState extends State<PremiumRequestScreen> {
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _consent = false;
  bool _uploadConsent = false;
  bool _busy = false;
  bool _loading = true;
  String? _error;
  String? _message;
  String? _shopId;
  String _shopName = '';
  Map<String, dynamic>? _draft;
  bool get _available => widget.requests != null || CloudDefaults.isAvailable;
  PremiumRequestService get _requests =>
      widget.requests ?? PremiumRequestService.instance;
  String? get _status => (_draft?['response'] as Map?)?['status'] as String?;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _shopId = widget.shopId ?? await DatabaseHelper.instance.currentShopId();
      _shopName =
          widget.shopName ??
          (await DatabaseHelper.instance.getShopProfile())?.name ??
          'My shop';
      final draft = _available ? await _requests.load() : null;
      if (!mounted) return;
      setState(() {
        _draft = draft;
        final body = draft?['body'] as Map?;
        _contact.text = body?['contact_name']?.toString() ?? '';
        _phone.text = body?['phone']?.toString() ?? '';
        _consent = body != null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = accountErrorText(error);
      });
    }
  }

  @override
  void dispose() {
    for (final c in [_contact, _phone, _email, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = accountErrorText(error));
    } finally {
      if (mounted) {
        try {
          final draft = _available ? await _requests.load() : null;
          if (mounted) setState(() => _draft = draft);
        } catch (error) {
          if (mounted) setState(() => _error = accountErrorText(error));
        }
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate() || !_consent) return;
    await _run(() async {
      await _requests.submit(
        shopId: _shopId!,
        shopName: _shopName,
        contactName: _contact.text,
        phone: _phone.text,
      );
    });
  }

  Future<void> _signIn() => _run(() async {
    await CloudService.instance.useStorelyCloud();
    if (!mounted) return;
    final done = await signInWithChallenges(
      context,
      email: _email.text,
      password: _password.text,
      syncAfterAuth: false,
    );
    if (done && mounted) {
      setState(
        () => _message = 'Signed in. Confirm the backup and upload below.',
      );
    }
  });
  Future<void> _signUp() => _run(() async {
    await CloudService.instance.useStorelyCloud();
    final result = await CloudService.instance.signUp(
      _email.text,
      _password.text,
      syncAfterAuth: false,
    );
    if (!mounted) return;
    if (result == SignUpOutcome.emailCodeSent) {
      final confirmed = await showEmailCodeDialog(
        context,
        email: _email.text.trim(),
      );
      if (mounted) {
        setState(
          () => _message = confirmed
              ? 'Email verified. Tell our team this email for approval, then sign in.'
              : 'Check your email to finish verification.',
        );
      }
    }
  });

  @override
  Widget build(BuildContext context) {
    final hasDraft = _draft != null && _status != 'rejected';
    return Scaffold(
      appBar: AppBar(title: const Text('Request Premium')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(_shopName, style: AppText.title),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Premium adds Storely Cloud and web access. Free use keeps your business data on this phone.',
                ),
                const SizedBox(height: AppSpacing.md),
                if (!_available)
                  const Text(
                    'Requests need an internet connection and a configured Storely service. You can keep using the app offline.',
                  ),
                if (_draft != null)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _status == null
                              ? 'Not sent — retry your saved request'
                              : 'Request: ${_status!}',
                          style: AppText.body,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Reference: ${(_draft!['body'] as Map)['id']}',
                          style: AppText.caption,
                        ),
                        if (_status == 'pending' || _status == 'contacted')
                          const Text(
                            'Our team will contact you on the number provided. Your business data stays on this phone.',
                          ),
                        if (_status == 'rejected')
                          const Text(
                            'The request was declined. Contact our team or send a new request.',
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                if (_status == null || _status == 'rejected')
                  Form(
                    key: _form,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _contact,
                          enabled: !hasDraft && !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Contact name',
                          ),
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Enter a contact name'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _phone,
                          enabled: !hasDraft && !_busy,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Phone with country code',
                            hintText: '+919876543210',
                          ),
                          validator: (v) =>
                              RegExp(
                                r'^\+[1-9][0-9]{7,14}$',
                              ).hasMatch((v ?? '').trim())
                              ? null
                              : 'Use a country code, for example +919876543210',
                        ),
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _consent,
                          onChanged: _busy || hasDraft
                              ? null
                              : (v) => setState(() => _consent = v ?? false),
                          title: const Text(
                            'I agree to be contacted about Storely Premium.',
                          ),
                        ),
                        FilledButton(
                          onPressed: !_available || _busy || !_consent
                              ? null
                              : _submit,
                          child: Text(
                            hasDraft
                                ? 'Retry saved request'
                                : 'Send premium request',
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_status != null)
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await _requests.refresh();
                          }),
                    child: const Text('Refresh request status'),
                  ),
                if (_status == 'pending' ||
                    _status == 'contacted' ||
                    _status == 'approved' ||
                    _status == 'activated') ...[
                  const SizedBox(height: AppSpacing.lg),
                  const Text(
                    'Create and verify an email account, then tell our team which email to approve. Use that account to activate this shop.',
                  ),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Account email',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton(
                    onPressed: _busy ? null : _signUp,
                    child: const Text('Create and verify account'),
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _signIn,
                    child: const Text('Sign in with approved account'),
                  ),
                ],
                if (_status == 'approved' || _status == 'activated') ...[
                  const SizedBox(height: AppSpacing.lg),
                  ValueListenableBuilder<CloudState>(
                    valueListenable: CloudService.instance.state,
                    builder: (context, state, _) => Text(
                      state.user == null
                          ? 'Sign in before activating.'
                          : 'Signed in as ${state.user!.email}',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'Activation creates a backup on this phone, then uploads your existing products, bills and store data. Held carts and drafts are backed up with their device ownership. Printer and security settings stay on this phone. Interrupted uploads can be retried.',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _uploadConsent,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _uploadConsent = v ?? false),
                    title: const Text(
                      'Create a local backup and upload my existing business data.',
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy || !_uploadConsent
                        ? null
                        : () => _run(() async {
                            await CloudService.instance.activatePremium();
                            if (mounted) {
                              setState(
                                () => _message =
                                    CloudService.instance.state.value.message,
                              );
                            }
                          }),
                    child: const Text('Back up and activate premium'),
                  ),
                ],
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(_message!),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
    );
  }
}
