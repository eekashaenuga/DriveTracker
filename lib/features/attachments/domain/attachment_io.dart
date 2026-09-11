import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'attachment.dart';

abstract class AttachmentPicker {
  Future<AttachmentSource?> pickAttachment();
}

abstract class AttachmentOpener {
  Future<AttachmentOpenResult> openAttachment({
    required String absolutePath,
    required String? mimeType,
  });
}

abstract class AttachmentStorage {
  Future<Directory> managedRootDirectory();

  Future<void> copyIntoManagedStorage({
    required String sourcePath,
    required String relativePath,
  });

  Future<bool> exists(String relativePath);
  Future<void> delete(String relativePath);
  Future<String> resolveAbsolutePath(String relativePath);
}

class PlatformAttachmentPicker implements AttachmentPicker {
  const PlatformAttachmentPicker({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  static const _channelName = 'drivetracker/attachments';

  @override
  Future<AttachmentSource?> pickAttachment() async {
    try {
      final result = await _channel.invokeMapMethod<String, Object?>(
        'pickAttachment',
      );
      if (result == null) {
        return null;
      }
      final path = result['path'] as String?;
      final name = result['fileName'] as String?;
      if (path == null || name == null) {
        return null;
      }
      return AttachmentSource(
        sourcePath: path,
        fileName: name,
        mimeType: result['mimeType'] as String?,
        fileSize: result['fileSize'] as int?,
      );
    } on MissingPluginException {
      throw const FileSystemException('File picker is unavailable.');
    }
  }
}

class PlatformAttachmentOpener implements AttachmentOpener {
  const PlatformAttachmentOpener({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final MethodChannel _channel;

  static const _channelName = 'drivetracker/attachments';

  @override
  Future<AttachmentOpenResult> openAttachment({
    required String absolutePath,
    required String? mimeType,
  }) async {
    try {
      final opened = await _channel.invokeMethod<bool>('openAttachment', {
        'path': absolutePath,
        'mimeType': mimeType,
      });
      if (opened == true) {
        return const AttachmentOpenResult(AttachmentOpenStatus.opened);
      }
      return const AttachmentOpenResult(
        AttachmentOpenStatus.failed,
        'No compatible viewer was available.',
      );
    } on MissingPluginException {
      return const AttachmentOpenResult(
        AttachmentOpenStatus.unavailable,
        'File opening is unavailable on this platform.',
      );
    } on PlatformException catch (error) {
      return AttachmentOpenResult(
        AttachmentOpenStatus.failed,
        error.message ?? 'Could not open attachment.',
      );
    }
  }
}

class ManagedAttachmentStorage implements AttachmentStorage {
  ManagedAttachmentStorage({this.rootDirectory, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(_channelName);

  final Future<Directory> Function()? rootDirectory;
  final MethodChannel _channel;
  Directory? _cachedRoot;

  static const _channelName = 'drivetracker/attachments';

  @override
  Future<Directory> managedRootDirectory() => _managedRoot();

  @override
  Future<void> copyIntoManagedStorage({
    required String sourcePath,
    required String relativePath,
  }) async {
    final target = File(await resolveAbsolutePath(relativePath));
    await target.parent.create(recursive: true);
    final source = File(sourcePath);
    await source.copy(target.path);
  }

  @override
  Future<void> delete(String relativePath) async {
    final file = File(await resolveAbsolutePath(relativePath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<bool> exists(String relativePath) async {
    return File(await resolveAbsolutePath(relativePath)).exists();
  }

  @override
  Future<String> resolveAbsolutePath(String relativePath) async {
    final root = await _managedRoot();
    final normalized = _safeRelativePath(relativePath);
    final resolved = p.normalize(p.join(root.path, normalized));
    final rootPath = p.normalize(root.path);
    if (resolved != rootPath && !p.isWithin(rootPath, resolved)) {
      throw const FileSystemException(
        'Attachment path is outside app storage.',
      );
    }
    return resolved;
  }

  Future<Directory> _managedRoot() async {
    final cached = _cachedRoot;
    if (cached != null) {
      return cached;
    }
    final rootProvider = rootDirectory;
    final root = rootProvider == null
        ? await _platformRootDirectory()
        : await rootProvider();
    await root.create(recursive: true);
    _cachedRoot = root;
    return root;
  }

  Future<Directory> _platformRootDirectory() async {
    final root = await _channel.invokeMethod<String>('managedRoot');
    if (root == null || root.trim().isEmpty) {
      throw const FileSystemException('Attachment storage is unavailable.');
    }
    return Directory(root);
  }

  String _safeRelativePath(String relativePath) {
    final normalized = p.posix.normalize(relativePath.replaceAll('\\', '/'));
    if (normalized == '.' ||
        normalized.startsWith('../') ||
        normalized == '..' ||
        p.isAbsolute(normalized)) {
      throw const FileSystemException('Invalid attachment path.');
    }
    return normalized;
  }
}
