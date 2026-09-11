import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/money.dart';
import '../../../core/utilities/scaled_decimal.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_form_section.dart';
import '../../../shared/widgets/dt_odometer_input.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../../shared/widgets/odometer_confirmation_dialog.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/presentation/attachment_panel.dart';
import '../../odometer/domain/odometer_policy.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/income.dart';
import '../domain/record_category.dart';
import 'category_name_dialog.dart';

class IncomeFormScreen extends StatefulWidget {
  const IncomeFormScreen({this.income, super.key});

  final Income? income;

  @override
  State<IncomeFormScreen> createState() => _IncomeFormScreenState();
}

class _IncomeFormScreenState extends State<IncomeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _odometerController = TextEditingController();
  final _sourceController = TextEditingController();
  final _notesController = TextEditingController();

  String? _vehicleId;
  String? _categoryId;
  late DateTime _eventDateTime;
  Future<List<RecordCategory>>? _categoriesFuture;
  String? _formError;
  bool _didDefaultFromController = false;
  int? _lastOdometer;

  bool get _isEditing => widget.income != null;

  @override
  void initState() {
    super.initState();
    final income = widget.income;
    _eventDateTime = income?.eventDateTime.toLocal() ?? DateTime.now();
    _vehicleId = income?.vehicleId;
    _categoryId = income?.categoryId;
    if (income != null) {
      _amountController.text = ScaledDecimal.format(
        income.amountMinor,
        scale: MoneyAmount.defaultCurrency.minorScale,
        minFractionDigits: 2,
        maxFractionDigits: 2,
      );
      _odometerController.text = income.odometer == null
          ? ''
          : DTFormatters.wholeNumber(income.odometer!);
      _sourceController.text = income.source ?? '';
      _notesController.text = income.notes ?? '';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _categoriesFuture ??= _loadCategories();
    if (_didDefaultFromController) {
      return;
    }
    _didDefaultFromController = true;
    final controller = context.read<DriveTrackerController>();
    if (widget.income == null) {
      _vehicleId = controller.selectedVehicle?.id;
      _lastOdometer = controller.currentOdometer;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _odometerController.dispose();
    _sourceController.dispose();
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
      appBar: AppBar(title: Text(_isEditing ? 'Edit income' : 'Add income')),
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
                  tooltip: 'Delete income',
                  onPressed: controller.isBusy ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
                const SizedBox(width: DTSpacing.md),
              ],
              Expanded(
                child: DTPrimaryButton(
                  key: const Key('saveIncomeButton'),
                  label: 'Save income',
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
                key: const Key('incomeVehicleField'),
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
              FutureBuilder<List<RecordCategory>>(
                future: _categoriesFuture,
                builder: (context, snapshot) {
                  final categories = snapshot.data ?? const <RecordCategory>[];
                  if (snapshot.connectionState != ConnectionState.done &&
                      categories.isEmpty) {
                    return const LinearProgressIndicator();
                  }
                  if (_categoryId == null && categories.isNotEmpty) {
                    _categoryId = categories.first.id;
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SizedBox(
                          key: const Key('incomeCategoryField'),
                          child: DropdownButtonFormField<String>(
                            key: ValueKey<String>(
                              'income-category-${_categoryId ?? 'none'}-${categories.length}',
                            ),
                            initialValue:
                                categories.any(
                                  (category) => category.id == _categoryId,
                                )
                                ? _categoryId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Category',
                            ),
                            items: [
                              for (final category in categories)
                                DropdownMenuItem(
                                  value: category.id,
                                  child: Text(category.name),
                                ),
                            ],
                            validator: (value) =>
                                value == null ? 'Select a category.' : null,
                            onChanged: (value) =>
                                setState(() => _categoryId = value),
                          ),
                        ),
                      ),
                      const SizedBox(width: DTSpacing.sm),
                      IconButton.filledTonal(
                        tooltip: 'Add category',
                        onPressed: () => _addCategory(categories),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('incomeAmountField'),
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,£]')),
                ],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'Amount',
                  prefixText: currencySymbol,
                ),
                validator: (value) => _validatePositiveMoney(value, 'Amount'),
              ),
              const SizedBox(height: DTSpacing.md),
              _DateTimeTile(
                label: 'Date/time',
                value: _eventDateTime,
                onChanged: (value) => setState(() => _eventDateTime = value),
              ),
              const SizedBox(height: DTSpacing.xl),
              DTFormSection(
                title: 'Optional details',
                icon: Icons.tune_rounded,
                subtitle: 'Add source and mileage context for this income.',
                children: [
                  DTOdometerInput(
                    controller: _odometerController,
                    unitLabel: selectedVehicle?.distanceUnit.shortLabel ?? 'mi',
                    label: 'Odometer',
                    validator: _validateOptionalOdometer,
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
                  TextFormField(
                    controller: _sourceController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Source'),
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
              const SizedBox(height: DTSpacing.lg),
              if (_isEditing)
                AttachmentPanel(
                  key: Key('incomeAttachments_${widget.income!.id}'),
                  parentType: AttachmentParentType.income,
                  parentId: widget.income!.id,
                )
              else
                const _AttachmentsAfterSaveHint(
                  text: 'Save this income record, then add supporting files.',
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

    final draft = IncomeDraft(
      vehicleId: _vehicleId!,
      categoryId: _categoryId!,
      eventDateTime: _eventDateTime,
      amountMinor: MoneyAmount.parseMinor(_amountController.text)!,
      odometer: _parseInt(_odometerController.text),
      source: _sourceController.text,
      notes: _notesController.text,
    );

    try {
      final controller = context.read<DriveTrackerController>();
      if (_isEditing) {
        await controller.updateIncome(
          widget.income!.id,
          draft,
          allowHistorical: allowHistorical,
          confirmLargeIncrease: confirmLargeIncrease,
        );
      } else {
        await controller.addIncome(
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
          .showSnackBar(const SnackBar(content: Text('Income saved.')));
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
      setState(() => _formError = 'Could not save income.');
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete income?'),
        content: const Text('This removes only its linked odometer entry.'),
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
    await context.read<DriveTrackerController>().deleteIncome(
      widget.income!.id,
    );
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Income deleted.')));
  }

  Future<void> _addCategory(List<RecordCategory> categories) async {
    final name = await showCategoryNameDialog(
      context,
      title: 'New income category',
      existingNames: categories.map((category) => category.name),
    );
    if (!mounted || name == null) {
      return;
    }

    try {
      final controller = context.read<DriveTrackerController>();
      final category = await controller.addCustomCategory(
        type: RecordCategoryType.income,
        name: name,
      );
      final categoriesFuture = controller.categoriesFor(
        RecordCategoryType.income,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _categoryId = category.id;
        _categoriesFuture = categoriesFuture;
        _formError = null;
      });
    } on ValidationException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _formError = error.message);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _formError = 'Could not save category.');
    }
  }

  Future<List<RecordCategory>> _loadCategories() async {
    final controller = context.read<DriveTrackerController>();
    final categories = await controller.categoriesFor(
      RecordCategoryType.income,
    );
    if (mounted && _categoryId == null && categories.isNotEmpty) {
      setState(() => _categoryId = categories.first.id);
    }
    return categories;
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
      historicalTitle: 'Save historical income?',
    );
  }

  String? _validatePositiveMoney(String? value, String label) {
    final parsed = MoneyAmount.parseMinor(value ?? '');
    if (parsed == null) {
      return '$label is required.';
    }
    if (parsed <= 0) {
      return '$label must be greater than zero.';
    }
    return null;
  }

  String? _validateOptionalOdometer(String? value) {
    final parsed = _parseInt(value ?? '');
    if (parsed == null) {
      return null;
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
