import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../shared/widgets/dt_date_field.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_section_header.dart';
import '../../attachments/domain/attachment.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/vehicle_document.dart';

class DocumentsScreen extends StatefulWidget {
  const DocumentsScreen({super.key});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  Future<List<VehicleDocument>>? _documentsFuture;
  String? _loadedVehicleId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicles = controller.activeVehicles;
    final vehicle = controller.selectedVehicle;

    if (vehicle == null || vehicles.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Documents')),
        body: const SafeArea(
          child: DTEmptyState(
            icon: Icons.description_outlined,
            title: 'No active vehicle',
            body: 'Select an active vehicle before adding documents.',
          ),
        ),
      );
    }

    if (_documentsFuture == null || _loadedVehicleId != vehicle.id) {
      _loadedVehicleId = vehicle.id;
      _documentsFuture = controller.documentsForSelectedVehicle(
        includeArchived: true,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            key: const Key('addDocumentButton'),
            tooltip: 'Add document',
            onPressed: () async {
              await AppNavigation.openAddDocument(context);
              if (mounted) {
                await _refresh();
              }
            },
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<List<VehicleDocument>>(
            future: _documentsFuture,
            builder: (context, snapshot) {
              final documents = snapshot.data;
              if (documents == null) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView(
                key: const Key('documentsLoaded'),
                padding: const EdgeInsets.fromLTRB(
                  DTSpacing.lg,
                  DTSpacing.lg,
                  DTSpacing.lg,
                  DTSpacing.xxxl,
                ),
                children: [
                  _VehicleSelector(
                    vehicles: vehicles,
                    selectedVehicle: vehicle,
                    onChanged: (vehicleId) async {
                      await controller.selectVehicle(vehicleId);
                      if (mounted) {
                        await _refresh();
                      }
                    },
                  ),
                  if (documents.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: DTSpacing.xxl),
                      child: DTEmptyState(
                        icon: Icons.folder_copy_outlined,
                        title: 'No documents yet',
                        body: 'Keep insurance, MOT, receipts and other vehicle records together.',
                        action: FilledButton.icon(
                          key: const Key('emptyAddDocumentButton'),
                          onPressed: () async {
                            await AppNavigation.openAddDocument(context);
                            if (mounted) {
                              await _refresh();
                            }
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Add document'),
                        ),
                      ),
                    )
                  else
                    _DocumentSections(
                      documents: documents,
                      asOf: controller.currentTime,
                      onRefresh: _refresh,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    final future = context
        .read<DriveTrackerController>()
        .documentsForSelectedVehicle(includeArchived: true);
    setState(() {
      _documentsFuture = future;
    });
    await future;
  }
}

class _VehicleSelector extends StatelessWidget {
  const _VehicleSelector({
    required this.vehicles,
    required this.selectedVehicle,
    required this.onChanged,
  });

  final List<Vehicle> vehicles;
  final Vehicle selectedVehicle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      key: const Key('documentsVehicleField'),
      initialValue: selectedVehicle.id,
      decoration: const InputDecoration(labelText: 'Vehicle'),
      items: [
        for (final vehicle in vehicles)
          DropdownMenuItem(value: vehicle.id, child: Text(vehicle.name)),
      ],
      onChanged: (value) {
        if (value != null && value != selectedVehicle.id) {
          onChanged(value);
        }
      },
    );
  }
}

class _DocumentSections extends StatelessWidget {
  const _DocumentSections({
    required this.documents,
    required this.asOf,
    required this.onRefresh,
  });

  final List<VehicleDocument> documents;
  final DateTime asOf;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final active = documents.where((document) => !document.isArchived).toList();
    final archived = documents
        .where((document) => document.isArchived)
        .toList();
    final attention = active
        .where(
          (document) =>
              document.statusAt(asOf).severity >=
              DocumentStatus.expiringSoon.severity,
        )
        .toList();
    final current = active
        .where((document) => !attention.any((item) => item.id == document.id))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (attention.isNotEmpty) ...[
          const DTSectionHeader(title: 'Needs attention'),
          for (final document in attention)
            _DocumentCard(document: document, asOf: asOf, onRefresh: onRefresh),
        ],
        if (current.isNotEmpty) ...[
          const DTSectionHeader(title: 'Current'),
          for (final document in current)
            _DocumentCard(document: document, asOf: asOf, onRefresh: onRefresh),
        ],
        if (archived.isNotEmpty) ...[
          const DTSectionHeader(title: 'Archived / History'),
          for (final document in archived)
            _DocumentCard(document: document, asOf: asOf, onRefresh: onRefresh),
        ],
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    required this.document,
    required this.asOf,
    required this.onRefresh,
  });

  final VehicleDocument document;
  final DateTime asOf;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final status = document.statusAt(asOf);
    final statusColors = _statusColors(colors, status);
    return Padding(
      padding: const EdgeInsets.only(bottom: DTSpacing.sm),
      child: Material(
        key: Key('documentCard_${document.id}'),
        color: colors.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: DTRadii.cardRadius,
        child: InkWell(
          borderRadius: DTRadii.cardRadius,
          onTap: () async {
            await AppNavigation.openDocumentDetails(context, document.id);
            await onRefresh();
          },
          child: Padding(
            padding: const EdgeInsets.all(DTSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: statusColors.background,
                    borderRadius: BorderRadius.circular(DTRadii.card),
                  ),
                  child: Icon(
                    _iconFor(document.category),
                    color: statusColors.foreground,
                  ),
                ),
                const SizedBox(width: DTSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        document.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: DTSpacing.xs),
                      Text(
                        _subtitle(document),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: DTSpacing.sm),
                      Wrap(
                        spacing: DTSpacing.sm,
                        runSpacing: DTSpacing.sm,
                        children: [
                          _StatusChip(
                            document: document,
                            status: status,
                            asOf: asOf,
                          ),
                          _AttachmentCount(documentId: document.id),
                          if (document.isArchived)
                            const _InfoChip(
                              icon: Icons.archive_outlined,
                              label: 'Archived',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _subtitle(VehicleDocument document) {
    final parts = [
      document.provider,
      document.referenceNumber,
      if (document.expiryDate != null)
        'Recorded expiry: ${compactDate(document.expiryDate!)}'
      else
        'No expiry recorded',
    ];
    return parts
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' / ');
  }
}

class _AttachmentCount extends StatelessWidget {
  const _AttachmentCount({required this.documentId});

  final String documentId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Attachment>>(
      future: context.read<DriveTrackerController>().attachmentsForParent(
        AttachmentParentType.document,
        documentId,
      ),
      builder: (context, snapshot) {
        final count = snapshot.data?.length ?? 0;
        return _InfoChip(
          icon: count == 0
              ? Icons.attach_file_rounded
              : Icons.attachment_rounded,
          label: count == 1 ? '1 attachment' : '$count attachments',
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.document,
    required this.status,
    required this.asOf,
  });

  final VehicleDocument document;
  final DocumentStatus status;
  final DateTime asOf;

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel(document, status, asOf);
    final colors = Theme.of(context).colorScheme;
    final chipColors = _statusColors(colors, status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DTSpacing.sm,
        vertical: DTSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: chipColors.background,
        borderRadius: BorderRadius.circular(DTRadii.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _statusIcon(status),
            size: DTIconSizes.sm,
            color: chipColors.foreground,
          ),
          const SizedBox(width: DTSpacing.xs),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: chipColors.foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

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
        color: colors.surfaceContainerHighest.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(DTRadii.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: DTIconSizes.sm, color: colors.onSurfaceVariant),
          const SizedBox(width: DTSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _StatusPalette {
  const _StatusPalette({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

_StatusPalette _statusColors(ColorScheme colors, DocumentStatus status) {
  return switch (status) {
    DocumentStatus.expired => _StatusPalette(
      background: colors.errorContainer,
      foreground: colors.onErrorContainer,
    ),
    DocumentStatus.expiringSoon => _StatusPalette(
      background: colors.tertiaryContainer,
      foreground: colors.onTertiaryContainer,
    ),
    DocumentStatus.valid => _StatusPalette(
      background: colors.primaryContainer.withValues(alpha: 0.78),
      foreground: colors.onPrimaryContainer,
    ),
    DocumentStatus.noExpiry => _StatusPalette(
      background: colors.secondaryContainer.withValues(alpha: 0.72),
      foreground: colors.onSecondaryContainer,
    ),
  };
}

IconData _iconFor(String category) {
  final normalized = category.toLowerCase();
  if (normalized.contains('insurance')) return Icons.shield_outlined;
  if (normalized.contains('mot')) return Icons.verified_outlined;
  if (normalized.contains('v5c')) return Icons.directions_car_outlined;
  if (normalized.contains('receipt')) return Icons.receipt_long_outlined;
  if (normalized.contains('warranty')) return Icons.workspace_premium_outlined;
  if (normalized.contains('breakdown')) return Icons.support_agent_outlined;
  if (normalized.contains('tax')) return Icons.account_balance_outlined;
  if (normalized.contains('finance') || normalized.contains('lease')) {
    return Icons.request_quote_outlined;
  }
  return Icons.description_outlined;
}

IconData _statusIcon(DocumentStatus status) {
  return switch (status) {
    DocumentStatus.expired => Icons.error_outline_rounded,
    DocumentStatus.expiringSoon => Icons.schedule_rounded,
    DocumentStatus.valid => Icons.event_available_rounded,
    DocumentStatus.noExpiry => Icons.event_note_rounded,
  };
}

String _statusLabel(
  VehicleDocument document,
  DocumentStatus status,
  DateTime asOf,
) {
  final days = document.daysUntilExpiry(asOf);
  return switch (status) {
    DocumentStatus.noExpiry => 'No expiry',
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
