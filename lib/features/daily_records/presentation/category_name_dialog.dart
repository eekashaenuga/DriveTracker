import 'package:flutter/material.dart';

Future<String?> showCategoryNameDialog(
  BuildContext context, {
  required String title,
  required Iterable<String> existingNames,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _CategoryNameDialog(title: title, existingNames: existingNames),
  );
}

class _CategoryNameDialog extends StatefulWidget {
  _CategoryNameDialog({
    required this.title,
    required Iterable<String> existingNames,
  }) : normalizedExistingNames = existingNames
           .map(_normalizeCategoryName)
           .toSet();

  final String title;
  final Set<String> normalizedExistingNames;

  @override
  State<_CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const Key('categoryNameField'),
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Name'),
          validator: _validateName,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cancelCategoryButton'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('addCategoryButton'),
          onPressed: _submit,
          child: const Text('Add'),
        ),
      ],
    );
  }

  String? _validateName(String? value) {
    final cleanName = (value ?? '').trim();
    if (cleanName.isEmpty) {
      return 'Category name is required.';
    }
    if (widget.normalizedExistingNames.contains(
      _normalizeCategoryName(cleanName),
    )) {
      return 'A category named "$cleanName" already exists.';
    }
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    Navigator.of(context).pop(_controller.text.trim());
  }
}

String _normalizeCategoryName(String value) => value.trim().toLowerCase();
