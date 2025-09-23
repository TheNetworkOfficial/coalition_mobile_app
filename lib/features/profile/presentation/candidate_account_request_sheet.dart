import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../data/candidate_account_request_controller.dart';
import '../domain/candidate_account_request.dart';

class CandidateAccountRequestSheet extends ConsumerStatefulWidget {
  const CandidateAccountRequestSheet({super.key});

  @override
  ConsumerState<CandidateAccountRequestSheet> createState() =>
      _CandidateAccountRequestSheetState();
}

class _CandidateAccountRequestSheetState
    extends ConsumerState<CandidateAccountRequestSheet>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _fecController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    if (user != null) {
      final displayName = user.displayName.trim();
      if (displayName.isNotEmpty) {
        _nameController.text = displayName;
      }
      _emailController.text = user.email;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _fecController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).user;
    final requestState = ref.watch(candidateAccountRequestControllerProvider);
    final requests = requestState.maybeWhen(
      data: (value) => value,
      orElse: () => const <CandidateAccountRequest>[],
    );
    final latest =
        user == null ? null : _latestForUser(requests, user.id);
    final hasPending =
        user == null ? false : _hasPending(requests, user.id);
    final isCandidate = user?.accountType == UserAccountType.candidate;
    final bool canSubmit =
        !hasPending && user != null && !isCandidate && !_submitting;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request candidate account',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Share your campaign details and our team will verify and migrate your account.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (requestState.isLoading)
              const LinearProgressIndicator(minHeight: 2),
            if (isCandidate)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: const _InfoBanner(
                  icon: Icons.check_circle_outlined,
                  iconColor: Colors.green,
                  message:
                      'You are already using a candidate account. There is no need to submit a new request.',
                ),
              )
            else if (hasPending && latest != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _InfoBanner(
                  icon: Icons.hourglass_bottom,
                  iconColor: Colors.orange,
                  message:
                      'We received your request on ${_formatDate(latest.submittedAt)}. Our team will reach out soon.',
                ),
              )
            else if (latest != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: _InfoBanner(
                  icon: latest.status == CandidateAccountRequestStatus.denied
                      ? Icons.info_outline
                      : Icons.check_circle_outline,
                  iconColor:
                      latest.status == CandidateAccountRequestStatus.denied
                          ? Colors.redAccent
                          : Colors.green,
                  message: latest.status ==
                          CandidateAccountRequestStatus.denied
                      ? 'Your previous request was not approved. Update your campaign information and submit again when ready.'
                      : 'Your account was upgraded on ${_formatDate(latest.reviewedAt ?? latest.submittedAt)}.',
                ),
              ),
            if (!isCandidate) ...[
              const SizedBox(height: 16),
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Full legal name',
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                      ),
                      keyboardType: TextInputType.phone,
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Campaign email',
                      ),
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        final result = _requiredValidator(value);
                        if (result != null) return result;
                        final email = value!.trim();
                        final emailRegExp =
                            RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                        if (!emailRegExp.hasMatch(email)) {
                          return 'Enter a valid email address.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      decoration: const InputDecoration(
                        labelText: 'Registered campaign address',
                      ),
                      minLines: 2,
                      maxLines: 3,
                      keyboardType: TextInputType.streetAddress,
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fecController,
                      decoration: const InputDecoration(
                        labelText: 'FEC registration number',
                      ),
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: canSubmit ? () => _submit(user) : null,
                        icon: const Icon(Icons.send),
                        label: Text(_submitting
                            ? 'Submitting...'
                            : 'Submit request'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _submit(AppUser user) async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) {
      return;
    }

    setState(() => _submitting = true);
    try {
      await ref
          .read(candidateAccountRequestControllerProvider.notifier)
          .submitRequest(
            userId: user.id,
            fullName: _nameController.text.trim(),
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            campaignAddress: _addressController.text.trim(),
            fecNumber: _fecController.text.trim(),
          );
      if (!mounted || !context.mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const _SubmissionSuccessDialog(),
      );
      if (!mounted || !context.mounted) return;
      Navigator.of(context).pop();
    } on StateError catch (error) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (_) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'We could not submit your request. Please try again in a moment.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  static String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  static CandidateAccountRequest? _latestForUser(
    List<CandidateAccountRequest> requests,
    String userId,
  ) {
    CandidateAccountRequest? latest;
    for (final request in requests) {
      if (request.userId != userId) continue;
      if (latest == null ||
          request.submittedAt.isAfter(latest.submittedAt)) {
        latest = request;
      }
    }
    return latest;
  }

  static bool _hasPending(
    List<CandidateAccountRequest> requests,
    String userId,
  ) {
    return requests.any((request) =>
        request.userId == userId &&
        request.status == CandidateAccountRequestStatus.pending);
  }

  String _formatDate(DateTime date) {
    return '${_weekdayNames[date.weekday - 1]}, ${_monthNames[date.month - 1]} ${date.day}';
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.iconColor,
    required this.message,
  });

  final IconData icon;
  final Color iconColor;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmissionSuccessDialog extends StatefulWidget {
  const _SubmissionSuccessDialog();

  @override
  State<_SubmissionSuccessDialog> createState() =>
      _SubmissionSuccessDialogState();
}

class _SubmissionSuccessDialogState extends State<_SubmissionSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOutBack,
            ),
            child: Icon(
              Icons.check_circle,
              color: Theme.of(context).colorScheme.primary,
              size: 72,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Request submitted!',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'We\'ll be in touch within 5–7 business days.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

const _weekdayNames = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
