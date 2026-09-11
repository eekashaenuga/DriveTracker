import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/money.dart';
import '../../../core/utilities/scaled_decimal.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/fuel_calculator.dart';

enum _CalculatorMode {
  tripCost('Trip Cost', Icons.route_rounded),
  costSharing('Cost Sharing', Icons.groups_rounded),
  fuelRequired('Fuel Required', Icons.local_gas_station_rounded),
  priceComparison('Price Comparison', Icons.compare_arrows_rounded);

  const _CalculatorMode(this.label, this.icon);

  final String label;
  final IconData icon;
}

enum _CalculatorValueSource { vehicle, manual }

enum _CostSharingMode { estimateTrip, knownCost }

class FuelCalculatorScreen extends StatefulWidget {
  const FuelCalculatorScreen({super.key});

  @override
  State<FuelCalculatorScreen> createState() => _FuelCalculatorScreenState();
}

class _FuelCalculatorScreenState extends State<FuelCalculatorScreen> {
  final _distanceController = TextEditingController();
  final _economyController = TextEditingController();
  final _priceController = TextEditingController();
  final _peopleController = TextEditingController(text: '2');
  final _knownCostController = TextEditingController();
  final _fuelAmountController = TextEditingController();
  final _stationAPriceController = TextEditingController();
  final _stationBPriceController = TextEditingController();
  final _extraDistanceController = TextEditingController();
  final _comparisonEconomyController = TextEditingController();

  var _mode = _CalculatorMode.tripCost;
  var _source = _CalculatorValueSource.manual;
  var _distanceUnit = DistanceUnit.miles;
  var _economyUnit = FuelEconomyUnit.ukMpg;
  var _fuelRequiredOutputUnit = FuelVolumeUnit.litres;
  var _costSharingMode = _CostSharingMode.estimateTrip;
  var _applyingVehicleDefaults = false;
  var _didInitializeUnits = false;

  @override
  void initState() {
    super.initState();
    for (final controller in _textControllers) {
      controller.addListener(_handleInputChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitializeUnits) {
      return;
    }
    _didInitializeUnits = true;
    final defaults = context.read<DriveTrackerController>().vehicleFuelDefaults;
    _distanceUnit = defaults.distanceUnit ?? DistanceUnit.miles;
  }

  @override
  void dispose() {
    for (final controller in _textControllers) {
      controller
        ..removeListener(_handleInputChanged)
        ..dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _textControllers => [
    _distanceController,
    _economyController,
    _priceController,
    _peopleController,
    _knownCostController,
    _fuelAmountController,
    _stationAPriceController,
    _stationBPriceController,
    _extraDistanceController,
    _comparisonEconomyController,
  ];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final defaults = controller.vehicleFuelDefaults;

    return Scaffold(
      appBar: AppBar(title: const Text('Fuel Calculator')),
      body: SafeArea(
        child: ListView(
          key: const Key('fuelCalculatorScreen'),
          padding: const EdgeInsets.fromLTRB(
            DTSpacing.lg,
            DTSpacing.md,
            DTSpacing.lg,
            DTSpacing.xxxl,
          ),
          children: [
            _HeaderCard(
              defaults: defaults,
              vehicles: controller.activeVehicles,
              selectedSource: _source,
              onVehicleChanged: (vehicleId) =>
                  _selectVehicle(controller, vehicleId),
              onSourceChanged: (source) {
                if (source == _CalculatorValueSource.vehicle) {
                  _applyVehicleDefaults(defaults);
                } else {
                  setState(() => _source = source);
                }
              },
              onApplyDefaults: defaults.hasAnyVehicleDefault
                  ? () => _applyVehicleDefaults(defaults)
                  : null,
            ),
            const SizedBox(height: DTSpacing.lg),
            _ModeSelector(
              selected: _mode,
              onChanged: (mode) => setState(() => _mode = mode),
            ),
            const SizedBox(height: DTSpacing.lg),
            _toolContent(defaults),
          ],
        ),
      ),
    );
  }

  Widget _toolContent(VehicleFuelDefaults defaults) {
    return switch (_mode) {
      _CalculatorMode.tripCost => _TripCostTool(
        distanceController: _distanceController,
        economyController: _economyController,
        priceController: _priceController,
        distanceUnit: _distanceUnit,
        economyUnit: _economyUnit,
        source: _source,
        result: _tripCostResult(),
        onDistanceUnitChanged: (value) => setState(() => _distanceUnit = value),
        onEconomyUnitChanged: (value) => setState(() => _economyUnit = value),
      ),
      _CalculatorMode.costSharing => _CostSharingTool(
        mode: _costSharingMode,
        distanceController: _distanceController,
        economyController: _economyController,
        priceController: _priceController,
        peopleController: _peopleController,
        knownCostController: _knownCostController,
        distanceUnit: _distanceUnit,
        economyUnit: _economyUnit,
        source: _source,
        result: _costSharingResult(),
        onModeChanged: (mode) => setState(() => _costSharingMode = mode),
        onDistanceUnitChanged: (value) => setState(() => _distanceUnit = value),
        onEconomyUnitChanged: (value) => setState(() => _economyUnit = value),
      ),
      _CalculatorMode.fuelRequired => _FuelRequiredTool(
        distanceController: _distanceController,
        economyController: _economyController,
        distanceUnit: _distanceUnit,
        economyUnit: _economyUnit,
        outputUnit: _fuelRequiredOutputUnit,
        source: _source,
        result: _fuelRequiredResult(),
        onDistanceUnitChanged: (value) => setState(() => _distanceUnit = value),
        onEconomyUnitChanged: (value) => setState(() => _economyUnit = value),
        onOutputUnitChanged: (value) =>
            setState(() => _fuelRequiredOutputUnit = value),
      ),
      _CalculatorMode.priceComparison => _PriceComparisonTool(
        fuelAmountController: _fuelAmountController,
        stationAPriceController: _stationAPriceController,
        stationBPriceController: _stationBPriceController,
        extraDistanceController: _extraDistanceController,
        economyController: _comparisonEconomyController,
        distanceUnit: _distanceUnit,
        economyUnit: _economyUnit,
        source: _source,
        result: _priceComparisonResult(),
        onDistanceUnitChanged: (value) => setState(() => _distanceUnit = value),
        onEconomyUnitChanged: (value) => setState(() => _economyUnit = value),
      ),
    };
  }

  Future<void> _selectVehicle(
    DriveTrackerController controller,
    String vehicleId,
  ) async {
    await controller.selectVehicle(vehicleId);
    if (!mounted) {
      return;
    }
    if (_source == _CalculatorValueSource.vehicle) {
      _applyVehicleDefaults(
        context.read<DriveTrackerController>().vehicleFuelDefaults,
      );
    } else {
      setState(() {});
    }
  }

  void _applyVehicleDefaults(VehicleFuelDefaults defaults) {
    setState(() {
      _applyingVehicleDefaults = true;
      _source = _CalculatorValueSource.vehicle;
      _distanceUnit = defaults.distanceUnit ?? _distanceUnit;

      final trustedEconomy = defaults.trustedUkMpg;
      if (trustedEconomy == null) {
        _economyController.clear();
        _comparisonEconomyController.clear();
      } else {
        _economyUnit = FuelEconomyUnit.ukMpg;
        final value = _formatNumber(trustedEconomy, maxFractionDigits: 2);
        _economyController.text = value;
        _comparisonEconomyController.text = value;
      }

      final latestPrice = defaults.latestFuelPriceMicrosPerLitre;
      if (latestPrice == null) {
        _priceController.clear();
        _stationAPriceController.clear();
      } else {
        final value = _formatMicrosPerLitreInput(latestPrice);
        _priceController.text = value;
        _stationAPriceController.text = value;
      }
      _applyingVehicleDefaults = false;
    });
  }

  void _handleInputChanged() {
    if (_applyingVehicleDefaults || !mounted) {
      return;
    }
    setState(() {
      if (_source == _CalculatorValueSource.vehicle) {
        _source = _CalculatorValueSource.manual;
      }
    });
  }

  TripCostInput? _tripCostInput() {
    final distance = _parsePositiveDouble(_distanceController.text);
    final economy = _parsePositiveDouble(_economyController.text);
    final price = _parsePriceMicros(_priceController.text);
    if (distance == null || economy == null || price == null) {
      return null;
    }
    return TripCostInput(
      distance: distance,
      distanceUnit: _distanceUnit,
      fuelEconomy: economy,
      fuelEconomyUnit: _economyUnit,
      fuelPriceMicrosPerLitre: price,
    );
  }

  TripCostResult? _tripCostResult() {
    final input = _tripCostInput();
    return input == null ? null : FuelCalculator.tripCost(input);
  }

  FuelRequiredResult? _fuelRequiredResult() {
    final distance = _parsePositiveDouble(_distanceController.text);
    final economy = _parsePositiveDouble(_economyController.text);
    if (distance == null || economy == null) {
      return null;
    }
    return FuelCalculator.fuelRequired(
      FuelRequiredInput(
        distance: distance,
        distanceUnit: _distanceUnit,
        fuelEconomy: economy,
        fuelEconomyUnit: _economyUnit,
      ),
    );
  }

  CostSharingResult? _costSharingResult() {
    final people = _parsePositiveInt(_peopleController.text);
    if (people == null) {
      return null;
    }
    if (_costSharingMode == _CostSharingMode.knownCost) {
      final cost = MoneyAmount.parseMinor(_knownCostController.text);
      if (cost == null || cost <= 0) {
        return null;
      }
      return FuelCalculator.costSharing(
        CostSharingInput.knownCost(totalCostMinor: cost, people: people),
      );
    }

    final input = _tripCostInput();
    if (input == null) {
      return null;
    }
    return FuelCalculator.costSharing(
      CostSharingInput.estimatedTrip(trip: input, people: people),
    );
  }

  FuelPriceComparisonResult? _priceComparisonResult() {
    final fuelLitres = _parsePositiveDouble(_fuelAmountController.text);
    final stationA = _parsePriceMicros(_stationAPriceController.text);
    final stationB = _parsePriceMicros(_stationBPriceController.text);
    if (fuelLitres == null || stationA == null || stationB == null) {
      return null;
    }

    final extraDistance = _parseOptionalPositiveDouble(
      _extraDistanceController.text,
    );
    final economy = _parseOptionalPositiveDouble(
      _comparisonEconomyController.text,
    );
    return FuelCalculator.priceComparison(
      FuelPriceComparisonInput(
        fuelLitres: fuelLitres,
        stationAPriceMicrosPerLitre: stationA,
        stationBPriceMicrosPerLitre: stationB,
        additionalRoundTripDistance: extraDistance,
        additionalDistanceUnit: extraDistance == null ? null : _distanceUnit,
        fuelEconomy: economy,
        fuelEconomyUnit: economy == null ? null : _economyUnit,
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.defaults,
    required this.vehicles,
    required this.selectedSource,
    required this.onVehicleChanged,
    required this.onSourceChanged,
    required this.onApplyDefaults,
  });

  final VehicleFuelDefaults defaults;
  final List<Vehicle> vehicles;
  final _CalculatorValueSource selectedSource;
  final ValueChanged<String> onVehicleChanged;
  final ValueChanged<_CalculatorValueSource> onSourceChanged;
  final VoidCallback? onApplyDefaults;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final vehicle = defaults.vehicle;

    return Container(
      padding: const EdgeInsets.all(DTSpacing.lg),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.48),
        borderRadius: DTRadii.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(DTRadii.card),
                ),
                child: Icon(
                  Icons.calculate_rounded,
                  color: colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: DTSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tools',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Fuel estimates without creating records',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: DTSpacing.lg),
          if (vehicles.length > 1)
            DropdownButtonFormField<String>(
              key: const Key('fuelCalculatorVehicleField'),
              initialValue: vehicle?.id,
              decoration: const InputDecoration(labelText: 'Vehicle'),
              items: [
                for (final vehicle in vehicles)
                  DropdownMenuItem(
                    value: vehicle.id,
                    child: Text(vehicle.name),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onVehicleChanged(value);
                }
              },
            )
          else
            _InfoLine(
              icon: Icons.directions_car_filled_rounded,
              label: vehicle?.name ?? 'Manual calculation',
              value: vehicle?.description ?? 'No vehicle selected',
            ),
          const SizedBox(height: DTSpacing.md),
          _InfoLine(
            icon: Icons.speed_rounded,
            label: defaults.hasTrustedEconomy
                ? 'Recorded average'
                : 'Fuel economy',
            value: defaults.hasTrustedEconomy
                ? '${_formatNumber(defaults.trustedUkMpg!, maxFractionDigits: 1)} UK MPG'
                : 'No reliable fuel economy is available for this vehicle yet.',
          ),
          const SizedBox(height: DTSpacing.sm),
          _InfoLine(
            icon: Icons.local_gas_station_rounded,
            label: defaults.hasLatestFuelPrice
                ? 'Latest fuel price'
                : 'Fuel price',
            value: defaults.hasLatestFuelPrice
                ? FuelNumbers.formatPoundsPerLitre(
                    defaults.latestFuelPriceMicrosPerLitre,
                  )
                : 'Enter a manual price per litre.',
          ),
          const SizedBox(height: DTSpacing.md),
          _SourceSelector(selected: selectedSource, onChanged: onSourceChanged),
          const SizedBox(height: DTSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              key: const Key('fuelCalculatorApplyVehicleDefaultsButton'),
              onPressed: onApplyDefaults,
              icon: const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Use vehicle values'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: DTIconSizes.sm, color: colors.onSurfaceVariant),
        const SizedBox(width: DTSpacing.sm),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                TextSpan(text: value),
              ],
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SourceSelector extends StatelessWidget {
  const _SourceSelector({required this.selected, required this.onChanged});

  final _CalculatorValueSource selected;
  final ValueChanged<_CalculatorValueSource> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<_CalculatorValueSource>(
        key: const Key('fuelCalculatorSourceSelector'),
        selected: {selected},
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(
            value: _CalculatorValueSource.vehicle,
            icon: Icon(Icons.directions_car_filled_rounded),
            label: Text('From vehicle'),
          ),
          ButtonSegment(
            value: _CalculatorValueSource.manual,
            icon: Icon(Icons.edit_rounded),
            label: Text('Manual'),
          ),
        ],
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.selected, required this.onChanged});

  final _CalculatorMode selected;
  final ValueChanged<_CalculatorMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560
            ? _CalculatorMode.values.length
            : constraints.maxWidth >= 300
            ? 2
            : 1;
        final gaps = DTSpacing.sm * (columns - 1);
        final width = (constraints.maxWidth - gaps) / columns;

        return Wrap(
          key: const Key('fuelCalculatorModeSelector'),
          spacing: DTSpacing.sm,
          runSpacing: DTSpacing.sm,
          children: [
            for (final mode in _CalculatorMode.values)
              SizedBox(
                width: width,
                child: _ModeOption(
                  mode: mode,
                  selected: mode == selected,
                  onSelected: () => onChanged(mode),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.mode,
    required this.selected,
    required this.onSelected,
  });

  final _CalculatorMode mode;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final foreground = selected ? colors.onSecondaryContainer : colors.primary;
    final background = selected
        ? colors.secondaryContainer
        : colors.surfaceContainerHighest.withValues(alpha: 0.52);

    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: Material(
        color: background,
        borderRadius: DTRadii.controlRadius,
        child: InkWell(
          onTap: onSelected,
          borderRadius: DTRadii.controlRadius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DTSpacing.sm,
                vertical: DTSpacing.sm,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(mode.icon, size: DTIconSizes.sm, color: foreground),
                  const SizedBox(height: DTSpacing.xs),
                  Text(
                    mode.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TripCostTool extends StatelessWidget {
  const _TripCostTool({
    required this.distanceController,
    required this.economyController,
    required this.priceController,
    required this.distanceUnit,
    required this.economyUnit,
    required this.source,
    required this.result,
    required this.onDistanceUnitChanged,
    required this.onEconomyUnitChanged,
  });

  final TextEditingController distanceController;
  final TextEditingController economyController;
  final TextEditingController priceController;
  final DistanceUnit distanceUnit;
  final FuelEconomyUnit economyUnit;
  final _CalculatorValueSource source;
  final TripCostResult? result;
  final ValueChanged<DistanceUnit> onDistanceUnitChanged;
  final ValueChanged<FuelEconomyUnit> onEconomyUnitChanged;

  @override
  Widget build(BuildContext context) {
    return _ToolSection(
      title: 'Trip Cost',
      subtitle: 'Estimate fuel and spend for a planned journey.',
      children: [
        _ResponsiveFields(
          children: [
            _NumberField(
              fieldKey: const Key('tripDistanceField'),
              controller: distanceController,
              label: 'Distance',
              suffix: distanceUnit.shortLabel,
            ),
            _DistanceUnitField(
              value: distanceUnit,
              onChanged: onDistanceUnitChanged,
            ),
            _NumberField(
              fieldKey: const Key('tripEconomyField'),
              controller: economyController,
              label: 'Fuel economy',
              suffix: economyUnit.label,
            ),
            _EconomyUnitField(
              value: economyUnit,
              onChanged: onEconomyUnitChanged,
            ),
            _NumberField(
              fieldKey: const Key('tripFuelPriceField'),
              controller: priceController,
              label: 'Fuel price',
              prefix: MoneyAmount.defaultCurrency.symbol,
              suffix: '/L',
            ),
          ],
        ),
        const SizedBox(height: DTSpacing.lg),
        if (result == null)
          const _ResultEmptyState(
            text:
                'Complete distance, economy and fuel price to estimate a trip.',
          )
        else
          _ResultGrid(
            children: [
              _ResultCard(
                key: const Key('tripEstimatedCostValue'),
                icon: Icons.payments_rounded,
                label: 'Estimated trip cost',
                value: _formatCurrency(result!.estimatedCostMinor),
                supportingText: _sourceLabel(source),
              ),
              _ResultCard(
                key: const Key('tripFuelRequiredValue'),
                icon: Icons.local_gas_station_rounded,
                label: 'Fuel required',
                value: _formatVolume(result!.fuelLitres, FuelVolumeUnit.litres),
                supportingText:
                    'Approx. ${_formatCostPerDistance(result!.costMinorPerDistance, distanceUnit)}',
              ),
            ],
          ),
      ],
    );
  }
}

class _CostSharingTool extends StatelessWidget {
  const _CostSharingTool({
    required this.mode,
    required this.distanceController,
    required this.economyController,
    required this.priceController,
    required this.peopleController,
    required this.knownCostController,
    required this.distanceUnit,
    required this.economyUnit,
    required this.source,
    required this.result,
    required this.onModeChanged,
    required this.onDistanceUnitChanged,
    required this.onEconomyUnitChanged,
  });

  final _CostSharingMode mode;
  final TextEditingController distanceController;
  final TextEditingController economyController;
  final TextEditingController priceController;
  final TextEditingController peopleController;
  final TextEditingController knownCostController;
  final DistanceUnit distanceUnit;
  final FuelEconomyUnit economyUnit;
  final _CalculatorValueSource source;
  final CostSharingResult? result;
  final ValueChanged<_CostSharingMode> onModeChanged;
  final ValueChanged<DistanceUnit> onDistanceUnitChanged;
  final ValueChanged<FuelEconomyUnit> onEconomyUnitChanged;

  @override
  Widget build(BuildContext context) {
    return _ToolSection(
      title: 'Cost Sharing',
      subtitle: 'Split a known or estimated fuel cost between people.',
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<_CostSharingMode>(
            key: const Key('costSharingModeSelector'),
            selected: {mode},
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: _CostSharingMode.estimateTrip,
                icon: Icon(Icons.route_rounded),
                label: Text('Estimate trip'),
              ),
              ButtonSegment(
                value: _CostSharingMode.knownCost,
                icon: Icon(Icons.receipt_long_rounded),
                label: Text('Known cost'),
              ),
            ],
            onSelectionChanged: (selection) => onModeChanged(selection.first),
          ),
        ),
        const SizedBox(height: DTSpacing.md),
        if (mode == _CostSharingMode.estimateTrip)
          _ResponsiveFields(
            children: [
              _NumberField(
                fieldKey: const Key('shareDistanceField'),
                controller: distanceController,
                label: 'Distance',
                suffix: distanceUnit.shortLabel,
              ),
              _DistanceUnitField(
                value: distanceUnit,
                onChanged: onDistanceUnitChanged,
              ),
              _NumberField(
                fieldKey: const Key('shareEconomyField'),
                controller: economyController,
                label: 'Fuel economy',
                suffix: economyUnit.label,
              ),
              _EconomyUnitField(
                value: economyUnit,
                onChanged: onEconomyUnitChanged,
              ),
              _NumberField(
                fieldKey: const Key('shareFuelPriceField'),
                controller: priceController,
                label: 'Fuel price',
                prefix: MoneyAmount.defaultCurrency.symbol,
                suffix: '/L',
              ),
              _NumberField(
                fieldKey: const Key('sharePeopleField'),
                controller: peopleController,
                label: 'People',
              ),
            ],
          )
        else
          _ResponsiveFields(
            children: [
              _NumberField(
                fieldKey: const Key('shareKnownCostField'),
                controller: knownCostController,
                label: 'Total fuel cost',
                prefix: MoneyAmount.defaultCurrency.symbol,
              ),
              _NumberField(
                fieldKey: const Key('sharePeopleField'),
                controller: peopleController,
                label: 'People',
              ),
            ],
          ),
        const SizedBox(height: DTSpacing.lg),
        if (result == null)
          const _ResultEmptyState(
            text: 'Enter a positive cost and at least one person.',
          )
        else
          _ResultGrid(
            children: [
              _ResultCard(
                key: const Key('costSharingTotalValue'),
                icon: Icons.receipt_long_rounded,
                label: 'Total estimated fuel cost',
                value: _formatCurrency(result!.totalCostMinor),
                supportingText: mode == _CostSharingMode.estimateTrip
                    ? _sourceLabel(source)
                    : 'Based on known trip fuel cost',
              ),
              _ResultCard(
                key: const Key('costSharingPerPersonValue'),
                icon: Icons.person_rounded,
                label: 'Cost per person',
                value: _formatCurrency(result!.costPerPersonMinor),
                supportingText: '${peopleController.text.trim()} people',
              ),
            ],
          ),
      ],
    );
  }
}

class _FuelRequiredTool extends StatelessWidget {
  const _FuelRequiredTool({
    required this.distanceController,
    required this.economyController,
    required this.distanceUnit,
    required this.economyUnit,
    required this.outputUnit,
    required this.source,
    required this.result,
    required this.onDistanceUnitChanged,
    required this.onEconomyUnitChanged,
    required this.onOutputUnitChanged,
  });

  final TextEditingController distanceController;
  final TextEditingController economyController;
  final DistanceUnit distanceUnit;
  final FuelEconomyUnit economyUnit;
  final FuelVolumeUnit outputUnit;
  final _CalculatorValueSource source;
  final FuelRequiredResult? result;
  final ValueChanged<DistanceUnit> onDistanceUnitChanged;
  final ValueChanged<FuelEconomyUnit> onEconomyUnitChanged;
  final ValueChanged<FuelVolumeUnit> onOutputUnitChanged;

  @override
  Widget build(BuildContext context) {
    final primaryVolume = result == null
        ? null
        : FuelUnitConversions.litresToVolume(result!.litres, outputUnit);

    return _ToolSection(
      title: 'Fuel Required',
      subtitle: 'Work out the approximate fuel needed for a distance.',
      children: [
        _ResponsiveFields(
          children: [
            _NumberField(
              fieldKey: const Key('fuelRequiredDistanceField'),
              controller: distanceController,
              label: 'Distance',
              suffix: distanceUnit.shortLabel,
            ),
            _DistanceUnitField(
              value: distanceUnit,
              onChanged: onDistanceUnitChanged,
            ),
            _NumberField(
              fieldKey: const Key('fuelRequiredEconomyField'),
              controller: economyController,
              label: 'Fuel economy',
              suffix: economyUnit.label,
            ),
            _EconomyUnitField(
              value: economyUnit,
              onChanged: onEconomyUnitChanged,
            ),
            _VolumeUnitField(
              fieldKey: const Key('fuelRequiredVolumeUnitField'),
              value: outputUnit,
              onChanged: onOutputUnitChanged,
            ),
          ],
        ),
        const SizedBox(height: DTSpacing.lg),
        if (result == null || primaryVolume == null)
          const _ResultEmptyState(
            text: 'Complete distance and economy to estimate fuel required.',
          )
        else
          _ResultGrid(
            children: [
              _ResultCard(
                key: const Key('fuelRequiredValue'),
                icon: Icons.local_gas_station_rounded,
                label: 'Approx. fuel required',
                value:
                    '${_formatNumber(primaryVolume, maxFractionDigits: 2)} ${outputUnit.shortLabel}',
                supportingText: _sourceLabel(source),
              ),
              _ResultCard(
                icon: Icons.swap_horiz_rounded,
                label: 'Equivalent',
                value: _formatVolume(result!.litres, FuelVolumeUnit.litres),
                supportingText:
                    '${_formatVolume(result!.imperialGallons, FuelVolumeUnit.imperialGallons)} · ${_formatVolume(result!.usGallons, FuelVolumeUnit.usGallons)}',
              ),
            ],
          ),
      ],
    );
  }
}

class _PriceComparisonTool extends StatelessWidget {
  const _PriceComparisonTool({
    required this.fuelAmountController,
    required this.stationAPriceController,
    required this.stationBPriceController,
    required this.extraDistanceController,
    required this.economyController,
    required this.distanceUnit,
    required this.economyUnit,
    required this.source,
    required this.result,
    required this.onDistanceUnitChanged,
    required this.onEconomyUnitChanged,
  });

  final TextEditingController fuelAmountController;
  final TextEditingController stationAPriceController;
  final TextEditingController stationBPriceController;
  final TextEditingController extraDistanceController;
  final TextEditingController economyController;
  final DistanceUnit distanceUnit;
  final FuelEconomyUnit economyUnit;
  final _CalculatorValueSource source;
  final FuelPriceComparisonResult? result;
  final ValueChanged<DistanceUnit> onDistanceUnitChanged;
  final ValueChanged<FuelEconomyUnit> onEconomyUnitChanged;

  @override
  Widget build(BuildContext context) {
    return _ToolSection(
      title: 'Price Comparison',
      subtitle:
          'Check whether a cheaper pump price still wins after extra travel.',
      children: [
        _ResponsiveFields(
          children: [
            _NumberField(
              fieldKey: const Key('comparisonFuelAmountField'),
              controller: fuelAmountController,
              label: 'Fuel to buy',
              suffix: 'L',
            ),
            _NumberField(
              fieldKey: const Key('comparisonStationAPriceField'),
              controller: stationAPriceController,
              label: 'Station A price',
              prefix: MoneyAmount.defaultCurrency.symbol,
              suffix: '/L',
            ),
            _NumberField(
              fieldKey: const Key('comparisonStationBPriceField'),
              controller: stationBPriceController,
              label: 'Station B price',
              prefix: MoneyAmount.defaultCurrency.symbol,
              suffix: '/L',
            ),
            _NumberField(
              fieldKey: const Key('comparisonExtraDistanceField'),
              controller: extraDistanceController,
              label: 'Extra round trip',
              suffix: distanceUnit.shortLabel,
            ),
            _DistanceUnitField(
              value: distanceUnit,
              onChanged: onDistanceUnitChanged,
            ),
            _NumberField(
              fieldKey: const Key('comparisonEconomyField'),
              controller: economyController,
              label: 'Economy for extra travel',
              suffix: economyUnit.label,
            ),
            _EconomyUnitField(
              value: economyUnit,
              onChanged: onEconomyUnitChanged,
            ),
          ],
        ),
        const SizedBox(height: DTSpacing.lg),
        if (result == null)
          const _ResultEmptyState(
            text: 'Enter litres and both station prices to compare.',
          )
        else
          _ResultGrid(
            children: [
              _ResultCard(
                key: const Key('priceComparisonBetterOptionValue'),
                icon: Icons.flag_rounded,
                label: 'Better option',
                value: _betterOptionLabel(result!.betterOption),
                supportingText: _sourceLabel(source),
              ),
              _ResultCard(
                key: const Key('priceComparisonGrossSavingValue'),
                icon: Icons.savings_rounded,
                label: 'Gross saving',
                value: _formatCurrency(result!.grossSavingMinor),
                supportingText:
                    'A: ${_formatCurrency(result!.stationACostMinor)} · B: ${_formatCurrency(result!.stationBCostMinor)}',
              ),
              if (result!.hasTravelAdjustment) ...[
                _ResultCard(
                  icon: Icons.route_rounded,
                  label: 'Extra travel cost',
                  value: _formatCurrency(result!.extraTravelCostMinor!),
                  supportingText:
                      '${_formatVolume(result!.extraTravelLitres!, FuelVolumeUnit.litres)} for the additional round trip',
                ),
                _ResultCard(
                  key: const Key('priceComparisonNetSavingValue'),
                  icon: Icons.account_balance_wallet_rounded,
                  label: 'Net saving',
                  value: _formatSignedCurrency(result!.netSavingMinor!),
                  supportingText: _netSavingText(result!),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _ToolSection extends StatelessWidget {
  const _ToolSection({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: DTSpacing.xs),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: DTSpacing.lg),
        ...children,
      ],
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 560;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - DTSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: DTSpacing.md,
          runSpacing: DTSpacing.md,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    this.prefix,
    this.suffix,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]'))],
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        suffixText: suffix,
      ),
    );
  }
}

class _DistanceUnitField extends StatelessWidget {
  const _DistanceUnitField({required this.value, required this.onChanged});

  final DistanceUnit value;
  final ValueChanged<DistanceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<DistanceUnit>(
      key: const Key('calculatorDistanceUnitField'),
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Distance unit'),
      items: [
        for (final unit in DistanceUnit.values)
          DropdownMenuItem(value: unit, child: Text(unit.label)),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _EconomyUnitField extends StatelessWidget {
  const _EconomyUnitField({required this.value, required this.onChanged});

  final FuelEconomyUnit value;
  final ValueChanged<FuelEconomyUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<FuelEconomyUnit>(
      key: const Key('calculatorEconomyUnitField'),
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Economy unit'),
      items: [
        for (final unit in FuelEconomyUnit.values)
          DropdownMenuItem(value: unit, child: Text(unit.label)),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _VolumeUnitField extends StatelessWidget {
  const _VolumeUnitField({
    required this.fieldKey,
    required this.value,
    required this.onChanged,
  });

  final Key fieldKey;
  final FuelVolumeUnit value;
  final ValueChanged<FuelVolumeUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<FuelVolumeUnit>(
      key: fieldKey,
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Result unit'),
      items: [
        for (final unit in FuelVolumeUnit.values)
          DropdownMenuItem(value: unit, child: Text(unit.label)),
      ],
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

class _ResultGrid extends StatelessWidget {
  const _ResultGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoColumns = constraints.maxWidth >= 560;
        final itemWidth = useTwoColumns
            ? (constraints.maxWidth - DTSpacing.md) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: DTSpacing.md,
          runSpacing: DTSpacing.md,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.icon,
    required this.label,
    required this.value,
    this.supportingText,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? supportingText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(DTSpacing.lg),
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.42),
        borderRadius: DTRadii.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: DTIconSizes.sm, color: colors.primary),
              const SizedBox(width: DTSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: DTSpacing.md),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          if (supportingText != null) ...[
            const SizedBox(height: DTSpacing.xs),
            Text(
              supportingText!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultEmptyState extends StatelessWidget {
  const _ResultEmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(DTSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.36,
        ),
        borderRadius: DTRadii.cardRadius,
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: DTSpacing.md),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

double? _parsePositiveDouble(String value) {
  final parsed = _parseOptionalPositiveDouble(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

double? _parseOptionalPositiveDouble(String value) {
  final normalized = value
      .trim()
      .replaceAll(',', '')
      .replaceAll('£', '')
      .trim();
  if (normalized.isEmpty) {
    return null;
  }
  final parsed = double.tryParse(normalized);
  if (parsed == null || parsed <= 0 || !parsed.isFinite) {
    return null;
  }
  return parsed;
}

int? _parsePositiveInt(String value) {
  final normalized = value.trim().replaceAll(',', '');
  final parsed = int.tryParse(normalized);
  if (parsed == null || parsed < 1) {
    return null;
  }
  return parsed;
}

int? _parsePriceMicros(String value) {
  final parsed = FuelNumbers.parsePoundsPerLitreToMicros(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

String _formatCurrency(int minor) {
  if (minor < 0) {
    return '-${MoneyAmount.formatMinor(-minor)}';
  }
  return MoneyAmount.formatMinor(minor);
}

String _formatSignedCurrency(int minor) {
  if (minor > 0) {
    return _formatCurrency(minor);
  }
  if (minor < 0) {
    return '-${_formatCurrency(-minor)}';
  }
  return _formatCurrency(0);
}

String _formatVolume(double value, FuelVolumeUnit unit) {
  return '${_formatNumber(value, maxFractionDigits: 2)} ${unit.shortLabel}';
}

String _formatCostPerDistance(double minorPerDistance, DistanceUnit unit) {
  final major = minorPerDistance / MoneyAmount.defaultCurrency.minorScale;
  return '${MoneyAmount.defaultCurrency.symbol}${major.toStringAsFixed(2)}/${unit.shortLabel}';
}

String _formatMicrosPerLitreInput(int microsPerLitre) {
  return ScaledDecimal.format(
    microsPerLitre,
    scale: FuelNumbers.microsPerMajorUnit,
    minFractionDigits: 3,
    maxFractionDigits: 3,
  );
}

String _formatNumber(double value, {required int maxFractionDigits}) {
  final fixed = value.toStringAsFixed(maxFractionDigits);
  if (!fixed.contains('.')) {
    return fixed;
  }
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

String _sourceLabel(_CalculatorValueSource source) {
  return switch (source) {
    _CalculatorValueSource.vehicle => 'Based on recorded vehicle values',
    _CalculatorValueSource.manual => 'Based on manual values',
  };
}

String _betterOptionLabel(FuelPriceBetterOption option) {
  return switch (option) {
    FuelPriceBetterOption.stationA => 'Station A',
    FuelPriceBetterOption.stationB => 'Station B',
    FuelPriceBetterOption.equal => 'Prices are equal',
  };
}

String _netSavingText(FuelPriceComparisonResult result) {
  final net = result.netSavingMinor;
  if (net == null) {
    return 'Gross comparison only.';
  }
  if (net > 0) {
    return '${_betterOptionLabel(result.betterOption)} saves approx. ${_formatCurrency(net)} after extra travel.';
  }
  if (net == 0) {
    return 'The price saving is roughly cancelled by the extra travel.';
  }
  return 'The extra travel costs more than the fuel-price saving.';
}
