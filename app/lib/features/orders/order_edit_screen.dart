import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../models/models.dart';
import '../../state/app_state.dart';
import '../../state/lookups.dart';

/// Sửa một hoặc nhiều đơn (mỗi đơn một tab, lưu tất cả cùng lúc) — thay frmEditOrder và frmEditMultipleOrders.
class OrderEditScreen extends ConsumerStatefulWidget {
  const OrderEditScreen({super.key, required this.orderIds});
  final List<String> orderIds;

  @override
  ConsumerState<OrderEditScreen> createState() => _OrderEditScreenState();
}

class _OrderEditScreenState extends ConsumerState<OrderEditScreen> {
  late final Map<String, GlobalKey<_OrderEditorState>> _keys = {
    for (final id in widget.orderIds) id: GlobalKey<_OrderEditorState>(),
  };
  final Map<String, String> _titles = {};
  bool _saving = false;

  Future<void> _saveAll() async {
    final editors = _keys.values.map((k) => k.currentState).whereType<_OrderEditorState>().toList();
    if (editors.isEmpty) return;

    setState(() => _saving = true);
    var ok = 0;
    final errors = <String>[];
    for (final e in editors) {
      final err = await e.save();
      if (err == null) {
        ok++;
      } else {
        errors.add('${e.title}: $err');
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);

    if (errors.isEmpty) {
      showMessage(context, editors.length > 1 ? 'Đã lưu $ok/${editors.length} đơn' : 'Lưu thành công!');
      Navigator.of(context).pop(true);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Đã lưu $ok/${editors.length} đơn'),
          content: Text(errors.join('\n\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.orderIds.length > 1;
    final editors = [
      for (final id in widget.orderIds)
        _OrderEditor(
          key: _keys[id],
          orderId: id,
          onTitle: (title) {
            if (_titles[id] != title) setState(() => _titles[id] = title);
          },
        ),
    ];

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Quay lại',
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.canPop() ? context.pop() : context.go('/orders'),
        ),
        title: Text(multiple ? 'Sửa ${widget.orderIds.length} đơn hàng' : 'Sửa đơn hàng'),
        bottom: multiple
            ? TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [for (final id in widget.orderIds) Tab(text: _titles[id] ?? 'Đơn …')],
              )
            : null,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveAll,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_rounded),
              label: Text(multiple ? 'Lưu tất cả' : 'Lưu'),
            ),
          ),
        ],
      ),
      body: multiple ? TabBarView(children: editors) : editors.first,
    );

    return multiple ? DefaultTabController(length: widget.orderIds.length, child: scaffold) : scaffold;
  }
}

class _OrderEditor extends ConsumerStatefulWidget {
  const _OrderEditor({super.key, required this.orderId, required this.onTitle});
  final String orderId;
  final ValueChanged<String> onTitle;

  @override
  ConsumerState<_OrderEditor> createState() => _OrderEditorState();
}

class _OrderEditorState extends ConsumerState<_OrderEditor> with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _tax = TextEditingController();

  List<OrderItem> _items = [];
  bool _converted = false;
  int _autoConverted = 0;
  bool _loading = true;
  String? _error;

  String get title => _name.text.isNotEmpty ? _name.text : widget.orderId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _tax]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = OrderDetail.fromJson(await ref.read(apiProvider).get('/api/orders/${Uri.encodeComponent(widget.orderId)}'));
      if (!mounted) return;
      setState(() {
        _name.text = d.customerName;
        _phone.text = d.customerPhone;
        _address.text = d.customerAddress;
        _tax.text = decimal(d.taxPercent);
        _items = d.items;
        _converted = d.isConvertToLiter;
        _autoConverted = d.autoConvertedCount;
      });
      widget.onTitle(d.customerPhone.isNotEmpty ? '${d.customerName} (${d.customerPhone})' : d.customerName);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _taxPercent => parseNumber(_tax.text) ?? 0;
  double get _subtotal => _items.fold(0, (s, i) => s + i.total);
  double get _total => _subtotal * (1 + _taxPercent / 100);

  /// Trả về null nếu thành công, ngược lại là thông báo lỗi.
  Future<String?> save() async {
    if (_loading || _error != null) return _error ?? 'Đang tải dữ liệu';
    if (_items.isEmpty) return 'Vui lòng thêm ít nhất một item!';
    try {
      await ref.read(apiProvider).put('/api/orders/${Uri.encodeComponent(widget.orderId)}', {
        'customerName': _name.text.trim(),
        'customerPhone': _phone.text.trim(),
        'customerAddress': _address.text.trim(),
        'taxPercent': _taxPercent,
        'isConvertToLiter': _converted,
        'items': _items.map((e) => e.toJson()).toList(),
      });
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<void> _editItem([int? index]) async {
    final item = await showAdaptiveSheet<OrderItem>(
      context,
      maxWidth: 520,
      builder: (_) => _ItemForm(initial: index == null ? null : _items[index]),
    );
    if (item == null) return;
    setState(() {
      if (index == null) {
        _items.add(item);
      } else {
        _items[index] = item;
      }
    });
  }

  Future<void> _removeItem(int index) async {
    final item = _items[index];
    final ok = await confirmDialog(
      context,
      title: 'Xóa item?',
      message: 'Bạn có chắc chắn muốn xóa "${item.serviceName}"?\nSố lượng: ${decimal(item.quantity)}, Đơn giá: ${money(item.unitPrice)}',
      confirmText: 'Xóa',
      destructive: true,
    );
    if (ok) setState(() => _items.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorView(message: _error!, onRetry: _load);

    final t = Theme.of(context);
    final wide = isWide(context);

    final customer = SectionCard(
      title: 'Khách hàng',
      child: Column(children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tên khách hàng', prefixIcon: Icon(Icons.storefront_outlined))),
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone_outlined)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _address,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Địa chỉ', prefixIcon: Icon(Icons.place_outlined)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _tax,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Thuế (%)', prefixIcon: Icon(Icons.percent_rounded)),
        ),
      ]),
    );

    final summary = SectionCard(
      title: 'Tổng cộng',
      child: Column(children: [
        _row(context, 'Tiền hàng (SL thực)', moneyVnd(_subtotal)),
        _row(context, 'Thuế ${decimal(_taxPercent)}%', moneyVnd(_subtotal * _taxPercent / 100)),
        const Divider(height: 20),
        _row(context, 'Tổng tiền', moneyVnd(_total), emphasize: true),
      ]),
    );

    final items = SectionCard(
      title: 'Hàng hóa (${_items.length})',
      trailing: FilledButton.tonalIcon(onPressed: () => _editItem(), icon: const Icon(Icons.add_rounded), label: const Text('Thêm')),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: _items.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Chưa có item nào')))
          : Column(children: [
              for (var i = 0; i < _items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _itemTile(context, i),
              ],
            ]),
    );

    final banners = <Widget>[
      if (_autoConverted > 0)
        WarningBox(['Đã tự động quy đổi $_autoConverted item sang Lít (số lượng × Production, đơn giá ÷ Production). Bấm Lưu để ghi vào database.']),
      if (_converted && _autoConverted == 0)
        Align(alignment: Alignment.centerLeft, child: StatusChip('Đã quy đổi sang Lít', color: AppColors.success, icon: Icons.water_drop_rounded)),
    ];

    if (wide) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 360, child: Column(children: [customer, const SizedBox(height: 16), summary])),
                const SizedBox(width: 16),
                Expanded(child: items),
              ]),
            ]),
          ),
        ),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      for (final b in banners) Padding(padding: const EdgeInsets.only(bottom: 12), child: b),
      customer,
      const SizedBox(height: 12),
      items,
      const SizedBox(height: 12),
      summary,
      SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
      Text('ID: ${widget.orderId}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.outline)),
    ]);
  }

  Widget _row(BuildContext context, String label, String value, {bool emphasize = false}) {
    final t = Theme.of(context);
    final style = emphasize
        ? t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: t.colorScheme.primary)
        : t.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
    );
  }

  Widget _itemTile(BuildContext context, int i) {
    final t = Theme.of(context);
    final item = _items[i];
    return InkWell(
      onTap: () => _editItem(i),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.serviceName, style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Wrap(spacing: 12, children: [
                Text('SL ${decimal(item.quantity)}', style: t.textTheme.bodySmall),
                if (item.promotionQuantity > 0)
                  Text('KM ${decimal(item.promotionQuantity)}', style: t.textTheme.bodySmall?.copyWith(color: AppColors.draft)),
                Text('SL thực ${decimal(item.actualQuantity)}', style: t.textTheme.bodySmall),
                Text('× ${decimal(item.unitPrice)}', style: t.textTheme.bodySmall),
              ]),
            ]),
          ),
          Text(money(item.total), style: t.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          PopupMenuButton<String>(
            onSelected: (v) => v == 'edit' ? _editItem(i) : _removeItem(i),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Sửa'), contentPadding: EdgeInsets.zero)),
              PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Xóa'), contentPadding: EdgeInsets.zero)),
            ],
          ),
        ]),
      ),
    );
  }
}

/// Form thêm / sửa một item của đơn.
class _ItemForm extends ConsumerStatefulWidget {
  const _ItemForm({this.initial});
  final OrderItem? initial;

  @override
  ConsumerState<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends ConsumerState<_ItemForm> {
  final _form = GlobalKey<FormState>();
  late final _qty = TextEditingController(text: widget.initial == null ? '' : '${widget.initial!.quantity}');
  late final _promo = TextEditingController(text: widget.initial == null ? '0' : '${widget.initial!.promotionQuantity}');
  late final _price = TextEditingController(text: widget.initial == null ? '' : formatPriceForInput(widget.initial!.unitPrice));
  ServiceItem? _service;
  late String _serviceName = widget.initial?.serviceName ?? '';
  late String _serviceId = widget.initial?.serviceId ?? '';

  @override
  void dispose() {
    _qty.dispose();
    _promo.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      OrderItem(
        serviceId: _service?.id ?? _serviceId,
        serviceName: _service?.name ?? _serviceName,
        quantity: int.parse(_qty.text.trim()),
        promotionQuantity: int.tryParse(_promo.text.trim()) ?? 0,
        unitPrice: parseNumber(_price.text)!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SheetHeader(title: widget.initial == null ? 'Thêm item' : 'Cập nhật item', icon: Icons.inventory_2_outlined),
      Flexible(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Form(
            key: _form,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              services.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Không tải được danh sách dịch vụ: $e'),
                data: (list) => Autocomplete<ServiceItem>(
                  initialValue: TextEditingValue(text: _serviceName),
                  displayStringForOption: (s) => s.name,
                  optionsBuilder: (v) {
                    final q = v.text.trim().toLowerCase();
                    if (q.isEmpty) return list.take(50);
                    return list.where((s) => s.name.toLowerCase().contains(q) || (s.code?.toLowerCase().contains(q) ?? false)).take(50);
                  },
                  onSelected: (s) => setState(() {
                    _service = s;
                    _serviceId = s.id;
                    _serviceName = s.name;
                  }),
                  fieldViewBuilder: (context, controller, focusNode, _) => TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(labelText: 'Dịch vụ / hàng hóa', prefixIcon: Icon(Icons.search_rounded)),
                    onChanged: (v) {
                      // Gõ lại tên thì phải chọn lại từ danh sách
                      if (v != _serviceName) {
                        _service = null;
                        _serviceId = '';
                      }
                    },
                    validator: (_) => _serviceId.isEmpty ? 'Vui lòng chọn dịch vụ từ danh sách!' : null,
                  ),
                ),
              ),
              if (_service != null && _service!.production > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('Quy cách: ${decimal(_service!.production)} Lít / ${_service!.unit ?? 'đơn vị'} · VAT ${fmtPercent(_service!.taxPercent)}',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Số lượng'),
                    validator: (v) => (int.tryParse(v?.trim() ?? '') ?? 0) <= 0 ? 'Số lượng không hợp lệ' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _promo,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'SL khuyến mãi'),
                    validator: (v) {
                      final p = int.tryParse(v?.trim() ?? '') ?? 0;
                      final q = int.tryParse(_qty.text.trim()) ?? 0;
                      return p > q ? 'Lớn hơn số lượng' : null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ThousandsInputFormatter()],
                decoration: const InputDecoration(labelText: 'Đơn giá', suffixText: '₫'),
                validator: (v) => (parseNumber(v ?? '') ?? 0) <= 0 ? 'Đơn giá không hợp lệ' : null,
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _submit, child: Text(widget.initial == null ? 'Thêm' : 'Cập nhật')),
            ]),
          ),
        ),
      ),
    ]);
  }
}
