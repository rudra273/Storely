part of '../store_screen.dart';

/// Owner/admin screen to manage shop members and pending invites.
class _MembersSheet extends StatefulWidget {
  const _MembersSheet();

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  bool _isBusy = false;
  String? _error;
  String? _message;
  List<ShopMember> _members = const [];
  List<ShopInvite> _invites = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await CloudService.instance.listMembers();
      final invites = await CloudService.instance.listPendingInvites();
      if (!mounted) return;
      setState(() {
        _members = members;
        _invites = invites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _cleanCloudError(error);
        _loading = false;
      });
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() {
      _isBusy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _message = success;
      });
      await _reload();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBusy = false;
        _error = _cleanCloudError(error);
      });
    }
  }

  Future<void> _invite() async {
    final result = await showModalBottomSheet<({String email, String role})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _InviteMemberSheet(),
    );
    if (result == null) return;
    await _run(
      () => CloudService.instance.inviteMember(result.email, result.role),
      success: 'Invite sent to ${result.email}',
    );
  }

  Future<void> _changeRole(ShopMember member) async {
    final newRole = member.role == 'admin' ? 'staff' : 'admin';
    await _run(
      () => CloudService.instance.changeMemberRole(member.userId, newRole),
      success: 'Role updated',
    );
  }

  Future<void> _removeMember(ShopMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
          'Remove ${member.email ?? 'this member'} from the shop? They will '
          'lose cloud access.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(
      () => CloudService.instance.removeMember(member.userId),
      success: 'Member removed',
    );
  }

  Future<void> _revokeInvite(ShopInvite invite) => _run(
    () => CloudService.instance.revokeInvite(invite.id),
    success: 'Invite revoked',
  );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isDark = AppColors.isDark(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: isDark
                ? Border.all(color: AppColors.borderOf(context))
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 42,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrongOf(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Members',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _isBusy ? null : _invite,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                    label: const Text('Invite'),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                _CloudStatusMessage(text: _error!, isError: true),
              ] else if (_message != null) ...[
                const SizedBox(height: 12),
                _CloudStatusMessage(text: _message!),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _MembersList(
                        members: _members,
                        invites: _invites,
                        busy: _isBusy,
                        onChangeRole: _changeRole,
                        onRemove: _removeMember,
                        onRevoke: _revokeInvite,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MembersList extends StatelessWidget {
  final List<ShopMember> members;
  final List<ShopInvite> invites;
  final bool busy;
  final ValueChanged<ShopMember> onChangeRole;
  final ValueChanged<ShopMember> onRemove;
  final ValueChanged<ShopInvite> onRevoke;

  const _MembersList({
    required this.members,
    required this.invites,
    required this.busy,
    required this.onChangeRole,
    required this.onRemove,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty && invites.isEmpty) {
      return Center(
        child: Text('No members yet.', style: AppText.caption),
      );
    }
    return ListView(
      children: [
        if (members.isNotEmpty) ...[
          Text('Members', style: AppText.caption),
          const SizedBox(height: 8),
          ...members.map(
            (m) => _MemberTile(
              member: m,
              busy: busy,
              onChangeRole: () => onChangeRole(m),
              onRemove: () => onRemove(m),
            ),
          ),
        ],
        if (invites.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Pending invites', style: AppText.caption),
          const SizedBox(height: 8),
          ...invites.map(
            (i) => _InviteTile(
              invite: i,
              busy: busy,
              onRevoke: () => onRevoke(i),
            ),
          ),
        ],
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final ShopMember member;
  final bool busy;
  final VoidCallback onChangeRole;
  final VoidCallback onRemove;

  const _MemberTile({
    required this.member,
    required this.busy,
    required this.onChangeRole,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.email ?? member.userId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                StatusPill(
                  label: member.role.toUpperCase(),
                  variant: member.isOwner || member.role == 'admin'
                      ? PillVariant.warning
                      : PillVariant.info,
                ),
              ],
            ),
          ),
          if (!member.isOwner)
            PopupMenuButton<String>(
              enabled: !busy,
              onSelected: (value) {
                if (value == 'role') onChangeRole();
                if (value == 'remove') onRemove();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'role',
                  child: Text(
                    member.role == 'admin' ? 'Make staff' : 'Make admin',
                  ),
                ),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
        ],
      ),
    );
  }
}

class _InviteTile extends StatelessWidget {
  final ShopInvite invite;
  final bool busy;
  final VoidCallback onRevoke;

  const _InviteTile({
    required this.invite,
    required this.busy,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.softBgOf(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        children: [
          const Icon(Icons.mail_outline_rounded, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  invite.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                StatusPill(
                  label: 'INVITED • ${invite.role.toUpperCase()}',
                  variant: PillVariant.neutral,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: busy ? null : onRevoke,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Revoke invite',
          ),
        ],
      ),
    );
  }
}

class _InviteMemberSheet extends StatefulWidget {
  const _InviteMemberSheet();

  @override
  State<_InviteMemberSheet> createState() => _InviteMemberSheetState();
}

class _InviteMemberSheetState extends State<_InviteMemberSheet> {
  late final TextEditingController _emailCtrl;
  String _role = 'staff';

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isDark = AppColors.isDark(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceOf(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: isDark
                ? Border.all(color: AppColors.borderOf(context))
                : null,
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 42,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrongOf(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Invite member',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'staff', label: Text('Staff')),
                  ButtonSegment(value: 'admin', label: Text('Admin')),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final email = _emailCtrl.text.trim().toLowerCase();
                    if (email.isEmpty || !email.contains('@')) return;
                    Navigator.pop(context, (email: email, role: _role));
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send Invite'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
