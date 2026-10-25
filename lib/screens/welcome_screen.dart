import 'package:flutter/material.dart';
import '../config/cloud_defaults.dart';
import '../db/database_helper.dart';
import '../services/cloud_service.dart';
import 'shared/cloud_account_dialogs.dart';
import '../theme/app_theme.dart';
import '../utils/test_keys.dart';
import '../l10n/l10n.dart';
import '../services/app_settings_service.dart';
import '../services/sample_data.dart';

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
  bool _addSampleData = false;

  /// Reveals the "use your own Supabase" fields in the join flow. Forced open
  /// when the bundled Storely Cloud credentials aren't compiled into the build.
  bool _showAdvanced = !CloudDefaults.isAvailable;
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
      if (_addSampleData) await SampleData.addProducts();
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

  /// Configure the cloud backend before sign in/up: bundled Storely Cloud by
  /// default, or the user-entered Supabase project when the advanced fields are
  /// shown.
  Future<void> _configureBackend() {
    if (_showAdvanced) {
      return CloudService.instance.saveConfig(
        CloudConfig(url: _cloudUrlCtrl.text, anonKey: _anonKeyCtrl.text),
      );
    }
    return CloudService.instance.useStorelyCloud();
  }

  Future<void> _joinCloudShop() async {
    setState(() {
      _isSaving = true;
      _message = null;
      _error = null;
    });
    try {
      await _configureBackend();
      if (!mounted) return;
      final signedIn = await signInWithChallenges(
        context,
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
        syncAfterAuth: false,
      );
      if (!signedIn) {
        if (mounted) setState(() => _isSaving = false);
        return;
      }
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
      await _configureBackend();
      final outcome = await CloudService.instance.signUp(
        _emailCtrl.text,
        _passwordCtrl.text,
        syncAfterAuth: false,
      );
      var confirmed = false;
      if (outcome == SignUpOutcome.emailCodeSent && mounted) {
        confirmed = await showEmailCodeDialog(
          context,
          email: _emailCtrl.text.trim(),
        );
      }
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _message = switch (outcome) {
          SignUpOutcome.emailCodeSent when !confirmed =>
            'Account created. Confirm your email with the code we sent, then ask the shop owner/admin to add this email as staff.',
          _ =>
            'Account created. Ask the shop owner/admin to add this email as staff, then sign in.',
        };
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = _cleanError(e);
      });
    }
  }

  Future<void> _forgotPassword() async {
    setState(() {
      _isSaving = true;
      _message = null;
      _error = null;
    });
    try {
      await _configureBackend();
      if (!mounted) return;
      final changed = await showResetPasswordDialog(
        context,
        email: _emailCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        if (changed) _message = 'Password changed. Sign in with your new one.';
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
              // Minus the keyboard, so the form (and Continue) stays above it.
              minHeight:
                  MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).vertical -
                  MediaQuery.viewInsetsOf(context).bottom -
                  AppSpacing.xxl * 2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_mode == _WelcomeMode.choice) ...[
                  const _LanguageChoice(),
                  const SizedBox(height: AppSpacing.xl),
                ],
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
                  context.l10n.welcomeTitle,
                  textAlign: TextAlign.center,
                  style: AppText.display.copyWith(
                    color: AppColors.inkOf(context),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _mode == _WelcomeMode.joinCloud
                      ? context.l10n.welcomeJoin
                      : _mode == _WelcomeMode.createShop
                      ? context.l10n.welcomeCreate
                      : context.l10n.welcomeChoice,
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
          label: Text(context.l10n.startFresh),
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
          label: Text(context.l10n.joinExistingShop),
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
          child: TestKeys.tag(
            TestKeys.welcomeShopNameField,
            TextFormField(
              controller: _shopNameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: context.l10n.shopName,
                prefixIcon: Icon(Icons.store_mall_directory_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? context.l10n.required
                  : null,
              onFieldSubmitted: (_) => _saveShopName(),
            ),
            textField: true,
          ),
        ),
        CheckboxListTile(
          key: const ValueKey('welcome-sample-data'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _addSampleData,
          onChanged: _isSaving
              ? null
              : (value) => setState(() => _addSampleData = value ?? false),
          title: Text(context.l10n.addSampleProducts),
          subtitle: Text(
            context.l10n.sampleProductsHint,
            style: AppText.caption,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TestKeys.tag(
          TestKeys.welcomeContinueBtn,
          FilledButton.icon(
            onPressed: _isSaving ? null : _saveShopName,
            icon: _busyIcon(Icons.arrow_forward_rounded),
            label: Text(context.l10n.continueLabel),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            ),
          ),
          button: true,
        ),
        TextButton(
          onPressed: _isSaving
              ? null
              : () => setState(() => _mode = _WelcomeMode.choice),
          child: Text(context.l10n.back),
        ),
      ],
    );
  }

  Widget _joinCloudForm() {
    final storelyCloudAvailable = CloudDefaults.isAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showAdvanced) ...[
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
        ],
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
        if (CloudDefaults.apiAvailable && !_showAdvanced)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('welcome-forgot-password'),
              onPressed: _isSaving ? null : _forgotPassword,
              child: const Text('Forgot password?'),
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
        if (storelyCloudAvailable)
          TextButton.icon(
            onPressed: _isSaving
                ? null
                : () => setState(() => _showAdvanced = !_showAdvanced),
            icon: Icon(
              _showAdvanced ? Icons.expand_less_rounded : Icons.tune_rounded,
              size: 18,
            ),
            style: TextButton.styleFrom(foregroundColor: AppColors.inkMuted),
            label: const Text('Advanced — use your own Supabase'),
          ),
        TextButton(
          onPressed: _isSaving
              ? null
              : () => setState(() => _mode = _WelcomeMode.choice),
          child: Text(context.l10n.back),
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

/// English / Hindi switch shown on the first screen.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice();

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsService.instance;
    final current = settings.language == AppLanguage.system
        ? (Localizations.localeOf(context).languageCode == 'hi'
              ? AppLanguage.hindi
              : AppLanguage.english)
        : settings.language;
    return Center(
      child: SegmentedButton<AppLanguage>(
        key: const ValueKey('welcome-language'),
        segments: const [
          ButtonSegment(value: AppLanguage.english, label: Text('English')),
          ButtonSegment(value: AppLanguage.hindi, label: Text('हिन्दी')),
        ],
        selected: {current},
        showSelectedIcon: false,
        onSelectionChanged: (value) => settings.setLanguage(value.first),
      ),
    );
  }
}
