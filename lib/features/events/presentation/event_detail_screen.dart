import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/in_memory_coalition_repository.dart';
import '../../auth/data/auth_controller.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../candidates/domain/candidate.dart';
import '../data/event_providers.dart';
import '../domain/event.dart';
import 'widgets/event_media_preview.dart';
import 'widgets/event_rsvp_sheet.dart';

class EventDetailScreen extends ConsumerStatefulWidget {
  const EventDetailScreen({required this.eventId, super.key});

  static const routeName = 'event-detail';

  final String eventId;

  @override
  ConsumerState<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends ConsumerState<EventDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showFloatingButton = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleScroll());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final hasScrollableContent = position.maxScrollExtent > 0;
    final atBottom = hasScrollableContent
        ? position.pixels >= position.maxScrollExtent - 4
        : true;
    final nextShowFab = hasScrollableContent && !atBottom;
    if (nextShowFab != _showFloatingButton) {
      setState(() => _showFloatingButton = nextShowFab);
    }
  }

  Future<void> _handleRsvpAction(
    CoalitionEvent event,
    bool attending,
  ) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to RSVP for this event.')),
      );
      return;
    }

    if (!attending) {
      await showEventRsvpSheet(context: context, ref: ref, event: event);
      return;
    }

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel RSVP'),
        content: Text(
          'Would you like to cancel your RSVP for "${event.title}"?',
        ),
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
          .cancelEventRsvp(eventId: event.id, userId: user.id);
      await ref.read(authControllerProvider.notifier).cancelEventRsvp(event.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('RSVP cancelled. We hope to see you next time!')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'We could not update your RSVP. Please try again or contact support.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final event = ref.watch(eventByIdProvider(widget.eventId));
    final authState = ref.watch(authControllerProvider);
    final candidates = ref.watch(candidateListProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <Candidate>[],
        );

    if (event == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Event not found. It may have been removed from the coalition.',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final attending = authState.user?.rsvpEventIds.contains(event.id) ?? false;
    final selectedSlotIds = Set<String>.from(
      authState.user?.eventRsvpSlotIds[event.id] ?? const <String>[],
    );
    final hostCandidates = event.hostCandidateIds
        .map((id) => candidates.firstWhere(
              (candidate) => candidate.id == id,
              orElse: () => Candidate(
                id: id,
                name: 'Coalition candidate',
                level: 'community',
                region: 'Montana',
                bio: '',
                tags: const [],
              ),
            ))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(event.title),
        actions: [
          IconButton(
            icon: Icon(attending ? Icons.check : Icons.event_available),
            onPressed: () => _handleRsvpAction(event, attending),
            tooltip: attending ? 'Cancel RSVP' : 'RSVP',
          ),
        ],
      ),
      floatingActionButton: _showFloatingButton
          ? FloatingActionButton.extended(
              onPressed: () => _handleRsvpAction(event, attending),
              icon: Icon(attending ? Icons.check : Icons.event_available),
              label: Text(attending ? 'Attending' : 'RSVP'),
            )
          : null,
      body: SafeArea(
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _EventHeader(event: event),
                  const SizedBox(height: 20),
                  _EventMetadata(event: event),
                  const SizedBox(height: 24),
                  _LocationSection(
                    event: event,
                    onOpenMaps: () => _launchMaps(event.location),
                  ),
                  if (event.timeSlots.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _TimeSlotOverview(
                      event: event,
                      selectedSlotIds: selectedSlotIds,
                    ),
                  ],
                  const SizedBox(height: 24),
                  _DescriptionSection(description: event.description),
                  if (event.tags.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _TagSection(tags: event.tags),
                  ],
                  if (hostCandidates.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    _HostSection(candidates: hostCandidates),
                  ],
                ]),
              ),
            ),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _ActionButtonsRow(
                      event: event,
                      attending: attending,
                      onPrimaryAction: () =>
                          _handleRsvpAction(event, attending),
                      onShare: (platform) => _shareEvent(platform, event),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchMaps(String query) async {
    final encoded = Uri.encodeComponent(query);
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps on this device.')),
      );
    }
  }

  Future<void> _shareEvent(String platform, CoalitionEvent event) async {
    final localStart = event.startDate.toLocal();
    final shareText = _buildShareMessage(event, platform, localStart);
    await SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: event.title.isNotEmpty ? event.title : null,
      ),
    );
  }

  String _buildShareMessage(
    CoalitionEvent event,
    String platform,
    DateTime localStart,
  ) {
    final dateLabel = _formatFullDate(localStart);
    final timeLabel = _formatTime(localStart);
    final buffer = StringBuffer()
      ..writeln(event.title)
      ..writeln('$dateLabel • $timeLabel')
      ..writeln(event.location)
      ..writeln()
      ..writeln(event.description);
    if (event.cost.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Cost: ${event.cost}');
    }
    buffer
      ..writeln()
      ..write('#CoalitionEvents #$platform');
    return buffer.toString();
  }

  String _formatFullDate(DateTime value) {
    const weekdayNames = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final weekday = weekdayNames[value.weekday - 1];
    final month = monthNames[value.month - 1];
    return '$weekday, $month ${value.day}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _EventHeader extends StatelessWidget {
  const _EventHeader({required this.event});

  final CoalitionEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = event.mediaUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (media != null && media.isNotEmpty) ...[
          EventMediaPreview(
            mediaUrl: media,
            aspectRatio: event.mediaAspectRatio ?? 16 / 9,
            coverImagePath: event.coverImagePath,
          ),
          const SizedBox(height: 20),
        ],
        Text(
          event.title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 12),
        _EventTypePill(type: event.type),
      ],
    );
  }
}

class _EventMetadata extends StatelessWidget {
  const _EventMetadata({required this.event});

  final CoalitionEvent event;

  @override
  Widget build(BuildContext context) {
    final localStart = event.startDate.toLocal();
    final dateLabel = _formatDate(localStart);
    final timeLabel = _formatTime(localStart);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _MetadataChip(
          icon: Icons.calendar_today_outlined,
          label: '$dateLabel • $timeLabel',
        ),
        _MetadataChip(
          icon: Icons.confirmation_number_outlined,
          label: event.cost.isEmpty ? 'Cost info coming soon' : event.cost,
        ),
      ],
    );
  }

  String _formatDate(DateTime value) {
    const weekdayNames = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    const monthNames = [
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
    final weekday = weekdayNames[value.weekday - 1];
    final month = monthNames[value.month - 1];
    return '$weekday, $month ${value.day}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _MetadataChip extends StatelessWidget {
  const _MetadataChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      labelStyle: theme.textTheme.bodyMedium,
    );
  }
}

class _LocationSection extends StatelessWidget {
  const _LocationSection({required this.event, required this.onOpenMaps});

  final CoalitionEvent event;
  final VoidCallback onOpenMaps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.place_outlined, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.location,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onOpenMaps,
            icon: const Icon(Icons.map_outlined),
            label: const Text('Open in maps'),
          ),
        ),
      ],
    );
  }
}

class _DescriptionSection extends StatelessWidget {
  const _DescriptionSection({required this.description});

  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About this event',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          description,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ],
    );
  }
}

class _TagSection extends StatelessWidget {
  const _TagSection({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Focus tags',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags) Chip(label: Text(tag)),
          ],
        ),
      ],
    );
  }
}

class _HostSection extends StatelessWidget {
  const _HostSection({required this.candidates});

  final List<Candidate> candidates;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hosted by',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final candidate in candidates)
              GestureDetector(
                onTap: () => context.push('/candidates/${candidate.id}'),
                child: Chip(
                  avatar: CircleAvatar(
                    child: Text(
                      candidate.name.isNotEmpty
                          ? candidate.name[0].toUpperCase()
                          : '?',
                    ),
                  ),
                  label: Text(candidate.name),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TimeSlotOverview extends StatelessWidget {
  const _TimeSlotOverview({
    required this.event,
    required this.selectedSlotIds,
  });

  final CoalitionEvent event;
  final Set<String> selectedSlotIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available time slots',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        for (final slot in event.timeSlots)
          _TimeSlotCard(
            slot: slot,
            isSelected: selectedSlotIds.contains(slot.id),
          ),
      ],
    );
  }
}

class _TimeSlotCard extends StatelessWidget {
  const _TimeSlotCard({required this.slot, required this.isSelected});

  final EventTimeSlot slot;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = slot.remainingCapacity;
    final statusText = remaining == null
        ? 'Open capacity'
        : remaining > 0
            ? '$remaining spot${remaining == 1 ? '' : 's'} left'
            : 'Full';
    final statusColor = remaining == null || remaining > 0
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    final backgroundColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerLowest;
    final borderColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.4);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              slot.label,
              style: theme.textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            statusText,
            style: theme.textTheme.labelMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            Icon(
              Icons.check_circle,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButtonsRow extends StatefulWidget {
  const _ActionButtonsRow({
    required this.event,
    required this.attending,
    required this.onPrimaryAction,
    required this.onShare,
  });

  final CoalitionEvent event;
  final bool attending;
  final VoidCallback onPrimaryAction;
  final Future<void> Function(String platform) onShare;

  @override
  State<_ActionButtonsRow> createState() => _ActionButtonsRowState();
}

class _ActionButtonsRowState extends State<_ActionButtonsRow> {
  bool _shareExpanded = false;

  static const _shareTargets = <_ShareTarget>[
    _ShareTarget(icon: Icons.facebook, label: 'Facebook'),
    _ShareTarget(icon: Icons.camera_alt_outlined, label: 'Instagram'),
    _ShareTarget(icon: Icons.music_note, label: 'TikTok'),
    _ShareTarget(icon: Icons.forum_outlined, label: 'Threads'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            FilledButton.icon(
              onPressed: widget.onPrimaryAction,
              icon: Icon(
                widget.attending ? Icons.check : Icons.event_available,
              ),
              label: Text(widget.attending ? 'Attending' : 'RSVP'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _shareExpanded = !_shareExpanded);
              },
              icon: const Icon(Icons.share),
              label: Text(_shareExpanded ? 'Hide share' : 'Share'),
            ),
          ],
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeIn,
          switchOutCurve: Curves.easeOut,
          child: _shareExpanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final target in _shareTargets)
                        Tooltip(
                          message: 'Share to ${target.label}',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(28),
                            onTap: () async {
                              await widget.onShare(target.label);
                              if (mounted) {
                                setState(() => _shareExpanded = false);
                              }
                            },
                            child: CircleAvatar(
                              radius: 24,
                              backgroundColor:
                                  Theme.of(context).colorScheme.secondary,
                              child: Icon(
                                target.icon,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSecondary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _ShareTarget {
  const _ShareTarget({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

class _EventTypePill extends StatelessWidget {
  const _EventTypePill({required this.type});

  final String type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = type
        .replaceAll('-', ' ')
        .split(' ')
        .map((part) =>
            part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          display,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
