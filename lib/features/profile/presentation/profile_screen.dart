import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/in_memory_coalition_repository.dart';
import '../../auth/data/auth_controller.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../candidates/domain/candidate.dart';
import '../../events/data/event_providers.dart';
import '../../events/domain/event.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static const routeName = 'profile';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to access your profile.')),
      );
    }

    final candidates = ref.watch(candidateListProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <Candidate>[],
        );
    final events = ref.watch(eventsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <CoalitionEvent>[],
        );

    Future<void> cancelRsvp(String eventId) async {
      final userId = user.id;
      CoalitionEvent? targetEvent;
      for (final event in events) {
        if (event.id == eventId) {
          targetEvent = event;
          break;
        }
      }
      final title = targetEvent?.title ?? 'this event';
      final shouldCancel = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cancel RSVP'),
          content: Text('Cancel your RSVP for "$title"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep RSVP'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel RSVP'),
            ),
          ],
        ),
      );

      if (shouldCancel != true) return;

      try {
        await ref
            .read(coalitionRepositoryProvider)
            .cancelEventRsvp(eventId: eventId, userId: userId);
        await ref.read(authControllerProvider.notifier).cancelEventRsvp(eventId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSVP for "$title" cancelled.')),
        );
      } catch (error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : 'We could not cancel your RSVP. Please try again.',
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your account'),
        actions: [
          IconButton(
            onPressed: () {
              ref.read(authControllerProvider.notifier).signOut();
            },
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _ProfileHeader(
              userDisplayName: user.displayName,
              email: user.email,
              username: user.username,
            ),
            const SizedBox(height: 24),
            _FollowedCandidatesSection(
              candidates: candidates
                  .where((c) => user.followedCandidateIds.contains(c.id))
                  .toList(),
              onToggleFollow: (id) {
                ref
                    .read(authControllerProvider.notifier)
                    .toggleFollowCandidate(id);
              },
            ),
            const SizedBox(height: 24),
            _FollowedTagsSection(
              tags: user.followedTags.toList()..sort(),
              onUnfollow: (tag) {
                ref
                    .read(authControllerProvider.notifier)
                    .toggleFollowTag(tag);
              },
            ),
            const SizedBox(height: 24),
            _RsvpSection(
              events: events
                  .where((event) => user.rsvpEventIds.contains(event.id))
                  .toList(),
              slotSelections: user.eventRsvpSlotIds,
              onCancelRsvp: cancelRsvp,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.userDisplayName,
    required this.email,
    required this.username,
  });

  final String userDisplayName;
  final String email;
  final String username;

  @override
  Widget build(BuildContext context) {
    final displayName = userDisplayName.isNotEmpty ? userDisplayName : '@$username';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('@$username'),
                  Text(email),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowedCandidatesSection extends StatelessWidget {
  const _FollowedCandidatesSection({
    required this.candidates,
    required this.onToggleFollow,
  });

  final List<Candidate> candidates;
  final void Function(String id) onToggleFollow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Candidates you follow',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (candidates.isEmpty)
          Text(
            'Follow candidates from the directory to see them here.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          ...candidates.map(
            (candidate) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(candidate.name),
              subtitle: Text(candidate.region),
              trailing: TextButton(
                onPressed: () => onToggleFollow(candidate.id),
                child: const Text('Unfollow'),
              ),
              onTap: () => context.push('/candidates/${candidate.id}'),
            ),
          ),
      ],
    );
  }
}

class _FollowedTagsSection extends StatelessWidget {
  const _FollowedTagsSection({required this.tags, required this.onUnfollow});

  final List<String> tags;
  final void Function(String tag) onUnfollow;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Priority tags',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (tags.isEmpty)
          Text(
            'Follow tags on candidate profiles to tailor your feed.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                InputChip(
                  label: Text(tag),
                  onPressed: () => context.go('/candidates?tag=${Uri.encodeComponent(tag)}'),
                  onDeleted: () => onUnfollow(tag),
                ),
            ],
          ),
      ],
    );
  }
}

class _RsvpSection extends StatelessWidget {
  const _RsvpSection({
    required this.events,
    required this.slotSelections,
    required this.onCancelRsvp,
  });

  final List<CoalitionEvent> events;
  final Map<String, List<String>> slotSelections;
  final Future<void> Function(String id) onCancelRsvp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Events you signed up for',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          Text(
            'RSVP for events to see them here and manage your attendance.',
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          ...events.map((event) {
            final slotIds = slotSelections[event.id] ?? const <String>[];
            final slotLabels = <String>[];
            for (final slotId in slotIds) {
              EventTimeSlot? match;
              for (final slot in event.timeSlots) {
                if (slot.id == slotId) {
                  match = slot;
                  break;
                }
              }
              if (match != null) {
                slotLabels.add(match.label);
              }
            }
            final dateLine =
                '${_weekdayNames[event.startDate.weekday - 1]}, ${_monthNames[event.startDate.month - 1]} ${event.startDate.day} • ${event.location}';
            final infoLines = <String>[dateLine];
            if (slotLabels.isNotEmpty) {
              infoLines.add('Selected: ${slotLabels.join(', ')}');
            }
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(event.title),
              subtitle: Text(infoLines.join('\n')),
              trailing: TextButton(
                onPressed: () => onCancelRsvp(event.id),
                child: const Text('Cancel'),
              ),
              onTap: () => context.push('/events/${event.id}'),
            );
          }),
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
