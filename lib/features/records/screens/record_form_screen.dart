import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/theme/app_theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/record_avatar.dart';
import '../../../data/models/gender.dart';
import '../../../data/models/personal_record.dart';
import '../../../data/models/sync_status.dart';
import '../../../data/providers/data_providers.dart';
import '../../settings/providers/settings_providers.dart';
import '../providers/records_providers.dart';

/// Create / edit form. Saves to SQLite first, then attempts a background sync.
class RecordFormScreen extends ConsumerStatefulWidget {
  const RecordFormScreen({super.key, this.existing});

  final PersonalRecord? existing;

  bool get isEditing => existing != null;

  @override
  ConsumerState<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends ConsumerState<RecordFormScreen> {
  static const _uuid = Uuid();

  final _formKey = GlobalKey<FormState>();

  late final String _recordId;
  late final TextEditingController _fullName;
  late final TextEditingController _fatherName;
  late final TextEditingController _motherName;
  late final TextEditingController _mobile;
  late final TextEditingController _email;
  late final TextEditingController _address;
  late final TextEditingController _dobText;

  DateTime? _dob;
  Gender _gender = Gender.other;
  String? _photoPath;
  bool _submitting = false;

  PersonalRecord? get existing => widget.existing;

  @override
  void initState() {
    super.initState();
    final record = existing;
    _recordId = record?.id ?? _uuid.v4();
    _fullName = TextEditingController(text: record?.fullName ?? '');
    _fatherName = TextEditingController(text: record?.fatherName ?? '');
    _motherName = TextEditingController(text: record?.motherName ?? '');
    _mobile = TextEditingController(text: record?.mobileNumber ?? '');
    _email = TextEditingController(text: record?.email ?? '');
    _address = TextEditingController(text: record?.address ?? '');
    _dob = record?.dateOfBirth;
    _dobText = TextEditingController(
      text: record == null ? '' : Formatters.date(record.dateOfBirth),
    );
    _gender = record?.gender ?? Gender.other;
    _photoPath = record?.photoPath;
  }

  @override
  void dispose() {
    _fullName.dispose();
    _fatherName.dispose();
    _motherName.dispose();
    _mobile.dispose();
    _email.dispose();
    _address.dispose();
    _dobText.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final photoService = ref.read(photoStorageServiceProvider);
      final picked = await photoService.pickImage();
      if (picked == null) return;
      final path = await photoService.persist(picked, _recordId);

      // Best-effort cleanup of the superseded photo, if any.
      final previous = _photoPath;
      setState(() => _photoPath = path);
      if (previous != null && previous != path) {
        await photoService.delete(previous);
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_safeMessage(e))));
    }
  }

  Future<void> _removePhoto() async {
    final approved = await ConfirmDialog.show(
      context,
      title: 'Remove profile photo?',
      message: 'The photo will be removed from this record.',
      confirmLabel: 'Remove',
      destructive: false,
    );
    if (!approved) return;
    await ref.read(photoStorageServiceProvider).delete(_photoPath);
    setState(() => _photoPath = null);
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dob ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900, 1, 1),
      lastDate: now,
      helpText: 'Select date of birth',
    );
    if (picked == null) return;
    setState(() {
      _dob = picked;
      _dobText.text = Formatters.date(picked);
    });
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) return;
    final dobError = Validators.dateOfBirth(_dob);
    if (dobError != null) {
      _dob = null;
      _dobText.clear();
      setState(() {});
      _formKey.currentState!.validate();
      messenger.showSnackBar(SnackBar(content: Text(dobError)));
      return;
    }

    setState(() => _submitting = true);

    final now = DateTime.now().toUtc();
    final record = PersonalRecord(
      id: _recordId,
      fullName: _fullName.text.trim(),
      fatherName: _fatherName.text.trim(),
      motherName: _motherName.text.trim(),
      mobileNumber: Validators.normaliseMobile(_mobile.text.trim()),
      email: _email.text.trim().toLowerCase(),
      address: _address.text.trim(),
      dateOfBirth: _dob!,
      gender: _gender,
      photoPath: _photoPath,
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      syncStatus: existing?.syncStatus ?? SyncStatus.pending,
    );

    try {
      final controller = ref.read(recordsProvider.notifier);
      await controller.save(record, isNew: existing == null);

      // Do not block the UI on connectivity; trigger a best-effort sync.
      final report = await ref
          .read(syncControllerProvider.notifier)
          .syncNow(auto: true);

      if (!mounted) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              existing == null
                  ? 'Record saved on this device.'
                  : 'Record updated on this device.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );

      if (report != null && report.hasIssues && mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Saved locally. Cloud sync has issues: ${report.message} '
              'It will retry automatically.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not save: ${_safeMessage(e)} Your changes are still on '
            'the form.',
          ),
        ),
      );
    }
  }

  String _safeMessage(Object error) {
    if (error is AppException) return error.userMessage;
    return 'Something went wrong. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'Add record' : 'Edit record'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            Center(child: _buildPhotoPicker(theme)),
            if (_photoPath != null)
              Center(
                child: TextButton.icon(
                  onPressed: _removePhoto,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Remove photo'),
                ),
              ),
            const SizedBox(height: AppSpacing.xl),
            AppTextField(
              label: 'Full name *',
              controller: _fullName,
              validator: Validators.fullName,
              prefixIcon: Icons.person_outline,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: "Father's name",
              controller: _fatherName,
              prefixIcon: Icons.man_outlined,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: "Mother's name",
              controller: _motherName,
              prefixIcon: Icons.woman_outlined,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Mobile number *',
              controller: _mobile,
              validator: Validators.mobile,
              keyboardType: TextInputType.phone,
              prefixIcon: Icons.phone_outlined,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Email *',
              controller: _email,
              validator: Validators.email,
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.mail_outline,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
            ),
            const SizedBox(height: AppSpacing.md),
            AppTextField(
              label: 'Full address *',
              controller: _address,
              validator: Validators.address,
              prefixIcon: Icons.location_on_outlined,
              keyboardType: TextInputType.multiline,
              maxLines: 3,
              textInputAction: TextInputAction.newline,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AppTextField(
                    label: 'Date of birth *',
                    controller: _dobText,
                    readOnly: true,
                    onTap: _pickDob,
                    validator: (_) {
                      if (_dob == null) {
                        return 'Date of birth is required';
                      }
                      return Validators.dateOfBirth(_dob);
                    },
                    prefixIcon: Icons.cake_outlined,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DropdownButtonFormField<Gender>(
                    initialValue: _gender,
                    decoration: const InputDecoration(
                      labelText: 'Gender',
                      prefixIcon: Icon(Icons.wc_outlined),
                    ),
                    items: [
                      for (final gender in Gender.values)
                        DropdownMenuItem(
                          value: gender,
                          child: Text(gender.label),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _gender = value);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),
            AppButton(
              label: existing == null ? 'Save record' : 'Save changes',
              icon: Icons.save_outlined,
              loading: _submitting,
              onPressed: _submitting ? null : _save,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Records are saved on your device and synced to Google Sheets '
              'when you are online.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPicker(ThemeData theme) {
    return Semantics(
      button: true,
      label: 'Change profile photo',
      child: InkWell(
        borderRadius: BorderRadius.circular(60),
        onTap: _pickPhoto,
        child: Stack(
          children: [
            RecordAvatar(
              name: _fullName.text.isEmpty ? '?' : _fullName.text,
              photoPath: _photoPath,
              radius: 52,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.camera_alt,
                  size: 16,
                  color: theme.colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
