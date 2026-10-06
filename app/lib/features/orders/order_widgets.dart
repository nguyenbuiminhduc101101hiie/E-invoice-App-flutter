import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';

/// Các chip trạng thái hóa đơn của một đơn hàng.
class OrderStatusChips extends StatelessWidget {
  const OrderStatusChips(this.order, {super.key, this.showConversion = true});
  final OrderSummary order;
  final bool showConversion;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 4, children: [
      if (order.hasViettelInvoice)
        StatusChip(order.invoiceNoViettel!, color: AppColors.success, icon: Icons.verified_rounded)
      else if (order.exported)
        const StatusChip('Đã xuất (chưa có số)', color: AppColors.warning, icon: Icons.hourglass_top_rounded),
      if (order.isDraft) const StatusChip('Nháp', color: AppColors.draft, icon: Icons.edit_note_rounded),
      if (!order.hasViettelInvoice && !order.exported && !order.isDraft)
        const StatusChip('Chưa lập', color: AppColors.info, icon: Icons.pending_outlined),
      if (showConversion && !order.isConvertToLiter)
        const StatusChip('Chưa quy đổi Lít', color: AppColors.warning, icon: Icons.water_drop_outlined),
    ]);
  }
}

String buyerLabel(OrderSummary o) => switch (o.buyerKind) {
      'company' => 'Doanh nghiệp',
      'personal' => 'Cá nhân',
      _ => 'Người tiêu dùng',
    };

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.selected, required this.onToggle, required this.onOpen});

  final OrderSummary order;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final bg = selected
        ? t.colorScheme.primaryContainer.withValues(alpha: 0.55)
        : !order.isConvertToLiter
            ? AppColors.notConverted(t.brightness)
            : t.colorScheme.surfaceContainerLowest;

    return Card(
      color: bg,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? t.colorScheme.primary : t.colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onOpen,
        onLongPress: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 14, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: selected, onChanged: (_) => onToggle()),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: Text(order.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  Text(moneyVnd(order.totalPrice),
                      style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: t.colorScheme.primary)),
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    fmtDateTime(order.createdAt),
                    if (order.customerPhone?.isNotEmpty ?? false) order.customerPhone!,
                    buyerLabel(order),
                  ].join(' · '),
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                ),
                if (order.items.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    order.items.map((i) => '${i.serviceName} ×${i.quantity}').join(', '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 8),
                OrderStatusChips(order),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Col {
  const _Col(this.title, this.width, {this.numeric = false});
  final String title;
  final double width;
  final bool numeric;
}

const _columns = [
  _Col('Tên quán', 210),
  _Col('Hóa đơn', 220),
  _Col('Tổng tiền', 115, numeric: true),
  _Col('Tiền mặt', 110, numeric: true),
  _Col('Chuyển khoản', 115, numeric: true),
  _Col('Ngày tạo', 145),
  _Col('Thanh toán', 100),
  _Col('Giao hàng', 100),
  _Col('MST', 115),
  _Col('CCCD/CMND', 120),
  _Col('Tên cá nhân', 150),
  _Col('Tên đơn vị', 220),
  _Col('Địa chỉ HĐ', 240),
];

const _checkboxWidth = 52.0;
final double _tableWidth = _checkboxWidth + _columns.fold<double>(0, (s, c) => s + c.width);

/// Bảng đơn hàng cho màn hình rộng: cuộn ngang, danh sách dòng dùng ListView.builder.
class OrdersTable extends StatefulWidget {
  const OrdersTable({
    super.key,
    required this.orders,
    required this.selected,
    required this.onToggle,
    required this.onToggleAll,
    required this.onOpen,
  });

  final List<OrderSummary> orders;
  final Set<String> selected;
  final ValueChanged<OrderSummary> onToggle;
  final ValueChanged<bool> onToggleAll;
  final ValueChanged<OrderSummary> onOpen;

  @override
  State<OrdersTable> createState() => _OrdersTableState();
}

class _OrdersTableState extends State<OrdersTable> {
  final _hController = ScrollController();

  @override
  void dispose() {
    _hController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final allSelected = widget.orders.isNotEmpty && widget.orders.every((o) => widget.selected.contains(o.id));
    final someSelected = widget.orders.any((o) => widget.selected.contains(o.id));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        controller: _hController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _hController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _tableWidth,
            child: Column(children: [
              Container(
                color: t.colorScheme.surfaceContainerHigh,
                height: 46,
                child: Row(children: [
                  SizedBox(
                    width: _checkboxWidth,
                    child: Checkbox(
                      tristate: true,
                      value: allSelected ? true : (someSelected ? null : false),
                      onChanged: (_) => widget.onToggleAll(!allSelected),
                    ),
                  ),
                  ..._columns.map((c) => _cell(
                        c,
                        Text(c.title, style: t.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                      )),
                ]),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: widget.orders.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _row(context, widget.orders[i]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _cell(_Col c, Widget child) => SizedBox(
        width: c.width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Align(alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft, child: child),
        ),
      );

  Widget _row(BuildContext context, OrderSummary o) {
    final t = Theme.of(context);
    final selected = widget.selected.contains(o.id);
    final style = t.textTheme.bodySmall;
    Text txt(String? v, {bool bold = false}) => Text(v ?? '',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: bold ? style?.copyWith(fontWeight: FontWeight.w600) : style);

    final values = <Widget>[
      Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        txt(o.displayName, bold: true),
        if (o.customerPhone?.isNotEmpty ?? false)
          Text(o.customerPhone!, style: style?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      ]),
      OrderStatusChips(o, showConversion: false),
      txt(money(o.totalPrice), bold: true),
      txt(money(o.cashAmount)),
      txt(money(o.transferAmount)),
      txt(fmtDateTime(o.createdAt)),
      txt(o.paymentStatus),
      txt(o.deliveryStatus),
      txt(o.taxCode),
      txt(o.identification),
      txt(o.personalName),
      txt(o.invoiceName),
      txt(o.invoiceAddress),
    ];

    return Material(
      color: selected
          ? t.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : !o.isConvertToLiter
              ? AppColors.notConverted(t.brightness)
              : Colors.transparent,
      child: InkWell(
        onTap: () => widget.onOpen(o),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(children: [
            SizedBox(width: _checkboxWidth, child: Checkbox(value: selected, onChanged: (_) => widget.onToggle(o))),
            for (var i = 0; i < _columns.length; i++)
              _cell(_columns[i], Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: values[i])),
          ]),
        ),
      ),
    );
  }
}

List<PaymentRecord> parsePaymentHistory(String? raw) {
  if (raw == null || raw.trim().isEmpty) return [];
  try {
    final list = jsonDecode(raw) as List;
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      return PaymentRecord(
        cash: (m['cashAmount'] as num?)?.toDouble() ?? 0,
        transfer: (m['transferAmount'] as num?)?.toDouble() ?? 0,
        date: DateTime.tryParse(m['paymentDate']?.toString() ?? ''),
      );
    }).toList();
  } catch (_) {
    return [];
  }
}

/// Chi tiết một đơn hàng (mở khi chạm vào dòng).
class OrderDetailSheet extends StatelessWidget {
  const OrderDetailSheet({super.key, required this.order, required this.actions});

  final OrderSummary order;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final payments = parsePaymentHistory(order.paymentHistory);

    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(title: order.displayName, subtitle: fmtDateTime(order.createdAt), icon: Icons.storefront_rounded),
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), children: [
          OrderStatusChips(order),
          const SizedBox(height: 16),
          SectionCard(
            title: 'Người mua (${buyerLabel(order)})',
            child: Column(children: [
              InfoRow('Tên quán', order.shopName ?? order.customerName),
              InfoRow('SĐT', order.customerPhone),
              InfoRow('MST', order.taxCode),
              InfoRow('CCCD/CMND', order.identification),
              InfoRow('Tên cá nhân', order.personalName),
              InfoRow('Tên đơn vị', order.invoiceName),
              InfoRow('Địa chỉ HĐ', order.invoiceAddress),
              InfoRow('Nhân viên', order.employeeNames),
            ]),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Hàng hóa',
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(children: [
              for (final item in order.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(item.serviceName, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          'SL ${decimal(item.quantity)}'
                          '${item.promotionQuantity > 0 ? ' (KM ${decimal(item.promotionQuantity)})' : ''}'
                          ' × ${decimal(item.unitPrice)}',
                          style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                        ),
                      ]),
                    ),
                    Text(money(item.total), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ]),
                ),
              const Divider(height: 20),
              InfoRow('Tổng tiền', moneyVnd(order.totalPrice), bold: true),
              InfoRow('Tiền mặt', moneyVnd(order.cashAmount)),
              InfoRow('Chuyển khoản', moneyVnd(order.transferAmount)),
              InfoRow('Thanh toán', order.paymentStatus),
              InfoRow('Giao hàng', order.deliveryStatus),
            ]),
          ),
          if (payments.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'Lịch sử thanh toán',
              child: Column(
                children: payments
                    .map((p) => InfoRow(fmtDateTime(p.date),
                        'TM ${money(p.cash)} · CK ${money(p.transfer)}'))
                    .toList(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: 'Hóa đơn',
            child: Column(children: [
              InfoRow('Số HĐ Viettel', order.invoiceNoViettel),
              InfoRow('Ngày xuất', order.dateInvViettel),
              InfoRow('Mẫu số', order.templateCode),
              InfoRow('HĐ nội bộ (nháp)', order.hoaDonNoiBo),
            ]),
          ),
        ]),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
      ),
    ]);
  }
}
