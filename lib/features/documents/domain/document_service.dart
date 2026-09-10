import 'package:sqflite/sqflite.dart' as sqflite;

import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../attachments/data/attachment_repository.dart';
import '../../attachments/domain/attachment.dart';
import '../../attachments/domain/attachment_service.dart';
import '../../vehicles/data/vehicle_repository.dart';
import '../data/document_repository.dart';
import 'vehicle_document.dart';

typedef Clock = DateTime Function();

class DocumentService {
  DocumentService({
    required this.database,
    required this.vehicleRepository,
    required this.documentRepository,
    required this.attachmentRepository,
    required this.attachmentService,
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final AppDatabase database;
  final VehicleRepository vehicleRepository;
  final DocumentRepository documentRepository;
  final AttachmentRepository attachmentRepository;
  final AttachmentService attachmentService;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<VehicleDocument> createDocument(VehicleDocumentDraft draft) async {
    final clean = await _validateDraft(draft);
    final now = _clock().toUtc();
    final document = VehicleDocument(
      id: _idGenerator.newId('doc'),
      vehicleId: clean.vehicleId,
      category: clean.category,
      title: clean.title,
      issueDate: _dateOnlyOrNull(clean.issueDate),
      expiryDate: _dateOnlyOrNull(clean.expiryDate),
      referenceNumber: _cleanOptional(clean.referenceNumber),
      provider: _cleanOptional(clean.provider),
      notes: _cleanOptional(clean.notes),
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );
    await documentRepository.insert(document);
    return document;
  }

  Future<VehicleDocument> updateDocument(
    String documentId,
    VehicleDocumentDraft draft,
  ) async {
    final existing = await documentRepository.getById(documentId);
    if (existing == null) {
      throw const ValidationException(['Document not found.']);
    }
    final clean = await _validateDraft(draft);
    if (clean.vehicleId != existing.vehicleId) {
      throw const ValidationException([
        'Move attachments by creating a new document for that vehicle.',
      ]);
    }

    final updated = VehicleDocument(
      id: existing.id,
      vehicleId: existing.vehicleId,
      category: clean.category,
      title: clean.title,
      issueDate: _dateOnlyOrNull(clean.issueDate),
      expiryDate: _dateOnlyOrNull(clean.expiryDate),
      referenceNumber: _cleanOptional(clean.referenceNumber),
      provider: _cleanOptional(clean.provider),
      notes: _cleanOptional(clean.notes),
      reminderId: existing.reminderId,
      isArchived: existing.isArchived,
      archivedAt: existing.archivedAt,
      createdAt: existing.createdAt,
      updatedAt: _clock().toUtc(),
    );
    await documentRepository.update(updated);
    return updated;
  }

  Future<void> archiveDocument(String documentId) async {
    final existing = await documentRepository.getById(documentId);
    if (existing == null || existing.isArchived) {
      return;
    }
    final now = _clock().toUtc();
    await documentRepository.update(
      existing.copyWith(isArchived: true, archivedAt: now, updatedAt: now),
    );
  }

  Future<VehicleDocument> renewDocument(
    String documentId,
    VehicleDocumentDraft renewalDraft,
  ) async {
    final existing = await documentRepository.getById(documentId);
    if (existing == null) {
      throw const ValidationException(['Document not found.']);
    }
    if (existing.isArchived) {
      throw const ValidationException([
        'Only current documents can be renewed.',
      ]);
    }
    final clean = await _validateDraft(renewalDraft);
    if (clean.vehicleId != existing.vehicleId) {
      throw const ValidationException([
        'Renewal must stay with the same vehicle.',
      ]);
    }

    final now = _clock().toUtc();
    final renewed = VehicleDocument(
      id: _idGenerator.newId('doc'),
      vehicleId: clean.vehicleId,
      category: clean.category,
      title: clean.title,
      issueDate: _dateOnlyOrNull(clean.issueDate),
      expiryDate: _dateOnlyOrNull(clean.expiryDate),
      referenceNumber: _cleanOptional(clean.referenceNumber),
      provider: _cleanOptional(clean.provider),
      notes: _cleanOptional(clean.notes),
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );

    await database.transaction((txn) async {
      await documentRepository.update(
        existing.copyWith(isArchived: true, archivedAt: now, updatedAt: now),
        executor: txn,
      );
      await documentRepository.insert(renewed, executor: txn);
    });
    return renewed;
  }

  Future<void> deleteDocumentPermanently(String documentId) async {
    final existing = await documentRepository.getById(documentId);
    if (existing == null) {
      return;
    }
    final attachments = await attachmentRepository.listForParent(
      AttachmentParentType.document,
      documentId,
    );
    await database.transaction((sqflite.Transaction txn) async {
      await attachmentRepository.deleteForParent(
        AttachmentParentType.document,
        documentId,
        executor: txn,
      );
      await documentRepository.delete(documentId, executor: txn);
    });
    await attachmentService.deleteManagedFilesBestEffort(attachments);
  }

  Future<List<DocumentExpiryReminder>> remindersForVehicle(
    String vehicleId, {
    DateTime? asOf,
  }) async {
    final documents = await documentRepository.activeExpiringForVehicle(
      vehicleId,
    );
    final reminders = documents
        .map(
          (document) => DocumentExpiryReminder.evaluate(
            document: document,
            asOf: asOf ?? _clock(),
          ),
        )
        .where((reminder) => reminder.shouldShowAsReminder)
        .toList();
    reminders.sort((a, b) {
      final severityCompare = b.state.severity.compareTo(a.state.severity);
      if (severityCompare != 0) {
        return severityCompare;
      }
      final dayCompare = a.daysRemaining.compareTo(b.daysRemaining);
      if (dayCompare != 0) {
        return dayCompare;
      }
      return a.document.title.compareTo(b.document.title);
    });
    return reminders;
  }

  Future<VehicleDocumentDraft> _validateDraft(
    VehicleDocumentDraft draft,
  ) async {
    final vehicleId = draft.vehicleId.trim();
    final vehicle = await vehicleRepository.getById(vehicleId);
    if (vehicle == null || vehicle.isArchived) {
      throw const ValidationException(['Select an active vehicle.']);
    }
    final category = draft.category.trim();
    final title = draft.title.trim();
    final errors = <String>[
      if (category.isEmpty) 'Category is required.',
      if (title.isEmpty) 'Title is required.',
    ];

    final issue = _dateOnlyOrNull(draft.issueDate);
    final expiry = _dateOnlyOrNull(draft.expiryDate);
    if (issue != null && expiry != null && expiry.isBefore(issue)) {
      errors.add('Expiry date cannot be before issue date.');
    }
    if (errors.isNotEmpty) {
      throw ValidationException(errors);
    }

    return VehicleDocumentDraft(
      vehicleId: vehicleId,
      category: category,
      title: title,
      issueDate: issue,
      expiryDate: expiry,
      referenceNumber: draft.referenceNumber,
      provider: draft.provider,
      notes: draft.notes,
    );
  }

  String? _cleanOptional(String? value) {
    final clean = value?.trim();
    return clean == null || clean.isEmpty ? null : clean;
  }

  DateTime? _dateOnlyOrNull(DateTime? value) {
    if (value == null) {
      return null;
    }
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
