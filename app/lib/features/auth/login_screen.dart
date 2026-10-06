import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../state/app_state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _fullName = TextEditingController();

  bool _loading = false;
  bool _obscure = true;
  bool? _needsSetup;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSetup());
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _confirm.dispose();
    _fullName.dispose();
    super.dispose();
  }

  Future<void> _checkSetup() async {
    if (ref.read(settingsProvider).baseUrl.isEmpty) {
      setState(() => _error = 'Chưa cấu hình địa chỉ máy chủ.');
      return;
    }
    try {
      final needs = await ref.read(authProvider.notifier).needsSetup();
      if (mounted) {
        setState(() {
          _needsSetup = needs;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider.notifier);
      if (_needsSetup == true) {
        await auth.setupFirstAdmin(_username.text, _password.text, _fullName.text.trim());
      } else {
        await auth.login(_username.text, _password.text);
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editServer() async {
    final ctrl = TextEditingController(text: ref.read(settingsProvider).baseUrl);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Địa chỉ máy chủ'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://hoadon.congty.vn', prefixIcon: Icon(Icons.dns_outlined)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Lưu')),
        ],
      ),
    );
    if (url == null) return;
    await ref.read(settingsProvider.notifier).setBaseUrl(url);
    setState(() => _needsSetup = null);
    _checkSetup();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final setup = _needsSetup == true;
    final baseUrl = ref.watch(settingsProvider.select((s) => s.baseUrl));

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.colorScheme.primary, Color.lerp(t.colorScheme.primary, t.colorScheme.tertiary, 0.6)!],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
                    child: const Icon(Icons.receipt_long_rounded, size: 44, color: Colors.white),
                  ),
                  const SizedBox(height: 14),
                  Text('Hóa đơn điện tử',
                      style: t.textTheme.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                  Text('Lập & quản lý hóa đơn Viettel',
                      style: t.textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85))),
                  const SizedBox(height: 24),
                  Card(
                    elevation: 8,
                    shadowColor: Colors.black26,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _form,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(setup ? 'Tạo tài khoản quản trị' : 'Đăng nhập',
                              style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                          if (setup)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text('Hệ thống chưa có tài khoản nào. Tài khoản đầu tiên sẽ có quyền Admin.',
                                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                            ),
                          const SizedBox(height: 20),
                          if (setup) ...[
                            TextFormField(
                              controller: _fullName,
                              decoration: const InputDecoration(labelText: 'Họ tên', prefixIcon: Icon(Icons.badge_outlined)),
                            ),
                            const SizedBox(height: 12),
                          ],
                          TextFormField(
                            controller: _username,
                            autofillHints: const [AutofillHints.username],
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline)),
                            validator: (v) => (v?.trim().length ?? 0) < (setup ? 3 : 1) ? 'Nhập tên đăng nhập' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: setup ? TextInputAction.next : TextInputAction.done,
                            onFieldSubmitted: (_) => setup ? null : _submit(),
                            decoration: InputDecoration(
                              labelText: 'Mật khẩu',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                onPressed: () => setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Nhập mật khẩu';
                              if (setup && v.length < 6) return 'Tối thiểu 6 ký tự';
                              return null;
                            },
                          ),
                          if (setup) ...[
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _confirm,
                              obscureText: _obscure,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu', prefixIcon: Icon(Icons.lock_reset)),
                              validator: (v) => v != _password.text ? 'Mật khẩu không khớp' : null,
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: t.colorScheme.errorContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(_error!, style: TextStyle(color: t.colorScheme.onErrorContainer)),
                            ),
                          ],
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: _loading || _needsSetup == null ? null : _submit,
                            child: _loading
                                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                : Text(setup ? 'Tạo tài khoản & đăng nhập' : 'Đăng nhập'),
                          ),
                          if (_needsSetup == null && _error != null) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(onPressed: _checkSetup, icon: const Icon(Icons.refresh), label: const Text('Thử kết nối lại')),
                          ],
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: _editServer,
                    icon: const Icon(Icons.dns_outlined, size: 18),
                    label: Text(baseUrl.isEmpty ? 'Cấu hình máy chủ' : 'Máy chủ: $baseUrl', overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
