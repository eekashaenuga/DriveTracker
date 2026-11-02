import 'dart:io';

import 'package:drivetracker/features/reports/infrastructure/report_file_bridge.dart';
import 'package:drivetracker/features/data_safety/domain/data_safety_service.dart';

class TestReportBridge implements ReportFileBridge {
  TestReportBridge(this.root);
  final Directory root;
  final calls = <String>[];
  bool fail = false, available = true, cancel = false;
  @override
  Future<Directory> cacheRoot() async => root;
  @override
  Future<bool> open(String path, String mime) async {
    calls.add('Open');
    if (fail) throw StateError('open');
    return available;
  }

  @override
  Future<bool> share(String path, String mime) async {
    calls.add('Share');
    if (fail) throw StateError('share');
    return available;
  }

  @override
  Future<DataSafetyFileSaveResult> save(
    String path,
    String name,
    String mime,
  ) async {
    calls.add('Save');
    if (fail) throw StateError('save');
    return DataSafetyFileSaveResult(
      cancel
          ? DataSafetyFileSaveStatus.cancelled
          : DataSafetyFileSaveStatus.saved,
    );
  }
}
