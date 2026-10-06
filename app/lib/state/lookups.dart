import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import 'app_state.dart';

// Danh mục được cache trong phiên đăng nhập; đổi tài khoản thì tự tải lại.

final customersProvider = FutureProvider<List<NamedItem>>((ref) async {
  ref.watch(authProvider.select((s) => s.token));
  final data = await ref.read(apiProvider).get('/api/lookups/customers') as List;
  return data.map((e) => NamedItem.fromJson(e)).toList();
});

final employeesProvider = FutureProvider<List<NamedItem>>((ref) async {
  ref.watch(authProvider.select((s) => s.token));
  final data = await ref.read(apiProvider).get('/api/lookups/employees') as List;
  return data.map((e) => NamedItem.fromJson(e)).toList();
});

final servicesProvider = FutureProvider<List<ServiceItem>>((ref) async {
  ref.watch(authProvider.select((s) => s.token));
  final data = await ref.read(apiProvider).get('/api/lookups/services') as List;
  return data.map((e) => ServiceItem.fromJson(e)).toList();
});

final serverInvoiceDefaultsProvider = FutureProvider<InvoiceDefaults>((ref) async {
  ref.watch(authProvider.select((s) => s.token));
  return InvoiceDefaults.fromJson(await ref.read(apiProvider).get('/api/lookups/invoice-defaults'));
});

/// Mẫu số / ký hiệu / MST đang dùng: ưu tiên giá trị đã chỉnh trong Cài đặt, còn lại lấy từ server.
final invoiceHeaderProvider = FutureProvider<InvoiceDefaults>((ref) async {
  final server = await ref.watch(serverInvoiceDefaultsProvider.future);
  final s = ref.watch(settingsProvider);
  String pick(String? local, String fallback) => (local?.trim().isNotEmpty ?? false) ? local!.trim() : fallback;
  return InvoiceDefaults(
    taxCode: pick(s.taxCode, server.taxCode),
    templateCode: pick(s.templateCode, server.templateCode),
    invoiceSeries: pick(s.invoiceSeries, server.invoiceSeries),
  );
});
