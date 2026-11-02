import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as p;

import '../../../core/product_identity.dart';
import '../domain/report_data.dart';
import '../domain/report_request.dart';

class PdfReportWriter {
  Future<Uint8List> write(
    ReportData data,
    Uint8List regular,
    Uint8List bold,
  ) async {
    final theme = p.ThemeData.withFont(
      base: p.Font.ttf(ByteData.sublistView(regular)),
      bold: p.Font.ttf(ByteData.sublistView(bold)),
    );
    final document = p.Document(
      title: '${ProductIdentity.name} Vehicle Report',
      author: ProductIdentity.name,
      compress: false,
    );
    final coverage = PdfTtfFont(PdfDocument(), ByteData.sublistView(regular));
    String checked(String value) {
      if (value.runes.any((r) => r > 32 && !coverage.isRuneSupported(r))) {
        throw const ReportException(
          'A recorded character is not supported by the bundled PDF font. Use Excel to preserve that text.',
        );
      }
      return value;
    }

    final accent = PdfColor.fromHex('#20564C');
    p.Widget heading(String text) => p.Padding(
      padding: const p.EdgeInsets.only(top: 18, bottom: 8),
      child: p.Text(
        text,
        style: p.TextStyle(
          fontSize: 15,
          fontWeight: p.FontWeight.bold,
          color: accent,
        ),
      ),
    );
    p.Widget line(ReportMetric m) => p.Padding(
      padding: const p.EdgeInsets.only(bottom: 6),
      child: p.Column(
        crossAxisAlignment: p.CrossAxisAlignment.start,
        children: [
          p.Text(checked('${m.label}: ${reportDisplay(m.value, m.type)}')),
          if (m.note.isNotEmpty)
            p.Text(
              checked(m.note),
              style: const p.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
        ],
      ),
    );
    final content = <p.Widget>[
      p.Text(
        ProductIdentity.name,
        style: p.TextStyle(
          fontSize: 24,
          fontWeight: p.FontWeight.bold,
          color: accent,
        ),
      ),
      p.Text('Vehicle Report', style: const p.TextStyle(fontSize: 18)),
      p.SizedBox(height: 12),
      for (final m in data.identity) line(m),
      p.Text('Period: ${data.period}'),
      p.Text(
        'Generated: ${data.generatedAt.toIso8601String()} (UTC)',
        style: const p.TextStyle(fontSize: 9),
      ),
      p.Text(data.timezone, style: const p.TextStyle(fontSize: 9)),
      p.SizedBox(height: 10),
      p.Text(
        data.recordCount == 0
            ? 'No selected transaction records. Overview and selected metadata are included.'
            : 'Based on recorded data. Summary covers all period records; selected sections control detail tables.',
      ),
      heading('Costs'),
      for (final key in [
        'operating',
        'fuel',
        'service',
        'expenses',
        'acquisition',
        'ownership',
        'undated',
      ])
        line(data.metrics[key]!),
      if (data.breakdown.isNotEmpty) ...[
        heading('Spending breakdown'),
        for (final b in data.breakdown) line(b),
      ],
      heading('Fuel summary'),
      for (final key in [
        'volume',
        'price',
        'economy',
        'distance',
        'costDistance',
      ])
        line(data.metrics[key]!),
      heading('Driving earnings'),
      for (final key in [
        'gross',
        'linked',
        'net',
        'distanceRate',
        'hourRate',
        'deliveryRate',
        'netDistanceRate',
        'netHourRate',
      ])
        line(data.metrics[key]!),
      p.Padding(
        padding: const p.EdgeInsets.only(top: 8),
        child: p.Text(
          'Tables use concise recorded fields. Notes, technical IDs and some detailed columns are omitted from PDF; Excel contains the full selected detail. Linked costs are not additional period operating expenses.',
          style: const p.TextStyle(fontSize: 9),
        ),
      ),
    ];
    const indexes = <String, List<int>>{
      'Fuel': [0, 1, 4, 5, 7, 8],
      'Services': [0, 1, 3, 4, 5],
      'Service Items': [0, 1, 2],
      'Expenses': [0, 1, 3, 4, 6],
      'Income Activities': [0, 1, 3, 4, 17, 18],
      'Linked Costs': [2, 3, 4, 5, 6],
      'Odometer': [0, 1, 2, 3],
      'Documents': [0, 1, 3, 4, 5, 6],
    };
    for (final table in data.tables) {
      content.add(p.NewPage(freeSpace: 140));
      content.add(heading(table.name));
      if (table.caption.isNotEmpty) {
        content.add(
          p.Text(table.caption, style: const p.TextStyle(fontSize: 9)),
        );
      }
      if (table.rows.isEmpty) {
        content.add(
          p.Text(
            table.name == 'Documents'
                ? 'No recorded documents.'
                : 'No records in this period.',
          ),
        );
        continue;
      }
      final selected = indexes[table.name]!;
      final serviceDates = {
        for (final t in data.tables.where((t) => t.name == 'Services'))
          for (final r in t.rows) r.last: r.first,
      };
      final rows = <List<String>>[];
      for (final row in table.rows) {
        final values = [
          for (final i in selected)
            row[i] == null
                ? '—'
                : checked(
                    reportDisplay(
                      table.name == 'Service Items' && i == 0
                          ? serviceDates[row[i]]
                          : row[i],
                      table.name == 'Service Items' && i == 0
                          ? ReportValueType.date
                          : table.columns[i].type,
                      precision: table.columns[i].precision,
                    ),
                  ),
        ];
        // Bound individual physical row height, retaining all text via continuation rows.
        final chunks = [
          for (final v in values)
            _chunks(v, table.name == 'Documents' ? 90 : 120),
        ];
        final count = chunks.fold<int>(
          1,
          (n, c) => n > c.length ? n : c.length,
        );
        for (var part = 0; part < count; part++) {
          rows.add([for (final c in chunks) part < c.length ? c[part] : '']);
        }
      }
      content.add(
        p.TableHelper.fromTextArray(
          headers: [
            for (final i in selected)
              table.name == 'Service Items' && i == 0
                  ? 'Service date'
                  : table.columns[i].label,
          ],
          data: rows,
          headerStyle: p.TextStyle(fontWeight: p.FontWeight.bold, fontSize: 9),
          cellStyle: const p.TextStyle(fontSize: 10),
          cellPadding: const p.EdgeInsets.all(5),
          headerDecoration: const p.BoxDecoration(color: PdfColors.grey200),
          border: const p.TableBorder(
            horizontalInside: p.BorderSide(color: PdfColors.grey300, width: .4),
          ),
        ),
      );
    }
    document.addPage(
      p.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const p.EdgeInsets.all(32),
        theme: theme,
        maxPages: 10000,
        header: (_) => p.Padding(
          padding: const p.EdgeInsets.only(bottom: 10),
          child: p.Text(
            '${String.fromCharCodes(data.vehicleName.runes.take(80))}${data.vehicleName.runes.length > 80 ? '…' : ''} · ${data.period}',
            style: const p.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
        footer: (c) => p.Align(
          alignment: p.Alignment.centerRight,
          child: p.Text(
            '${ProductIdentity.name} · ${c.pageNumber} / ${c.pagesCount}',
            style: const p.TextStyle(fontSize: 9),
          ),
        ),
        build: (_) => content,
      ),
    );
    return document.save();
  }

  List<String> _chunks(String value, int count) {
    final chars = value.runes.toList();
    return [
      for (var i = 0; i < chars.length; i += count)
        String.fromCharCodes(
          chars.sublist(i, i + count > chars.length ? chars.length : i + count),
        ),
    ];
  }
}
