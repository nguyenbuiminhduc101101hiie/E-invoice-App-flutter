import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/lookups.dart';
import 'invoice_actions.dart';
import 'invoice_header_fields.dart';

/// Lập hóa đơn nháp (createInvoiceDraftPreview): mỗi khách hàng một số HĐ nội bộ, tự tách theo VAT.
class DraftInvoiceSheet extends ConsumerStatefulWidget {
  const DraftInvoiceSheet({super.key, required this.orders});
  final List<OrderSummary> orders;

  @override
  ConsumerState<DraftInvoiceSheet> createState() => _DraftInvoiceSheetState();
}

class _DraftInvoiceSheetState extends ConsumerState<DraftInvoiceSheet> {
  final _taxCode = TextEditingController();
  final _template = TextEditingController();
  final _series = TextEditingController();

  List<DraftCustomerGroup> _groups = [];
  final List<TextEditingController> _numbers = [];
  List<String> _warnings = [];
  List<DraftGroupResult>? _results;
  int _converted = 0;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    for (final c in [_taxCode, _template, _series, ..._numbers]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _header => {
        'taxCode': _taxCode.text.trim(),
        'templateCode': _template.text.trim(),
        'invoiceSeries': _series.text.trim(),
      };

  Future<void> _prepare() async {
    try {
      final h = await ref.read(invoiceHeaderProvider.future);
      _taxCode.text = h.taxCode;
      _template.text = h.templateCode;
      _series.text = h.invoiceSeries;

      final res = await ref.read(apiProvider).post('/api/invoices/drafts/prepare', {
        ..._header,
        'orderIds': widget.orders.map((o) => o.id).toList(),
      });
      final groups = ((res['groups'] as List?) ?? []).map((e) => DraftCustomerGroup.fromJson(e)).toList();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _numbers.addAll(groups.map((g) => TextEditingController(text: g.suggestedInvoiceNo)));
        _warnings = ((res['warnings'] as List?) ?? []).map((e) => e.toString()).toList();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_numbers.any((c) => c.text.trim().isEmpty)) {
      showMessage(context, 'Vui lòng nhập số hóa đơn nội bộ cho tất cả khách hàng!', error: true);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).post('/api/invoices/drafts', {
        ..._header,
        'groups': [
          for (var i = 0; i < _groups.length; i++) {'orderIds': _groups[i].orderIds, 'invoiceNo': _numbers[i].text.trim()},
        ],
      });
      if (!mounted) return;
      setState(() {
        _results = ((res['groups'] as List?) ?? []).map((e) => DraftGroupResult.fromJson(e)).toList();
        _converted = (res['convertedOrders'] as num?)?.toInt() ?? 0;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(
        title: results == null ? 'Lập hóa đơn nháp' : 'Kết quả lập nháp',
        subtitle: '${widget.orders.length} đơn hàng',
        icon: Icons.edit_document,
      ),
      Flexible(child: results == null ? _form(context) : _resultList(context, results)),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(children: [
          if (results == null) TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Đóng')),
          const Spacer(),
          if (results == null)
            FilledButton.icon(
              onPressed: _loading || _submitting || _groups.isEmpty ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send_rounded),
              label: const Text('Lập nháp'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(context, results.any((r) => r.success)),
              child: const Text('Xong'),
            ),
        ]),
      ),
    ]);
  }

  Widget _form(BuildContext context) {
    final t = Theme.of(context);
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
      SectionCard(
        title: 'Thông tin hóa đơn',
        child: InvoiceHeaderFields(taxCode: _taxCode, templateCode: _template, invoiceSeries: _series),
      ),
      const SizedBox(height: 12),
      if (_error != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: t.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
          child: Text(_error!, style: TextStyle(color: t.colorScheme.onErrorContainer)),
        ),
        const SizedBox(height: 12),
      ],
      if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
      if (_warnings.isNotEmpty) ...[WarningBox(_warnings), const SizedBox(height: 12)],
      for (var i = 0; i < _groups.length; i++) ...[
        SectionCard(
          title: _groups[i].customerName,
          trailing: Text('${_groups[i].orderIds.length} đơn', style: t.textTheme.bodySmall),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_groups[i].customerPhone.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_groups[i].customerPhone, style: t.textTheme.bodySmall),
              ),
            Wrap(spacing: 6, children: [
              for (final tax in _groups[i].taxPercents) StatusChip('VAT ${fmtPercent(tax)}', color: AppColors.info),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _numbers[i],
              decoration: InputDecoration(
                labelText: _groups[i].taxPercents.length > 1 ? 'Số HĐ nội bộ (gốc, tách theo VAT)' : 'Số HĐ nội bộ',
                prefixIcon: const Icon(Icons.numbers_rounded),
                helperText: _groups[i].taxPercents.length > 1
                    ? 'Sẽ tạo: ${_groups[i].taxPercents.map((t) => '…_VAT${t % 1 == 0 ? t.toInt() : t}').join(', ')}'
                    : null,
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
      ],
    ]);
  }

  Widget _resultList(BuildContext context, List<DraftGroupResult> results) {
    final t = Theme.of(context);
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
      if (_converted > 0)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: WarningBox(['Đã tự động quy đổi $_converted đơn sang Lít và lưu vào database.']),
        ),
      for (final r in results) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(r.success ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: r.success ? AppColors.success : t.colorScheme.error),
                const SizedBox(width: 10),
                Expanded(child: SelectableText(r.invoiceNo, style: const TextStyle(fontWeight: FontWeight.w700))),
              ]),
              if (r.error != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.error!, style: TextStyle(color: t.colorScheme.error))),
              if (r.files.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final f in r.files)
                    FilledButton.tonalIcon(
                      onPressed: () => openDraftPdf(context, f),
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(r.files.length > 1 ? 'PDF VAT ${fmtPercent(f.taxPercent)}' : 'Xem PDF nháp'),
                    ),
                ]),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}
