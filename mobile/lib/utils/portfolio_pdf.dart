import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/portfolio.dart';
import '../services/api_service.dart';
import 'format.dart';

const _companyNames = {
  '3': 'Agropecuaria Santacruz',
  '8': 'Carnes Frías Santacruz',
  'MTAT': 'Montería TAT Agropecuaria',
};

String companyDisplayName(Company company) => _companyNames[company.id] ?? company.name;

const _green = PdfColor.fromInt(0xFF1E9B50);
const _red = PdfColor.fromInt(0xFFDC2626);
const _muted = PdfColor.fromInt(0xFF6B7280);
const _line = PdfColor.fromInt(0xFFE2E8F0);
const _soft = PdfColor.fromInt(0xFFF1F5F9);

/// Estado de cuenta del cliente en PDF (A4), con resumen, antigüedad y documentos.
Future<Uint8List> buildPortfolioPdf({
  required PortfolioDetail detail,
  required Company company,
  String? sellerName,
}) async {
  pw.MemoryImage? logo;
  try {
    logo = pw.MemoryImage((await rootBundle.load(company.logoAsset)).buffer.asUint8List());
  } catch (_) {
    logo = null;
  }
  final s = detail.summary;
  final doc = pw.Document(title: 'Estado de cartera ${detail.name}', author: companyDisplayName(company));

  pw.Widget label(String text) => pw.Text(text, style: const pw.TextStyle(fontSize: 8, color: _muted));

  pw.Widget kpi(String title, String value, {PdfColor color = PdfColors.black}) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(8),
      margin: const pw.EdgeInsets.only(right: 6),
      decoration: pw.BoxDecoration(color: _soft, borderRadius: pw.BorderRadius.circular(6)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          label(title),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color),
          ),
        ],
      ),
    ),
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      // Clientes grandes tienen cientos de documentos.
      maxPages: 200,
      margin: const pw.EdgeInsets.fromLTRB(32, 32, 32, 40),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                'Estado de cartera · ${detail.name} (NIT ${detail.nit})',
                style: const pw.TextStyle(fontSize: 8, color: _muted),
              ),
            ),
      footer: (context) => pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Generado por SIGCOM${sellerName == null ? '' : ' · $sellerName'} · ${formatDateTime(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7, color: _muted),
            ),
          ),
          pw.Text(
            'Página ${context.pageNumber} de ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          ),
        ],
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            if (logo != null) pw.Container(height: 44, width: 90, child: pw.Image(logo, fit: pw.BoxFit.contain)),
            if (logo != null) pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(companyDisplayName(company), style: const pw.TextStyle(fontSize: 10, color: _muted)),
                  pw.Text(
                    'Estado de cartera',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _green),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                label('Fecha de corte'),
                pw.Text(formatDate(s.asOf), style: const pw.TextStyle(fontSize: 11)),
              ],
            ),
          ],
        ),
        pw.Divider(color: _green, thickness: 1.5, height: 20),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  label('Cliente'),
                  pw.Text(detail.name, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text('NIT ${detail.nit}', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (detail.paymentTerm != null) ...[
                    label('Condición de pago'),
                    pw.Text(detail.paymentTerm!, style: const pw.TextStyle(fontSize: 9)),
                  ],
                  if (detail.phones.isNotEmpty) ...[
                    label('Teléfono'),
                    pw.Text(detail.phones.first, style: const pw.TextStyle(fontSize: 9)),
                  ],
                  if (detail.emails.isNotEmpty) ...[
                    label('Correo'),
                    pw.Text(detail.emails.first, style: const pw.TextStyle(fontSize: 9)),
                  ],
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Row(
          children: [
            kpi('Saldo total', formatMoney(s.total)),
            kpi('Saldo vencido', formatMoney(s.overdue), color: s.overdue > 0 ? _red : _green),
            kpi('Por vencer', formatMoney(s.current)),
            kpi('Mora máxima', '${s.maxDaysOverdue} días', color: s.maxDaysOverdue > 0 ? _red : PdfColors.black),
            if (s.creditLimit != null) kpi('Cupo', formatMoney(s.creditLimit!)),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text('Antigüedad de saldos', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Rango', 'Saldo', '%'],
          data: [
            for (final e in PortfolioSummary.agingLabels.entries)
              [
                e.value,
                formatMoney(s.aging[e.key] ?? 0),
                s.total == 0 ? '-' : formatPercent((s.aging[e.key] ?? 0) / s.total),
              ],
          ],
          headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _green),
          cellStyle: const pw.TextStyle(fontSize: 8.5),
          cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
          border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: 0.5)),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(1),
          },
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Documentos pendientes (${detail.documents.length})',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Documento', 'Tipo', 'Suc.', 'Fecha', 'Vence', 'Días', 'Saldo'],
          data: [
            for (final d in detail.documents)
              [
                d.number,
                d.type,
                d.branch,
                d.date == null ? '-' : formatDate(d.date!),
                d.dueDate == null ? '-' : formatDate(d.dueDate!),
                d.daysOverdue > 0 ? '${d.daysOverdue}' : '-',
                formatMoney(d.balance),
              ],
          ],
          headerStyle: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: _green),
          cellStyle: const pw.TextStyle(fontSize: 7.5),
          oddRowDecoration: const pw.BoxDecoration(color: _soft),
          cellAlignments: {2: pw.Alignment.center, 5: pw.Alignment.centerRight, 6: pw.Alignment.centerRight},
          textStyleBuilder: (index, data, rowNum) =>
              index == 5 && rowNum > 0 && data != '-' ? const pw.TextStyle(fontSize: 7.5, color: _red) : null,
          columnWidths: {
            0: const pw.FlexColumnWidth(1.6),
            1: const pw.FlexColumnWidth(2.6),
            2: const pw.FlexColumnWidth(0.6),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.4),
            5: const pw.FlexColumnWidth(0.7),
            6: const pw.FlexColumnWidth(1.6),
          },
        ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Si ya realizó algún pago, por favor haga caso omiso de los documentos correspondientes o envíenos el soporte.',
          style: const pw.TextStyle(fontSize: 8, color: _muted),
        ),
      ],
    ),
  );
  return doc.save();
}
