import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../../../shared/widgets/dt_form_section.dart';
import '../../../shared/widgets/dt_odometer_input.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/odometer_entry.dart';
import '../domain/odometer_policy.dart';

class OdometerEntryFormScreen extends StatefulWidget {
  const OdometerEntryFormScreen({required this.entry, super.key});

  final OdometerEntry entry;

  @override
  State<OdometerEntryFormScreen> createState() =>
      _OdometerEntryFormScreenState();
}

class _OdometerEntryFormScreenState extends State<OdometerEntryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _readingController;
  late DateTime _eventDateTime;
  Future<List<OdometerEntry>>? _historyFuture;
  String? _formError;

  @override
  void initState() {
    super.initState();
    _readingController = TextEditingController(
      text: DTFormatters.wholeNumber(widget.entry.odometer),
    );
    _eventDateTime = widget.entry.eventDateTime.toLocal();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _historyFuture ??= context
        .read<DriveTrackerController>()
        .odometerHistoryForVehicle(widget.entry.vehicleId);
  }

  @override
  void dispose() {
    _readingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicle = _vehicleForId([
      ...controller.activeVehicles,
      ...controller.archivedVehicles,
    ], widget.entry.vehicleId);

    if (vehicle == null) {
      return const Scaffold(
        appBar: _OdometerEntryAppBar(),
        body: DTEmptyState(
          icon: Icons.speed_rounded,
          title: 'Odometer reading not found',
          body: 'This reading is no longer available.',
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: const _OdometerEntryAppBar(),
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
            key: const Key('saveOdometerEntryButton'),
            label: 'Save reading',
            icon: Icons.check_rounded,
            isLoading: controller.isBusy,
            onPressed: controller.isBusy ? null : () => _save(),
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
                vehicle.name,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: DTSpacing.xs),
              Text(
                'Manual odometer reading',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: DTSpacing.xl),
              DTFormSection(
                title: 'Reading',
                icon: Icons.speed_rounded,
                subtitle: 'Correct the stored value and date from History.',
                children: [
                  DTOdometerInput(
                    fieldKey: const Key('editOdometerReadingField'),
                    controller: _readingController,
                    label: 'Odometer reading',
                    unitLabel: vehicle.distanceUnit.shortLabel,
                    validator: _validateReading,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: DTSpacing.sm),
                  FutureBuilder<List<OdometerEntry>>(
                    future: _historyFuture,
                    builder: (context, snapshot) {
                      return _OdometerNeighborContext(
                        entries: snapshot.data ?? const [],
                        editedEntry: widget.entry,
                        editedOdometer:
                            _parseInt(_readingController.text) ??
                            widget.entry.odometer,
                        editedDateTime: _eventDateTime,
                        unit: vehicle.distanceUnit,
                      );
                    },
                  ),
                  const SizedBox(height: DTSpacing.md),
                  _DateTimeTile(
                    key: const Key('editOdometerDateField'),
                    label: 'Reading date/time',
                    value: _eventDateTime,
                    onChanged: (value) {
                      setState(() => _eventDateTime = value);
                    },
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

  Future<void> _save({bool confirmUnusualSequence = false}) async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    try {
      await context.read<DriveTrackerController>().updateOdometerEntry(
        widget.entry.id,
        odometer: _parseInt(_readingController.text)!,
        eventDateTime: _eventDateTime,
        confirmUnusualSequence: confirmUnusualSequence,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Odometer reading saved.')));
    } on OdometerEditConfirmationRequired catch (error) {
      final confirmed = await _confirmUnusualSequence(error.message);
      if (!confirmed || !mounted) {
        return;
      }
      await _save(confirmUnusualSequence: true);
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() => _formError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _formError = 'Could not save odometer reading.');
      }
    }
  }

  Future<bool> _confirmUnusualSequence(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('odometerEditConfirmDialog'),
        title: const Text('Confirm odometer sequence'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('confirmOdometerEditButton'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
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

  Vehicle? _vehicleForId(List<Vehicle> vehicles, String vehicleId) {
    for (final vehicle in vehicles) {
      if (vehicle.id == vehicleId) {
        return vehicle;
      }
    }
    return null;
  }
}

class _OdometerEntryAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _OdometerEntryAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('Edit odometer reading'));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _OdometerNeighborContext extends StatelessWidget {
  const _OdometerNeighborContext({
    required this.entries,
    required this.editedEntry,
    required this.editedOdometer,
    required this.editedDateTime,
    required this.unit,
  });

  final List<OdometerEntry> entries;
  final OdometerEntry editedEntry;
  final int editedOdometer;
  final DateTime editedDateTime;
  final DistanceUnit unit;

  @override
  Widget build(BuildContext context) {
    final previous = _previous;
    final next = _next;
    if (previous == null && next == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (previous != null)
          Text(
            'Previous chronological reading: ${DTFormatters.odometer(previous.odometer, unit)}',
            key: const Key('editOdometerPreviousContext'),
            style: style,
          ),
        if (previous != null && next != null)
          const SizedBox(height: DTSpacing.xs),
        if (next != null)
          Text(
            'Next chronological reading: ${DTFormatters.odometer(next.odometer, unit)}',
            key: const Key('editOdometerNextContext'),
            style: style,
          ),
      ],
    );
  }

  OdometerEntry? get _previous {
    final chronological = _chronologicalEntries;
    final index = chronological.indexWhere(
      (entry) => entry.id == editedEntry.id,
    );
    return index > 0 ? chronological[index - 1] : null;
  }

  OdometerEntry? get _next {
    final chronological = _chronologicalEntries;
    final index = chronological.indexWhere(
      (entry) => entry.id == editedEntry.id,
    );
    return index >= 0 && index < chronological.length - 1
        ? chronological[index + 1]
        : null;
  }

  List<OdometerEntry> get _chronologicalEntries {
    final edited = OdometerEntry(
      id: editedEntry.id,
      vehicleId: editedEntry.vehicleId,
      odometer: editedOdometer,
      eventDateTime: editedDateTime.toUtc(),
      sourceType: editedEntry.sourceType,
      sourceRecordId: editedEntry.sourceRecordId,
      createdAt: editedEntry.createdAt,
      updatedAt: editedEntry.updatedAt,
    );
    return [
      for (final entry in entries)
        if (entry.id != edited.id) entry,
      edited,
    ]..sort(_compareChronologically);
  }

  int _compareChronologically(OdometerEntry left, OdometerEntry right) {
    final eventCompare = left.eventDateTime.compareTo(right.eventDateTime);
    if (eventCompare != 0) {
      return eventCompare;
    }
    final createdCompare = left.createdAt.compareTo(right.createdAt);
    if (createdCompare != 0) {
      return createdCompare;
    }
    return left.id.compareTo(right.id);
  }
}

class _DateTimeTile extends StatelessWidget {
  const _DateTimeTile({
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
          Expanded(child: Text(DTFormatters.dateTime(value))),
          IconButton(
            tooltip: 'Choose date',
            onPressed: () async {
              final now = context.read<DriveTrackerController>().currentTime;
              final picked = await showDatePicker(
                context: context,
                initialDate: value,
                firstDate: DateTime(1990),
                lastDate: DateTime(now.year + 1, 12, 31),
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
