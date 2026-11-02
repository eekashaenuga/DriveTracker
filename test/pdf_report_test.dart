import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drivetracker/features/reports/data/report_repository.dart';
import 'package:drivetracker/features/reports/domain/report_data.dart';
import 'package:drivetracker/features/reports/domain/report_request.dart';
import 'package:drivetracker/features/reports/infrastructure/pdf_report_writer.dart';

import 'helpers/report_fixture.dart';

void main() {
  for (final large in [false, true]) {
    test('bundled Unicode PDF multipage selected tables large=$large', () async {
      final (s, id) = await reportFixture(expenses: large ? 230 : 3);
      final d = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(reportRequest(id));
      final unicode = ReportData(
        vehicleName: 'Fiesta café Ελληνικά Привет',
        period: d.period,
        generatedAt: d.generatedAt,
        timezone: d.timezone,
        identity: [
          const ReportMetric('Vehicle', 'Fiesta café Ελληνικά Привет'),
          ...d.identity,
        ],
        metrics: d.metrics,
        tables: d.tables,
        breakdown: d.breakdown,
        recordCount: d.recordCount,
      );
      final bytes = await PdfReportWriter().write(
        unicode,
        await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes(),
        await File('assets/fonts/NotoSans-Bold.ttf').readAsBytes(),
      );
      final text = String.fromCharCodes(bytes);
      expect(text, startsWith('%PDF-'));
      expect(text, contains('/FontFile2'));
      expect(text, contains('/ToUnicode'));
      expect(
        RegExp(r'/Type\s*/Page\b').allMatches(text).length,
        greaterThan(large ? 5 : 1),
      );
      await File(
        '${Directory.systemTemp.path}/vehnora-m6-${large ? 'multipage' : 'representative'}.pdf',
      ).writeAsBytes(bytes);
    });
  }
  test(
    'empty selected tables and unavailable metrics generate successfully',
    () async {
      final (s, id) = await reportFixture();
      final d = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(reportRequest(id, sections: {ReportSection.fuel}));
      final empty = ReportData(
        vehicleName: d.vehicleName,
        period: d.period,
        generatedAt: d.generatedAt,
        timezone: d.timezone,
        identity: d.identity,
        metrics: d.metrics,
        tables: [ReportTable('Fuel', d.tables.first.columns, [])],
        breakdown: d.breakdown,
        recordCount: 0,
      );
      final bytes = await PdfReportWriter().write(
        empty,
        await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes(),
        await File('assets/fonts/NotoSans-Bold.ttf').readAsBytes(),
      );
      expect(bytes, isNotEmpty);
    },
  );
  test(
    'very long transaction labels paginate without silently dropping text',
    () async {
      final (s, id) = await reportFixture();
      final db = await s.database.database;
      await db.update(
        'expenses',
        {'merchant': 'Long merchant ' * 200},
        where: 'id = ?',
        whereArgs: ['e0'],
      );
      final d = await ReportRepository(
        s.database,
        clock: () => reportNow,
      ).load(reportRequest(id, sections: {ReportSection.expenses}));
      final bytes = await PdfReportWriter().write(
        d,
        await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes(),
        await File('assets/fonts/NotoSans-Bold.ttf').readAsBytes(),
      );
      expect(
        RegExp(r'/Type\s*/Page\b')
            .allMatches(String.fromCharCodes(bytes))
            .length,
        greaterThan(2),
      );
    },
  );
  test('unsupported PDF glyph fails clearly rather than losing recorded characters', () async {
    final (s, id) = await reportFixture();
    final d = await ReportRepository(
      s.database,
      clock: () => reportNow,
    ).load(reportRequest(id));
    final unsupported = ReportData(
      vehicleName: 'v',
      period: d.period,
      generatedAt: d.generatedAt,
      timezone: d.timezone,
      identity: [const ReportMetric('Vehicle', '車')],
      metrics: d.metrics,
      tables: [],
      breakdown: [],
      recordCount: 0,
    );
    await expectLater(
      PdfReportWriter().write(
        unsupported,
        await File('assets/fonts/NotoSans-Regular.ttf').readAsBytes(),
        await File('assets/fonts/NotoSans-Bold.ttf').readAsBytes(),
      ),
      throwsA(isA<ReportException>()),
    );
  });
}
