import 'earnings_formatters.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../core/utilities/money.dart';
import '../../../core/utilities/formatters.dart';
import '../../../core/utilities/scaled_decimal.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/income.dart';
import '../domain/income_activity.dart';
import '../domain/income_earnings.dart';
import '../domain/expense.dart';
import '../domain/record_category.dart';

class IncomeActivityFields extends StatefulWidget {
  const IncomeActivityFields({
    super.key,
    required this.vehicleId,
    required this.unit,
    required this.categoryId,
    required this.grossMinor,
    this.original,
  });
  final String? vehicleId, categoryId;
  final DistanceUnit unit;
  final int? grossMinor;
  final Income? original;
  @override
  State<IncomeActivityFields> createState() => IncomeActivityFieldsState();
}

class IncomeActivityFieldsState extends State<IncomeActivityFields>
    with AutomaticKeepAliveClientMixin<IncomeActivityFields> {
  late IncomeActivityType type;
  final base = TextEditingController(),
      tips = TextEditingController(),
      travel = TextEditingController(),
      other = TextEditingController(),
      distance = TextEditingController(),
      duration = TextEditingController(),
      count = TextEditingController(),
      rate = TextEditingController();
  bool breakdown = false,
      complete = false,
      _manualType = false,
      _loading = true,
      _distanceEdited = false;
  int? _originalMm;
  late DistanceUnit rateUnit;
  List<Expense> _choices = [];
  final Set<String> _linked = {};
  final List<TextEditingController> _dialogControllers = [];
  final List<ExpenseDraft> _new = [];
  List<String> get expenseIds => _linked.toList();
  List<ExpenseDraft> get newExpenses => List.unmodifiable(_new);
  String? _loadError;
  late Future<void> _loadFuture;
  Future<IncomeActivity> prepare() async {
    await _loadFuture;
    return activity();
  }

  @override
  void initState() {
    super.initState();
    final a =
        widget.original?.activity ??
        IncomeActivity(type: IncomeActivityType.suggested(widget.categoryId));
    type = a.type;
    breakdown = a.hasBreakdown;
    complete = a.directCostsComplete;
    _originalMm = a.distanceMm;
    rateUnit = a.rateUnit ?? widget.unit;
    String money(int? v) => v == null
        ? ''
        : ScaledDecimal.format(v, scale: 100, minFractionDigits: 2);
    base.text = money(a.baseMinor);
    tips.text = money(a.tipsMinor);
    travel.text = money(a.travelMinor);
    other.text = money(a.otherMinor);
    distance.text = ActivityDistance.input(a.distanceMm, widget.unit);
    duration.text = a.durationMinutes?.toString() ?? '';
    count.text = a.deliveryCount?.toString() ?? '';
    rate.text = a.rateMicros == null
        ? ''
        : ScaledDecimal.format(
            a.rateMicros!,
            scale: 1000000,
            minFractionDigits: 2,
            maxFractionDigits: 6,
          );
    _loadFuture = _load();
  }

  @override
  void didUpdateWidget(covariant IncomeActivityFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unit != widget.unit) {
      final mm = _distanceEdited
          ? ActivityDistance.parse(distance.text, oldWidget.unit)
          : _originalMm;
      distance.text = ActivityDistance.input(mm, widget.unit);
      _originalMm = mm;
      _distanceEdited = false;
    }
    if (oldWidget.vehicleId != widget.vehicleId) {
      _linked.clear();
      _new.clear();
      _choices = [];
      _loading = true;
      _loadError = null;
      complete = false;
      _loadFuture = _load();
    }
    if (widget.original == null &&
        !_manualType &&
        oldWidget.categoryId != widget.categoryId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _changeType(
            IncomeActivityType.suggested(widget.categoryId),
            manual: false,
          );
        }
      });
    }
  }

  Future<void> _load() async {
    final id = widget.vehicleId;
    if (id == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final c = context.read<DriveTrackerController>();
      final choices = await c.incomeExpenseChoices(id, widget.original?.id);
      final existing = widget.original == null
          ? <Expense>[]
          : await c.incomeExpenses(widget.original!.id);
      if (!mounted || widget.vehicleId != id) return;
      setState(() {
        _choices = choices;
        _linked.addAll(
          existing.where((e) => e.vehicleId == id).map((e) => e.id),
        );
        _loading = false;
        _loadError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError =
              'Could not load direct expenses. Reopen this form before saving.';
        });
      }
    }
  }

  IncomeActivity activity() {
    if (_loading || _loadError != null) {
      throw const ValidationException([
        'Direct expenses have not loaded. Please retry.',
      ]);
    }
    int? number(TextEditingController c) =>
        c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
    return IncomeActivity(
      type: type,
      baseMinor: breakdown ? MoneyAmount.parseMinor(base.text) : null,
      tipsMinor: breakdown ? MoneyAmount.parseMinor(tips.text) : null,
      travelMinor: breakdown ? MoneyAmount.parseMinor(travel.text) : null,
      otherMinor: breakdown ? MoneyAmount.parseMinor(other.text) : null,
      distanceMm: type == IncomeActivityType.simple
          ? null
          : _distanceEdited
          ? ActivityDistance.parse(distance.text, widget.unit)
          : _originalMm,
      durationMinutes:
          type == IncomeActivityType.simple ||
              type == IncomeActivityType.reimbursement
          ? null
          : number(duration),
      deliveryCount: type == IncomeActivityType.delivery ? number(count) : null,
      rateMicros:
          type == IncomeActivityType.reimbursement &&
              rate.text.trim().isNotEmpty
          ? ScaledDecimal.parse(rate.text, scale: 1000000)
          : null,
      rateUnit:
          type == IncomeActivityType.reimbursement &&
              rate.text.trim().isNotEmpty
          ? rateUnit
          : null,
      directCostsComplete: type != IncomeActivityType.simple && complete,
    );
  }

  Future<void> _changeType(
    IncomeActivityType next, {
    bool manual = true,
  }) async {
    if (next == type) {
      if (manual) _manualType = true;
      return;
    }
    final losesBreakdown = breakdown && !next.hasBreakdown;
    final losesDistance =
        next == IncomeActivityType.simple && distance.text.isNotEmpty;
    final losesDuration =
        (next == IncomeActivityType.simple ||
            next == IncomeActivityType.reimbursement) &&
        duration.text.isNotEmpty;
    final losesCount =
        next != IncomeActivityType.delivery && count.text.isNotEmpty;
    final losesRate =
        next != IncomeActivityType.reimbursement && rate.text.isNotEmpty;
    final losesCosts =
        next == IncomeActivityType.simple &&
        (_linked.isNotEmpty || _new.isNotEmpty || complete);
    if (losesBreakdown ||
        losesDistance ||
        losesDuration ||
        losesCount ||
        losesRate ||
        losesCosts) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change activity template?'),
          content: const Text(
            'Incompatible activity fields will be cleared. Gross received stays unchanged. Unlinked expenses remain in your records.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change template'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() {
      type = next;
      if (manual) _manualType = true;
      if (losesBreakdown) {
        breakdown = false;
        for (final c in [base, tips, travel, other]) {
          c.clear();
        }
      }
      if (losesDistance) {
        distance.clear();
        _originalMm = null;
        _distanceEdited = true;
      }
      if (losesDuration) duration.clear();
      if (losesCount) count.clear();
      if (losesRate) rate.clear();
      if (losesCosts) {
        _linked.clear();
        _new.clear();
        complete = false;
      }
    });
  }

  Widget _field(
    String label,
    TextEditingController c, {
    bool money = false,
    bool integer = false,
    bool distanceField = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: Key('activity_${label.replaceAll(' ', '_')}'),
      controller: c,
      keyboardType: TextInputType.numberWithOptions(decimal: !integer),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixText: money ? '£' : null,
      ),
      onChanged: (_) => setState(() {
        if (distanceField) _distanceEdited = true;
      }),
      validator: (text) {
        if ((text ?? '').trim().isEmpty) {
          return money ? 'Enter an amount (zero is allowed).' : null;
        }
        final n = money
            ? MoneyAmount.parseMinor(text!)
            : integer
            ? int.tryParse(text!)
            : ScaledDecimal.parse(text!, scale: 1000000);
        return n == null || n < 0 || (!money && n == 0)
            ? 'Enter a valid ${money ? 'nonnegative amount' : 'positive value'}.'
            : null;
      },
    ),
  );
  int get _costs =>
      _choices
          .where((e) => _linked.contains(e.id))
          .fold<int>(0, (s, e) => s + e.amountMinor) +
      _new.fold<int>(0, (s, e) => s + e.amountMinor);
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    IncomeEarnings? preview;
    try {
      preview = IncomeEarnings(
        Income(
          id: 'preview',
          vehicleId: widget.vehicleId ?? '',
          categoryId: widget.categoryId ?? '',
          eventDateTime: DateTime.now(),
          amountMinor: widget.grossMinor ?? 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          activity: activity(),
        ),
        _costs,
      );
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<IncomeActivityType>(
          key: ValueKey('activityTemplate_${type.name}'),
          initialValue: type,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Activity template'),
          items: [
            for (final t in IncomeActivityType.values)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: (v) {
            if (v != null) _changeType(v);
          },
        ),
        if (type != IncomeActivityType.simple) ...[
          const SizedBox(height: 12),
          Text(switch (type) {
            IncomeActivityType.rideshare =>
              'One ride or a whole rideshare session.',
            IncomeActivityType.delivery =>
              'One delivery shift/session, not each delivery.',
            IncomeActivityType.work => 'Associated work income; commute distance does not make salary vehicle-generated profit.',
            IncomeActivityType.reimbursement =>
              'Claim estimate is separate from actual money received.',
            _ => '',
          }),
          if (type.hasBreakdown) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Detailed income breakdown'),
              value: breakdown,
              onChanged: (v) => setState(() => breakdown = v),
            ),
            if (breakdown) ...[
              _field(
                type == IncomeActivityType.rideshare
                    ? 'Fare / base income'
                    : 'Base pay',
                base,
                money: true,
              ),
              _field('Tips', tips, money: true),
              _field('Travel compensation', travel, money: true),
              _field('Other income', other, money: true),
              const Text(
                'Enter every component, including zero. Sum must equal gross received.',
              ),
            ],
          ],
          const SizedBox(height: 12),
          _field(
            '${type == IncomeActivityType.reimbursement
                ? 'Distance claimed'
                : type == IncomeActivityType.work
                ? 'Associated work / commute distance'
                : 'Distance driven'} (${widget.unit.shortLabel})',
            distance,
            distanceField: true,
          ),
          if (type != IncomeActivityType.reimbursement)
            _field('Duration (minutes)', duration, integer: true),
          if (type == IncomeActivityType.delivery)
            _field('Deliveries', count, integer: true),
          if (type == IncomeActivityType.reimbursement) ...[
            _field('Reimbursement rate (£ per unit)', rate),
            DropdownButtonFormField<DistanceUnit>(
              initialValue: rateUnit,
              decoration: const InputDecoration(
                labelText: 'Contractual rate unit',
              ),
              items: [
                for (final u in DistanceUnit.values)
                  DropdownMenuItem(value: u, child: Text(u.label)),
              ],
              onChanged: (v) => setState(() => rateUnit = v!),
            ),
          ],
          const SizedBox(height: 16),
          Text('Direct costs', style: Theme.of(context).textTheme.titleMedium),
          const Text(
            'Link an existing Expense or create one on save. Expenses stay in ordinary expenditure once. Refuels/services are not allocated.',
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_loadError != null) Text(_loadError!),
          for (final e in _choices.where((e) => _linked.contains(e.id)))
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${DTFormatters.moneyMinor(e.amountMinor)} · ${e.merchant ?? 'Expense'}',
              ),
              subtitle: Text(DTFormatters.date(e.eventDateTime)),
              trailing: IconButton(
                tooltip: 'Unlink expense',
                onPressed: () => setState(() => _linked.remove(e.id)),
                icon: const Icon(Icons.link_off),
              ),
            ),
          for (var i = 0; i < _new.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${DTFormatters.moneyMinor(_new[i].amountMinor)} · New expense on save',
              ),
              trailing: IconButton(
                tooltip: 'Remove pending expense',
                onPressed: () {
                  setState(() => _new.removeAt(i));
                },
                icon: const Icon(Icons.close),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _loading || widget.vehicleId == null
                    ? null
                    : _selectExpense,
                icon: const Icon(Icons.link),
                label: const Text('Link existing expense'),
              ),
              OutlinedButton.icon(
                onPressed: _loading || widget.vehicleId == null
                    ? null
                    : _createExpense,
                icon: const Icon(Icons.add),
                label: const Text('New direct expense'),
              ),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Direct costs are complete'),
            subtitle: const Text(
              'Includes explicitly confirming no direct costs. Otherwise costs remain unknown/incomplete.',
            ),
            value: complete,
            onChanged: (v) => setState(() => complete = v!),
          ),
          Text('Recorded direct costs: ${earningsMoney(_costs)}'),
          if (preview != null) ...[
            Text('Net after direct costs: ${earningsMoney(preview.netMinor)}'),
            if (preview.grossPerDistance(widget.unit) != null)
              Text(
                'Gross per ${widget.unit.shortLabel}: ${earningsMoney(preview.grossPerDistance(widget.unit))}',
              ),
            if (preview.grossPerHour != null)
              Text('Gross per hour: ${earningsMoney(preview.grossPerHour)}'),
            if (preview.expectedClaimMinor != null)
              Text(
                'Expected claim (not received): ${earningsMoney(preview.expectedClaimMinor)}',
              ),
          ],
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _selectExpense() async {
    final options = _choices.where((e) => !_linked.contains(e.id)).toList();
    final id = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Link an existing expense'),
        children: [
          if (options.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No unassigned expenses for this vehicle.'),
            ),
          for (final e in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.id),
              child: Text(
                '${DTFormatters.moneyMinor(e.amountMinor)} · ${e.merchant ?? 'Expense'} · ${DTFormatters.date(e.eventDateTime)}',
              ),
            ),
        ],
      ),
    );
    if (id != null && mounted) setState(() => _linked.add(id));
  }

  Future<void> _createExpense() async {
    final categories = await context
        .read<DriveTrackerController>()
        .categoriesFor(RecordCategoryType.expense);
    if (!mounted) return;
    if (categories.isEmpty) return;
    final amount = TextEditingController(), merchant = TextEditingController();
    String category = categories.first.id;
    _dialogControllers.addAll([amount, merchant]);
    final form = GlobalKey<FormState>();
    final result = await showDialog<ExpenseDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New direct expense'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => category = v!,
                ),
                TextFormField(
                  controller: amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: '£',
                  ),
                  validator: (v) => (MoneyAmount.parseMinor(v ?? '') ?? 0) <= 0
                      ? 'Enter a positive amount.'
                      : null,
                ),
                TextFormField(
                  controller: merchant,
                  decoration: const InputDecoration(
                    labelText: 'Merchant (optional)',
                  ),
                ),
                const Text(
                  'Uses the income date/time when saved. No expense is created until Save income.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(
                  ctx,
                  ExpenseDraft(
                    vehicleId: widget.vehicleId!,
                    categoryId: category,
                    eventDateTime: DateTime.now(),
                    amountMinor: MoneyAmount.parseMinor(amount.text)!,
                    merchant: merchant.text,
                  ),
                );
              }
            },
            child: const Text('Add on save'),
          ),
        ],
      ),
    );
    if (result != null && mounted) setState(() => _new.add(result));
  }

  @override
  void dispose() {
    for (final c in [
      ..._dialogControllers,
      base,
      tips,
      travel,
      other,
      distance,
      duration,
      count,
      rate,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
