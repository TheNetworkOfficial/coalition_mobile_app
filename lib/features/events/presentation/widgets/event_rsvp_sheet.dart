import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/in_memory_coalition_repository.dart';
import '../../../auth/data/auth_controller.dart';
import '../../../auth/domain/app_user.dart';
import '../../domain/event.dart';

Future<void> showEventRsvpSheet({
  required BuildContext context,
  required WidgetRef ref,
  required CoalitionEvent event,
}) async {
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: EventRsvpSheet(event: event),
    ),
  );
}

class EventRsvpSheet extends ConsumerStatefulWidget {
  const EventRsvpSheet({required this.event, super.key});

  final CoalitionEvent event;

  @override
  ConsumerState<EventRsvpSheet> createState() => _EventRsvpSheetState();
}

class _EventRsvpSheetState extends ConsumerState<EventRsvpSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _zipController;
  final Set<String> _selectedSlotIds = <String>{};
  bool _submitting = false;
  String? _errorMessage;
  bool _success = false;
  late final AnimationController _successAnimationController;

  AppUser? get _user => ref.read(authControllerProvider).user;

  @override
  void initState() {
    super.initState();
    final user = _user;
    _firstNameController = TextEditingController(text: user?.firstName ?? '');
    _lastNameController = TextEditingController(text: user?.lastName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController();
    _zipController = TextEditingController(text: user?.zipCode ?? '');
    if (widget.event.timeSlots.length == 1) {
      final slot = widget.event.timeSlots.first;
      final remaining = slot.remainingCapacity;
      if (remaining == null || remaining > 0) {
        _selectedSlotIds.add(slot.id);
      }
    }
    _successAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _zipController.dispose();
    _successAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          children: [
            Opacity(
              opacity: _success ? 0 : 1,
              child: IgnorePointer(
                ignoring: _success,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RSVP for ${widget.event.title}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Share your details so the field team can reach you with any updates.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _firstNameController,
                                decoration:
                                    const InputDecoration(labelText: 'First name'),
                                validator: _requiredValidator,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _lastNameController,
                                decoration:
                                    const InputDecoration(labelText: 'Last name'),
                                validator: _requiredValidator,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _emailController,
                          decoration: const InputDecoration(labelText: 'Email'),
                          keyboardType: TextInputType.emailAddress,
                          validator: _emailValidator,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _phoneController,
                          decoration: const InputDecoration(labelText: 'Phone'),
                          keyboardType: TextInputType.phone,
                          validator: _requiredValidator,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _zipController,
                          decoration: const InputDecoration(labelText: 'ZIP code'),
                          keyboardType: TextInputType.number,
                          validator: _requiredValidator,
                        ),
                        const SizedBox(height: 20),
                        _TimeSlotSelector(
                          event: widget.event,
                          selectedIds: _selectedSlotIds,
                          onSelectionChanged: (id, selected) {
                            setState(() {
                              if (selected) {
                                _selectedSlotIds.add(id);
                              } else {
                                _selectedSlotIds.remove(id);
                              }
                            });
                          },
                        ),
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _errorMessage!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _submitting ? null : _handleSubmit,
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Confirm'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_success)
              Positioned.fill(
                child: _SuccessAnimation(controller: _successAnimationController),
              ),
          ],
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    return null;
  }

  String? _emailValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Required';
    }
    final email = value.trim();
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      return 'Enter a valid email.';
    }
    return null;
  }

  Future<void> _handleSubmit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedSlotIds.isEmpty) {
      setState(() {
        _errorMessage = 'Choose at least one time slot to RSVP.';
      });
      return;
    }
    final user = _user;
    if (user == null) {
      setState(() {
        _errorMessage = 'Sign in to RSVP for this event.';
      });
      return;
    }
    setState(() {
      _errorMessage = null;
      _submitting = true;
    });

    final repository = ref.read(coalitionRepositoryProvider);
    final submission = EventRsvpSubmission(
      eventId: widget.event.id,
      userId: user.id,
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      email: _emailController.text.trim(),
      phone: _phoneController.text.trim(),
      zipCode: _zipController.text.trim(),
      selectedSlotIds: _selectedSlotIds.toList(),
    );

    try {
      await repository.submitEventRsvp(submission);
      await ref
          .read(authControllerProvider.notifier)
          .recordEventRsvp(eventId: widget.event.id, slotIds: submission.selectedSlotIds);
      setState(() {
        _success = true;
      });
      _successAnimationController.forward(from: 0);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      setState(() {
        _errorMessage = error is StateError
            ? error.message
            : 'Something went wrong. Please contact support if this continues.';
        _submitting = false;
      });
    }
  }
}

class _TimeSlotSelector extends StatelessWidget {
  const _TimeSlotSelector({
    required this.event,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  final CoalitionEvent event;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (event.timeSlots.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Event coordinator has not added specific time slots yet.',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Available time slots',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final slot in event.timeSlots)
          _TimeSlotTile(
            slot: slot,
            selected: selectedIds.contains(slot.id),
            onChanged: (selected) => onSelectionChanged(slot.id, selected),
          ),
      ],
    );
  }
}

class _TimeSlotTile extends StatelessWidget {
  const _TimeSlotTile({
    required this.slot,
    required this.selected,
    required this.onChanged,
  });

  final EventTimeSlot slot;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final remaining = slot.remainingCapacity;
    final isFull = remaining != null && remaining <= 0 && !selected;
    final subtitleText = remaining == null
        ? 'Open capacity'
        : remaining > 0
            ? '$remaining spot${remaining == 1 ? '' : 's'} left'
            : 'Full';
    return CheckboxListTile(
      value: selected && !isFull,
      onChanged: isFull ? null : (value) => onChanged(value ?? false),
      title: Text(slot.label),
      subtitle: Text(subtitleText),
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}

class _SuccessAnimation extends StatelessWidget {
  const _SuccessAnimation({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final progress = controller.value.clamp(0.0, 1.0);
        return ClipPath(
          clipper: _WipeClipper(progress: progress),
          child: Container(
            color: colorScheme.primary,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            child: Icon(
              Icons.check_circle,
              size: 72,
              color: colorScheme.onPrimary,
            ),
          ),
        );
      },
    );
  }
}

class _WipeClipper extends CustomClipper<Path> {
  _WipeClipper({required this.progress});

  final double progress;

  @override
  Path getClip(Size size) {
    final width = size.width * progress;
    return Path()..addRect(Rect.fromLTWH(0, 0, width, size.height));
  }

  @override
  bool shouldReclip(covariant _WipeClipper oldClipper) =>
      oldClipper.progress != progress;
}
