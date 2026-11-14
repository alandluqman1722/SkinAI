import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<Uint8List> buildScanReportPdf({
  required String result,
  required double confidencePercent,
  required DateTime scannedAt,
  required String summary,
  required String Function(String key, {Map<String, String> arguments})
      localize,
}) async {
  final document = pw.Document();
  final timestamp =
      scannedAt.toLocal().toIso8601String().replaceFirst('T', ' ');

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      build: (context) => [
        pw.Text(
          localize('scanSummaryTitle'),
          style: pw.TextStyle(
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blue900,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '${localize('generatedAt')} ${DateTime.now().toLocal().toIso8601String()}',
        ),
        pw.SizedBox(height: 24),
        pw.Text(
          localize('screeningResult'),
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Divider(),
        _detailRow(localize('result'), result),
        _detailRow(
          localize('providerConfidence'),
          '${confidencePercent.toStringAsFixed(1)}%',
        ),
        _detailRow(localize('scanTime'), timestamp),
        pw.SizedBox(height: 20),
        pw.Text(
          localize('summaryLabel'),
          style: pw.TextStyle(
            fontSize: 15,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.Divider(),
        pw.Text(summary),
        pw.SizedBox(height: 30),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          color: PdfColors.grey200,
          child: pw.Text(
            localize('screeningDisclaimer'),
            style: const pw.TextStyle(fontSize: 10, lineSpacing: 3),
          ),
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _detailRow(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              label,
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(flex: 3, child: pw.Text(value)),
        ],
      ),
    );

Future<void> shareScanReport(Uint8List pdfBytes, String filename) =>
    Printing.sharePdf(bytes: pdfBytes, filename: filename);
