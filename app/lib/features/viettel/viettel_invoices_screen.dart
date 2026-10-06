import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/widgets.dart';
import '../../state/app_state.dart';
import '../../state/lookups.dart';
import '../invoices/invoice_actions.dart';

/// Tra cứu danh sách hóa đơn trên hệ thống Viettel (GetInvoiceList của bản cũ).
class ViettelInvoicesScreen extends ConsumerStatefulWidget {
  const ViettelInvoicesScreen({super.key});

  @override
  ConsumerState<ViettelInvoicesScreen> createState() => _ViettelInvoicesScreenState();
}

/// Một dòng hóa đơn Viettel. Tên trường giữa các tenant có thể khác nhau nên đọc theo danh sách tên ứng viên.
class ViettelRow {
  ViettelRow(this.data);
  final Map<String, dynamic> data;

  dynamic _pick(List<String> keys) {
    for (final k in keys) {
      for (final e in data.entries) {
        if (e.key.toLowerCase() == k.toLowerCase() && e.value != null && e.value.toString().isNotEmpty) return e.value;
      }
    }
    return null;
  }

  String? get invoiceNo => _pick(['invoiceNo', 'invoiceNumber'])?.toString();
  String? get templateCode => _pick(['templateCode', 'pattern'])?.toString();
  String? get buyer => _pick(['buyerName', 'buyerLegalName', 'buyerUnitName', 'customerName'])?.toString();
  String? get buyerTaxCode => _pick(['buyerTaxCode'])?.toString();
  String? get status => _pick(['status', 'invoiceStatus', 'exchangeStatus'])?.toString();
  String? get paymentStatus => _pick(['paymentStatusName', 'paymentStatus'])?.toString();

  num? get total {
    final v = _pick(['totalAmountWithTax', 'total', 'totalAmount', 'sumTotal']);
    return v is num ? v : num.tryParse(v?.toString() ?? '');
  }

  dynamic get issueDateRaw => _pick(['issueDate', 'invoiceIssuedDate', 'createTime', 'issuedDate']);

  DateTime? get issueDate {
    final v = issueDateRaw;
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    final s = v?.toString();
    if (s == null) return null;
    final ms = int.tryParse(s);
    if (ms != null) return DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime.tryParse(s);
  }

  bool matches(String q) => data.values.any((v) => v?.toString().toLowerCase().contains(q) ?? false);
}

class _ViettelInvoicesScreenState extends ConsumerState<ViettelInvoicesScreen> {
  late DateTimeRange _range;
  List<ViettelRow> _rows = [];
  String? _raw;
  String? _message;
  String? _endpoint;
  String? _error;
  bool _loading = false;
  bool _loaded = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _range = DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month, now.day));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final header = await ref.read(invoiceHeaderProvider.future);
      final res = await ref.read(apiProvider).get('/api/invoices/viettel', query: {
        'from': _range.start.toIso8601String().substring(0, 10),
        'to': _range.end.toIso8601String().substring(0, 10),
        'taxCode': header.taxCode,
      }) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _rows = ((res['rows'] as List?) ?? []).map((e) => ViettelRow(Map<String, dynamic>.from(e))).toList();
        _raw = res['raw']?.toString();
        _message = res['message']?.toString();
        _endpoint = res['endpoint']?.toString();
        _loaded = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _range,
    );
    if (picked != null) {
      setState(() => _range = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final wide = isWide(context);
    final pad = wide ? 24.0 : 16.0;
    final q = _query.trim().toLowerCase();
    final rows = q.isEmpty ? _rows : _rows.where((r) => r.matches(q)).toList();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(pad, 16, pad, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hóa đơn trên Viettel', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(_endpoint == null ? 'Tra cứu hóa đơn đã phát hành theo khoảng ngày' : 'Nguồn: $_endpoint',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text('${fmtDate(_range.start)} – ${fmtDate(_range.end)}'),
              ),
              FilledButton.icon(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Tải danh sách'),
              ),
              if (_rows.isNotEmpty)
                SizedBox(
                  width: wide ? 300 : double.infinity,
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm số HĐ, người mua, MST…'),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          Expanded(child: _body(context, rows, pad)),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context, List<ViettelRow> rows, double pad) {
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);
    if (!_loaded) {
      return EmptyState(
        icon: Icons.cloud_outlined,
        title: 'Chọn khoảng ngày và bấm "Tải danh sách"',
        message: 'Dữ liệu lấy trực tiếp từ hệ thống hóa đơn điện tử Viettel.',
      );
    }
    if (_raw != null) {
      return ListView(padding: EdgeInsets.all(pad), children: [
        const WarningBox(['Không đọc được danh sách dạng bảng, hiển thị phản hồi gốc từ Viettel:']),
        const SizedBox(height: 12),
        SelectableText(_raw!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ]);
    }
    if (rows.isEmpty) {
      return EmptyState(icon: Icons.search_off_rounded, title: _message ?? 'Không có hóa đơn nào');
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(pad, 4, pad, 24),
      itemCount: rows.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i == 0) {
          final total = rows.fold<num>(0, (s, r) => s + (r.total ?? 0));
          return Text('${rows.length} hóa đơn · Tổng ${moneyVnd(total)}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700));
        }
        return _tile(context, rows[i - 1]);
      },
    );
  }

  Widget _tile(BuildContext context, ViettelRow r) {
    final t = Theme.of(context);
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: t.colorScheme.primaryContainer,
          child: Icon(Icons.receipt_long_rounded, color: t.colorScheme.onPrimaryContainer),
        ),
        title: Text(r.invoiceNo ?? '(không có số)', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          [r.buyer, if (r.issueDate != null) fmtDateTime(r.issueDate), r.status].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(r.total == null ? '' : money(r.total), style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        onTap: () => _openDetail(r),
      ),
    );
  }

  void _openDetail(ViettelRow r) {
    final isAdmin = ref.read(authProvider).user?.isAdmin ?? false;
    showAdaptiveSheet(
      context,
      builder: (ctx) {
        final entries = r.data.entries.where((e) => e.value != null && e.value.toString().isNotEmpty).toList();
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SheetHeader(title: r.invoiceNo ?? 'Hóa đơn', subtitle: r.buyer, icon: Icons.receipt_long_rounded),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), children: [
              SectionCard(
                child: Column(children: [
                  for (final e in entries) InfoRow(e.key, e.value.toString()),
                ]),
              ),
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: [
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: r.invoiceNo ?? ''));
                  showMessage(ctx, 'Đã sao chép số hóa đơn');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Sao chép số'),
              ),
              if (isAdmin && r.invoiceNo != null) ...[
                OutlinedButton.icon(
                  onPressed: () => _updatePaymentStatus(ctx, r),
                  icon: const Icon(Icons.price_check_rounded),
                  label: const Text('Cập nhật TT thanh toán'),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Theme.of(ctx).colorScheme.error),
                  onPressed: () => _cancel(ctx, r),
                  icon: const Icon(Icons.block_rounded),
                  label: const Text('Hủy hóa đơn'),
                ),
              ],
              if (r.invoiceNo != null)
                FilledButton.icon(
                  onPressed: () => openViettelPdf(ctx, invoiceNo: r.invoiceNo!, templateCode: r.templateCode),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Xem PDF'),
                ),
            ]),
          ),
        ]);
      },
    );
  }

  String _issueMillis(ViettelRow r) => r.issueDate?.millisecondsSinceEpoch.toString() ?? '';

  Future<void> _cancel(BuildContext ctx, ViettelRow r) async {
    final reason = TextEditingController();
    final issue = TextEditingController(text: _issueMillis(r));
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: Text('Hủy hóa đơn ${r.invoiceNo}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Hóa đơn sẽ bị hủy trên hệ thống Viettel. Thao tác không thể hoàn tác.'),
          const SizedBox(height: 16),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Lý do / văn bản thỏa thuận')),
          const SizedBox(height: 10),
          TextField(controller: issue, decoration: const InputDecoration(labelText: 'Ngày lập (strIssueDate, ms)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Không')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(d).colorScheme.error),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Hủy hóa đơn'),
          ),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    await _callTool(ctx, '/api/invoices/viettel/cancel', {
      'invoiceNo': r.invoiceNo,
      'strIssueDate': issue.text.trim(),
      'additionalReferenceDesc': reason.text.trim(),
    });
  }

  Future<void> _updatePaymentStatus(BuildContext ctx, ViettelRow r) async {
    final issue = TextEditingController(text: _issueMillis(r));
    final email = TextEditingController();
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (d) => AlertDialog(
        title: const Text('Cập nhật trạng thái thanh toán'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Đánh dấu hóa đơn ${r.invoiceNo} đã thanh toán (TM/CK).'),
          const SizedBox(height: 16),
          TextField(controller: issue, decoration: const InputDecoration(labelText: 'Ngày lập (strIssueDate, ms)')),
          const SizedBox(height: 10),
          TextField(controller: email, decoration: const InputDecoration(labelText: 'Email người mua (không bắt buộc)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Cập nhật')),
        ],
      ),
    );
    if (ok != true || !ctx.mounted) return;
    await _callTool(ctx, '/api/invoices/viettel/payment-status', {
      'invoiceNo': r.invoiceNo,
      'strIssueDate': issue.text.trim(),
      'templateCode': r.templateCode,
      'buyerEmailAddress': email.text.trim(),
      'paymentType': 'TM/CK',
      'cusGetInvoiceRight': true,
    });
  }

  Future<void> _callTool(BuildContext ctx, String path, Map<String, dynamic> body) async {
    try {
      final res = await ref.read(apiProvider).post(path, body);
      if (!ctx.mounted) return;
      await showDialog(
        context: ctx,
        builder: (d) => AlertDialog(
          title: const Text('Phản hồi từ Viettel'),
          content: SingleChildScrollView(child: SelectableText(res['result']?.toString() ?? '')),
          actions: [FilledButton(onPressed: () => Navigator.pop(d), child: const Text('Đóng'))],
        ),
      );
    } on ApiException catch (e) {
      if (ctx.mounted) showMessage(ctx, e.message, error: true);
    }
  }
}
