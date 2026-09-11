import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_odometer_input.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/odometer_confirmation_dialog.dart';
import '../domain/odometer_policy.dart';

class UpdateOdometerScreen extends StatefulWidget {
  const UpdateOdometerScreen({super.key});

  @override
  State<UpdateOdometerScreen> createState() => _UpdateOdometerScreenState();
}

class _UpdateOdometerScreenState extends State<UpdateOdometerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _readingController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _readingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicle = controller.selectedVehicle;

    if (vehicle == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Update odometer')),
        body: DTEmptyState(
          icon: Icons.directions_car_rounded,
          title: 'Select a vehicle first',
          body: 'Add or select an active vehicle before recording mileage.',
        ),
      );
    }

    final current = controller.currentOdometer ?? 0;
    final reading = _parseInt(_readingController.text);
    final difference = reading == null ? null : reading - current;
    final unit = vehicle.distanceUnit;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Update odometer')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(DTSpacing.lg),
            children: [
              Text(
                vehicle.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: DTSpacing.xs),
              Text(
                vehicle.description,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DTSpacing.xl),
              _ReadingPanel(
                label: 'Current',
                value: DTFormatters.odometer(current, unit),
              ),
              const SizedBox(height: DTSpacing.lg),
              DTOdometerInput(
                fieldKey: const Key('updateOdometerField'),
                controller: _readingController,
                unitLabel: unit.shortLabel,
                label: 'New reading',
                validator: _validateReading,
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  } else {
                    setState(() {});
                  }
                },
              ),
              const SizedBox(height: DTSpacing.lg),
              _ReadingPanel(
                label: 'Difference',
                value: difference == null
                    ? 'Enter a reading'
                    : DTFormatters.signedDistance(difference, unit),
                emphasized: difference != null,
              ),
              if (_error != null) ...[
                const SizedBox(height: DTSpacing.lg),
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: DTSpacing.xl),
              DTPrimaryButton(
                key: const Key('saveOdometerButton'),
                label: 'Update odometer',
                icon: Icons.check_rounded,
                isLoading: controller.isBusy,
                onPressed: controller.isBusy ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _error = null);

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final reading = _parseInt(_readingController.text)!;
    final controller = context.read<DriveTrackerController>();
    final assessment = controller.assessOdometerUpdate(reading);

    if (assessment.decision == OdometerDecision.invalid) {
      setState(() => _error = assessment.message);
      return;
    }

    var allowHistorical = false;
    var confirmLargeIncrease = false;
    if (assessment.needsConfirmation) {
      final confirmed = await _confirmAssessment(assessment);
      if (!confirmed) {
        return;
      }
      allowHistorical = assessment.decision == OdometerDecision.belowCurrent;
      confirmLargeIncrease =
          assessment.decision == OdometerDecision.unusuallyLargeIncrease;
    }

    try {
      await controller.updateOdometer(
        reading,
        allowHistorical: allowHistorical,
        confirmLargeIncrease: confirmLargeIncrease,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Odometer reading saved.')));
    } on OdometerConfirmationRequired catch (error) {
      setState(() => _error = error.assessment.message);
    } on ValidationException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Could not save odometer reading.');
    }
  }

  Future<bool> _confirmAssessment(OdometerAssessment assessment) async {
    final vehicle = context.read<DriveTrackerController>().selectedVehicle;
    if (vehicle == null) {
      return false;
    }
    return showOdometerConfirmationDialog(
      context: context,
      assessment: assessment,
      unit: vehicle.distanceUnit,
      historicalTitle: 'Save historical reading?',
    );
  }

  String? _validateReading(String? value) {
    final parsed = _parseInt(value ?? '');
    if (parsed == null) {
      return 'Enter an odometer reading.';
    }
    if (parsed < 0) {
      return 'Odometer readings cannot be negative.';
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
}

class _ReadingPanel extends StatelessWidget {
  const _ReadingPanel({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(DTSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.42,
        ),
        borderRadius: DTRadii.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: DTSpacing.xs),
          Text(
            value,
            style:
                (emphasized
                        ? theme.textTheme.headlineSmall
                        : theme.textTheme.titleLarge)
                    ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
