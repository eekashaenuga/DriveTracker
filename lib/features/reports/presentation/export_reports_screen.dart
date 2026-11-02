import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../core/calculations/analytics_date_range.dart';
import '../../../shared/widgets/analytics_date_range_picker.dart';
import '../../data_safety/domain/data_safety_service.dart';
import '../../insights/presentation/insight_formatters.dart';
import '../domain/report_request.dart';
import '../domain/report_service.dart';

class ExportReportsScreen extends StatefulWidget {
  const ExportReportsScreen({required this.service, super.key});
  final ReportService service;
  @override
  State<ExportReportsScreen> createState() => _ExportReportsScreenState();
}

class _ExportReportsScreenState extends State<ExportReportsScreen> {
  String? _vehicleId;
  bool _initialized = false,
      _archived = false,
      _sensitive = false,
      _busy = false;
  var _range = AnalyticsDateRange.month;
  int _rangeRevision = 0;
  var _format = ReportFormat.xlsx;
  final _sections = ReportSection.values
      .where((s) => s != ReportSection.documents)
      .toSet();
  String? _retryAction;
  ReportArtifact? _artifact;
  String? _error, _feedback;
  Future<void> _generate() async {
    if (_busy || _vehicleId == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
      _retryAction = null;
    });
    try {
      final artifact = await widget.service.generate(
        ReportRequest(
          vehicleId: _vehicleId!,
          range: _range,
          sections: _sections,
          format: _format,
          includeSensitive: _sensitive,
        ),
      );
      if (mounted) setState(() => _artifact = artifact);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is ReportException
              ? e.message
              : 'Could not generate report. Try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String action) async {
    final a = _artifact;
    if (a == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _feedback = null;
    });
    try {
      String message;
      if (action == 'Save') {
        final result = await widget.service.bridge.save(a.path, a.name, a.mime);
        message = result.status == DataSafetyFileSaveStatus.saved
            ? 'Report saved.'
            : 'Save cancelled. Your generated report is still available.';
      } else {
        final success = action == 'Open'
            ? await widget.service.bridge.open(a.path, a.mime)
            : await widget.service.bridge.share(a.path, a.mime);
        message = success
            ? (action == 'Open'
                  ? 'Opened in an external viewer.'
                  : 'Share sheet opened. Choose a destination to continue.')
            : '$action is unavailable. Try another action or Save.';
      }
      if (mounted) setState(() => _feedback = message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _retryAction = action;
          _error =
              '$action failed. Your generated report is still available; try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriveTrackerController>();
    if (!_initialized) {
      _initialized = true;
      _vehicleId = c.selectedVehicle?.id;
    }
    final vehicles = [
      ...c.activeVehicles,
      if (_archived) ...c.archivedVehicles,
    ];
    final selectedExists = vehicles.any((v) => v.id == _vehicleId);
    return Scaffold(
      appBar: AppBar(title: const Text('Export & Reports')),
      body: SafeArea(
        child: ListView(
          key: const Key('reportsList'),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Your records, ready to keep or share',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text(
              'One vehicle. Generated locally. Backup, restore and CSV remain in Data & Storage.',
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: ValueKey('reportVehicle_${_vehicleId}_$_archived'),
              isExpanded: true,
              itemHeight: null,
              initialValue: selectedExists ? _vehicleId : null,
              decoration: const InputDecoration(
                labelText: 'Vehicle',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
              items: [
                for (final v in vehicles)
                  DropdownMenuItem(
                    value: v.id,
                    child: Text(
                      '${v.name}${v.isArchived ? ' (archived)' : ''}',
                    ),
                  ),
              ],
              onChanged: _busy ? null : (v) => setState(() => _vehicleId = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show archived vehicles'),
              value: _archived,
              onChanged: _busy
                  ? null
                  : (v) => setState(() {
                      _archived = v;
                      if (!v &&
                          !c.activeVehicles.any((a) => a.id == _vehicleId)) {
                        _vehicleId = null;
                      }
                    }),
            ),
            if (vehicles.isEmpty)
              const Text(
                'No vehicles available. Add a vehicle or show archived vehicles.',
              ),
            DropdownButtonFormField<AnalyticsRangePreset>(
              key: ValueKey((_range.preset, _rangeRevision)),
              initialValue: _range.preset,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Period'),
              items: [
                for (final p in [
                  AnalyticsRangePreset.month,
                  AnalyticsRangePreset.lastMonth,
                  AnalyticsRangePreset.lastThreeMonths,
                  AnalyticsRangePreset.year,
                  AnalyticsRangePreset.all,
                  AnalyticsRangePreset.custom,
                ])
                  DropdownMenuItem(
                    value: p,
                    child: Text(switch (p) {
                      AnalyticsRangePreset.month => 'This month',
                      AnalyticsRangePreset.year => 'This year',
                      AnalyticsRangePreset.all => 'All time',
                      _ => p.label,
                    }),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (v) async {
                      if (v == null) return;
                      if (v == AnalyticsRangePreset.custom) {
                        final range = await pickAnalyticsDateRange(
                          context: context,
                          currentRange: _range,
                          currentDate: c.currentTime,
                          pickerKey: const Key('reportCustomRange'),
                          helpText: 'Select report period',
                        );
                        if (mounted) {
                          setState(() {
                            if (range != null) _range = range;
                            _rangeRevision++;
                          });
                        }
                      } else {
                        setState(() => _range = AnalyticsDateRange.preset(v));
                      }
                    },
            ),
            if (_range.isCustom)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(InsightFormat.customRange(_range)),
              ),
            const SizedBox(height: 20),
            Text('Include', style: Theme.of(context).textTheme.titleMedium),
            const Text(
              'Overview is always included and summarizes all period data.',
            ),
            for (final section in ReportSection.values)
              CheckboxListTile(
                key: Key('reportSection_${section.name}'),
                contentPadding: EdgeInsets.zero,
                title: Text(section.label),
                subtitle: section == ReportSection.documents
                    ? const Text(
                        'Current metadata register, not transaction-period filtered. No attachment files.',
                      )
                    : null,
                value: _sections.contains(section),
                onChanged: _busy
                    ? null
                    : (v) => setState(
                        () => v == true
                            ? _sections.add(section)
                            : _sections.remove(section),
                      ),
              ),
            SwitchListTile(
              key: const Key('reportSensitive'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Include sensitive vehicle/document details'),
              subtitle: const Text(
                'Adds VIN, seller, vehicle notes and document references/notes. Transaction notes are included in Excel.',
              ),
              value: _sensitive,
              onChanged: _busy ? null : (v) => setState(() => _sensitive = v),
            ),
            const SizedBox(height: 16),
            Text('Output', style: Theme.of(context).textTheme.titleMedium),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in ReportFormat.values)
                  ChoiceChip(
                    label: Text(
                      f == ReportFormat.xlsx ? 'Excel (.xlsx)' : 'PDF report',
                    ),
                    selected: _format == f,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _format = f),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _format == ReportFormat.xlsx
                    ? 'Detailed, typed data for spreadsheets.'
                    : 'Readable, printable tables with concise fields. Complete detail is available in Excel.',
              ),
            ),
            FilledButton.icon(
              key: const Key('reportGenerate'),
              onPressed: _busy || !selectedExists ? null : _generate,
              icon: const Icon(Icons.file_download_outlined),
              label: Text(_busy ? 'Working…' : 'Generate'),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : (_retryAction == null
                          ? _generate
                          : () => _action(_retryAction!)),
                child: const Text('Retry'),
              ),
            ],
            if (_artifact != null) ...[
              const SizedBox(height: 24),
              Text(
                'Generated report',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SelectableText(_artifact!.name),
              Text(
                '${_artifact!.format.name.toUpperCase()} · ${(_artifact!.size / 1024).toStringAsFixed(1)} KB',
              ),
              if (_artifact!.recordCount == 0)
                const Text(
                  'No selected transaction records. Overview and selected metadata are included.',
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in ['Open', 'Share', 'Save'])
                    OutlinedButton(
                      onPressed: _busy ? null : () => _action(action),
                      child: Text(action),
                    ),
                ],
              ),
            ],
            if (_feedback != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_feedback!),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
