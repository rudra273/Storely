import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../db/database_helper.dart';
import '../models/supplier.dart';
import '../services/cloud_service.dart';

/// Standalone Suppliers page, opened from the Home → Workspace "Suppliers" tile.
///
/// View-only for staff: the supplier list is always visible, but Add/Edit/Delete
/// are hidden when the signed-in cloud user is not an owner/admin (those writes
/// are admin-gated in the DB layer and would otherwise throw). The Settings →
/// Suppliers manager is intentionally left untouched.
class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  List<SupplierProfile> _suppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final suppliers = await DatabaseHelper.instance.getSupplierProfiles();
      if (!mounted) return;
      setState(() {
        _suppliers = suppliers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not load suppliers: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addSupplier() async {
    final result = await showModalBottomSheet<SupplierProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SupplierEditorSheet(),
    );
    if (result == null) return;
    await _save(() => DatabaseHelper.instance.saveSupplierProfile(result));
  }

  Future<void> _editSupplier(SupplierProfile supplier) async {
    final result = await showModalBottomSheet<SupplierProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupplierEditorSheet(supplier: supplier),
    );
    if (result == null) return;
    await _save(
      () => DatabaseHelper.instance.saveSupplierProfile(
        result,
        oldName: supplier.name,
      ),
    );
  }

  Future<void> _deleteSupplier(SupplierProfile supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 34),
        title: const Text('Delete Supplier'),
        content: Text('Remove "${supplier.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _save(
      () => DatabaseHelper.instance.deleteSupplierOption(supplier.name),
    );
  }

  /// Runs a write, then reloads. Surfaces failures (e.g. the admin-only guard)
  /// instead of swallowing them.
  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to cloud state so Add/Edit/Delete actions appear the moment the
    // user's role resolves on startup — otherwise isAdmin is read once (null
    // role → false) and the buttons only show after a sync round-trip + reopen.
    return ValueListenableBuilder<CloudState>(
      valueListenable: CloudService.instance.state,
      builder: (context, cloudState, _) {
        final canManage = cloudState.isAdmin;
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: navyAppBar(title: 'Suppliers'),
          // Hidden when the list is empty — the centered empty-state button is
          // the single add action there. Shown once suppliers exist.
          floatingActionButton: canManage && _suppliers.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _addSupplier,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add Supplier'),
                )
              : null,
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _suppliers.isEmpty
              ? _EmptySuppliers(canManage: canManage, onAdd: _addSupplier)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xxxl * 2,
                  ),
                  itemCount: _suppliers.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) {
                    final supplier = _suppliers[index];
                    return _SupplierCard(
                      supplier: supplier,
                      canManage: canManage,
                      onEdit: () => _editSupplier(supplier),
                      onDelete: () => _deleteSupplier(supplier),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _EmptySuppliers extends StatelessWidget {
  final bool canManage;
  final VoidCallback onAdd;

  const _EmptySuppliers({required this.canManage, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 56,
              color: AppColors.inkMutedOf(context),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('No suppliers yet', style: AppText.subtitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              canManage
                  ? 'Add your suppliers to track who you buy from.'
                  : 'Your shop has not added any suppliers yet.',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
            if (canManage) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Supplier'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  final SupplierProfile supplier;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _SupplierCard({
    required this.supplier,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final details = [
      if (supplier.phone != null) supplier.phone!,
      if (supplier.email != null) supplier.email!,
      if (supplier.gstin != null) 'GSTIN ${supplier.gstin}',
      if (supplier.address != null) supplier.address!,
    ];
    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          const LeadingIconChip(
            icon: Icons.local_shipping_outlined,
            color: AppColors.amber,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.join(' • '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.inkMutedOf(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Edit',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, size: 20),
              color: AppColors.error,
              tooltip: 'Delete',
            ),
          ],
        ],
      ),
    );
  }
}

/// Add/Edit supplier form, shown as a bottom sheet from [SuppliersScreen].
/// Returns the edited [SupplierProfile] on save, or null on cancel.
class _SupplierEditorSheet extends StatefulWidget {
  final SupplierProfile? supplier;

  const _SupplierEditorSheet({this.supplier});

  @override
  State<_SupplierEditorSheet> createState() => _SupplierEditorSheetState();
}

class _SupplierEditorSheetState extends State<_SupplierEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _gstinCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    final supplier = widget.supplier;
    _nameCtrl = TextEditingController(text: supplier?.name ?? '');
    _phoneCtrl = TextEditingController(text: supplier?.phone ?? '');
    _emailCtrl = TextEditingController(text: supplier?.email ?? '');
    _gstinCtrl = TextEditingController(text: supplier?.gstin ?? '');
    _addressCtrl = TextEditingController(text: supplier?.address ?? '');
    _notesCtrl = TextEditingController(text: supplier?.notes ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _gstinCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final current = widget.supplier;
    Navigator.pop(
      context,
      SupplierProfile(
        id: current?.id,
        uuid: current?.uuid,
        shopId: current?.shopId ?? '',
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text,
        email: _emailCtrl.text,
        gstin: _gstinCtrl.text.toUpperCase(),
        address: _addressCtrl.text,
        notes: _notesCtrl.text,
        deviceId: current?.deviceId,
        createdAt: current?.createdAt,
        updatedAt: current?.updatedAt,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.supplier != null;
    final isDark = AppColors.isDark(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: BorderRadius.circular(24),
            border: isDark
                ? Border.all(color: AppColors.borderOf(context))
                : null,
          ),
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderStrongOf(context),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isEditing ? 'Edit Supplier' : 'Add Supplier',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _nameCtrl,
                    autofocus: !isEditing,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Supplier Name *',
                      prefixIcon: Icon(Icons.local_shipping_outlined, size: 18),
                    ),
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone',
                      prefixIcon: Icon(Icons.phone_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, size: 18),
                    ),
                    validator: (value) {
                      final email = value?.trim() ?? '';
                      if (email.isEmpty) return null;
                      return email.contains('@') ? null : 'Invalid email';
                    },
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _gstinCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'GSTIN',
                      prefixIcon: Icon(Icons.receipt_long_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _addressCtrl,
                    minLines: 2,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Address',
                      prefixIcon: Icon(Icons.location_on_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 3,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(isEditing ? 'Save Changes' : 'Add Supplier'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
