import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'api_client.dart';
import 'widgets.dart';

/// Tải PDF (kèm token) rồi mở màn hình xem / in / chia sẻ.
Future<void> openPdf(
  BuildContext context, {
  required String title,
  required String fileName,
  required Future<Uint8List> Function() load,
}) async {
  final navigator = Navigator.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: Card(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))),
  );
  Uint8List bytes;
  try {
    bytes = await load();
  } catch (e) {
    navigator.pop();
    if (context.mounted) showMessage(context, e is ApiException ? e.message : 'Không tải được PDF: $e', error: true);
    return;
  }
  navigator.pop();
  await navigator.push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => PdfViewerScreen(title: title, fileName: fileName, bytes: bytes),
  ));
}

class PdfViewerScreen extends StatelessWidget {
  const PdfViewerScreen({super.key, required this.title, required this.fileName, required this.bytes});

  final String title;
  final String fileName;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: 'Tải về / Chia sẻ',
            icon: const Icon(Icons.download_rounded),
            onPressed: () => Printing.sharePdf(bytes: bytes, filename: fileName),
          ),
          IconButton(
            tooltip: 'In',
            icon: const Icon(Icons.print_rounded),
            onPressed: () => Printing.layoutPdf(onLayout: (_) async => bytes, name: fileName),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PdfPreview(
        build: (_) async => bytes,
        pdfFileName: fileName,
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        scrollViewDecoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      ),
    );
  }
}
