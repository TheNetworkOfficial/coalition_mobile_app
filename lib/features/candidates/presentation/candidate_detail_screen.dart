import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_controller.dart';
import '../data/candidate_providers.dart';
import '../domain/candidate.dart';

class CandidateDetailScreen extends ConsumerStatefulWidget {
  const CandidateDetailScreen({required this.candidateId, super.key});

  static const routeName = 'candidate-detail';

  final String candidateId;

  @override
  ConsumerState<CandidateDetailScreen> createState() =>
      _CandidateDetailScreenState();
}

class _CandidateDetailScreenState extends ConsumerState<CandidateDetailScreen> {
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

  @override
  Widget build(BuildContext context) {
    final candidate = ref.watch(candidateByIdProvider(widget.candidateId));
    final user = ref.watch(authControllerProvider).user;

    if (candidate == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            'Candidate not found. They may have been removed from the coalition.',
            style: Theme.of(context).textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final authNotifier = ref.read(authControllerProvider.notifier);
    final isFollowing =
        user?.followedCandidateIds.contains(candidate.id) ?? false;
    final showConnectSection =
        candidate.socialLinks.isNotEmpty || candidate.websiteUrl != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(candidate.name),
        actions: [
          IconButton(
            icon: Icon(isFollowing ? Icons.favorite : Icons.favorite_border),
            onPressed: () {
              authNotifier.toggleFollowCandidate(candidate.id);
            },
            tooltip: isFollowing ? 'Unfollow candidate' : 'Follow candidate',
          ),
        ],
      ),
      floatingActionButton: _showFloatingButton
          ? FloatingActionButton.extended(
              onPressed: () {
                authNotifier.toggleFollowCandidate(candidate.id);
              },
              icon: Icon(isFollowing ? Icons.check : Icons.add),
              label: Text(isFollowing ? 'Following' : 'Follow'),
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
                  _CandidateHeader(candidate: candidate),
                  const SizedBox(height: 20),
                  _TagSection(
                    candidate: candidate,
                    userFollowing: user?.followedTags ?? {},
                  ),
                  const SizedBox(height: 24),
                  _BioSection(candidate: candidate),
                  const SizedBox(height: 24),
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
                    if (showConnectSection) ...[
                      _SocialLinksSection(candidate: candidate),
                      const SizedBox(height: 24),
                    ],
                    _ActionButtonsRow(
                      candidate: candidate,
                      isFollowing: isFollowing,
                      onFollowToggle: () {
                        authNotifier.toggleFollowCandidate(candidate.id);
                      },
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
}

class _CandidateHeader extends StatelessWidget {
  const _CandidateHeader({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CandidateAvatar(candidate: candidate),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      candidate.name,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (candidate.isVerified)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Icon(
                        Icons.verified,
                        color: Colors.blue.shade500,
                        size: 24,
                        semanticLabel: 'Verified candidate',
                      ),
                    ),
                  if (candidate.isCoalitionMember ||
                      candidate.isNonCoalitionMember)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _MembershipBadge(candidate: candidate),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text('${candidate.region} • ${_levelLabel(candidate.level)}'),
              if (candidate.pronouns != null) ...[
                const SizedBox(height: 4),
                Text(candidate.pronouns!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _levelLabel(String level) {
    return {
          'federal': 'Federal',
          'state': 'State',
          'county': 'County',
          'city': 'City',
        }[level] ??
        'Community';
  }
}

class _TagSection extends ConsumerWidget {
  const _TagSection({required this.candidate, required this.userFollowing});

  final Candidate candidate;
  final Set<String> userFollowing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(authControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Priority tags',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in candidate.tags)
              FilterChip(
                label: Text(tag),
                selected: userFollowing.contains(tag),
                onSelected: (_) {
                  controller.toggleFollowTag(tag);
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _BioSection extends StatelessWidget {
  const _BioSection({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bio',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.bio,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SocialLinksSection extends StatelessWidget {
  const _SocialLinksSection({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final links = <SocialLink>[
      if (candidate.websiteUrl != null)
        SocialLink(label: 'Website', url: candidate.websiteUrl!),
      ...candidate.socialLinks,
    ];

    if (links.isEmpty) {
      return const SizedBox.shrink();
    }

    final firstName = candidate.name.split(' ').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect & follow $firstName',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 16,
          children: [
            for (final link in links)
              _ContactIconTile(
                label: link.label,
                url: link.url,
                icon: _iconForSocialLabel(link.label),
                color: _colorForSocialLabel(theme, link.label),
              ),
          ],
        ),
      ],
    );
  }
}

class _ContactIconTile extends StatelessWidget {
  const _ContactIconTile({
    required this.label,
    required this.url,
    required this.icon,
    required this.color,
  });

  final String label;
  final String url;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final backgroundColor = color.withValues(alpha: 0.12);
    final host = Uri.tryParse(url)?.host;
    return Tooltip(
      message: host != null && host.isNotEmpty ? '$label · $host' : label,
      child: Semantics(
        button: true,
        label: '$label link',
        child: InkWell(
          onTap: () {
            // In a real app this would launch the provided URL or deep link.
          },
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 88,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: backgroundColor,
                    border: Border.all(
                      color: color.withValues(alpha: 0.36),
                    ),
                  ),
                  child: Icon(icon, size: 28, color: color),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.candidate,
    required this.isFollowing,
    required this.onFollowToggle,
  });

  final Candidate candidate;
  final bool isFollowing;
  final VoidCallback onFollowToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: () => context.go('/events?candidate=${candidate.id}'),
            icon: const Icon(Icons.event),
            label: const Text('Candidate Events'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onFollowToggle,
            icon: Icon(isFollowing ? Icons.check : Icons.add),
            label: Text(isFollowing ? 'Following' : 'Follow'),
          ),
        ),
      ],
    );
  }
}

class _CandidateAvatar extends StatelessWidget {
  const _CandidateAvatar({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final placeholder =
        Text(candidate.name.isNotEmpty ? candidate.name[0].toUpperCase() : '?');
    final borderRadius = BorderRadius.circular(16);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: 108,
        height: 108,
        child: candidate.headshotUrl != null
            ? Image.network(
                candidate.headshotUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _AvatarFallback(
                  placeholder: placeholder,
                ),
              )
            : _AvatarFallback(placeholder: placeholder),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.placeholder});

  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Center(child: placeholder),
    );
  }
}

class _MembershipBadge extends StatelessWidget {
  const _MembershipBadge({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final isCoalition = candidate.isCoalitionMember;
    final color =
        isCoalition ? const Color(0xFFFBC02D) : const Color(0xFFE53935);
    final icon = isCoalition ? Icons.workspace_premium : Icons.gpp_bad;
    final label = isCoalition ? 'Coalition member' : 'Non-coalition candidate';

    return Tooltip(
      message: label,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: 22, color: color),
      ),
    );
  }
}

IconData _iconForSocialLabel(String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('instagram')) return Icons.camera_alt;
  if (normalized.contains('facebook')) return Icons.facebook;
  if (normalized.contains('twitter') || normalized.contains('x')) {
    return Icons.alternate_email;
  }
  if (normalized.contains('threads')) return Icons.chat_bubble;
  if (normalized.contains('tiktok')) return Icons.music_note;
  if (normalized.contains('youtube')) return Icons.ondemand_video;
  if (normalized.contains('linkedin')) return Icons.work_outline;
  if (normalized.contains('phone') || normalized.contains('call')) {
    return Icons.phone;
  }
  if (normalized.contains('email') || normalized.contains('mail')) {
    return Icons.mail;
  }
  if (normalized.contains('text') || normalized.contains('sms')) {
    return Icons.sms;
  }
  if (normalized.contains('website') ||
      normalized.contains('campaign') ||
      normalized.contains('site') ||
      normalized.contains('link')) {
    return Icons.link;
  }
  if (normalized.contains('donate')) return Icons.volunteer_activism;
  return Icons.public;
}

Color _colorForSocialLabel(ThemeData theme, String label) {
  final normalized = label.toLowerCase();
  if (normalized.contains('instagram')) return Colors.pinkAccent;
  if (normalized.contains('facebook')) return const Color(0xFF1877F2);
  if (normalized.contains('twitter') || normalized.contains('x')) {
    return Colors.lightBlue;
  }
  if (normalized.contains('threads')) return Colors.black87;
  if (normalized.contains('tiktok')) return Colors.black87;
  if (normalized.contains('youtube')) return Colors.redAccent;
  if (normalized.contains('linkedin')) return const Color(0xFF0A66C2);
  if (normalized.contains('phone') || normalized.contains('call')) {
    return theme.colorScheme.primary;
  }
  if (normalized.contains('email') || normalized.contains('mail')) {
    return theme.colorScheme.secondary;
  }
  if (normalized.contains('text') || normalized.contains('sms')) {
    return theme.colorScheme.tertiary;
  }
  if (normalized.contains('donate')) return Colors.teal;
  return theme.colorScheme.primary;
}
