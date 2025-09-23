import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';

class EditProfileSheet extends ConsumerStatefulWidget {
  const EditProfileSheet({required this.user, super.key});

  final AppUser user;

  @override
  ConsumerState<EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<EditProfileSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _firstNameController = TextEditingController(text: user.firstName);
    _lastNameController = TextEditingController(text: user.lastName);
    _usernameController = TextEditingController(text: user.username);
    _bioController = TextEditingController(text: user.bio);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Edit profile',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(labelText: 'First name'),
                      textCapitalization: TextCapitalization.words,
                      validator: _requiredValidator,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(labelText: 'Last name'),
                      textCapitalization: TextCapitalization.words,
                      validator: _requiredValidator,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _usernameController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixText: '@',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(
                  labelText: 'About me',
                  helperText: 'Keep it short—this appears on your profile.',
                ),
                maxLength: 140,
                minLines: 3,
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _submit,
                  child: Text(_saving ? 'Saving...' : 'Save changes'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    final trimmedFirst = _firstNameController.text.trim();
    final trimmedLast = _lastNameController.text.trim();
    final trimmedUsername = _usernameController.text.trim();
    final trimmedBio = _bioController.text.trim();
    final usernameChanged =
        trimmedUsername.toLowerCase() != widget.user.username.toLowerCase();

    if (usernameChanged) {
      final proceed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Update username?'),
              content: const Text(
                'Usernames can only be changed once every 30 days. Are you sure you want to continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ) ??
          false;
      if (!proceed) {
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final controller = ref.read(authControllerProvider.notifier);
      final error = await controller.updateProfileDetails(
        firstName: trimmedFirst,
        lastName: trimmedLast,
        username: trimmedUsername,
        bio: trimmedBio,
      );
      if (!mounted) return;
      if (error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
        return;
      }
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated.')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  static String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}
