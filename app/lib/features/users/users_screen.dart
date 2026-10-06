import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';

final usersProvider = FutureProvider.autoDispose<List<AppUser>>((ref) async {
  final data = await ref.read(apiProvider).get('/api/users') as List;
  return data.map((e) => AppUser.fromJson(e)).toList();
});

/// Quản lý tài khoản đăng nhập (bảng AppUsers) — chỉ Admin.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  Future<void> _openForm(BuildContext context, WidgetRef ref, [AppUser? user]) async {
    final saved = await showAdaptiveSheet<bool>(context, maxWidth: 480, builder: (_) => _UserForm(user: user));
    if (saved == true) ref.invalidate(usersProvider);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, AppUser user) async {
    final ok = await confirmDialog(context,
        title: 'Xóa tài khoản?', message: 'Xóa tài khoản "${user.username}"?', confirmText: 'Xóa', destructive: true);
    if (!ok) return;
    try {
      await ref.read(apiProvider).delete('/api/users/${user.id}');
      ref.invalidate(usersProvider);
      if (context.mounted) showMessage(context, 'Đã xóa tài khoản ${user.username}');
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final users = ref.watch(usersProvider);
    final me = ref.watch(authProvider).user;
    final pad = isWide(context) ? 24.0 : 16.0;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Thêm tài khoản'),
      ),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 12),
            child: Text('Tài khoản', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: users.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(message: e.toString(), onRetry: () => ref.invalidate(usersProvider)),
              data: (list) => RefreshIndicator(
                onRefresh: () => ref.refresh(usersProvider.future),
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(pad, 0, pad, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final u = list[i];
                    return Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: u.isActive ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerHighest,
                          child: Text(u.displayName.characters.first.toUpperCase()),
                        ),
                        title: Row(children: [
                          Flexible(child: Text(u.displayName, style: const TextStyle(fontWeight: FontWeight.w700))),
                          const SizedBox(width: 8),
                          StatusChip(u.role, color: u.isAdmin ? AppColors.draft : AppColors.info),
                          if (!u.isActive) ...[const SizedBox(width: 6), StatusChip('Đã khóa', color: t.colorScheme.error)],
                          if (u.id == me?.id) ...[const SizedBox(width: 6), const StatusChip('Bạn', color: AppColors.success)],
                        ]),
                        subtitle: Text(
                            '@${u.username}${u.lastLoginAt != null ? ' · Đăng nhập gần nhất ${fmtDateTime(u.lastLoginAt)}' : ''}'),
                        onTap: () => _openForm(context, ref, u),
                        trailing: u.id == me?.id
                            ? null
                            : IconButton(
                                tooltip: 'Xóa',
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => _delete(context, ref, u),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _UserForm extends ConsumerStatefulWidget {
  const _UserForm({this.user});
  final AppUser? user;

  @override
  ConsumerState<_UserForm> createState() => _UserFormState();
}

class _UserFormState extends ConsumerState<_UserForm> {
  final _form = GlobalKey<FormState>();
  late final _username = TextEditingController(text: widget.user?.username);
  late final _fullName = TextEditingController(text: widget.user?.fullName);
  final _password = TextEditingController();
  late String _role = widget.user?.role ?? 'User';
  late bool _active = widget.user?.isActive ?? true;
  bool _saving = false;

  bool get _isNew => widget.user == null;

  @override
  void dispose() {
    _username.dispose();
    _fullName.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final api = ref.read(apiProvider);
      if (_isNew) {
        await api.post('/api/users', {
          'username': _username.text.trim(),
          'password': _password.text,
          'fullName': _fullName.text.trim(),
          'role': _role,
        });
      } else {
        await api.put('/api/users/${widget.user!.id}', {
          'fullName': _fullName.text.trim(),
          'role': _role,
          'isActive': _active,
          'newPassword': _password.text.isEmpty ? null : _password.text,
        });
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(title: _isNew ? 'Thêm tài khoản' : 'Sửa tài khoản', icon: Icons.manage_accounts_outlined),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextFormField(
                controller: _username,
                enabled: _isNew,
                decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline)),
                validator: (v) => (v?.trim().length ?? 0) < 3 ? 'Tối thiểu 3 ký tự' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(labelText: 'Họ tên', prefixIcon: Icon(Icons.badge_outlined)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _isNew ? 'Mật khẩu' : 'Mật khẩu mới (để trống nếu không đổi)',
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
                validator: (v) {
                  if (_isNew && (v?.length ?? 0) < 6) return 'Tối thiểu 6 ký tự';
                  if (!_isNew && (v?.isNotEmpty ?? false) && v!.length < 6) return 'Tối thiểu 6 ký tự';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Text('Quyền', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'User', label: Text('Nhân viên'), icon: Icon(Icons.person_rounded)),
                  ButtonSegment(value: 'Admin', label: Text('Quản trị'), icon: Icon(Icons.admin_panel_settings_rounded)),
                ],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              if (!_isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đang hoạt động'),
                  subtitle: const Text('Tắt để khóa tài khoản'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Lưu'),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
