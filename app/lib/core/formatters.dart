import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final _money = NumberFormat('#,##0', 'vi_VN');
final _decimal = NumberFormat('#,##0.####', 'vi_VN');
final _date = DateFormat('dd/MM/yyyy');
final _dateTime = DateFormat('dd/MM/yyyy HH:mm');

String money(num? v) => v == null ? '' : _money.format(v);
String moneyVnd(num? v) => v == null ? '' : '${_money.format(v)} ₫';
String decimal(num? v) => v == null ? '' : _decimal.format(v);
String fmtDate(DateTime? d) => d == null ? '' : _date.format(d.toLocal());
String fmtDateTime(DateTime? d) => d == null ? '' : _dateTime.format(d.toLocal());
String fmtPercent(num v) => '${v % 1 == 0 ? v.toInt() : v}%';

/// Parse số người dùng nhập theo kiểu Việt Nam (1.234.567,5) hoặc quốc tế (1,234,567.5).
double? parseNumber(String input) {
  var s = input.trim().replaceAll(' ', '');
  if (s.isEmpty) return null;
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  if (lastComma > lastDot) {
    // dấu phẩy là thập phân
    s = s.replaceAll('.', '').replaceAll(',', '.');
  } else if (lastDot > lastComma && lastComma >= 0) {
    s = s.replaceAll(',', '');
  } else if (lastDot >= 0 && RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(s)) {
    // 1.234.567 → nhóm hàng nghìn kiểu VN
    s = s.replaceAll('.', '');
  }
  return double.tryParse(s);
}

/// Tự chèn dấu chấm phân cách hàng nghìn khi nhập tiền.
class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;
    final commaIndex = text.indexOf(',');
    final intPart = (commaIndex >= 0 ? text.substring(0, commaIndex) : text).replaceAll(RegExp(r'[^0-9]'), '');
    final decPart = commaIndex >= 0 ? text.substring(commaIndex).replaceAll(RegExp(r'[^0-9,]'), '') : '';
    if (intPart.isEmpty) return newValue.copyWith(text: decPart, selection: TextSelection.collapsed(offset: decPart.length));
    final formatted = _money.format(int.parse(intPart)) + decPart;
    return TextEditingValue(text: formatted, selection: TextSelection.collapsed(offset: formatted.length));
  }
}

String formatPriceForInput(double v) {
  if (v % 1 == 0) return _money.format(v);
  return NumberFormat('#,##0.##########', 'vi_VN').format(v);
}
