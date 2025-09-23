import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/in_memory_coalition_repository.dart';
import '../../auth/data/auth_controller.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../candidates/domain/candidate.dart';
import '../../events/data/event_providers.dart';
import '../../events/domain/event.dart';
import '../../profile/data/candidate_account_request_controller.dart';
import '../../profile/domain/candidate_account_request.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  static const routeName = 'admin';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final candidates = ref.watch(candidateListProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <Candidate>[],
        );
    final events = ref.watch(eventsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <CoalitionEvent>[],
        );
    final requestsAsync = ref.watch(candidateAccountRequestControllerProvider);
    final candidateRequests = requestsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <CandidateAccountRequest>[],
    );
    final pendingRequestCount = candidateRequests
        .where((request) => request.status == CandidateAccountRequestStatus.pending)
        .length;

    if (user == null || !user.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Admin access required.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Coalition admin'),
            Text(
              'Signed in as ${user.displayName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _AdminStatsCard(
              candidateCount: candidates.length,
              eventCount: events.length,
              pendingRequestCount: pendingRequestCount,
            ),
            const SizedBox(height: 20),
            _CandidateAccountRequestsCard(
              requests: candidateRequests,
              isLoading: requestsAsync.isLoading,
            ),
            const SizedBox(height: 20),
            _CandidateFormCard(),
            const SizedBox(height: 20),
            _EventFormCard(candidates: candidates),
            const SizedBox(height: 20),
            _RsvpOverviewCard(),
          ],
        ),
      ),
    );
  }
}

class _AdminStatsCard extends StatelessWidget {
  const _AdminStatsCard({
    required this.candidateCount,
    required this.eventCount,
    required this.pendingRequestCount,
  });

  final int candidateCount;
  final int eventCount;
  final int pendingRequestCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            _StatTile(label: 'Candidates', value: candidateCount.toString()),
            const SizedBox(width: 20),
            _StatTile(label: 'Upcoming events', value: eventCount.toString()),
            const SizedBox(width: 20),
            _StatTile(
              label: 'Pending requests',
              value: pendingRequestCount.toString(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(label),
        ],
      ),
    );
  }
}

class _CandidateAccountRequestsCard extends ConsumerWidget {
  const _CandidateAccountRequestsCard({
    required this.requests,
    required this.isLoading,
  });

  final List<CandidateAccountRequest> requests;
  final bool isLoading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pending = requests
        .where((request) => request.status == CandidateAccountRequestStatus.pending)
        .toList()
      ..sort((a, b) => a.submittedAt.compareTo(b.submittedAt));
    final reviewed = requests
        .where((request) => request.status != CandidateAccountRequestStatus.pending)
        .toList()
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Candidate account requests',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (pending.isEmpty && reviewed.isEmpty)
              Text(
                'No candidate upgrade requests yet.',
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              if (pending.isNotEmpty) ...[
                Text(
                  'Pending',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < pending.length; i++) ...[
                  _PendingRequestTile(request: pending[i]),
                  if (i != pending.length - 1) const Divider(height: 24),
                ],
              ]
              else ...[
                Text(
                  'No pending requests right now.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
              ],
              if (reviewed.isNotEmpty) ...[
                Text(
                  'Recently reviewed',
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                for (final request in reviewed.take(5))
                  _ReviewedRequestTile(request: request),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingRequestTile extends ConsumerWidget {
  const _PendingRequestTile({required this.request});

  final CandidateAccountRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.fullName,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${request.email} • ${request.phone}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          request.campaignAddress,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          'FEC: ${request.fecNumber}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              onPressed: () => _reviewRequest(
                context,
                ref,
                request,
                CandidateAccountRequestStatus.denied,
              ),
              child: const Text('Deny'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => _reviewRequest(
                context,
                ref,
                request,
                CandidateAccountRequestStatus.approved,
              ),
              child: const Text('Approve'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _reviewRequest(
    BuildContext context,
    WidgetRef ref,
    CandidateAccountRequest request,
    CandidateAccountRequestStatus status,
  ) async {
    try {
      final reviewerId = ref.read(authControllerProvider).user?.id;
      await ref
          .read(candidateAccountRequestControllerProvider.notifier)
          .reviewRequest(
            requestId: request.id,
            status: status,
            reviewerId: reviewerId,
          );
      if (!context.mounted) {
        return;
      }
      final message = status == CandidateAccountRequestStatus.approved
          ? 'Approved ${request.fullName}.'
          : 'Marked ${request.fullName} as not approved.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not update that request. Please try again.'),
        ),
      );
    }
  }
}

class _ReviewedRequestTile extends StatelessWidget {
  const _ReviewedRequestTile({required this.request});

  final CandidateAccountRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = request.status;
    final reviewedOn = request.reviewedAt ?? request.submittedAt;
    final color = status == CandidateAccountRequestStatus.approved
        ? Colors.green
        : Colors.redAccent;
    final label = status == CandidateAccountRequestStatus.approved ? 'Approved' : 'Denied';

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(request.fullName),
      subtitle: Text('Reviewed ${_formatFullDate(reviewedOn)}'),
      trailing: Chip(
        label: Text(label),
        backgroundColor: color.withValues(alpha: 0.15),
        labelStyle: theme.textTheme.labelSmall?.copyWith(color: color),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
      ),
    );
  }
}

String _formatFullDate(DateTime date) {
  final weekday = _weekdayNames[date.weekday - 1];
  final month = _monthNames[date.month - 1];
  return '$weekday, $month ${date.day}';
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

class _CandidateFormCard extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CandidateFormCard> createState() => _CandidateFormCardState();
}

class _CandidateFormCardState extends ConsumerState<_CandidateFormCard> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _level = 'state';
  final _regionController = TextEditingController();
  final _bioController = TextEditingController();
  final _tagsController = TextEditingController();
  final _websiteController = TextEditingController();
  final _headshotController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _regionController.dispose();
    _bioController.dispose();
    _tagsController.dispose();
    _websiteController.dispose();
    _headshotController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(coalitionRepositoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add or update candidate',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full name'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_level),
                initialValue: _level,
                decoration: const InputDecoration(labelText: 'Level of office'),
                items: const [
                  DropdownMenuItem(value: 'federal', child: Text('Federal')),
                  DropdownMenuItem(value: 'state', child: Text('State')),
                  DropdownMenuItem(value: 'county', child: Text('County')),
                  DropdownMenuItem(value: 'city', child: Text('City')),
                ],
                onChanged: (value) => setState(() => _level = value ?? 'state'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _regionController,
                decoration: const InputDecoration(labelText: 'Region / district'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bioController,
                decoration: const InputDecoration(labelText: 'Short bio'),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _websiteController,
                decoration: const InputDecoration(labelText: 'Website URL'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _headshotController,
                decoration: const InputDecoration(labelText: 'Headshot URL'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final tags = _tagsController.text
                        .split(',')
                        .map((tag) => tag.trim())
                        .where((tag) => tag.isNotEmpty)
                        .toList();
                    final candidate = Candidate(
                      id: const Uuid().v4(),
                      name: _nameController.text,
                      level: _level,
                      region: _regionController.text,
                      bio: _bioController.text,
                      tags: tags,
                      websiteUrl: _websiteController.text.isEmpty
                          ? null
                          : _websiteController.text,
                      headshotUrl: _headshotController.text.isEmpty
                          ? null
                          : _headshotController.text,
                    );
                    await repository.addOrUpdateCandidate(candidate);
                    if (!mounted) return;
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('${candidate.name} added to directory.')),
                    );
                    _formKey.currentState!.reset();
                  },
                  child: const Text('Save candidate'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventFormCard extends ConsumerStatefulWidget {
  const _EventFormCard({required this.candidates});

  final List<Candidate> candidates;

  @override
  ConsumerState<_EventFormCard> createState() => _EventFormCardState();
}

class _EventFormCardState extends ConsumerState<_EventFormCard> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _costController = TextEditingController(text: 'Free');
  final _tagsController = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  final Set<String> _selectedCandidateIds = <String>{};
  String _eventType = 'general';
  final List<_EventTimeSlotInput> _timeSlots = <_EventTimeSlotInput>[
    _EventTimeSlotInput(),
  ];

  static const _eventTypes = <String, String>{
    'general': 'Community gathering',
    'organizing': 'Organizing & field',
    'town-hall': 'Town hall / forum',
    'fundraiser': 'Fundraiser',
    'training': 'Training / workshop',
  };

  void _addTimeSlot() {
    setState(() {
      _timeSlots.add(_EventTimeSlotInput());
    });
  }

  void _removeTimeSlotAt(int index) {
    if (_timeSlots.length <= 1) return;
    final removed = _timeSlots.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  List<Widget> _buildTimeSlotFields(BuildContext context) {
    final widgets = <Widget>[];
    for (var index = 0; index < _timeSlots.length; index++) {
      final slot = _timeSlots[index];
      widgets.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: slot.labelController,
                decoration: InputDecoration(
                  labelText: 'Time slot ${index + 1} label',
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextFormField(
                controller: slot.capacityController,
                decoration: const InputDecoration(labelText: 'Capacity'),
                keyboardType: TextInputType.number,
              ),
            ),
            if (_timeSlots.length > 1)
              IconButton(
                onPressed: () => _removeTimeSlotAt(index),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove slot',
              ),
          ],
        ),
      );
      if (index != _timeSlots.length - 1) {
        widgets.add(const SizedBox(height: 8));
      }
    }
    return widgets;
  }

  List<EventTimeSlot> _collectTimeSlots() {
    final slots = <EventTimeSlot>[];
    for (final slot in _timeSlots) {
      final label = slot.labelController.text.trim();
      if (label.isEmpty) continue;
      final capacityText = slot.capacityController.text.trim();
      final capacity = capacityText.isEmpty ? null : int.tryParse(capacityText);
      slots.add(
        EventTimeSlot(
          id: const Uuid().v4(),
          label: label,
          capacity: capacity,
        ),
      );
    }
    if (slots.isEmpty) {
      slots.add(
        EventTimeSlot(
          id: const Uuid().v4(),
          label: 'Main session',
        ),
      );
    }
    return slots;
  }

  void _resetTimeSlotInputs() {
    for (final slot in _timeSlots) {
      slot.dispose();
    }
    _timeSlots
      ..clear()
      ..add(_EventTimeSlotInput());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _costController.dispose();
    _tagsController.dispose();
    for (final slot in _timeSlots) {
      slot.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.watch(coalitionRepositoryProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add event', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Event title'),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_eventType),
                initialValue: _eventType,
                decoration: const InputDecoration(labelText: 'Event type'),
                items: [
                  for (final entry in _eventTypes.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _eventType = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(labelText: 'Cost'),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month),
                title: Text('Event date: ${_date.toLocal().toString().split(' ').first}'),
                trailing: TextButton(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      setState(() => _date = picked);
                    }
                  },
                  child: const Text('Change'),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final candidate in widget.candidates)
                    FilterChip(
                      label: Text(candidate.name),
                      selected: _selectedCandidateIds.contains(candidate.id),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedCandidateIds.add(candidate.id);
                          } else {
                            _selectedCandidateIds.remove(candidate.id);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tagsController,
                decoration:
                    const InputDecoration(labelText: 'Tags (comma separated)'),
              ),
              const SizedBox(height: 12),
              Text(
                'Time slots',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ..._buildTimeSlotFields(context),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addTimeSlot,
                  icon: const Icon(Icons.add),
                  label: const Text('Add time slot'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Leave capacity blank for unlimited RSVPs.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    if (!_formKey.currentState!.validate()) return;
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    final tags = _tagsController.text
                        .split(',')
                        .map((tag) => tag.trim())
                        .where((tag) => tag.isNotEmpty)
                        .toList();
                    final timeSlots = _collectTimeSlots();
                    final event = CoalitionEvent(
                      id: const Uuid().v4(),
                      title: _titleController.text,
                      description: _descriptionController.text,
                      startDate: _date,
                      location: _locationController.text,
                      type: _eventType,
                      cost: _costController.text.isEmpty
                          ? 'Free'
                          : _costController.text,
                      hostCandidateIds: _selectedCandidateIds.toList(),
                      tags: tags,
                      timeSlots: timeSlots,
                    );
                    await repository.addOrUpdateEvent(event);
                    if (!mounted) return;
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('Event "${event.title}" saved.')),
                    );
                    _formKey.currentState!.reset();
                    setState(() {
                      _selectedCandidateIds.clear();
                      _date = DateTime.now().add(const Duration(days: 7));
                      _eventType = 'general';
                      _resetTimeSlotInputs();
                    });
                    _costController.text = 'Free';
                  },
                  child: const Text('Save event'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventTimeSlotInput {
  _EventTimeSlotInput({String? label, String? capacity})
      : labelController = TextEditingController(text: label ?? ''),
        capacityController = TextEditingController(text: capacity ?? '');

  final TextEditingController labelController;
  final TextEditingController capacityController;

  void dispose() {
    labelController.dispose();
    capacityController.dispose();
  }
}

class _RsvpOverviewCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final events = ref.watch(eventsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <CoalitionEvent>[],
        );

    final attendeeCount = user == null ? 0 : user.rsvpEventIds.length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Event attendance snapshot',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (attendeeCount == 0)
              Text(
                'RSVP data will appear here as supporters sign up for events.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              ...events
                  .where((event) => user!.rsvpEventIds.contains(event.id))
                  .map(
                    (event) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(event.title),
                      subtitle: Text(event.location),
                    ),
                  ),
            const SizedBox(height: 12),
            Text(
              'Connect this screen to your campaign CRM or Airtable base to manage full supporter lists.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
