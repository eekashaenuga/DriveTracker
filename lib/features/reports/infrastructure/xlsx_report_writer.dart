import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart' as x;

import '../../../core/product_identity.dart';
import '../domain/report_data.dart';
import '../domain/report_request.dart';

class XlsxReportWriter {
  Uint8List write(ReportData data) {
    final book = x.Excel.createExcel();
    book.rename('Sheet1', 'Overview');
    final overview = book['Overview'];
    final summary = <List<Object?>>[
      [ProductIdentity.name, 'Vehicle report / data export', null],
      ['Report period', data.period, null],
      ['Generated UTC', data.generatedAt.toIso8601String(), null],
      ['Date interpretation', data.timezone, null],
      [
        'Scope',
        'Summary covers all recorded period data. Section choices control detail sheets.',
        null,
      ],
      [
        'Notes',
        'Blank = not recorded / unavailable. Numeric zero is a recorded zero. No spreadsheet formulas are used.',
        null,
      ],
      for (final m in data.identity) [m.label, m.value, m.note],
      for (final m in data.metrics.values) [m.label, m.value, m.note],
      for (final t in data.tables)
        ['${t.name} records', t.rows.length, t.caption],
    ];
    final types = <ReportValueType>[
      for (var i = 0; i < 6; i++) ReportValueType.text,
      ...data.identity.map((m) => m.type),
      ...data.metrics.values.map((m) => m.type),
      ...data.tables.map((_) => ReportValueType.number),
    ];
    final precisions = <int>[
      ...List.filled(6, 0),
      ...data.identity.map((_) => 0),
      ...data.metrics.keys.map(
        (key) => switch (key) {
          'volume' => 3,
          'price' => 4,
          'economy' => 1,
          'distance' || 'undated' => 0,
          _ => 2,
        },
      ),
      ...data.tables.map((_) => 0),
    ];
    overview.setColumnWidth(0, 48);
    overview.setColumnWidth(1, 42);
    overview.setColumnWidth(2, 70);
    for (var row = 0; row < summary.length; row++) {
      for (var col = 0; col < 3; col++) {
        _put(
          overview,
          row,
          col,
          summary[row][col],
          col == 1 ? types[row] : ReportValueType.text,
          precision: precisions[row],
        );
      }
    }
    for (var col = 0; col < 3; col++) {
      overview
          .cell(x.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
          .cellStyle = x.CellStyle(
        bold: true,
        fontSize: 16,
        backgroundColorHex: x.ExcelColor.fromHexString('#DDEEE9'),
        fontColorHex: x.ExcelColor.fromHexString('#173F38'),
      );
    }
    overview.freezePanes(rows: 1);
    // IDs are presentation-only relationship keys, never ordinary record metadata.
    final related = <String, Set<Object?>>{
      'Service ID': {},
      'Income ID': {},
      'Expense ID': {},
    };
    for (final table in data.tables) {
      if (table.name == 'Service Items') {
        related['Service ID']!.addAll(table.rows.map((r) => r[0]));
      } else if (table.name == 'Linked Costs') {
        related['Income ID']!.addAll(table.rows.map((r) => r[0]));
        related['Expense ID']!.addAll(table.rows.map((r) => r[1]));
      }
    }
    for (final table in data.tables) {
      if (table.rows.length > 1048575) {
        throw const ReportException(
          'This selection exceeds the spreadsheet row limit. Choose a shorter period.',
        );
      }
      final sheet = book[table.name];
      final columns = [
        for (var i = 0; i < table.columns.length; i++)
          if (!table.columns[i].label.endsWith('ID') ||
              table.name == 'Linked Costs' ||
              (table.name == 'Service Items' &&
                  table.columns[i].label == 'Service ID') ||
              (const {
                    'Services',
                    'Expenses',
                    'Income Activities',
                  }.contains(table.name) &&
                  (related[table.columns[i].label]?.isNotEmpty ?? false)))
            i,
      ];
      for (var col = 0; col < columns.length; col++) {
        final column = table.columns[columns[col]];
        sheet.setColumnWidth(col, column.width);
        _put(sheet, 0, col, column.label, ReportValueType.text);
        sheet
            .cell(x.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
            .cellStyle = x.CellStyle(
          bold: true,
          backgroundColorHex: x.ExcelColor.fromHexString('#DDEEE9'),
          fontColorHex: x.ExcelColor.fromHexString('#173F38'),
          textWrapping: x.TextWrapping.WrapText,
        );
      }
      for (var row = 0; row < table.rows.length; row++) {
        for (var col = 0; col < columns.length; col++) {
          final source = columns[col];
          final column = table.columns[source];
          final value = table.rows[row][source];
          _put(
            sheet,
            row + 1,
            col,
            column.label.endsWith('ID') &&
                    table.name != 'Linked Costs' &&
                    table.name != 'Service Items' &&
                    !related[column.label]!.contains(value)
                ? null
                : value,
            column.type,
            precision: column.precision,
            numberFormat: column.label == 'Reimbursement rate GBP'
                ? '£0.000000'
                : null,
          );
        }
      }
      sheet.freezePanes(rows: 1);
      sheet.setAutoFilter(
        x.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
        x.CellIndex.indexByColumnRow(
          columnIndex: columns.length - 1,
          rowIndex: table.rows.length,
        ),
      );
    }
    return Uint8List.fromList(book.encode()!);
  }

  void _put(
    x.Sheet sheet,
    int row,
    int col,
    Object? value,
    ReportValueType type, {
    int precision = 2,
    String? numberFormat,
  }) {
    if (value == null || value == '') return;
    final cell = sheet.cell(
      x.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    if (value is String) {
      if (value.length > 32767 ||
          RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]').hasMatch(value)) {
        throw const ReportException(
          'A text value exceeds spreadsheet format limits. No values were truncated. Use the existing CSV export or review the record.',
        );
      }
      cell.value = x.TextCellValue(value);
    } else if (value is DateTime) {
      final d = value.toLocal();
      cell.value = type == ReportValueType.date
          ? x.DateCellValue(year: d.year, month: d.month, day: d.day)
          : x.DateTimeCellValue(
              year: d.year,
              month: d.month,
              day: d.day,
              hour: d.hour,
              minute: d.minute,
              second: d.second,
            );
    } else if (value is num) {
      if (!value.isFinite || value.abs() >= 1000000000000000) {
        throw const ReportException(
          'A number exceeds safe spreadsheet precision. No rounded replacement was exported.',
        );
      }
      cell.value = type == ReportValueType.money
          ? x.DoubleCellValue(value / 100)
          : value is int
          ? x.IntCellValue(value)
          : x.DoubleCellValue(value.toDouble());
    } else {
      cell.value = x.TextCellValue(value.toString());
    }
    final style = x.CellStyle(
      textWrapping: x.TextWrapping.WrapText,
      verticalAlign: x.VerticalAlign.Top,
    );
    if (value is DateTime) {
      style.numberFormat = x.CustomDateTimeNumFormat(
        formatCode: type == ReportValueType.date
            ? 'dd mmm yyyy'
            : 'dd mmm yyyy hh:mm:ss',
      );
    } else if (value is num) {
      style.numberFormat = x.CustomNumericNumFormat(
        formatCode:
            numberFormat ??
            (type == ReportValueType.money
                ? '£#,##0.00'
                : precision == 0
                ? '0'
                : '0.${'0' * precision}'),
      );
    }
    cell.cellStyle = style;
  }
}
