import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_date_field.dart';
import '../../../shared/widgets/dt_primary_button.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/presentation/attachment_panel.dart';
import '../../vehicles/domain/vehicle.dart';
import '../domain/vehicle_document.dart';

class DocumentFormScreen extends StatefulWidget {
  const DocumentFormScreen({this.document, this.renewingFrom, super.key})
    : assert(document == null || renewingFrom == null);

  final VehicleDocument? document;
  final VehicleDocument? renewingFrom;

  @override
  State<DocumentFormScreen> createState() => _DocumentFormScreenState();
}

class _DocumentFormScreenState extends State<DocumentFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _categoryController = TextEditingController();
  final _titleController = TextEditingController();
  final _providerController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();

  String? _vehicleId;
  DateTime? _issueDate;
  DateTime? _expiryDate;
  String? _formError;
  bool _didDefaultFromController = false;

  bool get _isEditing => widget.document != null;
  bool get _isRenewing => widget.renewingFrom != null;
  VehicleDocument? get _source => widget.document ?? widget.renewingFrom;

  @override
  void initState() {
    super.initState();
    final document = _source;
    _vehicleId = document?.vehicleId;
    _categoryController.text =
        document?.category ?? defaultDocumentCategories.first;
    _titleController.text = document?.title ?? '';
    _providerController.text = document?.provider ?? '';
    _referenceController.text = _isRenewing
        ? ''
        : document?.referenceNumber ?? '';
    _notesController.text = _isRenewing ? '' : document?.notes ?? '';
    _issueDate = _isRenewing ? null : document?.issueDate;
    _expiryDate = _isRenewing ? null : document?.expiryDate;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didDefaultFromController) {
      return;
    }
    _didDefaultFromController = true;
    _vehicleId ??= context.read<DriveTrackerController>().selectedVehicle?.id;
  }

  @override
  void dispose() {
    _categoryController.dispose();
    _titleController.dispose();
    _providerController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<DriveTrackerController>();
    final vehicles = controller.activeVehicles;
    final selectedVehicle = _vehicleForId(vehicles, _vehicleId);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
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
            key: const Key('saveDocumentButton'),
            label: _isRenewing ? 'Save renewal' : 'Save document',
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
                key: const Key('documentVehicleField'),
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
                    value == null ? 'Select an active vehicle.' : null,
                onChanged: _isEditing || _isRenewing
                    ? null
                    : (value) => setState(() => _vehicleId = value),
              ),
              const SizedBox(height: DTSpacing.lg),
              Text(
                'Category',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: DTSpacing.sm),
              Wrap(
                spacing: DTSpacing.sm,
                runSpacing: DTSpacing.sm,
                children: [
                  for (final category in defaultDocumentCategories)
                    ChoiceChip(
                      key: Key('documentCategoryChip_$category'),
                      label: Text(category),
                      selected: _categoryController.text == category,
                      onSelected: (_) =>
                          setState(() => _categoryController.text = category),
                    ),
                ],
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('documentCategoryField'),
                controller: _categoryController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Category'),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? 'Category is required.'
                    : null,
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('documentTitleField'),
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Title is required.' : null,
              ),
              const SizedBox(height: DTSpacing.lg),
              Text(
                'Dates',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: DTSpacing.md),
              DTDateField(
                fieldKey: const Key('documentIssueDateField'),
                label: 'Issue date',
                value: _issueDate,
                currentDate: controller.currentTime,
                onChanged: (value) => setState(() => _issueDate = value),
              ),
              const SizedBox(height: DTSpacing.md),
              DTDateField(
                fieldKey: const Key('documentExpiryDateField'),
                label: 'Expiry date',
                value: _expiryDate,
                currentDate: controller.currentTime,
                onChanged: (value) => setState(() => _expiryDate = value),
              ),
              const SizedBox(height: DTSpacing.lg),
              Text(
                'Optional details',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('documentProviderField'),
                controller: _providerController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Provider'),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('documentReferenceField'),
                controller: _referenceController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Reference number',
                ),
              ),
              const SizedBox(height: DTSpacing.md),
              TextFormField(
                key: const Key('documentNotesField'),
                controller: _notesController,
                minLines: 3,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Notes'),
              ),
              const SizedBox(height: DTSpacing.lg),
              if (_isEditing)
                AttachmentPanel(
                  key: Key('documentAttachments_${widget.document!.id}'),
                  parentType: AttachmentParentType.document,
                  parentId: widget.document!.id,
                )
              else
                _AttachmentAfterSaveHint(isRenewing: _isRenewing),
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

  String get _title {
    if (_isRenewing) {
      return 'Renew document';
    }
    if (_isEditing) {
      return 'Edit document';
    }
    return 'Add document';
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final vehicleId = _vehicleId;
    if (vehicleId == null) {
      setState(() => _formError = 'Select an active vehicle.');
      return;
    }
    final draft = VehicleDocumentDraft(
      vehicleId: vehicleId,
      category: _categoryController.text,
      title: _titleController.text,
      issueDate: _issueDate,
      expiryDate: _expiryDate,
      provider: _providerController.text,
      referenceNumber: _referenceController.text,
      notes: _notesController.text,
    );
    try {
      final controller = context.read<DriveTrackerController>();
      final VehicleDocument saved;
      if (_isEditing) {
        saved = await controller.updateDocument(widget.document!.id, draft);
      } else if (_isRenewing) {
        saved = await controller.renewDocument(widget.renewingFrom!.id, draft);
      } else {
        saved = await controller.addDocument(draft);
      }
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isRenewing ? 'Document renewed.' : 'Document saved.'),
        ),
      );
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() => _formError = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _formError = 'Could not save document.');
      }
    }
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

class _AttachmentAfterSaveHint extends StatelessWidget {
  const _AttachmentAfterSaveHint({required this.isRenewing});

  final bool isRenewing;

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
                isRenewing
                    ? 'Save the renewal, then attach the new file from its document details.'
                    : 'Save this document, then add PDFs or images from its details.',
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
