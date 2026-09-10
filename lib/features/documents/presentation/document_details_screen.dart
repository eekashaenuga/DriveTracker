import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_date_field.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/presentation/attachment_panel.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/vehicle_document.dart';

class DocumentDetailsScreen extends StatefulWidget {
  const DocumentDetailsScreen({required this.documentId, super.key});

  final String documentId;

  @override
  State<DocumentDetailsScreen> createState() => _DocumentDetailsScreenState();
}

class _DocumentDetailsScreenState extends State<DocumentDetailsScreen> {
  Future<VehicleDocument?>? _documentFuture;

  @override
  void initState() {
    super.initState();
    _documentFuture = _load();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    return FutureBuilder<VehicleDocument?>(
      future: _documentFuture,
      builder: (context, snapshot) {
        final document = snapshot.data;
        if (document == null &&
            snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (document == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Document')),
            body: const DTEmptyState(
              icon: Icons.description_outlined,
              title: 'Document unavailable',
              body: 'This document could not be found.',
            ),
          );
        }

        final vehicle = _vehicleForId(
          controller.activeVehicles,
          document.vehicleId,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(document.title),
            actions: [
              IconButton(
                key: const Key('editDocumentButton'),
                tooltip: 'Edit document',
                onPressed: () async {
                  await AppNavigation.openEditDocument(context, document);
                  if (mounted) {
                    await _refresh();
                  }
                },
                icon: const Icon(Icons.edit_outlined),
              ),
              PopupMenuButton<_DocumentAction>(
                tooltip: 'Document actions',
                itemBuilder: (context) => [
                  if (!document.isArchived)
                    const PopupMenuItem(
                      value: _DocumentAction.renew,
                      child: Text('Renew'),
                    ),
                  if (!document.isArchived)
                    const PopupMenuItem(
                      value: _DocumentAction.archive,
                      child: Text('Archive'),
                    ),
                  const PopupMenuItem(
                    value: _DocumentAction.delete,
                    child: Text('Delete permanently'),
                  ),
                ],
                onSelected: (action) => _handleAction(action, document),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              key: const Key('documentDetailsLoaded'),
              padding: const EdgeInsets.all(DTSpacing.lg),
              children: [
                _DocumentHeader(document: document, vehicle: vehicle),
                const SizedBox(height: DTSpacing.lg),
                _DetailsSection(document: document, vehicle: vehicle),
                const SizedBox(height: DTSpacing.lg),
                AttachmentPanel(
                  key: Key('documentDetailsAttachments_${document.id}'),
                  parentType: AttachmentParentType.document,
                  parentId: document.id,
                ),
                const SizedBox(height: DTSpacing.xxxl),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<VehicleDocument?> _load() {
    return context.read<DriveTrackerController>().documentById(
      widget.documentId,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _documentFuture = future;
    });
    await future;
  }

  Future<void> _handleAction(
    _DocumentAction action,
    VehicleDocument document,
  ) async {
    switch (action) {
      case _DocumentAction.renew:
        final renewed = await AppNavigation.openRenewDocument(
          context,
          document,
        );
        if (!mounted) {
          return;
        }
        if (renewed != null) {
          setState(() {
            _documentFuture = Future.value(renewed);
          });
        } else {
          await _refresh();
        }
        break;
      case _DocumentAction.archive:
        await context.read<DriveTrackerController>().archiveDocument(
          document.id,
        );
        if (mounted) {
          await _refresh();
        }
        break;
      case _DocumentAction.delete:
        await _deletePermanently(document);
        break;
    }
  }

  Future<void> _deletePermanently(VehicleDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document permanently?'),
        content: Text(
          'This removes ${document.title} and its managed attachment files from DriveTracker.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmDeleteDocumentButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<DriveTrackerController>().deleteDocumentPermanently(
      document.id,
    );
    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Document deleted.')));
    }
  }

  Vehicle? _vehicleForId(List<Vehicle> vehicles, String id) {
    for (final vehicle in vehicles) {
      if (vehicle.id == id) {
        return vehicle;
      }
    }
    return null;
  }
}

enum _DocumentAction { renew, archive, delete }

class _DocumentHeader extends StatelessWidget {
  const _DocumentHeader({required this.document, required this.vehicle});

  final VehicleDocument document;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = document.statusAt(
      context.read<DriveTrackerController>().currentTime,
    );
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
      borderRadius: DTRadii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(DTSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primaryContainer,
                  foregroundColor: colors.onPrimaryContainer,
                  child: const Icon(Icons.description_outlined),
                ),
                const SizedBox(width: DTSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.category,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        document.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DTSpacing.lg),
            Wrap(
              spacing: DTSpacing.sm,
              runSpacing: DTSpacing.sm,
              children: [
                _DetailChip(
                  icon: Icons.directions_car_filled_outlined,
                  label: vehicle?.name ?? 'Vehicle',
                ),
                _DetailChip(
                  icon: _statusIcon(status),
                  label: _statusText(document, status, context),
                ),
                if (document.isArchived)
                  const _DetailChip(
                    icon: Icons.archive_outlined,
                    label: 'Archived',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsSection extends StatelessWidget {
  const _DetailsSection({required this.document, required this.vehicle});

  final VehicleDocument document;
  final Vehicle? vehicle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DetailRow(
          label: 'Vehicle',
          value: vehicle?.name ?? document.vehicleId,
        ),
        _DetailRow(label: 'Category', value: document.category),
        _DetailRow(
          label: 'Issue date',
          value: _dateOrBlank(document.issueDate),
        ),
        _DetailRow(
          label: 'Recorded expiry',
          value: _dateOrBlank(document.expiryDate),
        ),
        _DetailRow(label: 'Provider', value: document.provider),
        _DetailRow(label: 'Reference', value: document.referenceNumber),
        _DetailRow(label: 'Notes', value: document.notes),
        _DetailRow(label: 'Created', value: compactDate(document.createdAt)),
        _DetailRow(label: 'Updated', value: compactDate(document.updatedAt)),
      ],
    );
  }

  String? _dateOrBlank(DateTime? date) {
    return date == null ? null : compactDate(date);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final valueText = value;
    if (valueText == null || valueText.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DTSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 116,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: DTSpacing.md),
          Expanded(child: Text(valueText)),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DTSpacing.sm,
        vertical: DTSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(DTRadii.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DTIconSizes.sm, color: colors.onSurfaceVariant),
          const SizedBox(width: DTSpacing.xs),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _statusIcon(DocumentStatus status) {
  return switch (status) {
    DocumentStatus.noExpiry => Icons.event_note_rounded,
    DocumentStatus.valid => Icons.event_available_rounded,
    DocumentStatus.expiringSoon => Icons.schedule_rounded,
    DocumentStatus.expired => Icons.error_outline_rounded,
  };
}

String _statusText(
  VehicleDocument document,
  DocumentStatus status,
  BuildContext context,
) {
  final days = document.daysUntilExpiry(
    context.read<DriveTrackerController>().currentTime,
  );
  return switch (status) {
    DocumentStatus.noExpiry => 'No expiry recorded',
    DocumentStatus.valid when days != null => 'Expires in $days days',
    DocumentStatus.valid => 'Recorded',
    DocumentStatus.expiringSoon when days == 0 => 'Expires today',
    DocumentStatus.expiringSoon when days == 1 => 'Expires tomorrow',
    DocumentStatus.expiringSoon when days != null => 'Expires in $days days',
    DocumentStatus.expiringSoon => 'Expiring soon',
    DocumentStatus.expired when days == -1 => 'Expired yesterday',
    DocumentStatus.expired when days != null => 'Expired ${-days} days ago',
    DocumentStatus.expired => 'Expired',
  };
}
