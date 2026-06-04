import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../services/cloud_service.dart';
import '../theme/app_theme.dart';

enum _WelcomeMode { choice, createShop, joinCloud }

class WelcomeScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const WelcomeScreen({super.key, required this.onComplete});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _shopNameCtrl = TextEditingController();
  final _cloudUrlCtrl = TextEditingController();
  final _anonKeyCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  _WelcomeMode _mode = _WelcomeMode.choice;
  bool _isSaving = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _cloudUrlCtrl.dispose();
    _anonKeyCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveShopName() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await DatabaseHelper.instance.saveShopName(_shopNameCtrl.text);
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Invalid argument: ', '')),
        ),
      );
    }
  }

  Future<void> _joinCloudShop() async {
    setState(() {
      _isSaving = true;
      _message = null;
      _error = null;
    });
    try {
      await CloudService.instance.saveConfig(
        CloudConfig(url: _cloudUrlCtrl.text, anonKey: _anonKeyCtrl.text),
      );
      await CloudService.instance.signIn(
        _emailCtrl.text,
        _passwordCtrl.text,
        syncAfterAuth: false,
      );
      if (!await CloudService.instance.currentUserHasShopMembership()) {
        throw StateError(
          'This account is not added to a shop yet. Ask the owner/admin to add this email, then sign in again.',
        );
      }
      await CloudService.instance.syncNow(reason: 'Joined cloud shop');
      if (!mounted) return;
      widget.onComplete();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = _cleanError(e);
      });
    }
  }

  Future<void> _createCloudAccount() async {
    setState(() {
      _isSaving = true;
      _message = null;
      _error = null;
    });
    try {
      await CloudService.instance.saveConfig(
        CloudConfig(url: _cloudUrlCtrl.text, anonKey: _anonKeyCtrl.text),
      );
      await CloudService.instance.signUp(
        _emailCtrl.text,
        _passwordCtrl.text,
        syncAfterAuth: false,
      );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _message =
            'Account created. Ask the shop owner/admin to add this email as staff, then sign in.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = _cleanError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
            AppSpacing.xxl,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).vertical -
                  AppSpacing.xxl * 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Align(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: AppColors.navy,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      color: AppColors.amber,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  'Welcome to Storely',
                  textAlign: TextAlign.center,
                  style: AppText.display.copyWith(color: AppColors.navy),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _mode == _WelcomeMode.joinCloud
                      ? 'Sign in to join a shop you were added to'
                      : _mode == _WelcomeMode.createShop
                      ? 'Add your shop name to get started'
                      : 'Start a new shop or join an existing cloud shop',
                  textAlign: TextAlign.center,
                  style: AppText.body.copyWith(color: AppColors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.xxxl),
                if (_mode == _WelcomeMode.choice) _choiceActions(),
                if (_mode == _WelcomeMode.createShop) _createShopForm(),
                if (_mode == _WelcomeMode.joinCloud) _joinCloudForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _choiceActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _isSaving
              ? null
              : () => setState(() => _mode = _WelcomeMode.createShop),
          icon: const Icon(Icons.add_business_rounded),
          label: const Text('Start Fresh'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _isSaving
              ? null
              : () => setState(() => _mode = _WelcomeMode.joinCloud),
          icon: const Icon(Icons.cloud_done_outlined),
          label: const Text('Join Existing Shop'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          ),
        ),
      ],
    );
  }

  Widget _createShopForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _shopNameCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: 'Shop Name',
              prefixIcon: Icon(Icons.store_mall_directory_outlined),
            ),
            validator: (value) =>
                value == null || value.trim().isEmpty ? 'Required' : null,
            onFieldSubmitted: (_) => _saveShopName(),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _isSaving ? null : _saveShopName,
          icon: _busyIcon(Icons.arrow_forward_rounded),
          label: const Text('Continue'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          ),
        ),
        TextButton(
          onPressed: _isSaving
              ? null
              : () => setState(() => _mode = _WelcomeMode.choice),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _joinCloudForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cloudUrlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Supabase URL',
            prefixIcon: Icon(Icons.link_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _anonKeyCtrl,
          decoration: const InputDecoration(
            labelText: 'Supabase anon key',
            prefixIcon: Icon(Icons.key_outlined),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.mail_outline_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _passwordCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _WelcomeMessage(text: _error!, isError: true),
        ] else if (_message != null) ...[
          const SizedBox(height: AppSpacing.md),
          _WelcomeMessage(text: _message!),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _isSaving ? null : _joinCloudShop,
          icon: _busyIcon(Icons.login_rounded),
          label: const Text('Sign In and Join'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: _isSaving ? null : _createCloudAccount,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Create Account'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          ),
        ),
        TextButton(
          onPressed: _isSaving
              ? null
              : () => setState(() => _mode = _WelcomeMode.choice),
          child: const Text('Back'),
        ),
      ],
    );
  }

  Widget _busyIcon(IconData icon) {
    return _isSaving
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon);
  }
}

class _WelcomeMessage extends StatelessWidget {
  final String text;
  final bool isError;

  const _WelcomeMessage({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isError
            ? AppColors.error.withValues(alpha: 0.08)
            : AppColors.success.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdRadius,
        border: Border.all(
          color: isError
              ? AppColors.error.withValues(alpha: 0.25)
              : AppColors.success.withValues(alpha: 0.25),
        ),
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          color: isError ? AppColors.error : AppColors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _cleanError(Object error) {
  return error
      .toString()
      .replaceFirst('Invalid argument: ', '')
      .replaceFirst('Bad state: ', '')
      .replaceFirst('AuthException(message: ', '')
      .replaceFirst(RegExp(r', statusCode:.*\)$'), '');
}
