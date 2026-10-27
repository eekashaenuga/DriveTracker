import 'income_earnings_details.dart';
import '../domain/income.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/router/app_navigation.dart';
import '../../../core/utilities/formatters.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/presentation/attachment_panel.dart';
import '../../odometer/domain/odometer_entry.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/daily_activity.dart';

/// Shared read-only presentation, with type-specific fields and existing edit flows.
class RecordDetailsScreen extends StatefulWidget {
  const RecordDetailsScreen({
    required this.type,
    required this.recordId,
    super.key,
  });
  final DailyActivityType type;
  final String recordId;
  @override
  State<RecordDetailsScreen> createState() => _RecordDetailsScreenState();
}

class _RecordDetailsScreenState extends State<RecordDetailsScreen> {
  late Future<_RecordDetails?> _future;
  bool _editing = false;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_RecordDetails?> _load() async {
    final c = context.read<DriveTrackerController>();
    Income? income;
    String vehicleId;
    DateTime date;
    int? odometer;
    String primary;
    String? notes;
    AttachmentParentType? parent;
    Future<void> Function()? edit;
    final fields = <(String, String)>[];
    switch (widget.type) {
      case DailyActivityType.refuel:
        final r = await c.refuelById(widget.recordId);
        if (r == null) return null;
        vehicleId = r.vehicleId;
        date = r.eventDateTime;
        odometer = r.odometer;
        primary = DTFormatters.moneyMinor(r.totalCostMinor);
        notes = r.notes;
        fields.addAll([
          ('Fuel', r.fuelType.label),
          ('Volume', DTFormatters.fuelVolume(r.volumeMillilitres)),
          ('Unit price', DTFormatters.fuelPrice(r.unitPriceMicrosPerLitre)),
          ('Tank', r.isFullTank ? 'Full tank' : 'Partial tank'),
          ('Missed previous refuel', r.missedPreviousRefuel ? 'Yes' : 'No'),
        ]);
        if (r.station != null) fields.add(('Station', r.station!));
        parent = AttachmentParentType.refuel;
        edit = () => AppNavigation.editRefuel(context, r);
        break;
      case DailyActivityType.expense:
        final r = await c.expenseById(widget.recordId);
        if (r == null) return null;
        vehicleId = r.vehicleId;
        date = r.eventDateTime;
        odometer = r.odometer;
        primary = DTFormatters.moneyMinor(r.amountMinor);
        notes = r.notes;
        final category = await c.categoryById(r.categoryId);
        fields.add((
          'Category',
          category == null
              ? 'Category unavailable'
              : '${category.name}${category.isArchived ? ' (archived)' : ''}',
        ));
        if (r.merchant != null) fields.add(('Merchant', r.merchant!));
        if (r.paymentMethod != null) {
          fields.add(('Payment method', r.paymentMethod!));
        }
        parent = AttachmentParentType.expense;
        edit = () => AppNavigation.editExpense(context, r);
        break;
      case DailyActivityType.income:
        final r = await c.incomeById(widget.recordId);
        if (r == null) return null;
        income = r;
        vehicleId = r.vehicleId;
        date = r.eventDateTime;
        odometer = r.odometer;
        primary = DTFormatters.moneyMinor(r.amountMinor);
        notes = r.notes;
        final category = await c.categoryById(r.categoryId);
        fields.add((
          'Category',
          category == null
              ? 'Category unavailable'
              : '${category.name}${category.isArchived ? ' (archived)' : ''}',
        ));
        if (r.source != null) fields.add(('Source', r.source!));
        parent = AttachmentParentType.income;
        edit = () => AppNavigation.editIncome(context, r);
        break;
      case DailyActivityType.service:
        final r = await c.serviceRecordById(widget.recordId);
        if (r == null) return null;
        vehicleId = r.record.vehicleId;
        date = r.record.eventDateTime;
        odometer = r.record.odometer;
        primary = r.record.isBaseline
            ? 'Baseline'
            : DTFormatters.moneyMinor(r.record.totalCostMinor);
        notes = r.record.notes;
        fields.add((
          'Record kind',
          r.record.isBaseline ? 'Zero-cost maintenance baseline' : 'Service',
        ));
        if (r.record.garage != null) fields.add(('Garage', r.record.garage!));
        for (final item in r.items) {
          fields.add(('Service item', item.itemName));
          if (item.allocatedCostMinor != null) {
            fields.add((
              'Allocated cost',
              DTFormatters.moneyMinor(item.allocatedCostMinor),
            ));
          }
          if (item.notes != null) fields.add(('Item notes', item.notes!));
        }
        parent = AttachmentParentType.service;
        edit = () => AppNavigation.editService(context, r);
        break;
      case DailyActivityType.odometer:
        final r = await c.odometerEntryById(widget.recordId);
        if (r == null) return null;
        vehicleId = r.vehicleId;
        date = r.eventDateTime;
        odometer = r.odometer;
        primary = '';
        notes = null;
        fields.add(('Source', r.sourceType.label));
        if (r.sourceType == OdometerSourceType.manual) {
          edit = () => AppNavigation.openEditOdometerEntry(context, r);
        }
        break;
      case DailyActivityType.all:
        return null;
    }
    final vehicles = [...c.activeVehicles, ...c.archivedVehicles];
    Vehicle? vehicle;
    for (final v in vehicles) {
      if (v.id == vehicleId) {
        vehicle = v;
        break;
      }
    }
    final unit = vehicle?.distanceUnit ?? DistanceUnit.miles;
    final reading = odometer == null
        ? 'Not recorded'
        : DTFormatters.odometer(odometer, unit);
    if (widget.type == DailyActivityType.odometer) primary = reading;
    return _RecordDetails(
      income: income,
      unit: unit,
      primary: primary,
      notes: notes,
      parent: parent,
      edit: vehicle == null || vehicle.isArchived ? null : edit,
      fields: [
        ('Vehicle', vehicle?.name ?? 'Vehicle unavailable'),
        ('Date', DTFormatters.dateTime(date)),
        if (widget.type != DailyActivityType.odometer) ('Odometer', reading),
        ...fields,
      ],
    );
  }

  Future<void> _edit(_RecordDetails data) async {
    setState(() => _editing = true);
    try {
      await data.edit!();
      if (!mounted) return;
      final refreshed = await _load();
      if (!mounted) return;
      if (refreshed == null) {
        Navigator.pop(context);
        return;
      }
      setState(() {
        _future = Future.value(refreshed);
        _revision++;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not refresh this record. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (widget.type) {
      DailyActivityType.refuel => 'Refuel',
      DailyActivityType.odometer => 'Odometer',
      _ => widget.type.label,
    };
    return FutureBuilder<_RecordDetails?>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        return Scaffold(
          key: Key(
            widget.type == DailyActivityType.odometer
                ? 'historyOdometerDetails'
                : '${widget.type.name}Details',
          ),
          appBar: AppBar(
            title: Text('$title details'),
            actions: [
              if (data?.edit != null)
                TextButton.icon(
                  key: Key(
                    widget.type == DailyActivityType.odometer
                        ? 'historyEditOdometerButton'
                        : 'recordDetailsEdit',
                  ),
                  onPressed: _editing ? null : () => _edit(data!),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
            ],
          ),
          body: SafeArea(
            child: snapshot.hasError
                ? Center(
                    child: TextButton(
                      onPressed: () => setState(() => _future = _load()),
                      child: const Text('Could not load record. Retry'),
                    ),
                  )
                : snapshot.connectionState != ConnectionState.done
                ? const Center(child: CircularProgressIndicator())
                : data == null
                ? const Center(child: Text('Record no longer exists.'))
                : ListView(
                    key: Key('recordDetailsLoaded_${widget.recordId}'),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        data.primary,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 24),
                      Material(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          children: [
                            for (final field in data.fields)
                              ListTile(
                                title: Text(field.$1),
                                subtitle: Text(field.$2),
                              ),
                          ],
                        ),
                      ),
                      if (data.income != null)
                        IncomeEarningsDetails(
                          income: data.income!,
                          unit: data.unit,
                        ),
                      if (data.notes != null && data.notes!.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(
                          'Notes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(data.notes!),
                      ],
                      if (data.parent != null) ...[
                        const SizedBox(height: 24),
                        AttachmentPanel(
                          key: ValueKey('${widget.recordId}_$_revision'),
                          parentType: data.parent!,
                          parentId: widget.recordId,
                          readOnly: true,
                        ),
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _RecordDetails {
  const _RecordDetails({
    this.income,
    this.unit = DistanceUnit.miles,
    required this.primary,
    required this.fields,
    this.notes,
    this.parent,
    this.edit,
  });
  final Income? income;
  final DistanceUnit unit;
  final String primary;
  final List<(String, String)> fields;
  final String? notes;
  final AttachmentParentType? parent;
  final Future<void> Function()? edit;
}
