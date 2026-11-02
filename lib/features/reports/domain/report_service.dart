import '../../../core/product_identity.dart';

import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../data/report_repository.dart';
import '../infrastructure/report_file_bridge.dart';
import '../infrastructure/pdf_report_writer.dart';
import '../infrastructure/xlsx_report_writer.dart';
import 'report_data.dart';
import 'report_request.dart';

class ReportArtifact {
  const ReportArtifact({
    required this.path,
    required this.name,
    required this.format,
    required this.size,
    required this.recordCount,
  });
  final String path, name;
  final ReportFormat format;
  final int size, recordCount;
  String get mime => format == ReportFormat.pdf
      ? 'application/pdf'
      : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
}

class ReportService {
  ReportService(
    this.repository, {
    ReportFileBridge? bridge,
    Future<Uint8List> Function(String)? fontLoader,
    DateTime Function()? clock,
  }) : bridge = bridge ?? const PlatformReportFileBridge(),
       fontLoader = fontLoader ?? _font,
       clock = clock ?? DateTime.now;
  final ReportRepository repository;
  final ReportFileBridge bridge;
  final Future<Uint8List> Function(String) fontLoader;
  final DateTime Function() clock;
  bool _busy = false;
  static Future<Uint8List> _font(String path) async =>
      (await rootBundle.load(path)).buffer.asUint8List();
  Future<ReportArtifact> generate(ReportRequest request) async {
    if (_busy) {
      throw const ReportException('A report is already being generated.');
    }
    _busy = true;
    Directory? job;
    try {
      final data = await repository.load(request);
      final root = await bridge.cacheRoot();
      await root.create(recursive: true);
      await cleanup(root, clock());
      job = await root.createTemp('job_');
      final name = filename(data, request);
      final output = File(p.join(job.path, name));
      final format = request.format;
      final regular = format == ReportFormat.pdf
          ? await fontLoader('assets/fonts/NotoSans-Regular.ttf')
          : Uint8List(0);
      final bold = format == ReportFormat.pdf
          ? await fontLoader('assets/fonts/NotoSans-Bold.ttf')
          : Uint8List(0);
      final bytes = await compute(_encodeReport, (data, format, regular, bold));
      await output.writeAsBytes(bytes, flush: true);
      return ReportArtifact(
        path: output.path,
        name: name,
        format: format,
        size: bytes.length,
        recordCount: data.recordCount,
      );
    } on ReportException {
      if (job != null) await _remove(job);
      rethrow;
    } catch (_) {
      if (job != null) await _remove(job);
      throw const ReportException(
        'Could not generate or write the report. Check available storage and try a shorter period.',
      );
    } finally {
      _busy = false;
    }
  }

  static Future<void> _remove(Directory job) async {
    try {
      if (await job.exists()) await job.delete(recursive: true);
    } catch (_) {
      /* Best-effort cleanup of this owned job only. */
    }
  }

  static Future<void> cleanup(Directory root, DateTime now) async {
    // A week leaves external consumers time to read their granted content URI.
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || !p.basename(entity.path).startsWith('job_')) {
        continue;
      }
      final stat = await entity.stat();
      if (now.difference(stat.modified) > const Duration(days: 7)) {
        await _remove(entity);
      }
    }
  }

  static String filename(ReportData data, ReportRequest request) {
    var slug = data.vehicleName
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F\x7F]'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'[. -]+$'), '');
    slug = String.fromCharCodes(slug.runes.take(60))
        .replaceAll(RegExp(r'[. -]+$'), '');
    if (slug.isEmpty) slug = 'Vehicle';
    final range = request.range.resolve(data.generatedAt);
    String day(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final period = range.startInclusive == null
        ? 'All-time'
        : '${day(range.startInclusive!)}_to_${day(range.endInclusive!)}';
    final timestamp = data.generatedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[-:]'), '')
        .split('.')
        .first;
    return '${ProductIdentity.name}_${slug}_${period}_${timestamp}Z.${request.format.name}';
  }
}

Future<Uint8List> _encodeReport(
  (ReportData, ReportFormat, Uint8List, Uint8List) input,
) async => input.$2 == ReportFormat.xlsx
    ? XlsxReportWriter().write(input.$1)
    : PdfReportWriter().write(input.$1, input.$3, input.$4);
