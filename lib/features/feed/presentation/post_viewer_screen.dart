import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/data/feed_content_store.dart';
import '../../feed/domain/feed_content.dart';
import 'widgets/feed_card.dart';
import '../../auth/data/auth_controller.dart';

class PostViewerScreen extends ConsumerStatefulWidget {
  const PostViewerScreen({
    required this.initialContentId,
    super.key,
  });

  final String initialContentId;

  @override
  ConsumerState<PostViewerScreen> createState() => _PostViewerScreenState();
}

class _PostViewerScreenState extends ConsumerState<PostViewerScreen> {
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
    final catalog = ref.watch(feedContentCatalogProvider);
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    final items = List<FeedContent>.from(catalog);
    final startIndex = items.indexWhere((c) => c.id == widget.initialContentId);
    final initialPage = startIndex == -1 ? 0 : startIndex;

    // ensure controller jump once after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pageController.hasClients) {
        _pageController.jumpToPage(initialPage);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: items.length,
        onPageChanged: (index) => setState(() => _activePageIndex = index),
        itemBuilder: (context, index) {
          final content = items[index];
          final isLiked = user?.likedContentIds.contains(content.id) ?? false;
          final isFollowing = _isFollowing(user, content);
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: FeedCard(
              content: content,
              isActive: index == _activePageIndex,
              isLiked: isLiked,
              isFollowingPoster: isFollowing,
              onShare: () {},
              onToggleLike: () => ref.read(authControllerProvider.notifier).toggleLikeContent(content.id),
              onComment: () {},
              onOpenProfile: () {},
              onToggleFollow: () {},
            ),
          );
        },
      ),
    );
  }

  bool _isFollowing(user, FeedContent content) {
    if (user == null) return false;
    switch (content.sourceType) {
      case FeedSourceType.candidate:
        return user.followedCandidateIds.contains(content.posterId);
      case FeedSourceType.event:
      case FeedSourceType.creator:
        return user.followedCreatorIds.contains(content.posterId);
    }
  }
}
