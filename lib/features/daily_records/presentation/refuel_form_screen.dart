import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../../core/utilities/scaled_decimal.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_odometer_input.dart';
import '../../../shared/widgets/dt_form_section.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/odometer_confirmation_dialog.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/presentation/attachment_panel.dart';
import '../../odometer/domain/odometer_policy.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/fuel_entry_calculator.dart';
import '../domain/refuel.dart';

enum _UnitPriceMode { pencePerLitre, poundsPerLitre }

class RefuelFormScreen extends StatefulWidget {
  const RefuelFormScreen({this.refuel, super.key});

  final Refuel? refuel;

  @override
  State<RefuelFormScreen> createState() => _RefuelFormScreenState();
}

class _RefuelFormScreenState extends State<RefuelFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _odometerController = TextEditingController();
  final _totalCostController = TextEditingController();
  final _volumeController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _stationController = TextEditingController();
  final _notesController = TextEditingController();

  String? _vehicleId;
  late DateTime _eventDateTime;
  late FuelType _fuelType;
  late bool _isFullTank;
  late bool _missedPreviousRefuel;
  var _unitPriceMode = _UnitPriceMode.pencePerLitre;
  var _fuelValues = const FuelEntryValues();
  var _manualFields = <FuelEntryField>[];
  FuelEntryField? _calculatedField;
  var _syncingFuelFields = false;
  String? _formError;
  bool _didDefaultFromController = false;
  int? _lastOdometer;

  bool get _isEditing => widget.refuel != null;

  @override
  void initState() {
    super.initState();
    final refuel = widget.refuel;
    _eventDateTime = refuel?.eventDateTime.toLocal() ?? DateTime.now();
    _fuelType = refuel?.fuelType ?? FuelType.petrol;
    _isFullTank = refuel?.isFullTank ?? true;
    _missedPreviousRefuel = refuel?.missedPreviousRefuel ?? false;
    _vehicleId = refuel?.vehicleId;
    if (refuel != null) {
      _fuelValues = FuelEntryValues(
        totalCostMinor: refuel.totalCostMinor,
        volumeMillilitres: refuel.volumeMillilitres,
        unitPriceMicrosPerLitre: refuel.unitPriceMicrosPerLitre,
      );
      _manualFields = [FuelEntryField.totalCost, FuelEntryField.volume];
      _calculatedField = FuelEntryField.unitPrice;
      _odometerController.text = DTFormatters.wholeNumber(refuel.odometer);
      _totalCostController.text = ScaledDecimal.format(
        refuel.totalCostMinor,
        scale: MoneyAmount.defaultCurrency.minorScale,
        minFractionDigits: 2,
        maxFractionDigits: 2,
      );
      _volumeController.text = ScaledDecimal.format(
        refuel.volumeMillilitres,
        scale: FuelNumbers.millilitresPerLitre,
        maxFractionDigits: 3,
      );
      _unitPriceController.text = ScaledDecimal.format(
        refuel.unitPriceMicrosPerLitre,
        scale: FuelNumbers.microsPerPence,
        maxFractionDigits: 3,
      );
      _stationController.text = refuel.station ?? '';
      _notesController.text = refuel.notes ?? '';
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
    final vehicle = widget.refuel == null ? controller.selectedVehicle : null;
    if (vehicle == null) {
      return;
    }
    _vehicleId = vehicle.id;
    _fuelType = vehicle.fuelType;
    final odometer = controller.currentOdometer;
    _lastOdometer = odometer;
    if (odometer != null) {
      _odometerController.text = DTFormatters.wholeNumber(odometer);
    }
  }

  @override
  void dispose() {
    _odometerController.dispose();
    _totalCostController.dispose();
    _volumeController.dispose();
    _unitPriceController.dispose();
    _stationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicles = controller.activeVehicles;
    final selectedVehicle = _vehicleForId(vehicles, _vehicleId);
    final theme = Theme.of(context);
    final currencySymbol = MoneyAmount.defaultCurrency.symbol;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit refuel' : 'Add refuel')),
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
                  tooltip: 'Delete refuel',
                  onPressed: controller.isBusy ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: DTSpacing.md),
              ],
              Expanded(
                child: DTPrimaryButton(
                  key: const Key('saveRefuelButton'),
                  label: _isEditing ? 'Save refuel' : 'Save refuel',
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
              DTFormSection(
                title: 'Record',
                icon: Icons.receipt_long_rounded,
                subtitle: 'Vehicle, date and mileage for this refuel.',
                children: [
                  DropdownButtonFormField<String>(
                    key: const Key('refuelVehicleField'),
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
                            if (value == null) {
                              return;
                            }
                            final vehicle = _vehicleForId(vehicles, value);
                            setState(() {
                              _vehicleId = value;
                              if (vehicle != null) {
                                _fuelType = vehicle.fuelType;
                              }
                            });
                            final odometer = await context
                                .read<DriveTrackerController>()
                                .currentOdometerForVehicle(value);
                            if (mounted) {
                              setState(() {
                                _lastOdometer = odometer;
                                if (odometer != null) {
                                  _odometerController.text =
                                      DTFormatters.wholeNumber(odometer);
                                }
                              });
                            }
                          },
                  ),
                  const SizedBox(height: DTSpacing.md),
                  _DateTimeTile(
                    label: 'Date/time',
                    value: _eventDateTime,
                    onChanged: (value) =>
                        setState(() => _eventDateTime = value),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  DTOdometerInput(
                    fieldKey: const Key('refuelOdometerField'),
                    controller: _odometerController,
                    unitLabel: selectedVehicle?.distanceUnit.shortLabel ?? 'mi',
                    validator: _validateRequiredOdometer,
                    helperText: _isEditing
                        ? null
                        : dtOdometerContextText(
                            referenceOdometer: _lastOdometer,
                            unit: selectedVehicle?.distanceUnit,
                            enteredOdometer: dtParseOdometerInput(
                              _odometerController.text,
                            ),
                          ),
                    textInputAction: TextInputAction.next,
                    onChanged: _isEditing ? null : (_) => setState(() {}),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  DropdownButtonFormField<FuelType>(
                    key: const Key('refuelFuelTypeField'),
                    initialValue: _fuelType,
                    decoration: const InputDecoration(labelText: 'Fuel type'),
                    items: [
                      for (final type in FuelType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _fuelType = value);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: DTSpacing.xl),
              DTFormSection(
                title: 'Fuel details',
                icon: Icons.local_gas_station_rounded,
                subtitle: 'Enter any two values and DriveTracker calculates the third.',
                children: [
                  TextFormField(
                    key: const Key('refuelTotalCostField'),
                    controller: _totalCostController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]')),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Total cost',
                      prefixText: currencySymbol,
                    ),
                    validator: (value) => _validatePositive(
                      MoneyAmount.parseMinor(value ?? ''),
                      'Total cost',
                    ),
                    onChanged: (_) =>
                        _onFuelFieldChanged(FuelEntryField.totalCost),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    key: const Key('refuelVolumeField'),
                    controller: _volumeController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Fuel volume',
                      suffixText: 'L',
                    ),
                    validator: (value) => _validatePositive(
                      FuelNumbers.parseLitresToMillilitres(value ?? ''),
                      'Fuel volume',
                    ),
                    onChanged: (_) =>
                        _onFuelFieldChanged(FuelEntryField.volume),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<_UnitPriceMode>(
                      selected: {_unitPriceMode},
                      segments: [
                        ButtonSegment(
                          value: _UnitPriceMode.pencePerLitre,
                          label: const Text('p/L'),
                          icon: const Icon(Icons.local_gas_station_rounded),
                        ),
                        ButtonSegment(
                          value: _UnitPriceMode.poundsPerLitre,
                          label: Text('$currencySymbol/L'),
                          icon: const Icon(Icons.payments_rounded),
                        ),
                      ],
                      onSelectionChanged: (selection) {
                        setState(() {
                          _unitPriceMode = selection.first;
                          _formatUnitPriceController();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    key: const Key('refuelUnitPriceField'),
                    controller: _unitPriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]')),
                    ],
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: 'Unit price',
                      suffixText: _unitPriceMode == _UnitPriceMode.pencePerLitre
                          ? 'p/L'
                          : '$currencySymbol/L',
                    ),
                    validator: (value) => _validatePositive(
                      _parseUnitPrice(value ?? ''),
                      'Unit price',
                    ),
                    onChanged: (_) =>
                        _onFuelFieldChanged(FuelEntryField.unitPrice),
                  ),
                  if (_calculatedField != null) ...[
                    const SizedBox(height: DTSpacing.sm),
                    Text(
                      '${_labelForFuelField(_calculatedField!)} calculated from the other two values.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: DTSpacing.lg),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isFullTank,
                title: const Text('Full tank'),
                subtitle: const Text('Turn off for a partial fill'),
                onChanged: (value) => setState(() => _isFullTank = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _missedPreviousRefuel,
                title: const Text('Previous refuel was not recorded'),
                subtitle: const Text('Breaks fuel economy calculations safely'),
                onChanged: (value) =>
                    setState(() => _missedPreviousRefuel = value),
              ),
              const SizedBox(height: DTSpacing.lg),
              TextFormField(
                controller: _stationController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Station'),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                controller: _notesController,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: DTSpacing.lg),
              if (_isEditing)
                AttachmentPanel(
                  key: Key('refuelAttachments_${widget.refuel!.id}'),
                  parentType: AttachmentParentType.refuel,
                  parentId: widget.refuel!.id,
                )
              else
                const _AttachmentsAfterSaveHint(
                  text: 'Save this refuel, then add receipt PDFs or images.',
                ),
              if (_formError != null) ...[
                const SizedBox(height: DTSpacing.lg),
                Text(
                  _formError!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: DTSpacing.xxxl),
            ],
          ),
        ),
      ),
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

    final draft = RefuelDraft(
      vehicleId: _vehicleId!,
      eventDateTime: _eventDateTime,
      odometer: _parseInt(_odometerController.text)!,
      fuelType: _fuelType,
      totalCostMinor: MoneyAmount.parseMinor(_totalCostController.text)!,
      volumeMillilitres: FuelNumbers.parseLitresToMillilitres(
        _volumeController.text,
      )!,
      unitPriceMicrosPerLitre: _parseUnitPrice(_unitPriceController.text)!,
      isFullTank: _isFullTank,
      missedPreviousRefuel: _missedPreviousRefuel,
      station: _stationController.text,
      notes: _notesController.text,
    );

    try {
      final controller = context.read<DriveTrackerController>();
      if (_isEditing) {
        await controller.updateRefuel(
          widget.refuel!.id,
          draft,
          allowHistorical: allowHistorical,
          confirmLargeIncrease: confirmLargeIncrease,
        );
      } else {
        await controller.addRefuel(
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
          .showSnackBar(const SnackBar(content: Text('Refuel saved.')));
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
      if (!mounted) {
        return;
      }
      setState(() => _formError = error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _formError = 'Could not save refuel.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete refuel?'),
        content: const Text('This removes the linked refuel odometer entry.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await context.read<DriveTrackerController>().deleteRefuel(
      widget.refuel!.id,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Refuel deleted.')));
  }

  Future<bool> _confirmAssessment(OdometerAssessment assessment) async {
    final vehicle = _vehicleForId(
      context.read<DriveTrackerController>().activeVehicles,
      _vehicleId,
    );
    if (vehicle == null) {
      return false;
    }
    return showOdometerConfirmationDialog(
      context: context,
      assessment: assessment,
      unit: vehicle.distanceUnit,
      historicalTitle: 'Save historical refuel?',
    );
  }

  void _onFuelFieldChanged(FuelEntryField editedField) {
    if (_syncingFuelFields) {
      return;
    }

    final editedValue = switch (editedField) {
      FuelEntryField.totalCost => MoneyAmount.parseMinor(
        _totalCostController.text,
      ),
      FuelEntryField.volume => FuelNumbers.parseLitresToMillilitres(
        _volumeController.text,
      ),
      FuelEntryField.unitPrice => _parseUnitPrice(_unitPriceController.text),
    };

    final result = FuelEntryCalculator.update(
      current: _fuelValues,
      manualFields: _manualFields,
      editedField: editedField,
      editedValue: editedValue,
    );
    _fuelValues = result.values;
    _manualFields = result.manualFields;
    _calculatedField = result.calculatedField;

    _syncingFuelFields = true;
    if (result.calculatedField == FuelEntryField.totalCost) {
      _totalCostController.text = ScaledDecimal.format(
        result.values.totalCostMinor!,
        scale: MoneyAmount.defaultCurrency.minorScale,
        minFractionDigits: 2,
        maxFractionDigits: 2,
      );
    } else if (result.calculatedField == FuelEntryField.volume) {
      _volumeController.text = ScaledDecimal.format(
        result.values.volumeMillilitres!,
        scale: FuelNumbers.millilitresPerLitre,
        maxFractionDigits: 3,
      );
    } else if (result.calculatedField == FuelEntryField.unitPrice) {
      _formatUnitPriceController();
    }
    _syncingFuelFields = false;
    setState(() {});
  }

  void _formatUnitPriceController() {
    final micros = _fuelValues.unitPriceMicrosPerLitre;
    if (micros == null) {
      return;
    }
    _unitPriceController.text = ScaledDecimal.format(
      micros,
      scale: _unitPriceMode == _UnitPriceMode.pencePerLitre
          ? FuelNumbers.microsPerPence
          : FuelNumbers.microsPerMajorUnit,
      minFractionDigits: _unitPriceMode == _UnitPriceMode.pencePerLitre ? 0 : 3,
      maxFractionDigits: 3,
    );
  }

  int? _parseUnitPrice(String value) {
    return _unitPriceMode == _UnitPriceMode.pencePerLitre
        ? FuelNumbers.parsePencePerLitreToMicros(value)
        : FuelNumbers.parsePoundsPerLitreToMicros(value);
  }

  String? _validateRequiredOdometer(String? value) {
    final parsed = _parseInt(value ?? '');
    if (parsed == null) {
      return 'Odometer is required.';
    }
    if (parsed < 0) {
      return 'Odometer readings cannot be negative.';
    }
    return null;
  }

  String? _validatePositive(int? value, String label) {
    if (value == null) {
      return '$label is required.';
    }
    if (value <= 0) {
      return '$label must be greater than zero.';
    }
    return null;
  }

  int? _parseInt(String value) {
    final normalized = value.replaceAll(',', '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return int.tryParse(normalized);
  }

  String _labelForFuelField(FuelEntryField field) {
    return switch (field) {
      FuelEntryField.totalCost => 'Total cost',
      FuelEntryField.volume => 'Fuel volume',
      FuelEntryField.unitPrice => 'Unit price',
    };
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
