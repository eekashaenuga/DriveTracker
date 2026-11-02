import 'dart:io';

import 'package:flutter/services.dart';

import '../../data_safety/domain/data_safety_service.dart';
import '../domain/report_request.dart';

abstract class ReportFileBridge {
  Future<Directory> cacheRoot();
  Future<bool> open(String path, String mime);
  Future<bool> share(String path, String mime);
  Future<DataSafetyFileSaveResult> save(String path, String name, String mime);
}

class PlatformReportFileBridge implements ReportFileBridge {
  const PlatformReportFileBridge();
  static const channel = MethodChannel('drivetracker/reports');
  @override
  Future<Directory> cacheRoot() async {
    final path = await channel.invokeMethod<String>('cacheRoot');
    if (path == null) {
      throw const ReportException('Report cache is unavailable.');
    }
    return Directory(path);
  }

  @override
  Future<bool> open(String path, String mime) async =>
      await channel.invokeMethod<bool>('open', {
        'path': path,
        'mimeType': mime,
      }) ??
      false;
  @override
  Future<bool> share(String path, String mime) async =>
      await channel.invokeMethod<bool>('share', {
        'path': path,
        'mimeType': mime,
      }) ??
      false;
  @override
  Future<DataSafetyFileSaveResult> save(
    String path,
    String name,
    String mime,
  ) async {
    final result = await channel.invokeMapMethod<String, Object?>('save', {
      'sourcePath': path,
      'suggestedName': name,
      'mimeType': mime,
    });
    return result == null
        ? const DataSafetyFileSaveResult(DataSafetyFileSaveStatus.cancelled)
        : DataSafetyFileSaveResult(
            DataSafetyFileSaveStatus.saved,
            displayName: result['displayName'] as String? ?? name,
          );
  }
}
