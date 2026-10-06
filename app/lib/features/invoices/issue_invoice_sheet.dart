import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Xem trước (đã tách theo VAT) rồi lập hóa đơn trên Viettel.
class IssueInvoiceSheet extends ConsumerStatefulWidget {
  const IssueInvoiceSheet({super.key, required this.orders});
  final List<OrderSummary> orders;

  @override
  ConsumerState<IssueInvoiceSheet> createState() => _IssueInvoiceSheetState();
}

class _IssueInvoiceSheetState extends ConsumerState<IssueInvoiceSheet> {
  final _taxCode = TextEditingController();
  final _template = TextEditingController();
  final _series = TextEditingController();

  InvoicePreview? _preview;
  CreateInvoiceResult? _result;
  String? _error;
  bool _loading = true;
  bool _submitting = false;
  bool _headerDirty = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _taxCode.dispose();
    _template.dispose();
    _series.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final h = await ref.read(invoiceHeaderProvider.future);
      _taxCode.text = h.taxCode;
      _template.text = h.templateCode;
      _series.text = h.invoiceSeries;
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
    await _loadPreview();
  }

  Map<String, dynamic> get _body => {
        'orderIds': widget.orders.map((o) => o.id).toList(),
        'taxCode': _taxCode.text.trim(),
        'templateCode': _template.text.trim(),
        'invoiceSeries': _series.text.trim(),
      };

  Future<void> _loadPreview() async {
    setState(() {
      _loading = true;
      _error = null;
      _headerDirty = false;
    });
    try {
      final res = await ref.read(apiProvider).post('/api/invoices/preview', _body);
      if (mounted) setState(() => _preview = InvoicePreview.fromJson(res));
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _preview = null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final count = _preview?.groups.length ?? 0;
    final ok = await confirmDialog(
      context,
      title: 'Lập hóa đơn trên Viettel?',
      message: 'Hệ thống sẽ phát hành $count hóa đơn điện tử cho ${widget.orders.length} đơn hàng. '
          'Thao tác này không thể hoàn tác.',
      confirmText: 'Lập hóa đơn',
    );
    if (!ok) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final res = await ref.read(apiProvider).post('/api/invoices', _body);
      if (mounted) setState(() => _result = CreateInvoiceResult.fromJson(res));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(
        title: result == null ? 'Lập hóa đơn' : 'Kết quả lập hóa đơn',
        subtitle: '${widget.orders.length} đơn · ${widget.orders.first.displayName}',
        icon: Icons.task_alt_rounded,
      ),
      Flexible(child: result == null ? _previewBody(context) : _resultBody(context, result)),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: result == null ? _previewActions() : _resultActions(result),
      ),
    ]);
  }

  Widget _previewActions() {
    final groups = _preview?.groups.length ?? 0;
    return Row(children: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Đóng')),
      const Spacer(),
      if (_headerDirty)
        OutlinedButton.icon(onPressed: _loading ? null : _loadPreview, icon: const Icon(Icons.refresh), label: const Text('Xem lại')),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: _loading || _submitting || _headerDirty || groups == 0 ? null : _submit,
        icon: _submitting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.send_rounded),
        label: Text(groups > 1 ? 'Lập $groups hóa đơn' : 'Lập hóa đơn'),
      ),
    ]);
  }

  Widget _resultActions(CreateInvoiceResult r) => Row(children: [
        const Spacer(),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xong')),
      ]);

  Widget _previewBody(BuildContext context) {
    final t = Theme.of(context);
    final p = _preview;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
      SectionCard(
        title: 'Thông tin hóa đơn',
        child: InvoiceHeaderFields(
          taxCode: _taxCode,
          templateCode: _template,
          invoiceSeries: _series,
          onChanged: () => setState(() => _headerDirty = true),
        ),
      ),
      const SizedBox(height: 12),
      if (_error != null) ...[
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: t.colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, color: t.colorScheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(child: Text(_error!, style: TextStyle(color: t.colorScheme.onErrorContainer))),
          ]),
        ),
        const SizedBox(height: 12),
      ],
      if (_loading)
        const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
      else if (p != null) ...[
        if (p.ordersToConvert > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: WarningBox(['${p.ordersToConvert} đơn chưa quy đổi sang Lít sẽ được tự động quy đổi và lưu trước khi lập hóa đơn.']),
          ),
        if (p.warnings.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 12), child: WarningBox(p.warnings)),
        _BuyerCard(p.buyer),
        for (final g in p.groups) ...[const SizedBox(height: 12), InvoiceGroupCard(group: g)],
      ],
    ]);
  }

  Widget _resultBody(BuildContext context, CreateInvoiceResult r) {
    final t = Theme.of(context);
    final ok = r.invoiceNos.isNotEmpty;
    return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
      Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: (ok ? AppColors.success : t.colorScheme.error).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(ok ? Icons.check_rounded : Icons.close_rounded, size: 40, color: ok ? AppColors.success : t.colorScheme.error),
        ),
      ),
      const SizedBox(height: 12),
      Text(ok ? 'Đã lập ${r.invoiceNos.length} hóa đơn' : 'Không lập được hóa đơn',
          textAlign: TextAlign.center, style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      if (r.convertedOrders > 0)
        Text('Đã tự động quy đổi ${r.convertedOrders} đơn sang Lít.',
            textAlign: TextAlign.center, style: t.textTheme.bodySmall),
      const SizedBox(height: 16),
      for (final no in r.invoiceNos)
        Card(
          child: ListTile(
            leading: const Icon(Icons.receipt_long_rounded, color: AppColors.success),
            title: SelectableText(no, style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: FilledButton.tonalIcon(
              onPressed: () => openViettelPdf(context, invoiceNo: no, templateCode: _template.text.trim()),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
          ),
        ),
      if (r.error != null) ...[
        const SizedBox(height: 12),
        WarningBox(['${r.error} — các hóa đơn còn lại chưa được lập, vui lòng kiểm tra trên Viettel.']),
      ],
      if (r.warnings.isNotEmpty) ...[const SizedBox(height: 12), WarningBox(r.warnings)],
    ]);
  }
}

class _BuyerCard extends StatelessWidget {
  const _BuyerCard(this.buyer);
  final BuyerPreview buyer;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (buyer.kind) {
      'company' => ('Doanh nghiệp', AppColors.info, Icons.business_rounded),
      'personal' => ('Cá nhân', AppColors.draft, Icons.person_rounded),
      'consumer' => ('Người tiêu dùng', AppColors.success, Icons.groups_rounded),
      _ => ('Không rõ', AppColors.warning, Icons.help_outline_rounded),
    };
    return SectionCard(
      title: 'Người mua',
      trailing: StatusChip(label, color: color, icon: icon),
      child: Column(children: [
        if (buyer.buyerLegalName?.isNotEmpty ?? false) InfoRow('Tên đơn vị', buyer.buyerLegalName),
        if (buyer.buyerName?.isNotEmpty ?? false) InfoRow('Người mua', buyer.buyerName),
        if (buyer.taxCode?.isNotEmpty ?? false) InfoRow('MST', buyer.taxCode),
        if (buyer.idNo?.isNotEmpty ?? false) InfoRow('CCCD', buyer.idNo),
        if (buyer.address?.isNotEmpty ?? false) InfoRow('Địa chỉ', buyer.address),
        if (buyer.phone?.isNotEmpty ?? false) InfoRow('SĐT', buyer.phone),
      ]),
    );
  }
}

class InvoiceGroupCard extends StatelessWidget {
  const InvoiceGroupCard({super.key, required this.group});
  final InvoiceGroup group;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant);
    return SectionCard(
      title: 'Hóa đơn VAT ${fmtPercent(group.taxPercent)}',
      trailing: Text('${group.lines.length} dòng', style: muted),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final l in group.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 26, child: Text('${l.lineNumber}.', style: muted)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.itemName, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text('${decimal(l.quantity)} ${l.unitName} × ${money(l.unitPrice)} · thuế ${money(l.taxAmount)}', style: muted),
                ]),
              ),
              Text(money(l.amountWithoutTax), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ]),
          ),
        const Divider(height: 20),
        _total(context, 'Cộng tiền hàng', group.totalWithoutTax),
        if (group.discountAmount > 0) _total(context, 'Chiết khấu', group.discountAmount),
        _total(context, 'Tiền thuế GTGT', group.totalTax),
        _total(context, 'Tổng thanh toán', group.totalWithTax, emphasize: true),
        const SizedBox(height: 4),
        Text(group.amountInWords, style: muted?.copyWith(fontStyle: FontStyle.italic), textAlign: TextAlign.right),
        Theme(
          data: t.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Xem JSON gửi Viettel', style: t.textTheme.labelLarge),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: SelectableText(group.requestJson, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: group.requestJson));
                    showMessage(context, 'Đã sao chép JSON');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Sao chép'),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _total(BuildContext context, String label, double value, {bool emphasize = false}) {
    final t = Theme.of(context);
    final style = emphasize
        ? t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: t.colorScheme.primary)
        : t.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(moneyVnd(value), style: style)]),
    );
  }
}
