import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('vi');
  final prefs = await SharedPreferences.getInstance();

  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    // Lỗi API hiển thị ngay cho người dùng, không tự thử lại ngầm
    retry: (_, _) => null,
    child: const InvoiceApp(),
  ));
}
