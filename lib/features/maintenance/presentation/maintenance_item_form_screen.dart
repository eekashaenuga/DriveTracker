import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_odometer_input.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/maintenance_item.dart';

class MaintenanceItemFormScreen extends StatefulWidget {
  const MaintenanceItemFormScreen({this.item, super.key});

  final MaintenanceItem? item;

  @override
  State<MaintenanceItemFormScreen> createState() =>
      _MaintenanceItemFormScreenState();
}

class _MaintenanceItemFormScreenState extends State<MaintenanceItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _mileageIntervalController = TextEditingController();
  final _timeIntervalController = TextEditingController();
  final _mileageWarningController = TextEditingController(text: '1000');
  final _dateWarningController = TextEditingController(text: '30');
  final _baselineOdometerController = TextEditingController();

  String? _vehicleId;
  var _reminderEnabled = true;
  var _addBaseline = false;
  var _baselineDate = DateTime.now();
  String? _formError;
  bool _didDefaultFromController = false;
  int? _lastOdometer;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    if (item != null) {
      _vehicleId = item.vehicleId;
      _nameController.text = item.name;
      _categoryController.text = item.category ?? '';
      _mileageIntervalController.text = item.mileageInterval?.toString() ?? '';
      _timeIntervalController.text = item.timeIntervalDays?.toString() ?? '';
      _mileageWarningController.text = item.mileageWarning.toString();
      _dateWarningController.text = item.dateWarningDays.toString();
      _reminderEnabled = item.reminderEnabled;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didDefaultFromController) {
      return;
    }
    _didDefaultFromController = true;
    final controller = context.read<DriveTrackerController>();
    _vehicleId ??= controller.selectedVehicle?.id;
    _lastOdometer = controller.currentOdometer;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _mileageIntervalController.dispose();
    _timeIntervalController.dispose();
    _mileageWarningController.dispose();
    _dateWarningController.dispose();
    _baselineOdometerController.dispose();
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
            body: 'Add or restore a vehicle before creating maintenance items.',
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit maintenance item' : 'Add maintenance'),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.sm,
            DTSpacing.lg,
            DTSpacing.lg,
          ),
          child: DTPrimaryButton(
            key: const Key('saveMaintenanceItemButton'),
            label: _isEditing ? 'Save item' : 'Save item',
            icon: Icons.check_rounded,
            isLoading: controller.isBusy,
            onPressed: controller.isBusy ? null : _save,
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
                key: const Key('maintenanceVehicleField'),
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
                    : (value) async {
                        setState(() => _vehicleId = value);
                        if (value == null) {
                          return;
                        }
                        final odometer = await context
                            .read<DriveTrackerController>()
                            .currentOdometerForVehicle(value);
                        if (mounted) {
                          setState(() => _lastOdometer = odometer);
                        }
                      },
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('maintenanceNameField'),
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if ((value ?? '').trim().isEmpty) {
                    return 'Maintenance item name is required.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('maintenanceCategoryField'),
                controller: _categoryController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
              const SizedBox(height: DTSpacing.xl),
              Text(
                'Intervals',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('maintenanceMileageIntervalField'),
                controller: _mileageIntervalController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Mileage interval',
                  suffixText: selectedVehicle?.distanceUnit.shortLabel ?? 'mi',
                ),
                validator: (value) =>
                    _validateOptionalPositiveInt(value, 'Mileage interval'),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('maintenanceTimeIntervalField'),
                controller: _timeIntervalController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Time interval',
                  suffixText: 'days',
                ),
                validator: (value) =>
                    _validateOptionalPositiveInt(value, 'Time interval'),
              ),
              const SizedBox(height: DTSpacing.lg),
              SwitchListTile(
                key: const Key('maintenanceReminderSwitch'),
                contentPadding: EdgeInsets.zero,
                value: _reminderEnabled,
                title: const Text('Reminders'),
                subtitle: const Text('Show this item on Home and Reminders'),
                onChanged: (value) => setState(() => _reminderEnabled = value),
              ),
              if (_reminderEnabled) ...[
                const SizedBox(height: DTSpacing.md),
                TextFormField(
                  key: const Key('maintenanceMileageWarningField'),
                  controller: _mileageWarningController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Mileage warning',
                    suffixText:
                        selectedVehicle?.distanceUnit.shortLabel ?? 'mi',
                  ),
                  validator: (value) =>
                      _validateNonNegativeInt(value, 'Mileage warning'),
                ),
                const SizedBox(height: DTSpacing.md),
                TextFormField(
                  key: const Key('maintenanceDateWarningField'),
                  controller: _dateWarningController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Date warning',
                    suffixText: 'days',
                  ),
                  validator: (value) =>
                      _validateNonNegativeInt(value, 'Date warning'),
                ),
              ],
              if (!_isEditing) ...[
                const SizedBox(height: DTSpacing.xl),
                SwitchListTile(
                  key: const Key('maintenanceBaselineSwitch'),
                  contentPadding: EdgeInsets.zero,
                  value: _addBaseline,
                  title: const Text('Add last completed'),
                  subtitle: const Text(
                    'Creates a zero-cost baseline service history record',
                  ),
                  onChanged: (value) => setState(() => _addBaseline = value),
                ),
                if (_addBaseline) ...[
                  const SizedBox(height: DTSpacing.md),
                  _DateTile(
                    key: const Key('maintenanceBaselineDateField'),
                    label: 'Last completed date',
                    value: _baselineDate,
                    onChanged: (value) => setState(() => _baselineDate = value),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  DTOdometerInput(
                    fieldKey: const Key('maintenanceBaselineOdometerField'),
                    controller: _baselineOdometerController,
                    label: 'Last completed odometer',
                    unitLabel: selectedVehicle?.distanceUnit.shortLabel ?? 'mi',
                    helperText: dtOdometerContextText(
                      referenceOdometer: _lastOdometer,
                      unit: selectedVehicle?.distanceUnit,
                      enteredOdometer: dtParseOdometerInput(
                        _baselineOdometerController.text,
                      ),
                    ),
                    textInputAction: TextInputAction.done,
                    validator: (value) =>
                        _validateOptionalNonNegativeInt(value, 'Odometer'),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
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

  Future<void> _save() async {
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

    final draft = MaintenanceItemDraft(
      vehicleId: vehicleId,
      name: _nameController.text,
      category: _categoryController.text,
      mileageInterval: _parseOptionalInt(_mileageIntervalController.text),
      timeIntervalDays: _parseOptionalInt(_timeIntervalController.text),
      mileageWarning: _parseOptionalInt(_mileageWarningController.text) ?? 1000,
      dateWarningDays: _parseOptionalInt(_dateWarningController.text) ?? 30,
      reminderEnabled: _reminderEnabled,
    );

    try {
      final controller = context.read<DriveTrackerController>();
      if (_isEditing) {
        await controller.updateMaintenanceItem(widget.item!.id, draft);
      } else {
        await controller.addMaintenanceItem(
          draft,
          baselineDateTime: _addBaseline ? _baselineDate : null,
          baselineOdometer: _addBaseline
              ? _parseOptionalInt(_baselineOdometerController.text)
              : null,
        );
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Maintenance saved.')));
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() => _formError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _formError = 'Could not save maintenance item.');
      }
    }
  }

  String? _validateOptionalPositiveInt(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return null;
    }
    final parsed = _parseOptionalInt(value ?? '');
    if (parsed == null) {
      return '$label must be a whole number.';
    }
    if (parsed <= 0) {
      return '$label must be greater than zero.';
    }
    return null;
  }

  String? _validateOptionalNonNegativeInt(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return null;
    }
    final parsed = _parseOptionalInt(value ?? '');
    if (parsed == null) {
      return '$label must be a whole number.';
    }
    if (parsed < 0) {
      return '$label cannot be negative.';
    }
    return null;
  }

  String? _validateNonNegativeInt(String? value, String label) {
    final parsed = _parseOptionalInt(value ?? '');
    if (parsed == null) {
      return '$label must be a whole number.';
    }
    if (parsed < 0) {
      return '$label cannot be negative.';
    }
    return null;
  }

  int? _parseOptionalInt(String value) {
    final clean = value.replaceAll(',', '').trim();
    if (clean.isEmpty) {
      return null;
    }
    return int.tryParse(clean);
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

class _DateTile extends StatelessWidget {
  const _DateTile({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
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
          Expanded(child: Text(DTFormatters.date(value))),
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
              onChanged(picked);
            },
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
    );
  }
}
