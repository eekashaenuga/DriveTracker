import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel_plus/excel_plus.dart' as x;
import 'package:drivetracker/features/reports/data/report_repository.dart';
import 'package:drivetracker/features/reports/domain/report_request.dart';
import 'package:drivetracker/features/reports/domain/report_data.dart';
import 'package:drivetracker/features/reports/infrastructure/xlsx_report_writer.dart';

import 'helpers/report_fixture.dart';

num numeric(x.CellValue? value) => switch (value) {
  x.IntCellValue() => value.value,
  x.DoubleCellValue() => value.value,
  _ => throw StateError('Expected typed numeric cell, got $value'),
};
void main() {
  test('Overview qualifications are text or truly blank, with typed metric formats', () async {
    final (s, id) = await reportFixture(complete: true);
    final d = await ReportRepository(
      s.database,
      clock: () => reportNow,
    ).load(reportRequest(id));
    final bytes = XlsxReportWriter().write(d);
    final zip = ZipDecoder().decodeBytes(bytes);
    final xml = utf8.decode(zip.find('xl/worksheets/sheet1.xml')!.readBytes()!);
    final b = x.Excel.decodeBytes(bytes);
    final o = b['Overview'];
    for (var r = 0; r < o.maxRows; r++) {
      final c = o.cell(
        x.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: r),
      );
      expect(c.value, anyOf(isNull, isA<x.TextCellValue>()));
      final originalNote = r >= 6 && r < 6 + d.identity.length
          ? d.identity[r - 6].note
          : r >= 6 + d.identity.length &&
                r < 6 + d.identity.length + d.metrics.length
          ? d.metrics.values.elementAt(r - 6 - d.identity.length).note
          : null;
      if (originalNote == '') {
        final cells = RegExp(
          '<c\\b[^>]*\\br="C${r + 1}"[^>]*>(.*?)</c>',
          dotAll: true,
        ).allMatches(xml);
        expect(
          cells.where((c) => RegExp(r'<v\b').hasMatch(c.group(1)!)),
          isEmpty,
          reason: 'Empty qualifications must not serialize a shared-string index such as 14',
        );
      }
    }
    x.Data metric(String label) {
      final r = o.rows.indexWhere(
        (row) => row.first?.value.toString() == label,
      );
      expect(r, greaterThanOrEqualTo(0));
      return o.cell(x.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r));
    }

    for (final m in [
      ...d.identity,
      ...d.metrics.values,
    ].where((m) => m.type == ReportValueType.money && m.value != null)) {
      final c = metric(m.label);
      expect(numeric(c.value), (m.value as num) / 100);
      expect(c.cellStyle!.numberFormat.formatCode, '£#,##0.00');
    }
    for (final label in [
      'Year',
      'Acquisitions without a recorded date',
      'Fuel records',
      'Expenses records',
    ]) {
      expect(metric(label).cellStyle!.numberFormat.formatCode, '0');
      expect(numeric(metric(label).value), isA<num>());
    }
    expect(
      metric('Purchased fuel (L)').cellStyle!.numberFormat.formatCode,
      '0.000',
    );
    expect(
      metric('Volume-weighted purchase price (p/L)')
          .cellStyle!
          .numberFormat
          .formatCode,
      '0.0000',
    );
    expect(
      metric('Measured full-to-full economy (UK MPG)')
          .cellStyle!
          .numberFormat
          .formatCode,
      '0.0',
    );
    expect(
      metric('Purchase date (vehicle context)').value,
      isA<x.DateCellValue>(),
    );
    expect(
      metric('Purchase date (vehicle context)')
          .cellStyle!
          .numberFormat
          .formatCode,
      'dd mmm yyyy',
    );
    for (final table in d.tables) {
      final sheet = b[table.name];
      for (final column in table.columns) {
        final ci = sheet.rows.first.indexWhere(
          (c) => c?.value.toString() == column.label,
        );
        if (ci < 0) continue; // Intentionally omitted ordinary ID.
        for (var r = 0; r < table.rows.length; r++) {
          final value = table.rows[r][table.columns.indexOf(column)];
          if (value is! num && value is! DateTime) continue;
          final cell = sheet.cell(
            x.CellIndex.indexByColumnRow(columnIndex: ci, rowIndex: r + 1),
          );
          final expected = value is DateTime
              ? column.type == ReportValueType.date
                    ? 'dd mmm yyyy'
                    : 'dd mmm yyyy hh:mm:ss'
              : column.type == ReportValueType.money
              ? '£#,##0.00'
              : column.label == 'Reimbursement rate GBP'
              ? '£0.000000'
              : column.precision == 0
              ? '0'
              : '0.${'0' * column.precision}';
          expect(
            cell.cellStyle!.numberFormat.formatCode,
            expected,
            reason: '${table.name}/${column.label}',
          );
          if (value is num) {
            expect(
              numeric(cell.value),
              column.type == ReportValueType.money ? value / 100 : value,
            );
          }
        }
      }
    }
  });

  test('only explicit relationship IDs appear in exported sheets', () async {
    final (s, id) = await reportFixture();
    final d = await ReportRepository(
      s.database,
      clock: () => reportNow,
    ).load(reportRequest(id));
    final b = x.Excel.decodeBytes(XlsxReportWriter().write(d));
    List<String> headers(String name) =>
        b[name].rows.first.map((c) => c?.value.toString() ?? '').toList();
    for (final name in ['Fuel', 'Odometer', 'Documents']) {
      expect(headers(name).where((h) => h.endsWith('ID')), isEmpty);
    }
    expect(headers('Service Items'), contains('Service ID'));
    expect(headers('Service Items'), isNot(contains('Item ID')));
    expect(headers('Services'), contains('Service ID'));
    expect(headers('Income Activities'), contains('Income ID'));
    expect(headers('Linked Costs').take(2), ['Income ID', 'Expense ID']);
    final links = d.tables.singleWhere((t) => t.name == 'Linked Costs');
    for (var r = 0; r < links.rows.length; r++) {
      expect(
        b['Linked Costs'].rows[r + 1][0]!.value.toString(),
        links.rows[r][0],
      );
      expect(
        b['Linked Costs'].rows[r + 1][1]!.value.toString(),
        links.rows[r][1],
      );
    }
    // An in-period relationship exposes its parent key, not unrelated row IDs.
    final expenses = d.tables.singleWhere((t) => t.name == 'Expenses');
    final expenseId = expenses.rows.first.last;
    final linkedRows = links.rows
        .map((r) => [r[0], expenseId, ...r.skip(2)])
        .toList();
    final inPeriod = ReportData(
      vehicleName: d.vehicleName,
      period: d.period,
      generatedAt: d.generatedAt,
      timezone: d.timezone,
      identity: d.identity,
      metrics: d.metrics,
      tables: [
        for (final t in d.tables)
          if (t.name == 'Linked Costs')
            ReportTable(t.name, t.columns, linkedRows, caption: t.caption)
          else
            t,
      ],
      breakdown: d.breakdown,
      recordCount: d.recordCount,
    );
    final relatedBook = x.Excel.decodeBytes(XlsxReportWriter().write(inPeriod));
    final expenseSheet = relatedBook['Expenses'];
    final keyColumn = expenseSheet.rows.first.indexWhere(
      (c) => c?.value.toString() == 'Expense ID',
    );
    expect(keyColumn, greaterThanOrEqualTo(0));
    expect(expenseSheet.rows[1][keyColumn]!.value.toString(), expenseId);
    for (final row in expenseSheet.rows.skip(2)) {
      expect(
        row[keyColumn]?.value,
        isNull,
        reason: 'Unreferenced expense keys are not exported',
      );
    }
    // Expense IDs are exposed only when needed to resolve a linked cost.
    final withoutLinks = ReportData(
      vehicleName: d.vehicleName,
      period: d.period,
      generatedAt: d.generatedAt,
      timezone: d.timezone,
      identity: d.identity,
      metrics: d.metrics,
      tables: d.tables
          .where((t) => t.name != 'Linked Costs' && t.name != 'Service Items')
          .toList(),
      breakdown: d.breakdown,
      recordCount: d.recordCount,
    );
    final unlinked = x.Excel.decodeBytes(
      XlsxReportWriter().write(withoutLinks),
    );
    for (final name in ['Services', 'Expenses', 'Income Activities']) {
      expect(
        unlinked[name].rows.first.where(
          (c) => c?.value.toString().endsWith('ID') ?? false,
        ),
        isEmpty,
      );
    }
  });

  test('export omits template author and host metadata', () async {
    final (s, id) = await reportFixture();
    final d = await ReportRepository(
      s.database,
      clock: () => reportNow,
    ).load(reportRequest(id));
    final zip = ZipDecoder().decodeBytes(XlsxReportWriter().write(d));
    // The writer omits document properties entirely. Reader defaults are not
    // metadata stored in the export.
    expect(zip.find('docProps/core.xml'), isNull);
    expect(zip.find('docProps/app.xml'), isNull);
  });

  test('workbook headers types money precision dates relationships and >200 rows roundtrip', () async {
    final (s, id) = await reportFixture(expenses: 1001, complete: true);
    final d = await ReportRepository(
      s.database,
      clock: () => reportNow,
    ).load(reportRequest(id));
    final bytes = XlsxReportWriter().write(d);
    await File('${Directory.systemTemp.path}/vehnora-m6-final-artifact.xlsx')
        .writeAsBytes(bytes);
    final b = x.Excel.decodeBytes(bytes);
    expect(b.tables.keys, [
      'Overview',
      'Fuel',
      'Services',
      'Service Items',
      'Expenses',
      'Income Activities',
      'Linked Costs',
      'Odometer',
      'Documents',
    ]);
    final e = b['Expenses'];
    expect(e.maxRows, 1002);
    expect(e.frozenRows, 1);
    expect(
      e.cell(x.CellIndex.indexByString('A1')).value.toString(),
      'Local date/time',
    );
    expect(
      e.cell(x.CellIndex.indexByString('A2')).value,
      isA<x.DateTimeCellValue>(),
    );
    expect(numeric(e.cell(x.CellIndex.indexByString('D2')).value), 1.0);
    expect(
      e.cell(x.CellIndex.indexByString('G2')).value,
      isA<x.TextCellValue>(),
    );
    expect(
      e.cell(x.CellIndex.indexByString('G2')).value.toString(),
      '=SUM(A1:A2)',
    );
    expect(
      (b['Fuel'].cell(x.CellIndex.indexByString('E2')).value
              as x.DoubleCellValue)
          .value,
      40.001,
    );
    expect(
      b['Linked Costs'].cell(x.CellIndex.indexByString('G2')).value.toString(),
      'Yes',
    );
    expect(b['Services'].cell(x.CellIndex.indexByString('F2')).value, isNull);
    expect(
      numeric(b['Service Items'].cell(x.CellIndex.indexByString('C2')).value),
      0,
    );
    expect(
      b['Service Items'].cell(x.CellIndex.indexByString('C3')).value,
      isNull,
    );
    expect(
      numeric(
        b['Income Activities'].cell(x.CellIndex.indexByString('E2')).value,
      ),
      10,
    );
    expect(bytes, isNotEmpty);
  });
  for (final prefix in ['=', '+', '-', '@']) {
    test('explicit text prevents formula injection $prefix', () {
      final table = ReportTable(
        'Expenses',
        [const ReportColumn('Text')],
        [
          ['${prefix}SUM(A1:A2)'],
        ],
      );
      final d = ReportData(
        vehicleName: 'v',
        period: 'All time',
        generatedAt: reportNow,
        timezone: 'UTC',
        identity: [],
        metrics: {},
        tables: [table],
        breakdown: [],
        recordCount: 1,
      );
      final b = x.Excel.decodeBytes(XlsxReportWriter().write(d));
      expect(
        b['Expenses'].cell(x.CellIndex.indexByString('A2')).value,
        isA<x.TextCellValue>(),
      );
      expect(
        b['Expenses'].cell(x.CellIndex.indexByString('A2')).value.toString(),
        '${prefix}SUM(A1:A2)',
      );
    });
  }
  test('empty selected sheet is present; absent sections omitted', () async {
    final (s, id) = await reportFixture();
    final d = await ReportRepository(s.database, clock: () => reportNow).load(
      reportRequest(
        id,
        sections: {ReportSection.fuel},
        range: reportRequest(id).range,
      ),
    );
    final table = ReportTable('Fuel', d.tables.first.columns, []);
    final empty = ReportData(
      vehicleName: d.vehicleName,
      period: d.period,
      generatedAt: d.generatedAt,
      timezone: d.timezone,
      identity: d.identity,
      metrics: d.metrics,
      tables: [table],
      breakdown: d.breakdown,
      recordCount: 0,
    );
    final b = x.Excel.decodeBytes(XlsxReportWriter().write(empty));
    expect(b.tables.keys, ['Overview', 'Fuel']);
    expect(b['Fuel'].maxRows, 1);
  });
  for (final length in [32000, 32768]) {
    test('long text $length preserved or rejected explicitly', () {
      final table = ReportTable(
        'Notes',
        [const ReportColumn('Notes')],
        [
          ['a' * length],
        ],
      );
      final d = ReportData(
        vehicleName: 'v',
        period: 'All time',
        generatedAt: reportNow,
        timezone: 'UTC',
        identity: [],
        metrics: {},
        tables: [table],
        breakdown: [],
        recordCount: 1,
      );
      if (length > 32767) {
        expect(
          () => XlsxReportWriter().write(d),
          throwsA(isA<ReportException>()),
        );
      } else {
        final b = x.Excel.decodeBytes(XlsxReportWriter().write(d));
        expect(
          b['Notes'].cell(x.CellIndex.indexByString('A2')).value.toString(),
          hasLength(length),
        );
      }
    });
  }
}
