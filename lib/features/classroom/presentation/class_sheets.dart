import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/form_error.dart';
import '../application/classroom_controller.dart';
import '../data/classroom_models.dart';
import 'classroom_palette.dart';

/// Opens the "create a class" sheet. Resolves once it closes.
Future<void> showCreateClassSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _CreateClassSheet(),
  );
}

/// Opens the "join a class" sheet.
Future<void> showJoinClassSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _JoinClassSheet(),
  );
}

/// Padding that lifts sheet content above the keyboard.
EdgeInsets _sheetPadding(BuildContext context) => EdgeInsets.fromLTRB(
      20,
      0,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    );

class _CreateClassSheet extends ConsumerStatefulWidget {
  const _CreateClassSheet();

  @override
  ConsumerState<_CreateClassSheet> createState() => _CreateClassSheetState();
}

class _CreateClassSheetState extends ConsumerState<_CreateClassSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _sectionController = TextEditingController();

  ClassroomType _type = ClassroomType.personal;
  String _themeColor = ClassroomPalette.themeColors.first;
  bool _isSubmitting = false;
  String? _formError;

  @override
  void dispose() {
    _nameController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      await ref.read(classroomListProvider.notifier).create(
            name: _nameController.text.trim(),
            section: _sectionController.text.trim(),
            type: _type,
            themeColor: _themeColor,
          );
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: _sheetPadding(context),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Create a class', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'You will be the owner. Share the join code with your students.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_formError != null) ...[
              FormError(message: _formError!),
              const SizedBox(height: 16),
            ],
            AppTextField(
              controller: _nameController,
              label: 'Class name',
              hintText: 'Discrete Mathematics',
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value?.trim().isEmpty ?? true) ? 'Enter a class name' : null,
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _sectionController,
              label: 'Section',
              hintText: 'Optional — e.g. B, Semester 4',
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 20),
            Text('Visibility', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<ClassroomType>(
              segments: const [
                ButtonSegment(
                  value: ClassroomType.personal,
                  label: Text('Private'),
                ),
                ButtonSegment(
                  value: ClassroomType.public,
                  label: Text('Public'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 20),
            Text('Card colour', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final color in ClassroomPalette.themeColors)
                  GestureDetector(
                    onTap: () => setState(() => _themeColor = color),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: ClassroomPalette.gradientFor(color),
                        borderRadius: BorderRadius.circular(10),
                        border: _themeColor == color
                            ? Border.all(
                                color: theme.colorScheme.onSurface,
                                width: 3,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            AppButton(
              label: 'Create',
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinClassSheet extends ConsumerStatefulWidget {
  const _JoinClassSheet();

  @override
  ConsumerState<_JoinClassSheet> createState() => _JoinClassSheetState();
}

class _JoinClassSheetState extends ConsumerState<_JoinClassSheet> {
  static const _codeLength = 6;

  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  bool _isSubmitting = false;
  String? _formError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _formError = null;
    });

    try {
      await ref
          .read(classroomListProvider.notifier)
          .join(_codeController.text.trim());
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: _sheetPadding(context),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Join a class', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Enter the $_codeLength-character code your teacher shared.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_formError != null) ...[
              FormError(message: _formError!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _codeController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              maxLength: _codeLength,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                letterSpacing: 8,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                // Uppercase as the user types, so what they see matches what
                // the backend stores.
                TextInputFormatter.withFunction(
                  (_, newValue) => newValue.copyWith(
                    text: newValue.text.toUpperCase(),
                  ),
                ),
              ],
              decoration: InputDecoration(
                labelText: 'Class code',
                hintText: 'A1B2C3',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator: (value) {
                final code = value?.trim() ?? '';
                if (code.length != _codeLength) {
                  return 'Class codes are $_codeLength characters';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 20),
            AppButton(
              label: 'Join',
              isLoading: _isSubmitting,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
