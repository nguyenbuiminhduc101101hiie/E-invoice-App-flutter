import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:invoice_app/core/formatters.dart';

void main() {
  setUpAll(() => initializeDateFormatting('vi'));

  test('parseNumber hiểu cả kiểu Việt Nam và quốc tế', () {
    expect(parseNumber('1.234.567'), 1234567);
    expect(parseNumber('1.234.567,5'), 1234567.5);
    expect(parseNumber('1,234,567.5'), 1234567.5);
    expect(parseNumber('55000'), 55000);
    expect(parseNumber('10,5'), 10.5);
    expect(parseNumber(''), isNull);
  });

  test('money định dạng phân cách hàng nghìn', () {
    expect(money(2200000), '2.200.000');
    expect(moneyVnd(440000), '440.000 ₫');
  });

  test('formatPriceForInput giữ phần thập phân', () {
    expect(formatPriceForInput(55000), '55.000');
    expect(formatPriceForInput(20000.5), '20.000,5');
    expect(parseNumber(formatPriceForInput(20000.5)), 20000.5);
  });
}
