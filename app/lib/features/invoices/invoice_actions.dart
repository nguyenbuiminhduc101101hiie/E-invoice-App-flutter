import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/pdf_viewer.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/lookups.dart';
import 'draft_invoice_sheet.dart';
import 'issue_invoice_sheet.dart';

Future<bool?> showIssueInvoiceSheet(BuildContext context, List<OrderSummary> orders) {
  if (orders.isEmpty) return Future.value(false);
  return showAdaptiveSheet<bool>(context, maxWidth: 900, builder: (_) => IssueInvoiceSheet(orders: orders));
}

Future<bool?> showDraftInvoiceSheet(BuildContext context, List<OrderSummary> orders) {
  if (orders.isEmpty) return Future.value(false);
  return showAdaptiveSheet<bool>(context, maxWidth: 820, builder: (_) => DraftInvoiceSheet(orders: orders));
}

Future<String?> _pickInvoiceNo(BuildContext context, List<String> numbers) async {
  if (numbers.isEmpty) return null;
  if (numbers.length == 1) return numbers.first;
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Chọn hóa đơn'),
      children: numbers
          .map((n) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, n),
                child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(n)),
              ))
          .toList(),
    ),
  );
}

/// Mở PDF hóa đơn thật trên Viettel.
Future<void> openViettelPdf(BuildContext context, {required String invoiceNo, String? templateCode}) async {
  final container = ProviderScope.containerOf(context);
  final api = container.read(apiProvider);
  final header = await container.read(invoiceHeaderProvider.future).catchError((_) =>
      InvoiceDefaults(taxCode: '', templateCode: templateCode ?? '', invoiceSeries: ''));
  if (!context.mounted) return;
  await openPdf(
    context,
    title: 'Hóa đơn $invoiceNo',
    fileName: '$invoiceNo.pdf',
    load: () => api.getBytes('/api/invoices/pdf', query: {
      'invoiceNo': invoiceNo,
      'templateCode': (templateCode?.isNotEmpty ?? false) ? templateCode : header.templateCode,
      'taxCode': header.taxCode,
    }),
  );
}

Future<void> openOrderInvoicePdf(BuildContext context, OrderSummary order) async {
  final no = await _pickInvoiceNo(context, order.viettelInvoiceNos);
  if (no == null || !context.mounted) return;
  await openViettelPdf(context, invoiceNo: no, templateCode: order.templateCode);
}

Future<void> openDraftPdf(BuildContext context, DraftFile file) async {
  if (file.fileId == null) return;
  final api = ProviderScope.containerOf(context).read(apiProvider);
  await openPdf(
    context,
    title: 'Nháp ${file.invoiceNo}',
    fileName: file.fileName ?? '${file.invoiceNo}.pdf',
    load: () => api.getBytes('/api/invoices/drafts/files/${file.fileId}'),
  );
}

Future<void> sendInvoiceEmail(BuildContext context, OrderSummary order) async {
  final no = await _pickInvoiceNo(context, order.viettelInvoiceNos);
  if (no == null || !context.mounted) return;

  final emailCtrl = TextEditingController();
  final send = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Gửi hóa đơn qua email'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hóa đơn $no — ${order.displayName}'),
        const SizedBox(height: 16),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email người nhận',
            helperText: 'Để trống để dùng email của khách trong danh mục',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.send_rounded),
          label: const Text('Gửi'),
        ),
      ],
    ),
  );
  if (send != true || !context.mounted) return;

  final container = ProviderScope.containerOf(context);
  try {
    showMessage(context, 'Đang gửi email…');
    final header = await container.read(invoiceHeaderProvider.future);
    final res = await container.read(apiProvider).post('/api/invoices/email', {
      'invoiceNo': no,
      'templateCode': order.templateCode ?? header.templateCode,
      'taxCode': header.taxCode,
      'customerPhone': order.customerPhone,
      'customerName': order.customerName,
      'toEmail': emailCtrl.text.trim(),
    });
    if (context.mounted) showMessage(context, 'Đã gửi hóa đơn đến ${res['sentTo']}');
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message, error: true);
  }
}
