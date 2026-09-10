import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../../../core/utilities/id_generator.dart';
import '../../../core/utilities/validation_exception.dart';
import '../data/attachment_repository.dart';
import 'attachment.dart';
import 'attachment_io.dart';

typedef AttachmentParentExists = Future<bool> Function(
  AttachmentParentType parentType,
  String parentId,
);
typedef Clock = DateTime Function();

class AttachmentService {
  AttachmentService({
    required this.database,
    required this.attachmentRepository,
    required this.storage,
    required this.picker,
    required this.opener,
    required this.parentExists,
    IdGenerator? idGenerator,
    Clock? clock,
  }) : _idGenerator = idGenerator ?? IdGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  static const maxAttachmentBytes = 20 * 1024 * 1024;
  static const supportedExtensions = {'pdf', 'jpg', 'jpeg', 'png'};

  static const _mimeByExtension = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };

  final AppDatabase database;
  final AttachmentRepository attachmentRepository;
  final AttachmentStorage storage;
  final AttachmentPicker picker;
  final AttachmentOpener opener;
  final AttachmentParentExists parentExists;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<List<Attachment>> listForParent(
    AttachmentParentType parentType,
    String parentId,
  ) {
    return attachmentRepository.listForParent(parentType, parentId);
  }

  Future<Attachment?> pickAndAttach({
    required AttachmentParentType parentType,
    required String parentId,
  }) async {
    final source = await picker.pickAttachment();
    if (source == null) {
      return null;
    }
    return addAttachment(
      parentType: parentType,
      parentId: parentId,
      source: source,
    );
  }

  Future<Attachment> addAttachment({
    required AttachmentParentType parentType,
    required String parentId,
    required AttachmentSource source,
  }) async {
    if (!await parentExists(parentType, parentId)) {
      throw const ValidationException(['Attachment parent record not found.']);
    }

    final sourceFile = File(source.sourcePath);
    if (!await sourceFile.exists()) {
      throw const ValidationException(['Selected file could not be read.']);
    }

    final fileName = _displayFileName(source.fileName);
    final extension = _extensionFor(
      fileName,
      source.sourcePath,
      source.mimeType,
    );
    if (!supportedExtensions.contains(extension)) {
      throw const ValidationException([
        'Choose a PDF, JPG, JPEG or PNG attachment.',
      ]);
    }

    final fileSize = source.fileSize ?? await sourceFile.length();
    if (fileSize <= 0) {
      throw const ValidationException(['Attachment file is empty.']);
    }
    if (fileSize > maxAttachmentBytes) {
      throw const ValidationException(['Attachment must be 20 MB or smaller.']);
    }

    final id = _idGenerator.newId('attach');
    final now = _clock().toUtc();
    final storedPath = p.posix.join(
      'attachments',
      parentType.storageSegment,
      _safeSegment(parentId),
      '$id.$extension',
    );
    final attachment = Attachment(
      id: id,
      parentType: parentType,
      parentId: parentId,
      fileName: fileName,
      storedPath: storedPath,
      mimeType: source.mimeType ?? _mimeByExtension[extension],
      fileSize: fileSize,
      createdAt: now,
      updatedAt: now,
    );

    await storage.copyIntoManagedStorage(
      sourcePath: source.sourcePath,
      relativePath: storedPath,
    );

    try {
      await attachmentRepository.insert(attachment);
    } catch (_) {
      await storage.delete(storedPath);
      rethrow;
    }
    return attachment;
  }

  Future<void> removeAttachment(String attachmentId) async {
    final attachment = await attachmentRepository.getById(attachmentId);
    if (attachment == null) {
      return;
    }
    await attachmentRepository.delete(attachment.id);
    await deleteManagedFilesBestEffort([attachment]);
  }

  Future<void> removeAttachmentsForParent(
    AttachmentParentType parentType,
    String parentId,
  ) async {
    final attachments = await attachmentRepository.listForParent(
      parentType,
      parentId,
    );
    if (attachments.isEmpty) {
      return;
    }
    await database.transaction((txn) async {
      await attachmentRepository.deleteForParent(
        parentType,
        parentId,
        executor: txn,
      );
    });
    await deleteManagedFilesBestEffort(attachments);
  }

  Future<bool> attachmentFileExists(Attachment attachment) {
    return storage.exists(attachment.storedPath);
  }

  Future<AttachmentOpenResult> openAttachment(Attachment attachment) async {
    if (!await attachmentFileExists(attachment)) {
      return const AttachmentOpenResult(
        AttachmentOpenStatus.missing,
        'File unavailable',
      );
    }
    return opener.openAttachment(
      absolutePath: await storage.resolveAbsolutePath(attachment.storedPath),
      mimeType: attachment.mimeType,
    );
  }

  Future<void> deleteManagedFilesBestEffort(
    List<Attachment> attachments,
  ) async {
    for (final attachment in attachments) {
      try {
        await storage.delete(attachment.storedPath);
      } catch (_) {
        // Metadata has already been removed; a future storage audit can retry.
      }
    }
  }

  String _displayFileName(String value) {
    final cleaned = value
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'[\u0000-\u001F]'), '')
        .trim();
    return cleaned.isEmpty ? 'Attachment' : cleaned;
  }

  String _extensionFor(String fileName, String sourcePath, String? mimeType) {
    final fromName = p.extension(fileName).replaceFirst('.', '').toLowerCase();
    if (fromName.isNotEmpty) {
      return fromName;
    }
    final fromPath = p
        .extension(sourcePath)
        .replaceFirst('.', '')
        .toLowerCase();
    if (fromPath.isNotEmpty) {
      return fromPath;
    }
    return switch (mimeType) {
      'application/pdf' => 'pdf',
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      _ => '',
    };
  }

  String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
  }
}
