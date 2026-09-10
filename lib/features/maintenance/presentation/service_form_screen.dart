import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../../core/utilities/scaled_decimal.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_odometer_input.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/presentation/attachment_panel.dart';
import '../../odometer/domain/odometer_policy.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/maintenance_item.dart';
import '../domain/service_record.dart';

class ServiceFormScreen extends StatefulWidget {
  const ServiceFormScreen({
    this.service,
    this.preselectedMaintenanceItemId,
    super.key,
  });

  final ServiceRecordWithItems? service;
  final String? preselectedMaintenanceItemId;

  @override
  State<ServiceFormScreen> createState() => _ServiceFormScreenState();
}

class _ServiceFormScreenState extends State<ServiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _odometerController = TextEditingController();
  final _totalCostController = TextEditingController();
  final _garageController = TextEditingController();
  final _notesController = TextEditingController();
  final _customItemController = TextEditingController();
  final _customItemCostController = TextEditingController();
  final _customItemNotesController = TextEditingController();
  final _selectedMaintenanceItemIds = <String>{};
  final _itemCostText = <String, String>{};
  final _itemNotesText = <String, String>{};

  String? _vehicleId;
  late DateTime _eventDateTime;
  Future<List<MaintenanceItem>>? _itemsFuture;
  String? _formError;
  bool _didDefaultFromController = false;

  bool get _isEditing => widget.service != null;

  @override
  void initState() {
    super.initState();
    final service = widget.service;
    _eventDateTime = service?.record.eventDateTime.toLocal() ?? DateTime.now();
    _vehicleId = service?.record.vehicleId;
    if (service != null) {
      final record = service.record;
      _odometerController.text = record.odometer?.toString() ?? '';
      _totalCostController.text = _moneyInputText(record.totalCostMinor);
      _garageController.text = record.garage ?? '';
      _notesController.text = record.notes ?? '';
      for (final item in service.items) {
        final maintenanceItemId = item.maintenanceItemId;
        if (maintenanceItemId == null) {
          if (_customItemController.text.isEmpty) {
            _customItemController.text = item.itemName;
            _customItemCostController.text = _moneyInputText(
              item.allocatedCostMinor,
            );
            _customItemNotesController.text = item.notes ?? '';
          }
          continue;
        }
        _selectedMaintenanceItemIds.add(maintenanceItemId);
        _itemCostText[maintenanceItemId] = _moneyInputText(
          item.allocatedCostMinor,
        );
        _itemNotesText[maintenanceItemId] = item.notes ?? '';
      }
    }
    final preselected = widget.preselectedMaintenanceItemId;
    if (preselected != null) {
      _selectedMaintenanceItemIds.add(preselected);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didDefaultFromController) {
      _didDefaultFromController = true;
      _vehicleId ??= context.read<DriveTrackerController>().selectedVehicle?.id;
      final odometer = context.read<DriveTrackerController>().currentOdometer;
      if (!_isEditing && odometer != null) {
        _odometerController.text = odometer.toString();
      }
    }
    _itemsFuture ??= _loadMaintenanceItems();
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _totalCostController.dispose();
    _garageController.dispose();
    _notesController.dispose();
    _customItemController.dispose();
    _customItemCostController.dispose();
    _customItemNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicles = controller.activeVehicles;
    final selectedVehicle = _vehicleForId(vehicles, _vehicleId);

    if (vehicles.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: DTEmptyState(
            icon: Icons.directions_car_filled_rounded,
            title: 'No active vehicle',
            body: 'Add or restore a vehicle before saving service records.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit service' : 'Add service')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.sm,
            DTSpacing.lg,
            DTSpacing.lg,
          ),
          child: Row(
            children: [
              if (_isEditing) ...[
                IconButton.filledTonal(
                  key: const Key('deleteServiceButton'),
                  tooltip: 'Delete service',
                  onPressed: controller.isBusy ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: DTSpacing.md),
              ],
              Expanded(
                child: DTPrimaryButton(
                  key: const Key('saveServiceButton'),
                  label: _isEditing ? 'Save service' : 'Save service',
                  icon: Icons.check_rounded,
                  isLoading: controller.isBusy,
                  onPressed: controller.isBusy ? null : () => _save(),
                ),
              ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(DTSpacing.lg),
            children: [
              DropdownButtonFormField<String>(
                key: const Key('serviceVehicleField'),
                initialValue: selectedVehicle?.id,
                decoration: const InputDecoration(labelText: 'Vehicle'),
                items: [
                  for (final vehicle in vehicles)
                    DropdownMenuItem(
                      value: vehicle.id,
                      child: Text(vehicle.name),
                    ),
                ],
                validator: (value) =>
                    value == null ? 'Select a vehicle.' : null,
                onChanged: _isEditing
                    ? null
                    : (value) {
                        setState(() {
                          _vehicleId = value;
                          _selectedMaintenanceItemIds.clear();
                          _itemsFuture = _loadMaintenanceItems();
                        });
                      },
              ),
              const SizedBox(height: DTSpacing.md),
              _DateTimeTile(
                label: 'Service date/time',
                value: _eventDateTime,
                onChanged: (value) => setState(() => _eventDateTime = value),
              ),
              const SizedBox(height: DTSpacing.md),
              DTOdometerInput(
                fieldKey: const Key('serviceOdometerField'),
                controller: _odometerController,
                unitLabel: selectedVehicle?.distanceUnit.shortLabel ?? 'mi',
                validator: _validateRequiredOdometer,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('serviceTotalCostField'),
                controller: _totalCostController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]')),
                ],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Total cost',
                  prefixText: '£',
                ),
                validator: _validateNonNegativeMoney,
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('serviceGarageField'),
                controller: _garageController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Garage'),
              ),
              const SizedBox(height: DTSpacing.xl),
              Text(
                'Service items',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: DTSpacing.sm),
              FutureBuilder<List<MaintenanceItem>>(
                future: _itemsFuture,
                builder: (context, snapshot) {
                  final items = snapshot.data;
                  if (items == null) {
                    return const Padding(
                      key: Key('serviceItemsLoading'),
                      padding: EdgeInsets.symmetric(vertical: DTSpacing.lg),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (items.isEmpty) {
                    return const Padding(
                      key: Key('serviceItemsEmpty'),
                      padding: EdgeInsets.only(bottom: DTSpacing.md),
                      child: Text(
                        'No tracked maintenance items yet. Add an untracked service line below.',
                      ),
                    );
                  }
                  return Column(
                    key: const Key('serviceItemsLoaded'),
                    children: [
                      for (final item in items)
                        _trackedServiceItemTile(
                          item,
                          selectedVehicle?.distanceUnit.shortLabel ?? 'mi',
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: DTSpacing.lg),
              TextFormField(
                key: const Key('customServiceItemNameField'),
                controller: _customItemController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Untracked service line',
                ),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('customServiceItemCostField'),
                controller: _customItemCostController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]')),
                ],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Untracked allocated cost',
                  prefixText: '£',
                ),
                validator: _validateOptionalMoney,
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('customServiceItemNotesField'),
                controller: _customItemNotesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Untracked item notes',
                ),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('serviceNotesField'),
                controller: _notesController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: DTSpacing.lg),
              if (_isEditing)
                AttachmentPanel(
                  key: Key('serviceAttachments_${widget.service!.record.id}'),
                  parentType: AttachmentParentType.service,
                  parentId: widget.service!.record.id,
                )
              else
                const _AttachmentsAfterSaveHint(
                  text: 'Save this service, then add invoice PDFs or images.',
                ),
              if (_formError != null) ...[
                const SizedBox(height: DTSpacing.lg),
                Text(
                  _formError!,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: DTSpacing.xxxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackedServiceItemTile(MaintenanceItem item, String unitLabel) {
    final selected = _selectedMaintenanceItemIds.contains(item.id);
    return Column(
      children: [
        CheckboxListTile(
          key: Key('serviceItemCheckbox_${item.id}'),
          contentPadding: EdgeInsets.zero,
          value: selected,
          title: Text(item.name),
          subtitle: Text(_maintenanceSubtitle(item, unitLabel)),
          onChanged: (value) {
            setState(() {
              if (value ?? false) {
                _selectedMaintenanceItemIds.add(item.id);
              } else {
                _selectedMaintenanceItemIds.remove(item.id);
              }
            });
          },
        ),
        if (selected) ...[
          TextFormField(
            key: Key('serviceItemCost_${item.id}'),
            initialValue: _itemCostText[item.id] ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]')),
            ],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Allocated cost',
              prefixText: '£',
            ),
            validator: _validateOptionalMoney,
            onChanged: (value) => _itemCostText[item.id] = value,
          ),
          const SizedBox(height: DTSpacing.sm),
          TextFormField(
            key: Key('serviceItemNotes_${item.id}'),
            initialValue: _itemNotesText[item.id] ?? '',
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Item notes'),
            onChanged: (value) => _itemNotesText[item.id] = value,
          ),
          const SizedBox(height: DTSpacing.md),
        ],
      ],
    );
  }

  Future<List<MaintenanceItem>> _loadMaintenanceItems() {
    final vehicleId = _vehicleId;
    if (vehicleId == null) {
      return Future.value(const []);
    }
    return context.read<DriveTrackerController>().maintenanceItemsForVehicle(
      vehicleId,
      includeArchived: _isEditing,
    );
  }

  Future<void> _save({
    bool allowHistorical = false,
    bool confirmLargeIncrease = false,
  }) async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final vehicleId = _vehicleId;
    if (vehicleId == null) {
      setState(() => _formError = 'Select a vehicle.');
      return;
    }

    final maintenanceItems = await context
        .read<DriveTrackerController>()
        .maintenanceItemsForVehicle(vehicleId, includeArchived: _isEditing);
    if (!mounted) {
      return;
    }

    final draft = ServiceRecordDraft(
      vehicleId: vehicleId,
      eventDateTime: _eventDateTime,
      odometer: _parseInt(_odometerController.text),
      totalCostMinor: _parseMoneyAllowingBlank(_totalCostController.text) ?? -1,
      garage: _garageController.text,
      notes: _notesController.text,
      isBaseline: widget.service?.record.isBaseline ?? false,
      items: _buildServiceItems(maintenanceItems),
    );

    try {
      final controller = context.read<DriveTrackerController>();
      if (_isEditing) {
        await controller.updateServiceRecord(
          widget.service!.record.id,
          draft,
          allowHistorical: allowHistorical,
          confirmLargeIncrease: confirmLargeIncrease,
        );
      } else {
        await controller.addServiceRecord(
          draft,
          allowHistorical: allowHistorical,
          confirmLargeIncrease: confirmLargeIncrease,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Service saved.')));
    } on OdometerConfirmationRequired catch (error) {
      final confirmed = await _confirmAssessment(error.assessment);
      if (!confirmed) {
        return;
      }
      await _save(
        allowHistorical:
            error.assessment.decision == OdometerDecision.belowCurrent,
        confirmLargeIncrease:
            error.assessment.decision ==
            OdometerDecision.unusuallyLargeIncrease,
      );
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() => _formError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _formError = 'Could not save service.');
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete service?'),
        content: const Text(
          'This removes the service and its linked odometer entry.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmDeleteServiceButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<DriveTrackerController>().deleteServiceRecord(
      widget.service!.record.id,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Service deleted.')));
  }

  List<ServiceItemDraft> _buildServiceItems(
    List<MaintenanceItem> maintenanceItems,
  ) {
    final drafts = <ServiceItemDraft>[];
    for (final item in maintenanceItems) {
      if (!_selectedMaintenanceItemIds.contains(item.id)) {
        continue;
      }
      drafts.add(
        ServiceItemDraft(
          maintenanceItemId: item.id,
          itemName: item.name,
          allocatedCostMinor: _parseOptionalMoney(_itemCostText[item.id] ?? ''),
          notes: _itemNotesText[item.id],
        ),
      );
    }

    final customName = _customItemController.text.trim();
    if (customName.isNotEmpty) {
      drafts.add(
        ServiceItemDraft(
          itemName: customName,
          allocatedCostMinor: _parseOptionalMoney(
            _customItemCostController.text,
          ),
          notes: _customItemNotesController.text,
        ),
      );
    }
    return drafts;
  }

  String? _validateRequiredOdometer(String? value) {
    final parsed = _parseInt(value ?? '');
    if (parsed == null) {
      return 'Service odometer is required.';
    }
    if (parsed < 0) {
      return 'Odometer readings cannot be negative.';
    }
    return null;
  }

  String? _validateNonNegativeMoney(String? value) {
    final parsed = _parseMoneyAllowingBlank(value ?? '');
    if (parsed == null) {
      return 'Enter a valid amount.';
    }
    if (parsed < 0) {
      return 'Amount cannot be negative.';
    }
    return null;
  }

  String? _validateOptionalMoney(String? value) {
    if ((value ?? '').trim().isEmpty) {
      return null;
    }
    final parsed = MoneyAmount.parseMinor(value ?? '');
    if (parsed == null) {
      return 'Enter a valid amount.';
    }
    if (parsed < 0) {
      return 'Amount cannot be negative.';
    }
    return null;
  }

  Future<bool> _confirmAssessment(OdometerAssessment assessment) async {
    final isHistorical = assessment.decision == OdometerDecision.belowCurrent;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isHistorical ? 'Save historical service?' : 'Confirm large increase',
        ),
        content: Text(assessment.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isHistorical ? 'Save historical' : 'Confirm'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  int? _parseInt(String value) {
    final normalized = value.replaceAll(',', '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return int.tryParse(normalized);
  }

  int? _parseMoneyAllowingBlank(String value) {
    if (value.trim().isEmpty) {
      return 0;
    }
    return MoneyAmount.parseMinor(value);
  }

  int? _parseOptionalMoney(String value) {
    if (value.trim().isEmpty) {
      return null;
    }
    return MoneyAmount.parseMinor(value);
  }

  String _moneyInputText(int? value) {
    if (value == null) {
      return '';
    }
    return ScaledDecimal.format(
      value,
      scale: MoneyAmount.defaultCurrency.minorScale,
      minFractionDigits: 2,
      maxFractionDigits: 2,
    );
  }

  String _maintenanceSubtitle(MaintenanceItem item, String unitLabel) {
    final parts = [
      item.category,
      if (item.mileageInterval != null)
        'Every ${DTFormatters.wholeNumber(item.mileageInterval!)} $unitLabel',
      if (item.timeIntervalDays != null) 'Every ${item.timeIntervalDays} days',
      if (item.isArchived) 'Archived',
    ];
    return parts
        .where((part) => part != null && part.trim().isNotEmpty)
        .join(' / ');
  }

  Vehicle? _vehicleForId(List<Vehicle> vehicles, String? id) {
    if (id == null) {
      return null;
    }
    for (final vehicle in vehicles) {
      if (vehicle.id == id) {
        return vehicle;
      }
    }
    return null;
  }
}

class _AttachmentsAfterSaveHint extends StatelessWidget {
  const _AttachmentsAfterSaveHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: DTRadii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(DTSpacing.md),
        child: Row(
          children: [
            Icon(Icons.attach_file_rounded, color: colors.primary),
            const SizedBox(width: DTSpacing.md),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(child: Text(DTFormatters.dateTime(value))),
          IconButton(
            tooltip: 'Choose date',
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(1990),
                lastDate: DateTime(DateTime.now().year + 1, 12, 31),
              );
              if (picked == null) {
                return;
              }
              onChanged(
                DateTime(
                  picked.year,
                  picked.month,
                  picked.day,
                  value.hour,
                  value.minute,
                ),
              );
            },
            icon: const Icon(Icons.calendar_month_rounded),
          ),
          IconButton(
            tooltip: 'Choose time',
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(value),
              );
              if (picked == null) {
                return;
              }
              onChanged(
                DateTime(
                  value.year,
                  value.month,
                  value.day,
                  picked.hour,
                  picked.minute,
                ),
              );
            },
            icon: const Icon(Icons.schedule_rounded),
          ),
        ],
      ),
    );
  }
}
