import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../shared/widgets/dt_date_field.dart';
import '../../attachments/domain/attachment.dart';
import '../../maintenance/domain/maintenance_item.dart';
import '../domain/document_type.dart';
import '../domain/vehicle_document_overview.dart';

class VehicleDocumentsOverview extends StatefulWidget {
  const VehicleDocumentsOverview({
    required this.vehicleId,
    this.showAll = true,
    super.key,
  });
  final String vehicleId;
  final bool showAll;
  @override
  State<VehicleDocumentsOverview> createState() =>
      _VehicleDocumentsOverviewState();
}

class _VehicleDocumentsOverviewState extends State<VehicleDocumentsOverview> {
  Future<(VehicleDocumentOverview, int)>? _future;
  int? _revision;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.read<DriveTrackerController>().dataRevision;
    if (_future == null || _revision != revision) {
      _revision = revision;
      _future = _load();
    }
  }

  @override
  void didUpdateWidget(VehicleDocumentsOverview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicleId != widget.vehicleId) _future = _load();
  }

  Future<(VehicleDocumentOverview, int)> _load() async {
    final controller = context.read<DriveTrackerController>();
    final vehicleId = widget.vehicleId;
    final documents = await controller.documentsForVehicle(vehicleId);
    final maintenance = await controller.maintenanceItemsForVehicle(vehicleId);
    var files = 0;
    for (final document in documents) {
      files += (await controller.attachmentsForParent(
        AttachmentParentType.document,
        document.id,
      )).length;
    }
    return (
      VehicleDocumentOverview(
        vehicleId: vehicleId,
        documents: documents,
        maintenance: maintenance,
      ),
      files,
    );
  }

  Future<void> _open(Future<void> Function() action) async {
    await action();
    if (mounted) setState(() => _future = _load());
  }

  String _dateSummary(DocumentType type, DateTime? date, DateTime asOf) =>
      '${documentStatusLabel(type, date, asOf)}${date == null ? '' : '\n${type == DocumentType.tax ? 'Due' : 'Expires'} ${compactDate(date)}'}';

  Widget _typeSection(
    VehicleDocumentOverview overview,
    DocumentType type,
    DateTime asOf,
  ) {
    final documents = overview.forType(type);
    final items = type == DocumentType.mot
        ? overview.motItems
        : const <MaintenanceItem>[];
    final count = documents.length + items.length;
    final review = count > 1;
    final document = documents.firstOrNull;
    final item = items.firstOrNull;
    Future<void> openDocument() =>
        _open(() => AppNavigation.openDocumentDetails(context, document!.id));
    Future<void> openMaintenance() =>
        _open(() => AppNavigation.openEditMaintenanceItem(context, item!));
    return Column(
      children: [
        ListTile(
          key: !review && document != null
              ? Key('complianceDocument_${document.id}')
              : !review && item != null
              ? Key('complianceMaintenance_${item.id}')
              : Key('complianceType_${type.name}'),
          contentPadding: EdgeInsets.zero,
          title: Text(type.label),
          subtitle: Text(
            review
                ? type == DocumentType.mot
                      ? 'Review needed: multiple active MOT sources'
                      : '$count active records - review dates below'
                : document != null
                ? '${document.title}\n${_dateSummary(type, document.expiryDate, asOf)}'
                : item != null
                ? item.isExpiry
                      ? _dateSummary(type, item.expiryDate, asOf)
                      : 'Legacy maintenance schedule'
                : 'Setup needed',
          ),
          trailing: review
              ? const Icon(Icons.info_outline)
              : Icon(count == 0 ? Icons.add : Icons.chevron_right),
          onTap: review
              ? null
              : document != null
              ? openDocument
              : item != null
              ? openMaintenance
              : () => _open(() async {
                  await AppNavigation.openAddDocument(
                    context,
                    vehicleId: widget.vehicleId,
                    category: type.label,
                  );
                }),
        ),
        if (review) ...[
          for (final document in documents)
            ListTile(
              key: Key('complianceDocument_${document.id}'),
              contentPadding: const EdgeInsets.only(left: 16),
              title: Text(document.title),
              subtitle: Text(_dateSummary(type, document.expiryDate, asOf)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(
                () => AppNavigation.openDocumentDetails(context, document.id),
              ),
            ),
          for (final item in items)
            ListTile(
              key: Key('complianceMaintenance_${item.id}'),
              contentPadding: const EdgeInsets.only(left: 16),
              title: Text(item.name),
              subtitle: Text(
                item.isExpiry
                    ? _dateSummary(type, item.expiryDate, asOf)
                    : 'Legacy maintenance schedule',
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _open(
                () => AppNavigation.openEditMaintenanceItem(context, item),
              ),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    return FutureBuilder<(VehicleDocumentOverview, int)>(
      key: ValueKey(widget.vehicleId),
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('Documents could not be loaded.');
        }
        final data = snapshot.data;
        if (data == null) return const LinearProgressIndicator();
        final overview = data.$1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Documents & Compliance',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Text('User-recorded information'),
            for (final type in [
              DocumentType.mot,
              DocumentType.insurance,
              DocumentType.tax,
              DocumentType.v5c,
            ])
              _typeSection(overview, type, controller.currentTime),
            Text(
              '${overview.documents.where((d) => ![DocumentType.mot, DocumentType.insurance, DocumentType.tax, DocumentType.v5c].contains(d.type)).length} other documents / ${data.$2} document files',
            ),
            if (widget.showAll)
              TextButton.icon(
                onPressed: () => _open(
                  () => AppNavigation.openDocuments(
                    context,
                    vehicleId: widget.vehicleId,
                  ),
                ),
                icon: const Icon(Icons.folder_open),
                label: const Text('All documents'),
              ),
          ],
        );
      },
    );
  }
}
