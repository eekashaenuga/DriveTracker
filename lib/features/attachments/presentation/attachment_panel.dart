import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/app_controller.dart';
import '../../../app/theme/dt_tokens.dart';
import '../../../core/utilities/validation_exception.dart';
import '../../../shared/widgets/dt_empty_state.dart';
import '../domain/attachment.dart';

class AttachmentPanel extends StatefulWidget {
  const AttachmentPanel({
    required this.parentType,
    required this.parentId,
    this.compact = false,
    super.key,
  });

  final AttachmentParentType parentType;
  final String parentId;
  final bool compact;

  @override
  State<AttachmentPanel> createState() => _AttachmentPanelState();
}

class _AttachmentPanelState extends State<AttachmentPanel> {
  Future<List<Attachment>>? _attachmentsFuture;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _attachmentsFuture = _load();
  }

  @override
  void didUpdateWidget(covariant AttachmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentId != widget.parentId ||
        oldWidget.parentType != widget.parentType) {
      _attachmentsFuture = _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: DTRadii.cardRadius,
      child: Padding(
        padding: const EdgeInsets.all(DTSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_file_rounded, color: colors.primary),
                const SizedBox(width: DTSpacing.sm),
                Expanded(
                  child: Text(
                    'Attachments',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  key: Key('addAttachment_${widget.parentId}'),
                  tooltip: 'Add attachment',
                  onPressed: _addAttachment,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: DTSpacing.sm),
              Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.error,
                ),
              ),
            ],
            FutureBuilder<List<Attachment>>(
              future: _attachmentsFuture,
              builder: (context, snapshot) {
                final attachments = snapshot.data;
                if (attachments == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: DTSpacing.lg),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (attachments.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.only(top: DTSpacing.sm),
                    child: _AttachmentEmptyState(),
                  );
                }
                return Column(
                  children: [
                    const SizedBox(height: DTSpacing.sm),
                    for (final attachment in attachments)
                      _AttachmentTile(
                        key: Key('attachment_${attachment.id}'),
                        attachment: attachment,
                        onOpen: () => _openAttachment(attachment),
                        onRemove: () => _removeAttachment(attachment),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Attachment>> _load() {
    return context.read<DriveTrackerController>().attachmentsForParent(
      widget.parentType,
      widget.parentId,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() {
      _attachmentsFuture = future;
    });
    await future;
  }

  Future<void> _addAttachment() async {
    setState(() => _errorMessage = null);
    try {
      await context.read<DriveTrackerController>().pickAndAttach(
        parentType: widget.parentType,
        parentId: widget.parentId,
      );
      if (mounted) {
        await _refresh();
      }
    } on ValidationException catch (error) {
      if (mounted) {
        setState(() => _errorMessage = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not add attachment.');
      }
    }
  }

  Future<void> _openAttachment(Attachment attachment) async {
    final result = await context.read<DriveTrackerController>().openAttachment(
      attachment,
    );
    if (!mounted || result.opened) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message ?? 'Could not open attachment.')),
    );
    if (result.status == AttachmentOpenStatus.missing) {
      setState(() {});
    }
  }

  Future<void> _removeAttachment(Attachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: Text('Remove ${attachment.fileName} from this record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: Key('confirmRemoveAttachment_${attachment.id}'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await context.read<DriveTrackerController>().removeAttachment(
      attachment.id,
    );
    if (mounted) {
      await _refresh();
    }
  }
}

class _AttachmentEmptyState extends StatelessWidget {
  const _AttachmentEmptyState();

  @override
  Widget build(BuildContext context) {
    return const DTEmptyState(
      icon: Icons.upload_file_rounded,
      title: 'No attachments',
      body: 'Add PDFs or images when they help explain this record.',
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.onOpen,
    required this.onRemove,
    super.key,
  });

  final Attachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return FutureBuilder<bool>(
      future: context.read<DriveTrackerController>().attachmentFileExists(
        attachment,
      ),
      builder: (context, snapshot) {
        final exists = snapshot.data ?? true;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: colors.primaryContainer.withValues(alpha: 0.75),
            foregroundColor: colors.onPrimaryContainer,
            child: Icon(_iconFor(attachment)),
          ),
          title: Text(
            attachment.fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              _sizeLabel(attachment.fileSize),
              if (!exists) 'File unavailable',
            ].where((part) => part.isNotEmpty).join(' / '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: exists ? colors.onSurfaceVariant : colors.error,
            ),
          ),
          onTap: onOpen,
          trailing: Wrap(
            spacing: DTSpacing.xs,
            children: [
              IconButton(
                tooltip: 'Open ${attachment.fileName}',
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new_rounded),
              ),
              IconButton(
                tooltip: 'Remove ${attachment.fileName}',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _iconFor(Attachment attachment) {
    return switch (attachment.extension) {
      'pdf' => Icons.picture_as_pdf_rounded,
      'png' || 'jpg' || 'jpeg' => Icons.image_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  String _sizeLabel(int? bytes) {
    if (bytes == null) {
      return '';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 10 ? 1 : 2)} MB';
  }
}
