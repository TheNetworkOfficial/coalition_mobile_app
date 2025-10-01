import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../feed/data/feed_comments_provider.dart';
import '../../feed/data/feed_ranking_algorithm.dart';
import '../../feed/domain/feed_content.dart';
import 'widgets/feed_card.dart';
import 'widgets/feed_comments_sheet.dart';

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  static const routeName = 'feed';

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late final PageController _pageController;
  int _activePageIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(personalizedFeedProvider);
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    return feedAsync.when(
      data: (ranked) {
        if (ranked.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Your feed is warming up. Follow candidates, RSVP to events, and engage with tags to see stories tailored to you.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          );
        }

        final items = ranked.map((entry) => entry.content).toList(growable: false);

        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(personalizedFeedProvider);
            await ref.read(personalizedFeedProvider.future);
          },
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Theme.of(context).colorScheme.surfaceContainerLowest,
                  Theme.of(context).colorScheme.surface,
                ],
              ),
            ),
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              physics: const PageScrollPhysics(),
              onPageChanged: (index) {
                setState(() => _activePageIndex = index);
              },
              itemBuilder: (context, index) {
                final cycleLength = items.length;
                if (cycleLength == 0) {
                  return const SizedBox.shrink();
                }
                final isActive = index == _activePageIndex;
                final contentIndex = index % cycleLength;
                final content = items[contentIndex];
                final isLiked = user?.likedContentIds.contains(content.id) ?? false;
                final isFollowingCreator = _isFollowingPoster(user, content);

                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                  child: FeedCard(
                    key: ValueKey('${content.id}-$index'),
                    content: content,
                    isActive: isActive,
                    isLiked: isLiked,
                    isFollowingPoster: isFollowingCreator,
                    onShare: () => _handleShare(content),
                    onToggleLike: () =>
                        ref.read(authControllerProvider.notifier).toggleLikeContent(content.id),
                    onComment: () => _openComments(context, content),
                    onOpenProfile: () => _openProfile(context, content),
                    onToggleFollow: () =>
                        _handleFollowToggle(ref, content, isFollowingCreator),
                  ),
                );
              },
            ),
          ),
        );
      },
      loading: () => const Center(
        child: CircularProgressIndicator.adaptive(),
      ),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'We could not load your feed right now. $error',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  bool _isFollowingPoster(AppUser? user, FeedContent content) {
    if (user == null) return false;
    switch (content.sourceType) {
      case FeedSourceType.candidate:
        return user.followedCandidateIds.contains(content.posterId);
      case FeedSourceType.event:
        return user.followedCreatorIds.contains(content.posterId);
      case FeedSourceType.creator:
        return user.followedCreatorIds.contains(content.posterId);
    }
  }

  Future<void> _handleShare(FeedContent content) async {
    final subject = 'Check this out on Coalition for Montana';
    final link = Uri.parse('https://coalitionmt.app/feed/${content.id}');
    await SharePlus.instance.share(
      ShareParams(
        uri: link,
        subject: subject,
        title: subject,
      ),
    );
  }

  Future<void> _openComments(BuildContext context, FeedContent content) async {
    final comments = ref.read(feedCommentsProvider(content.id));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => FeedCommentsSheet(
        content: content,
        initialComments: comments,
      ),
    );
  }

  void _openProfile(BuildContext context, FeedContent content) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    switch (content.sourceType) {
      case FeedSourceType.candidate:
        context.push('/candidates/${content.posterId}');
        break;
      case FeedSourceType.event:
        context.push('/events/${content.posterId}');
        break;
      case FeedSourceType.creator:
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              'Creator profiles are coming soon for ${content.posterName}.',
            ),
          ),
        );
        break;
    }
  }

  Future<void> _handleFollowToggle(
    WidgetRef ref,
    FeedContent content,
    bool isFollowing,
  ) async {
    final authNotifier = ref.read(authControllerProvider.notifier);
    switch (content.sourceType) {
      case FeedSourceType.candidate:
        await authNotifier.toggleFollowCandidate(content.posterId);
        break;
      case FeedSourceType.event:
      case FeedSourceType.creator:
        await authNotifier.toggleFollowCreator(content.posterId);
        break;
    }
  }
}
