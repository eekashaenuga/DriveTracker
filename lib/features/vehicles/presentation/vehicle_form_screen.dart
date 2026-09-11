import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_odometer_input.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../vehicles/domain/distance_unit_conversion.dart';
import '../../vehicles/domain/vehicle.dart';
import '../../vehicles/domain/vehicle_draft.dart';

class VehicleFormScreen extends StatefulWidget {
  const VehicleFormScreen({this.vehicle, this.firstVehicle = false, super.key});

  final Vehicle? vehicle;
  final bool firstVehicle;

  @override
  State<VehicleFormScreen> createState() => _VehicleFormScreenState();
}

class _VehicleFormScreenState extends State<VehicleFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _makeController;
  late final TextEditingController _modelController;
  late final TextEditingController _odometerController;
  late final TextEditingController _yearController;
  late final TextEditingController _registrationController;
  late final TextEditingController _trimController;
  late final TextEditingController _engineController;
  late final TextEditingController _transmissionController;
  late final TextEditingController _vinController;
  late final TextEditingController _colourController;
  late final TextEditingController _purchaseMileageController;
  late final TextEditingController _purchasePriceController;
  late final TextEditingController _sellerController;
  late final TextEditingController _notesController;

  late FuelType _fuelType;
  late DistanceUnit _distanceUnit;
  DateTime? _purchaseDate;
  String? _formError;

  bool get _isEditing => widget.vehicle != null;

  @override
  void initState() {
    super.initState();
    final vehicle = widget.vehicle;
    final purchaseMileage = vehicle?.purchaseMileage;
    _nameController = TextEditingController(text: vehicle?.name ?? '');
    _makeController = TextEditingController(text: vehicle?.make ?? '');
    _modelController = TextEditingController(text: vehicle?.model ?? '');
    _odometerController = TextEditingController();
    _yearController = TextEditingController(
      text: vehicle?.year?.toString() ?? '',
    );
    _registrationController = TextEditingController(
      text: vehicle?.registration ?? '',
    );
    _trimController = TextEditingController(text: vehicle?.trim ?? '');
    _engineController = TextEditingController(text: vehicle?.engine ?? '');
    _transmissionController = TextEditingController(
      text: vehicle?.transmission ?? '',
    );
    _vinController = TextEditingController(text: vehicle?.vin ?? '');
    _colourController = TextEditingController(text: vehicle?.colour ?? '');
    _purchaseMileageController = TextEditingController(
      text: purchaseMileage == null
          ? ''
          : DTFormatters.wholeNumber(purchaseMileage),
    );
    _purchasePriceController = TextEditingController(
      text: vehicle?.purchasePrice?.toStringAsFixed(2) ?? '',
    );
    _sellerController = TextEditingController(text: vehicle?.seller ?? '');
    _notesController = TextEditingController(text: vehicle?.notes ?? '');
    _fuelType = vehicle?.fuelType ?? FuelType.petrol;
    _distanceUnit = vehicle?.distanceUnit ?? DistanceUnit.miles;
    _purchaseDate = vehicle?.purchaseDate;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _makeController.dispose();
    _modelController.dispose();
    _odometerController.dispose();
    _yearController.dispose();
    _registrationController.dispose();
    _trimController.dispose();
    _engineController.dispose();
    _transmissionController.dispose();
    _vinController.dispose();
    _colourController.dispose();
    _purchaseMileageController.dispose();
    _purchasePriceController.dispose();
    _sellerController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final theme = Theme.of(context);
    final currencySymbol = MoneyAmount.defaultCurrency.symbol;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit vehicle' : 'Add vehicle')),
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
            key: const Key('saveVehicleButton'),
            label: _isEditing ? 'Save vehicle' : 'Add vehicle',
            icon: _isEditing ? Icons.check_rounded : Icons.add_rounded,
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
              Text(
                _isEditing
                    ? 'Keep the profile accurate without changing mileage history.'
                    : widget.firstVehicle
                    ? 'Start with the basics. You can add more details later.'
                    : 'Add another vehicle to your local garage.',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DTSpacing.xl),
              TextFormField(
                key: const Key('vehicleNameField'),
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Vehicle name'),
                validator: (value) => _required(value, 'Vehicle name'),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('vehicleMakeField'),
                controller: _makeController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Make'),
                validator: (value) => _required(value, 'Make'),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('vehicleModelField'),
                controller: _modelController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Model'),
                validator: (value) => _required(value, 'Model'),
              ),
              if (!_isEditing) ...[
                const SizedBox(height: DTSpacing.md),
                DTOdometerInput(
                  fieldKey: const Key('vehicleOdometerField'),
                  controller: _odometerController,
                  label: 'Current odometer',
                  unitLabel: _distanceUnit.shortLabel,
                  textInputAction: TextInputAction.next,
                  validator: _validateRequiredOdometer,
                ),
              ],
              const SizedBox(height: DTSpacing.md),
              DropdownButtonFormField<FuelType>(
                key: const Key('vehicleFuelTypeField'),
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
              const SizedBox(height: DTSpacing.lg),
              Text('Distance unit', style: theme.textTheme.labelLarge),
              const SizedBox(height: DTSpacing.sm),
              SegmentedButton<DistanceUnit>(
                key: const Key('vehicleDistanceUnitField'),
                selected: {_distanceUnit},
                segments: [
                  for (final unit in DistanceUnit.values)
                    ButtonSegment(
                      value: unit,
                      label: Text(unit.label),
                      icon: const Icon(Icons.straighten_rounded),
                    ),
                ],
                onSelectionChanged: (selection) {
                  _setDistanceUnit(selection.first);
                },
              ),
              const SizedBox(height: DTSpacing.xl),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: DTSpacing.md),
                title: Text(
                  'Optional details',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                subtitle: const Text('Registration, year and profile notes'),
                children: [
                  TextFormField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Year'),
                    validator: _validateYear,
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _registrationController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Registration',
                    ),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _purchaseDate == null
                              ? 'Purchase date not set'
                              : 'Purchase date: ${DTFormatters.date(_purchaseDate!)}',
                        ),
                      ),
                      TextButton(
                        onPressed: _pickPurchaseDate,
                        child: const Text('Choose'),
                      ),
                      if (_purchaseDate != null)
                        IconButton(
                          tooltip: 'Clear purchase date',
                          onPressed: () => setState(() => _purchaseDate = null),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _trimController,
                    decoration: const InputDecoration(labelText: 'Trim'),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _engineController,
                    decoration: const InputDecoration(labelText: 'Engine'),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _transmissionController,
                    decoration: const InputDecoration(
                      labelText: 'Transmission',
                    ),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _vinController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'VIN'),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _colourController,
                    decoration: const InputDecoration(labelText: 'Colour'),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _purchaseMileageController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Purchase mileage',
                      suffixText: _distanceUnit.shortLabel,
                    ),
                    validator: _validateOptionalNonNegativeInt,
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _purchasePriceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Purchase price',
                      prefixText: currencySymbol,
                    ),
                    validator: _validateOptionalNonNegativeDouble,
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _sellerController,
                    decoration: const InputDecoration(labelText: 'Seller'),
                  ),
                  const SizedBox(height: DTSpacing.md),
                  TextFormField(
                    controller: _notesController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                ],
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

  Future<void> _pickPurchaseDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate ?? now,
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) {
      setState(() => _purchaseDate = picked);
    }
  }

  void _setDistanceUnit(DistanceUnit unit) {
    if (unit == _distanceUnit) {
      return;
    }

    _convertWholeDistanceText(
      _odometerController,
      from: _distanceUnit,
      to: unit,
    );
    _convertWholeDistanceText(
      _purchaseMileageController,
      from: _distanceUnit,
      to: unit,
    );
    setState(() => _distanceUnit = unit);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final draft = VehicleDraft(
      name: _nameController.text,
      make: _makeController.text,
      model: _modelController.text,
      currentOdometer: _parseInt(_odometerController.text),
      fuelType: _fuelType,
      distanceUnit: _distanceUnit,
      year: _parseInt(_yearController.text),
      registration: _registrationController.text,
      trim: _trimController.text,
      engine: _engineController.text,
      transmission: _transmissionController.text,
      vin: _vinController.text,
      colour: _colourController.text,
      purchaseDate: _purchaseDate,
      purchaseMileage: _parseInt(_purchaseMileageController.text),
      purchasePrice: _parseDouble(_purchasePriceController.text),
      seller: _sellerController.text,
      notes: _notesController.text,
    );

    try {
      final controller = context.read<DriveTrackerController>();
      if (_isEditing) {
        final confirmed = await _confirmDistanceUnitChangeIfNeeded();
        if (!confirmed) {
          return;
        }
        await controller.updateVehicle(widget.vehicle!.id, draft);
      } else {
        await controller.addVehicle(draft);
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isEditing ? 'Vehicle updated.' : 'Vehicle added.'),
        ),
      );
    } on ValidationException catch (error) {
      setState(() => _formError = error.message);
    } catch (_) {
      setState(() => _formError = 'Could not save vehicle. Please try again.');
    }
  }

  Future<bool> _confirmDistanceUnitChangeIfNeeded() async {
    final vehicle = widget.vehicle;
    if (vehicle == null || vehicle.distanceUnit == _distanceUnit) {
      return true;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change distance unit?'),
        content: Text(
          'Existing mileage records for ${vehicle.name} will be converted from '
          '${_unitLabel(vehicle.distanceUnit)} to ${_unitLabel(_distanceUnit)}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change unit'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  String? _required(String? value, String label) {
    if ((value ?? '').trim().isEmpty) {
      return '$label is required.';
    }
    return null;
  }

  String? _validateRequiredOdometer(String? value) {
    final parsed = _parseInt(value ?? '');
    if (parsed == null) {
      return 'Current odometer is required.';
    }
    if (parsed < 0) {
      return 'Current odometer cannot be negative.';
    }
    return null;
  }

  String? _validateYear(String? value) {
    final parsed = _parseInt(value ?? '');
    if (parsed == null) {
      return null;
    }
    final maxYear = DateTime.now().year + 1;
    if (parsed < 1886 || parsed > maxYear) {
      return 'Use a year from 1886 to $maxYear.';
    }
    return null;
  }

  String? _validateOptionalNonNegativeInt(String? value) {
    final parsed = _parseInt(value ?? '');
    if (parsed == null) {
      return null;
    }
    if (parsed < 0) {
      return 'Value cannot be negative.';
    }
    return null;
  }

  String? _validateOptionalNonNegativeDouble(String? value) {
    final parsed = _parseDouble(value ?? '');
    if (parsed == null) {
      return null;
    }
    if (parsed < 0) {
      return 'Value cannot be negative.';
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

  void _convertWholeDistanceText(
    TextEditingController controller, {
    required DistanceUnit from,
    required DistanceUnit to,
  }) {
    final value = _parseInt(controller.text);
    if (value == null) {
      return;
    }
    controller.text = DTFormatters.wholeNumber(
      DistanceUnitConversion.convertWholeDistance(value, from: from, to: to),
    );
  }

  String _unitLabel(DistanceUnit unit) {
    return switch (unit) {
      DistanceUnit.miles => 'Miles (mi)',
      DistanceUnit.kilometers => 'Kilometres (km)',
    };
  }

  double? _parseDouble(String value) {
    final normalized = value
        .replaceAll(',', '')
        .replaceAll(MoneyAmount.defaultCurrency.symbol, '')
        .trim();
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }
}
