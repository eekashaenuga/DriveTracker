import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drivetracker/features/reports/data/report_repository.dart';
import 'package:drivetracker/features/reports/domain/report_request.dart';
import 'package:drivetracker/features/reports/domain/report_service.dart';
import 'package:drivetracker/features/reports/infrastructure/report_file_bridge.dart';

import 'helpers/report_fixture.dart';
import 'helpers/report_file_bridge.dart';

void main() {
  test(
    'fresh cached reports survive cleanup and missing vehicle creates no job',
    () async {
      final (s, _) = await reportFixture();
      final root = await Directory.systemTemp.createTemp(
        'vehnora_fresh_report_',
      );
      addTearDown(() => root.delete(recursive: true));
      final recent = await Directory('${root.path}/job_recent').create();
      await File('${recent.path}/keep.pdf').writeAsString('keep');
      await ReportService.cleanup(root, DateTime.now());
      expect(await recent.exists(), isTrue);
      final service = ReportService(
        ReportRepository(s.database, clock: () => reportNow),
        bridge: TestReportBridge(root),
      );
      await expectLater(
        service.generate(reportRequest('missing')),
        throwsA(isA<ReportException>()),
      );
      expect(await root.list().length, 1);
    },
  );
  test(
    'write/cache failure is clear and leaves unrelated files intact',
    () async {
      final (s, id) = await reportFixture();
      final root = await Directory.systemTemp.createTemp(
        'vehnora_write_error_',
      );
      addTearDown(() => root.delete(recursive: true));
      final blocker = File('${root.path}/blocked');
      await blocker.writeAsString('unrelated');
      final service = ReportService(
        ReportRepository(s.database, clock: () => reportNow),
        bridge: TestReportBridge(Directory(blocker.path)),
      );
      await expectLater(
        service.generate(reportRequest(id)),
        throwsA(isA<ReportException>()),
      );
      expect(await blocker.readAsString(), 'unrelated');
    },
  );

  TestWidgetsFlutterBinding.ensureInitialized();
  for (final format in ReportFormat.values) {
    test(
      'isolated ${format.name} generation retains cached artifact and safe filename',
      () async {
        final (s, id) = await reportFixture();
        final root = await Directory.systemTemp.createTemp(
          'vehnora_report_test_',
        );
        addTearDown(() => root.delete(recursive: true));
        final db = await s.database.database;
        await db.update(
          'vehicles',
          {'name': '../ Car : / ? * name ...', 'vin': 'DO-NOT-FILENAME'},
          where: 'id = ?',
          whereArgs: [id],
        );
        final bridge = TestReportBridge(root);
        final service = ReportService(
          ReportRepository(s.database, clock: () => reportNow),
          bridge: bridge,
          fontLoader: (path) => File(path).readAsBytes(),
          clock: () => reportNow,
        );
        final artifact = await service.generate(
          reportRequest(id, format: format),
        );
        expect(await File(artifact.path).exists(), isTrue);
        expect(artifact.size, greaterThan(100));
        expect(artifact.name, endsWith('.${format.name}'));
        expect(artifact.name, contains('2026-10-01_to_2026-10-31'));
        expect(
          artifact.name,
          contains(
            '20261024T${reportNow.toUtc().hour.toString().padLeft(2, '0')}0000Z',
          ),
        );
        expect(artifact.name, isNot(contains('DO-NOT-FILENAME')));
        expect(RegExp(r'[<>:"/\\|?*]').hasMatch(artifact.name), isFalse);
        bridge.cancel = true;
        await bridge.save(artifact.path, artifact.name, artifact.mime);
        expect(await File(artifact.path).exists(), isTrue);
        final second = await service.generate(
          reportRequest(id, format: format),
        );
        expect(second.path, isNot(artifact.path));
      },
    );
  }
  test(
    'failed encoding cleans owned partial job and generation can retry',
    () async {
      final (s, id) = await reportFixture();
      final root = await Directory.systemTemp.createTemp(
        'vehnora_report_fail_',
      );
      addTearDown(() => root.delete(recursive: true));
      final db = await s.database.database;
      await db.update(
        'expenses',
        {'notes': 'a' * 32768},
        where: 'id = ?',
        whereArgs: ['e0'],
      );
      final service = ReportService(
        ReportRepository(s.database, clock: () => reportNow),
        bridge: TestReportBridge(root),
      );
      await expectLater(
        service.generate(reportRequest(id)),
        throwsA(isA<ReportException>()),
      );
      expect(await root.list().toList(), isEmpty);
      await db.update(
        'expenses',
        {'notes': 'fixed'},
        where: 'id = ?',
        whereArgs: ['e0'],
      );
      expect((await service.generate(reportRequest(id))).size, greaterThan(0));
    },
  );
  test('cleanup removes only old owned job directories', () async {
    final root = await Directory.systemTemp.createTemp(
      'vehnora_report_cleanup_',
    );
    addTearDown(() => root.delete(recursive: true));
    final old = await Directory('${root.path}/job_old').create();
    final recent = await Directory('${root.path}/job_recent').create();
    final other = await Directory('${root.path}/attachments').create();
    // Future clock makes existing directories old without changing the phone/system clock.
    await ReportService.cleanup(
      root,
      DateTime.now().add(const Duration(days: 8)),
    );
    expect(await old.exists(), isFalse);
    expect(await recent.exists(), isFalse);
    expect(await other.exists(), isTrue);
  });
  test('platform bridge forwards path mime and Save cancellation', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(PlatformReportFileBridge.channel, (
          call,
        ) async {
          calls.add(call);
          return call.method == 'cacheRoot'
              ? 'test-cache'
              : call.method == 'save'
              ? null
              : true;
        });
    const safety = MethodChannel('drivetracker/data_safety');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(safety, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(PlatformReportFileBridge.channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(safety, null);
    });
    const bridge = PlatformReportFileBridge();
    expect((await bridge.cacheRoot()).path, 'test-cache');
    expect(await bridge.open('a.pdf', 'application/pdf'), isTrue);
    expect(
      await bridge.share(
        'a.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
      isTrue,
    );
    await bridge.save('a.pdf', 'a.pdf', 'application/pdf');
    expect(calls.map((c) => c.method), ['cacheRoot', 'open', 'share', 'save']);
    expect((calls[1].arguments as Map)['mimeType'], 'application/pdf');
  });
}
