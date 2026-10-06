import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/lookups.dart';
import '../invoices/invoice_actions.dart';
import 'order_widgets.dart';

enum StatusFilter { all, pending, draft, issued }

extension on StatusFilter {
  String get label => switch (this) {
        StatusFilter.all => 'Tất cả',
        StatusFilter.pending => 'Chưa lập',
        StatusFilter.draft => 'Đã nháp',
        StatusFilter.issued => 'Đã xuất',
      };

  bool matches(OrderSummary o) => switch (this) {
        StatusFilter.all => true,
        StatusFilter.pending => !o.hasViettelInvoice && !o.exported && !o.isDraft,
        StatusFilter.draft => o.isDraft && !o.hasViettelInvoice,
        StatusFilter.issued => o.hasViettelInvoice || o.exported,
      };
}

class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  DateTimeRange _range = DateTimeRange(start: _today(), end: _today());
  String _customer = '';
  String _employee = '';
  bool _byPaymentDate = false;
  StatusFilter _status = StatusFilter.all;
  String _quickSearch = '';

  List<OrderSummary> _orders = [];
  final Set<String> _selected = {};
  bool _loading = false;
  String? _error;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(apiProvider).get('/api/orders', query: {
        'from': _range.start.toIso8601String().substring(0, 10),
        'to': _range.end.toIso8601String().substring(0, 10),
        'customerName': _customer,
        'employeeName': _employee,
        'byPaymentDate': _byPaymentDate,
      }) as List;
      final orders = data.map((e) => OrderSummary.fromJson(e)).toList();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _selected.removeWhere((id) => !orders.any((o) => o.id == id));
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<OrderSummary> get _visible {
    final q = _quickSearch.trim().toLowerCase();
    return _orders.where((o) {
      if (!_status.matches(o)) return false;
      if (q.isEmpty) return true;
      return [o.displayName, o.customerName, o.customerPhone, o.invoiceNoViettel, o.hoaDonNoiBo, o.taxCode]
          .any((v) => v?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  List<OrderSummary> get _selectedOrders => _orders.where((o) => _selected.contains(o.id)).toList();

  void _toggle(OrderSummary o) => setState(() => _selected.contains(o.id) ? _selected.remove(o.id) : _selected.add(o.id));

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
      helpText: _byPaymentDate ? 'Chọn khoảng ngày thanh toán' : 'Chọn khoảng ngày tạo đơn',
    );
    if (picked != null) {
      setState(() => _range = picked);
      _search();
    }
  }

  void _setQuickRange(DateTimeRange r) {
    setState(() => _range = r);
    _search();
  }

  // ---------------- Hành động ----------------

  Future<void> _issue() async {
    final done = await showIssueInvoiceSheet(context, _selectedOrders);
    if (done == true) {
      _selected.clear();
      _search();
    }
  }

  Future<void> _draft() async {
    final done = await showDraftInvoiceSheet(context, _selectedOrders);
    if (done == true) {
      _selected.clear();
      _search();
    }
  }

  Future<void> _edit([List<OrderSummary>? orders]) async {
    final list = orders ?? _selectedOrders;
    if (list.isEmpty) return;
    final saved = await context.push<bool>('/orders/edit?ids=${list.map((o) => Uri.encodeComponent(o.id)).join(',')}');
    if (saved == true) _search();
  }

  void _openDetail(OrderSummary o) {
    showAdaptiveSheet(
      context,
      builder: (ctx) => OrderDetailSheet(order: o, actions: [
        if (o.hasViettelInvoice) ...[
          OutlinedButton.icon(
            onPressed: () => sendInvoiceEmail(ctx, o),
            icon: const Icon(Icons.mail_outline_rounded),
            label: const Text('Gửi email'),
          ),
          OutlinedButton.icon(
            onPressed: () => openOrderInvoicePdf(ctx, o),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Xem PDF'),
          ),
        ],
        if (!o.hasViettelInvoice)
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.pop(ctx);
              _edit([o]);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Sửa đơn'),
          ),
      ]),
    );
  }

  // ---------------- Giao diện ----------------

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final visible = _visible;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _header(context),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
            child: wide ? _filtersWide(context) : _filtersNarrow(context),
          ),
          const SizedBox(height: 12),
          _stats(context, visible),
          const SizedBox(height: 8),
          _statusBar(context),
          const SizedBox(height: 8),
          Expanded(child: _body(context, visible, wide)),
        ]),
      ),
      bottomNavigationBar: _selectionBar(context),
    );
  }

  Widget _header(BuildContext context) {
    final t = Theme.of(context);
    final wide = isWide(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 16 : 8, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Đơn hàng', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              '${_byPaymentDate ? 'Theo ngày thanh toán' : 'Theo ngày tạo'} · ${fmtDate(_range.start)} – ${fmtDate(_range.end)}',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
          ]),
        ),
        IconButton.filledTonal(
          tooltip: 'Tải lại',
          onPressed: _loading ? null : _search,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ]),
    );
  }

  Widget _rangeButton(BuildContext context) => OutlinedButton.icon(
        onPressed: _pickRange,
        icon: const Icon(Icons.date_range_rounded, size: 18),
        label: Text('${fmtDate(_range.start)} – ${fmtDate(_range.end)}'),
      );

  Widget _quickRanges() {
    final today = _today();
    final ranges = {
      'Hôm nay': DateTimeRange(start: today, end: today),
      'Hôm qua': DateTimeRange(start: today.subtract(const Duration(days: 1)), end: today.subtract(const Duration(days: 1))),
      '7 ngày': DateTimeRange(start: today.subtract(const Duration(days: 6)), end: today),
      'Tháng này': DateTimeRange(start: DateTime(today.year, today.month, 1), end: today),
      'Tháng trước': DateTimeRange(
          start: DateTime(today.year, today.month - 1, 1), end: DateTime(today.year, today.month, 0)),
    };
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (final e in ranges.entries)
        ChoiceChip(
          label: Text(e.key),
          selected: _range.start == e.value.start && _range.end == e.value.end,
          onSelected: (_) => _setQuickRange(e.value),
        ),
    ]);
  }

  Widget _filtersWide(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _rangeButton(context),
          const SizedBox(width: 12),
          Expanded(child: _NameFilterField(
            label: 'Khách hàng',
            icon: Icons.storefront_outlined,
            provider: customersProvider,
            value: _customer,
            onChanged: (v) => _customer = v,
            onSubmitted: _search,
          )),
          const SizedBox(width: 12),
          Expanded(child: _NameFilterField(
            label: 'Nhân viên',
            icon: Icons.badge_outlined,
            provider: employeesProvider,
            value: _employee,
            onChanged: (v) => _employee = v,
            onSubmitted: _search,
          )),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _loading ? null : _search,
            icon: const Icon(Icons.search_rounded),
            label: const Text('Tìm'),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _quickRanges()),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Theo ngày thanh toán', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 8),
            Switch(
              value: _byPaymentDate,
              onChanged: (v) {
                setState(() => _byPaymentDate = v);
                _search();
              },
            ),
          ]),
        ]),
      ]),
    );
  }

  Widget _filtersNarrow(BuildContext context) {
    final activeCount = [_customer.isNotEmpty, _employee.isNotEmpty, _byPaymentDate].where((e) => e).length;
    return Row(children: [
      Expanded(child: _rangeButton(context)),
      const SizedBox(width: 8),
      Badge(
        isLabelVisible: activeCount > 0,
        label: Text('$activeCount'),
        child: IconButton.filledTonal(
          tooltip: 'Bộ lọc',
          onPressed: _openFilterSheet,
          icon: const Icon(Icons.tune_rounded),
        ),
      ),
    ]);
  }

  Future<void> _openFilterSheet() async {
    await showAdaptiveSheet(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SheetHeader(title: 'Bộ lọc', icon: Icons.tune_rounded),
          Flexible(
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 4, 20, 20), children: [
              _quickRanges(),
              const SizedBox(height: 16),
              _NameFilterField(
                label: 'Khách hàng',
                icon: Icons.storefront_outlined,
                provider: customersProvider,
                value: _customer,
                onChanged: (v) => _customer = v,
              ),
              const SizedBox(height: 12),
              _NameFilterField(
                label: 'Nhân viên',
                icon: Icons.badge_outlined,
                provider: employeesProvider,
                value: _employee,
                onChanged: (v) => _employee = v,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lọc theo ngày thanh toán'),
                subtitle: const Text('Dùng ngày trong lịch sử thanh toán thay cho ngày tạo đơn'),
                value: _byPaymentDate,
                onChanged: (v) => setSheet(() => _byPaymentDate = v),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _customer = '';
                        _employee = '';
                        _byPaymentDate = false;
                      });
                      Navigator.pop(ctx);
                      _search();
                    },
                    child: const Text('Xóa lọc'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      setState(() {});
                      _search();
                    },
                    child: const Text('Áp dụng'),
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stats(BuildContext context, List<OrderSummary> visible) {
    final total = visible.fold<double>(0, (s, o) => s + o.totalPrice);
    final cash = visible.fold<double>(0, (s, o) => s + o.cashAmount);
    final transfer = visible.fold<double>(0, (s, o) => s + o.transferAmount);
    final notConverted = visible.where((o) => !o.isConvertToLiter).length;
    final wide = isWide(context);

    final cards = [
      _StatCard(label: 'Số đơn', value: '${visible.length}', icon: Icons.receipt_outlined, color: AppColors.info),
      _StatCard(label: 'Tổng tiền', value: money(total), icon: Icons.account_balance_wallet_outlined, color: AppColors.seed),
      _StatCard(label: 'Tiền mặt', value: money(cash), icon: Icons.payments_outlined, color: AppColors.success),
      _StatCard(label: 'Chuyển khoản', value: money(transfer), icon: Icons.account_balance_outlined, color: AppColors.draft),
      _StatCard(label: 'Chưa quy đổi Lít', value: '$notConverted', icon: Icons.water_drop_outlined, color: AppColors.warning),
    ];

    return SizedBox(
      height: 84,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
        scrollDirection: Axis.horizontal,
        itemCount: cards.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (_, i) => cards[i],
      ),
    );
  }

  Widget _statusBar(BuildContext context) {
    final wide = isWide(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final s in StatusFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('${s.label} (${_orders.where(s.matches).length})'),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                ),
            ]),
          ),
        ),
        if (wide) ...[
          const SizedBox(width: 12),
          SizedBox(
            width: 260,
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Tìm nhanh: tên, SĐT, số HĐ…'),
              onChanged: (v) => setState(() => _quickSearch = v),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _body(BuildContext context, List<OrderSummary> visible, bool wide) {
    if (_loading && _orders.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_error != null && _orders.isEmpty) return ErrorView(message: _error!, onRetry: _search);
    if (visible.isEmpty) {
      return EmptyState(
        icon: Icons.inbox_outlined,
        title: 'Không có đơn hàng',
        message: _orders.isEmpty ? 'Thử đổi khoảng ngày hoặc bộ lọc.' : 'Không có đơn nào khớp trạng thái đang chọn.',
      );
    }

    final content = wide
        ? Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: OrdersTable(
              orders: visible,
              selected: _selected,
              onToggle: _toggle,
              onToggleAll: (all) => setState(() {
                if (all) {
                  _selected.addAll(visible.map((o) => o.id));
                } else {
                  _selected.removeAll(visible.map((o) => o.id));
                }
              }),
              onOpen: _openDetail,
            ),
          )
        : RefreshIndicator(
            onRefresh: _search,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              itemCount: visible.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final o = visible[i];
                return OrderCard(
                  order: o,
                  selected: _selected.contains(o.id),
                  onToggle: () => _toggle(o),
                  onOpen: () => _openDetail(o),
                );
              },
            ),
          );

    return Stack(children: [
      Positioned.fill(child: content),
      if (_loading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
    ]);
  }

  Widget? _selectionBar(BuildContext context) {
    if (_selected.isEmpty) return null;
    final t = Theme.of(context);
    final selected = _selectedOrders;
    final single = selected.length == 1 ? selected.first : null;
    final wide = isWide(context);

    final actions = <(IconData, String, VoidCallback?, bool)>[
      (Icons.task_alt_rounded, 'Lập hóa đơn', _issue, true),
      (Icons.edit_document, 'Lập nháp', _draft, false),
      (Icons.edit_outlined, 'Sửa', () => _edit(), false),
      (Icons.picture_as_pdf_outlined, 'PDF', single?.hasViettelInvoice == true ? () => openOrderInvoicePdf(context, single!) : null, false),
      (Icons.mail_outline_rounded, 'Email', single?.hasViettelInvoice == true ? () => sendInvoiceEmail(context, single!) : null, false),
    ];

    return Material(
      elevation: 8,
      color: t.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? 24 : 12, vertical: 10),
          child: Row(children: [
            IconButton(
              tooltip: 'Bỏ chọn',
              onPressed: () => setState(_selected.clear),
              icon: const Icon(Icons.close_rounded),
            ),
            Text('${_selected.length} đã chọn', style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            if (wide)
              Wrap(spacing: 8, children: [
                for (final (icon, label, onTap, primary) in actions)
                  primary
                      ? FilledButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label))
                      : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
              ])
            else ...[
              FilledButton.icon(onPressed: _issue, icon: const Icon(Icons.task_alt_rounded), label: const Text('Lập HĐ')),
              PopupMenuButton<int>(
                icon: const Icon(Icons.more_vert_rounded),
                itemBuilder: (_) => [
                  for (var i = 1; i < actions.length; i++)
                    PopupMenuItem(
                      value: i,
                      enabled: actions[i].$3 != null,
                      child: ListTile(leading: Icon(actions[i].$1), title: Text(actions[i].$2), contentPadding: EdgeInsets.zero),
                    ),
                ],
                onSelected: (i) => actions[i].$3?.call(),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Container(
        constraints: const BoxConstraints(minWidth: 170),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.textTheme.labelSmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            Text(value, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }
}

/// Ô lọc theo tên có gợi ý (thay combobox lọc Khách hàng / Nhân viên của bản cũ).
class _NameFilterField extends ConsumerWidget {
  const _NameFilterField({
    required this.label,
    required this.icon,
    required this.provider,
    required this.value,
    required this.onChanged,
    this.onSubmitted,
  });

  final String label;
  final IconData icon;
  final FutureProvider<List<NamedItem>> provider;
  final String value;
  final ValueChanged<String> onChanged;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final names = ref.watch(provider).value?.map((e) => e.name).toList() ?? const <String>[];
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: value),
      optionsBuilder: (v) {
        final q = v.text.trim().toLowerCase();
        if (q.isEmpty) return const Iterable<String>.empty();
        return names.where((n) => n.toLowerCase().contains(q)).take(30);
      },
      onSelected: (v) {
        onChanged(v);
        onSubmitted?.call();
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) => TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: (_) {
          onFieldSubmitted();
          onSubmitted?.call();
        },
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: ValueListenableBuilder(
            valueListenable: controller,
            builder: (_, v, _) => v.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                      onSubmitted?.call();
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
