import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/widgets.dart';
import '../../state/app_state.dart';
import '../../state/lookups.dart';
import '../invoices/invoice_header_fields.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _taxCode = TextEditingController();
  final _template = TextEditingController();
  final _series = TextEditingController();
  bool _headerLoaded = false;

  @override
  void dispose() {
    _taxCode.dispose();
    _template.dispose();
    _series.dispose();
    super.dispose();
  }

  Future<void> _saveHeader() async {
    await ref.read(settingsProvider.notifier).setInvoiceHeader(
          taxCode: _taxCode.text,
          templateCode: _template.text,
          invoiceSeries: _series.text,
        );
    if (mounted) showMessage(context, 'Đã lưu thông tin hóa đơn mặc định trên thiết bị này');
  }

  Future<void> _resetHeader() async {
    await ref.read(settingsProvider.notifier).resetInvoiceHeader();
    final server = await ref.read(serverInvoiceDefaultsProvider.future);
    _taxCode.text = server.taxCode;
    _template.text = server.templateCode;
    _series.text = server.invoiceSeries;
    if (mounted) showMessage(context, 'Đã khôi phục theo cấu hình máy chủ');
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final confirm = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đổi mật khẩu'),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'Mật khẩu hiện tại')),
            const SizedBox(height: 10),
            TextFormField(
              controller: next,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Mật khẩu mới'),
              validator: (v) => (v?.length ?? 0) < 6 ? 'Tối thiểu 6 ký tự' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: confirm,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu mới'),
              validator: (v) => v != next.text ? 'Mật khẩu không khớp' : null,
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, true);
            },
            child: const Text('Đổi mật khẩu'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).post('/api/auth/change-password', {
        'currentPassword': current.text,
        'newPassword': next.text,
      });
      if (mounted) showMessage(context, 'Đã đổi mật khẩu');
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(authProvider).user;
    final header = ref.watch(invoiceHeaderProvider);
    final pad = isWide(context) ? 24.0 : 16.0;

    if (!_headerLoaded && header.hasValue) {
      _taxCode.text = header.value!.taxCode;
      _template.text = header.value!.templateCode;
      _series.text = header.value!.invoiceSeries;
      _headerLoaded = true;
    }

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(padding: EdgeInsets.fromLTRB(pad, 16, pad, 32), children: [
              Text('Cài đặt', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    radius: 26,
                    backgroundColor: t.colorScheme.primaryContainer,
                    child: Text((user?.displayName ?? '?').characters.first.toUpperCase(), style: t.textTheme.titleLarge),
                  ),
                  title: Text(user?.displayName ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('@${user?.username ?? ''} · ${user?.isAdmin == true ? 'Quản trị' : 'Nhân viên'}'),
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Thông tin hóa đơn mặc định',
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Dùng khi lập hóa đơn / nháp. Giá trị lưu trên thiết bị này, mặc định lấy từ cấu hình máy chủ.',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  if (header.isLoading) const LinearProgressIndicator(),
                  InvoiceHeaderFields(taxCode: _taxCode, templateCode: _template, invoiceSeries: _series),
                  const SizedBox(height: 12),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: _resetHeader, child: const Text('Khôi phục mặc định')),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _saveHeader, child: const Text('Lưu')),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'Giao diện',
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('Theo hệ thống'), icon: Icon(Icons.brightness_auto_rounded)),
                    ButtonSegment(value: ThemeMode.light, label: Text('Sáng'), icon: Icon(Icons.light_mode_rounded)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Tối'), icon: Icon(Icons.dark_mode_rounded)),
                  ],
                  selected: {settings.themeMode},
                  onSelectionChanged: (s) => ref.read(settingsProvider.notifier).setThemeMode(s.first),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(children: [
                  ListTile(
                    leading: const Icon(Icons.dns_outlined),
                    title: const Text('Máy chủ'),
                    subtitle: Text(settings.baseUrl),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: const Text('Đổi mật khẩu'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _changePassword,
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.logout_rounded, color: t.colorScheme.error),
                    title: Text('Đăng xuất', style: TextStyle(color: t.colorScheme.error)),
                    onTap: () async {
                      if (await confirmDialog(context, title: 'Đăng xuất?', message: 'Bạn muốn đăng xuất khỏi ứng dụng?')) {
                        ref.read(authProvider.notifier).logout();
                      }
                    },
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
