import 'package:flutter/material.dart';

/// Nhóm ô Mẫu số / Ký hiệu / MST dùng chung cho lập hóa đơn và lập nháp.
class InvoiceHeaderFields extends StatelessWidget {
  const InvoiceHeaderFields({
    super.key,
    required this.taxCode,
    required this.templateCode,
    required this.invoiceSeries,
    this.onChanged,
  });

  final TextEditingController taxCode;
  final TextEditingController templateCode;
  final TextEditingController invoiceSeries;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c, IconData icon) => TextField(
          controller: c,
          onChanged: (_) => onChanged?.call(),
          decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20)),
        );

    return LayoutBuilder(builder: (context, c) {
      final children = [
        field('Mẫu số', templateCode, Icons.description_outlined),
        field('Ký hiệu (Series)', invoiceSeries, Icons.tag_rounded),
        field('Mã số thuế bên bán', taxCode, Icons.business_outlined),
      ];
      if (c.maxWidth < 560) {
        return Column(children: [
          for (final w in children) Padding(padding: const EdgeInsets.only(bottom: 10), child: w),
        ]);
      }
      return Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: children[i]),
        ],
      ]);
    });
  }
}
