import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_category_icon.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../domain/data_safety_service.dart';

class DataStorageScreen extends StatefulWidget {
  const DataStorageScreen({super.key});

  @override
  State<DataStorageScreen> createState() => _DataStorageScreenState();
}

class _DataStorageScreenState extends State<DataStorageScreen> {
  Future<DataStorageSummary>? _summaryFuture;
  String? _busyAction;

  bool get _isBusy => _busyAction != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _summaryFuture ??= _loadSummary();
  }

  @override
  Widget build(BuildContext context) {
    final summaryFuture = _summaryFuture;
    return Scaffold(
      appBar: AppBar(title: const Text('Data & Storage')),
      body: SafeArea(
        child: FutureBuilder<DataStorageSummary>(
          future: summaryFuture,
          builder: (context, snapshot) {
            final summary = snapshot.data;
            if (summary == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                key: const Key('dataStorageLoaded'),
                padding: const EdgeInsets.fromLTRB(
                  DTSpacing.lg,
                  DTSpacing.lg,
                  DTSpacing.lg,
                  DTSpacing.xxxl,
                ),
                children: [
                  const DTSectionHeader(title: 'Backup'),
                  _ActionPanel(
                    icon: Icons.backup_outlined,
                    title: 'Save backup',
                    body: 'Create a portable .dtbackup file containing your local database and managed attachments.',
                    action: FilledButton.icon(
                      key: const Key('dataStorageBackupButton'),
                      onPressed: _isBusy ? null : _createBackup,
                      icon: _actionIcon('backup'),
                      label: Text(
                        _busyAction == 'backup' ? 'Saving...' : 'Save backup',
                      ),
                    ),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  _ActionPanel(
                    icon: Icons.restore_rounded,
                    title: 'Restore',
                    body: 'Choose a DriveTracker backup, review its contents, then replace the local data on this device.',
                    action: OutlinedButton.icon(
                      key: const Key('dataStorageRestoreButton'),
                      onPressed: _isBusy ? null : _pickRestoreBackup,
                      icon: _actionIcon('restore'),
                      label: Text(
                        _busyAction == 'restore'
                            ? 'Restoring...'
                            : 'Restore from backup',
                      ),
                    ),
                  ),
                  const SizedBox(height: DTSpacing.xl),
                  const DTSectionHeader(title: 'Export'),
                  _ActionPanel(
                    icon: Icons.table_chart_outlined,
                    title: 'CSV export',
                    body: 'Save a ZIP of CSV files for spreadsheet review. This does not replace backups.',
                    action: OutlinedButton.icon(
                      key: const Key('dataStorageExportCsvButton'),
                      onPressed: _isBusy ? null : _exportCsv,
                      icon: _actionIcon('export'),
                      label: Text(
                        _busyAction == 'export' ? 'Exporting...' : 'Export CSV',
                      ),
                    ),
                  ),
                  const SizedBox(height: DTSpacing.xl),
                  const DTSectionHeader(title: 'Storage'),
                  _StorageRows(summary: summary),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _actionIcon(String action) {
    if (_busyAction == action) {
      return const SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2.2),
      );
    }
    return switch (action) {
      'backup' => const Icon(Icons.save_alt_rounded),
      'restore' => const Icon(Icons.folder_open_rounded),
      _ => const Icon(Icons.file_download_outlined),
    };
  }

  Future<DataStorageSummary> _loadSummary() {
    return context.read<DriveTrackerController>().dataStorageSummary();
  }

  Future<void> _refresh() async {
    final future = _loadSummary();
    setState(() {
      _summaryFuture = future;
    });
    await future;
  }

  Future<void> _createBackup() {
    return _run('backup', () async {
      final result = await context
          .read<DriveTrackerController>()
          .createAndSaveBackup();
      if (!mounted) {
        return;
      }
      _showSnack(
        result.saved
            ? 'Backup saved${_displayName(result.displayName)}.'
            : 'Backup cancelled.',
      );
      await _refresh();
    });
  }

  Future<void> _exportCsv() {
    return _run('export', () async {
      final result = await context
          .read<DriveTrackerController>()
          .createAndSaveCsvExport();
      if (!mounted) {
        return;
      }
      _showSnack(
        result.saved
            ? 'CSV export saved${_displayName(result.displayName)}.'
            : 'CSV export cancelled.',
      );
    });
  }

  Future<void> _pickRestoreBackup() {
    return _run('restore', () async {
      final controller = context.read<DriveTrackerController>();
      final inspection = await controller.pickAndInspectBackup();
      if (!mounted || inspection == null) {
        if (mounted) {
          _showSnack('Restore cancelled.');
        }
        return;
      }
      final confirmed = await _confirmRestore(inspection);
      if (!mounted || confirmed != true) {
        return;
      }
      await controller.restoreBackupFromFile(
        inspection.path,
        fileName: inspection.fileName,
      );
      if (!mounted) {
        return;
      }
      _showSnack('Restore complete. A safety backup was created first.');
      await _refresh();
    });
  }

  Future<bool?> _confirmRestore(BackupInspection inspection) {
    final manifest = inspection.manifest;
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          key: const Key('restoreBackupConfirmDialog'),
          title: const Text('Restore backup?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inspection.fileName),
                const SizedBox(height: DTSpacing.md),
                _DialogFact(
                  label: 'Created',
                  value: _formatDateTime(manifest.createdAtUtc),
                ),
                _DialogFact(
                  label: 'Schema',
                  value: 'Version ${manifest.schemaVersion}',
                ),
                _DialogFact(
                  label: 'Vehicles',
                  value: '${manifest.tableCounts['vehicles'] ?? 0}',
                ),
                _DialogFact(
                  label: 'Attachments',
                  value: '${manifest.attachmentCount}',
                ),
                const SizedBox(height: DTSpacing.sm),
                Text(
                  'DriveTracker will create a safety backup first, then replace the local data on this device.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: const Key('cancelRestoreBackupButton'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('confirmRestoreBackupButton'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Restore'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _run(String action, Future<void> Function() operation) async {
    setState(() {
      _busyAction = action;
    });
    try {
      await operation();
    } on DataSafetyException catch (error) {
      if (mounted) {
        _showSnack(error.message);
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Data operation failed. Your existing data was kept.');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyAction = null;
        });
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String _displayName(String? name) {
    if (name == null || name.trim().isEmpty) {
      return '';
    }
    return ' as $name';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    String two(int part) => part.toString().padLeft(2, '0');
    return '${local.day} ${_month(local.month)} ${local.year}, '
        '${two(local.hour)}:${two(local.minute)}';
  }

  String _month(int month) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[month - 1];
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: DTRadii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(DTSpacing.md),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 420;
            final content = [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(DTRadii.card),
                ),
                child: Icon(icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: DTSpacing.md, height: DTSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: DTSpacing.xs),
                    Text(
                      body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ];
            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: content,
                  ),
                  const SizedBox(height: DTSpacing.md),
                  action,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ...content,
                const SizedBox(width: DTSpacing.md),
                Flexible(
                  child: Align(alignment: Alignment.centerRight, child: action),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _StorageRows extends StatelessWidget {
  const _StorageRows({required this.summary});

  final DataStorageSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _StorageRow(
          icon: Icons.storage_rounded,
          label: 'Database',
          value: _formatBytes(summary.databaseBytes),
        ),
        const SizedBox(height: DTSpacing.sm),
        _StorageRow(
          icon: Icons.attachment_rounded,
          label: 'Attachments',
          value:
              '${summary.attachmentCount} / ${_formatBytes(summary.attachmentBytes)}',
        ),
        const SizedBox(height: DTSpacing.sm),
        _StorageRow(
          icon: Icons.inventory_2_outlined,
          label: 'Total local data',
          value: _formatBytes(summary.totalBytes),
        ),
        const SizedBox(height: DTSpacing.sm),
        _StorageRow(
          icon: Icons.schema_outlined,
          label: 'Schema version',
          value: '${summary.schemaVersion}',
        ),
        const SizedBox(height: DTSpacing.sm),
        _StorageRow(
          icon: Icons.verified_user_outlined,
          label: 'Backup format',
          value: '${summary.backupFormatVersion}',
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kib = bytes / 1024;
    if (kib < 1024) {
      return '${kib.toStringAsFixed(kib >= 10 ? 0 : 1)} KB';
    }
    final mib = kib / 1024;
    return '${mib.toStringAsFixed(mib >= 10 ? 1 : 2)} MB';
  }
}

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.38),
      borderRadius: DTRadii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(DTSpacing.md),
        child: Row(
          children: [
            DTCategoryIcon(
              icon: icon,
              color: DTAccents.storage(context),
              size: 38,
              iconSize: DTIconSizes.sm,
            ),
            const SizedBox(width: DTSpacing.md),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: DTSpacing.sm),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogFact extends StatelessWidget {
  const _DialogFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DTSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: DTSpacing.md),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
