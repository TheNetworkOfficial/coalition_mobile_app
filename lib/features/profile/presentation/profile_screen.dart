import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/theme_controller.dart';
import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../events/data/event_providers.dart';
import '../../events/domain/event.dart';
import '../data/candidate_account_request_controller.dart';
import '../data/user_content_provider.dart';
import '../data/profile_connections_provider.dart';
import '../domain/candidate_account_request.dart';
import '../domain/profile_connection.dart';
import '../domain/user_content.dart';
import 'candidate_account_request_sheet.dart';
import 'edit_profile_sheet.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  static const routeName = 'profile';

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to access your profile.')),
      );
    }

    final events = ref.watch(eventsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => const <CoalitionEvent>[],
        );
    final connectionMap = ref.watch(profileConnectionsProvider);
    final catalog = ref.watch(userContentCatalogProvider);
    final contentById = {
      for (final item in catalog) item.id: item,
    };

    final likedContent = [
      for (final id in user.likedContentIds)
        if (contentById[id] != null) contentById[id]!,
    ];
    final myContent = [
      for (final id in user.myContentIds)
        if (contentById[id] != null) contentById[id]!,
    ];

    final attendingEvents = events
        .where((event) => user.rsvpEventIds.contains(event.id))
        .toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));

    final followerConnections = [
      for (final id in user.followerIds)
        if (connectionMap[id] != null) connectionMap[id]!,
    ];
    final followingConnections = [
      for (final id in user.followingIds)
        if (connectionMap[id] != null) connectionMap[id]!,
    ];
    final followersCountDisplay = followerConnections.isEmpty
        ? user.followersCount
        : followerConnections.length;
    final followingCountDisplay = user.followingIds.length;

    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: DefaultTabController(
          length: 3,
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                  child: _ProfileHeader(
                    user: user,
                    onEditProfile: () => _openEditProfileSheet(user),
                    onOpenSettings: _openSettingsSheet,
                    onChangePhoto: () => _handleAvatarChange(context, user),
                    onFollowersTap: () =>
                        _showConnectionsSheet('Followers', followerConnections),
                    onFollowingTap: () =>
                        _showConnectionsSheet('Following', followingConnections),
                    followersCount: followersCountDisplay,
                    followingCount: followingCountDisplay,
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _ProfileTabBarDelegate(
                  TabBar(
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    indicatorColor: theme.colorScheme.primary,
                    tabs: const [
                      Tab(text: 'My content'),
                      Tab(text: 'Events'),
                      Tab(text: 'Liked'),
                    ],
                  ),
                  backgroundColor: theme.scaffoldBackgroundColor,
                ),
              ),
            ],
            body: TabBarView(
              children: [
                _ProfileContentTab(
                  key: const PageStorageKey('my-content'),
                  items: myContent,
                  emptyIcon: Icons.movie_creation_outlined,
                  emptyMessage:
                      'You\'re ready to showcase campaign stories once you publish content.',
                  actionLabel: 'Draft a story',
                  onAction: () => _openEditProfileSheet(user),
                ),
                _ProfileEventsTab(
                  key: const PageStorageKey('events'),
                  events: attendingEvents,
                ),
                _ProfileContentTab(
                  key: const PageStorageKey('liked-content'),
                  items: likedContent,
                  emptyIcon: Icons.favorite_border,
                  emptyMessage: 'Tap the heart on videos to save them here.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditProfileSheet(AppUser user) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => EditProfileSheet(user: user),
    );
  }

  Future<void> _openSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ProfileSettingsSheet(),
    );
  }

  Future<void> _handleAvatarChange(BuildContext context, AppUser user) async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxHeight: 720,
        maxWidth: 720,
        imageQuality: 85,
      );
      if (image == null) return;
      await ref.read(authControllerProvider.notifier).updateProfileImage(image.path);
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } catch (_) {
      if (!mounted || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not update your photo. Please try again.'),
        ),
      );
    }
  }

  void _showConnectionsSheet(
    String title,
    List<ProfileConnection> connections,
  ) {
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ConnectionsSheet(
        title: title,
        connections: connections,
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.onEditProfile,
    required this.onOpenSettings,
    required this.onChangePhoto,
    required this.onFollowersTap,
    required this.onFollowingTap,
    required this.followersCount,
    required this.followingCount,
  });

  final AppUser user;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenSettings;
  final VoidCallback onChangePhoto;
  final VoidCallback onFollowersTap;
  final VoidCallback onFollowingTap;
  final int followersCount;
  final int followingCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = user.displayName.isEmpty ? '@${user.username}' : user.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              onPressed: onOpenSettings,
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
            ),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileAvatar(
              imagePath: user.profileImagePath,
              displayName: displayName,
              onTap: onChangePhoto,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _AccountTypeChip(accountType: user.accountType),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user.username}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileStat(
                          label: 'Following',
                          value: followingCount,
                          onTap: onFollowingTap,
                        ),
                      ),
                      Expanded(
                        child: _ProfileStat(
                          label: 'Followers',
                          value: followersCount,
                          onTap: onFollowersTap,
                        ),
                      ),
                      Expanded(
                        child: _ProfileStat(
                          label: 'Likes',
                          value: user.totalLikes,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onEditProfile,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit profile'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _BioSection(bio: user.bio, onEditProfile: onEditProfile),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imagePath,
    required this.displayName,
    required this.onTap,
  });

  final String? imagePath;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = 48.0;
    ImageProvider? provider;
    if (imagePath != null && imagePath!.isNotEmpty) {
      if (kIsWeb) {
        provider = NetworkImage(imagePath!);
      } else {
        final file = File(imagePath!);
        if (file.existsSync()) {
          provider = FileImage(file);
        }
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundImage: provider,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: provider == null
                ? Text(
                    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  )
                : null,
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: CircleAvatar(
              radius: 17,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(
                Icons.camera_alt,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTypeChip extends StatelessWidget {
  const _AccountTypeChip({required this.accountType});

  final UserAccountType accountType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCandidate = accountType == UserAccountType.candidate;
    final background = isCandidate
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.secondaryContainer;
    final foreground = isCandidate
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCandidate ? Icons.campaign_outlined : Icons.person_outline,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Text(
            isCandidate ? 'Candidate' : 'Constituent',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStat extends StatelessWidget {
  const _ProfileStat({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatCount(value),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: content,
        ),
      ),
    );
  }
}

class _BioSection extends StatelessWidget {
  const _BioSection({required this.bio, required this.onEditProfile});

  final String bio;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final trimmed = bio.trim();
    if (trimmed.isEmpty) {
      return OutlinedButton.icon(
        onPressed: onEditProfile,
        icon: const Icon(Icons.add),
        label: const Text('Add a short bio'),
      );
    }

    return Text(
      trimmed,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _ProfileContentTab extends StatelessWidget {
  const _ProfileContentTab({
    super.key,
    required this.items,
    required this.emptyIcon,
    required this.emptyMessage,
    this.actionLabel,
    this.onAction,
  });

  final List<UserContent> items;
  final IconData emptyIcon;
  final String emptyMessage;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _ProfileEmptyState(
        icon: emptyIcon,
        message: emptyMessage,
        actionLabel: actionLabel,
        onAction: onAction,
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 3 / 4,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final content = items[index];
                return _UserContentTile(content: content);
              },
              childCount: items.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileEventsTab extends StatelessWidget {
  const _ProfileEventsTab({super.key, required this.events});

  final List<CoalitionEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const _ProfileEmptyState(
        icon: Icons.event_busy,
        message: 'Your RSVPs will appear here once you sign up for events.',
      );
    }

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 3 / 4,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final event = events[index];
                return _EventTile(event: event);
              },
              childCount: events.length,
            ),
          ),
        ),
      ],
    );
  }
}

class _UserContentTile extends StatelessWidget {
  const _UserContentTile({required this.content});

  final UserContent content;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (content.thumbnailUrl != null)
            Image.network(
              content.thumbnailUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _ContentPlaceholder(
                title: content.title,
              ),
            )
          else
            _ContentPlaceholder(title: content.title),
          Align(
            alignment: Alignment.bottomLeft,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
              child: Text(
                content.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentPlaceholder extends StatelessWidget {
  const _ContentPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
          colors.primaryContainer.withValues(alpha: 0.8),
          colors.primary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({required this.event});

  final CoalitionEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ended = event.startDate.isBefore(DateTime.now());

    return InkWell(
      onTap: () => context.push('/events/${event.id}'),
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
          theme.colorScheme.primary.withValues(alpha: 0.85),
          theme.colorScheme.primaryContainer.withValues(alpha: 0.9),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 12,
              top: 12,
              right: 12,
              child: Text(
                _formatEventDate(event.startDate),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    event.location,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (ended) const _EndedOverlay(),
          ],
        ),
      ),
    );
  }
}

class _EndedOverlay extends StatelessWidget {
  const _EndedOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Container(color: Colors.black38),
          Transform.rotate(
            angle: -0.785398, // -45 degrees
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 6),
              color: Colors.redAccent.withValues(alpha: 0.9),
              child: const Text(
                'ENDED',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileEmptyState extends StatelessWidget {
  const _ProfileEmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ConnectionsSheet extends StatelessWidget {
  const _ConnectionsSheet({
    required this.title,
    required this.connections,
  });

  final String title;
  final List<ProfileConnection> connections;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.75,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: connections.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'No profiles to show yet.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemBuilder: (context, index) {
                        final connection = connections[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundImage: connection.avatarUrl != null
                                ? NetworkImage(connection.avatarUrl!)
                                : null,
                            child: connection.avatarUrl == null
                                ? Text(connection.displayName.isNotEmpty
                                    ? connection.displayName[0].toUpperCase()
                                    : '?')
                                : null,
                          ),
                          title: Text(connection.displayName),
                          subtitle: Text('@${connection.username}'),
                        );
                      },
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemCount: connections.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTabBarDelegate extends SliverPersistentHeaderDelegate {
  _ProfileTabBarDelegate(this.tabBar, {required this.backgroundColor});

  final TabBar tabBar;
  final Color backgroundColor;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: backgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _ProfileTabBarDelegate oldDelegate) {
    return oldDelegate.tabBar != tabBar || oldDelegate.backgroundColor != backgroundColor;
  }
}

class _ProfileSettingsSheet extends ConsumerWidget {
  const _ProfileSettingsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authControllerProvider).user;
    final themeMode = ref.watch(themeControllerProvider);
    final requestState = ref.watch(candidateAccountRequestControllerProvider);
    final requests = requestState.maybeWhen(
      data: (value) => value,
      orElse: () => const <CandidateAccountRequest>[],
    );

    CandidateAccountRequest? latestRequest;
    var hasPendingRequest = false;
    if (user != null) {
      for (final request in requests) {
        if (request.userId != user.id) continue;
        if (latestRequest == null ||
            request.submittedAt.isAfter(latestRequest.submittedAt)) {
          latestRequest = request;
        }
        if (request.status == CandidateAccountRequestStatus.pending) {
          hasPendingRequest = true;
        }
      }
    }

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Text(
              'Appearance',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: [
                for (final mode in ThemeMode.values)
                  ButtonSegment<ThemeMode>(
                    value: mode,
                    label: Text(_themeModeLabel(mode)),
                  ),
              ],
              selected: <ThemeMode>{themeMode},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) {
                  return;
                }
                final nextMode = selection.first;
                ref
                    .read(themeControllerProvider.notifier)
                    .setThemeMode(nextMode);
              },
            ),
            if (user != null) ...[
              const SizedBox(height: 24),
              Text(
                'Account',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  user.accountType == UserAccountType.candidate
                      ? Icons.campaign_outlined
                      : Icons.person_outline,
                ),
                title: Text(
                  'Account type: ${user.accountType == UserAccountType.candidate ? 'Candidate' : 'Constituent'}',
                ),
                subtitle: latestRequest == null
                    ? null
                    : Text(
                        _describeRequestStatus(latestRequest),
                      ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Request candidate account'),
                subtitle: user.accountType == UserAccountType.candidate
                    ? const Text('You already have candidate access.')
                    : hasPendingRequest
                        ? const Text('Your request is being reviewed.')
                        : const Text('Submit campaign details to upgrade your account.'),
                trailing: user.accountType == UserAccountType.candidate || hasPendingRequest
                    ? null
                    : const Icon(Icons.chevron_right),
                enabled: user.accountType != UserAccountType.candidate && !hasPendingRequest,
                onTap: user.accountType == UserAccountType.candidate || hasPendingRequest
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          showDragHandle: true,
                          builder: (_) => const CandidateAccountRequestSheet(),
                        );
                      },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () async {
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Signed out.')),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return 'Use device setting';
    case ThemeMode.light:
      return 'Light mode';
    case ThemeMode.dark:
      return 'Dark mode';
  }
}

String _describeRequestStatus(CandidateAccountRequest request) {
  switch (request.status) {
    case CandidateAccountRequestStatus.pending:
      return 'Submitted on ${_formatFullDate(request.submittedAt)} — pending review.';
    case CandidateAccountRequestStatus.approved:
      final reviewed = request.reviewedAt ?? request.submittedAt;
      return 'Approved on ${_formatFullDate(reviewed)}';
    case CandidateAccountRequestStatus.denied:
      final reviewed = request.reviewedAt ?? request.submittedAt;
      return 'Last reviewed on ${_formatFullDate(reviewed)} — not approved.';
  }
}

String _formatCount(int value) {
  if (value >= 1000000) {
    return value % 1000000 == 0
        ? '${(value / 1000000).round()}M'
        : '${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value >= 1000) {
    return value % 1000 == 0
        ? '${(value / 1000).round()}K'
        : '${(value / 1000).toStringAsFixed(1)}K';
  }
  return value.toString();
}

String _formatEventDate(DateTime date) {
  final month = _monthNames[date.month - 1];
  final day = date.day;
  return '$month $day';
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
