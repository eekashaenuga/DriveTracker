import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../domain/data_safety_service.dart';

enum RestoreBackupFlowResult { cancelled, confirmationCancelled, restored }

Future<RestoreBackupFlowResult> runRestoreBackupFlow(
  BuildContext context, {
  bool clearControllerErrorOnFailure = false,
}) async {
  final controller = context.read<DriveTrackerController>();
  try {
    final inspection = await controller.pickAndInspectBackup();
    if (!context.mounted || inspection == null) {
      return RestoreBackupFlowResult.cancelled;
    }

    final confirmed = await showRestoreBackupConfirmation(context, inspection);
    if (!context.mounted || confirmed != true) {
      return RestoreBackupFlowResult.confirmationCancelled;
    }

    await controller.restoreBackupFromFile(
      inspection.path,
      fileName: inspection.fileName,
    );
    return RestoreBackupFlowResult.restored;
  } catch (_) {
    if (clearControllerErrorOnFailure) {
      controller.clearError();
    }
    rethrow;
  }
}

Future<bool?> showRestoreBackupConfirmation(
  BuildContext context,
  BackupInspection inspection,
) {
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
