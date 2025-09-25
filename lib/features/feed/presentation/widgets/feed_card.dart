import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/video/adaptive_video_player.dart';
import '../../../create/presentation/widgets/static_transform_view.dart';
import '../../../feed/domain/feed_content.dart';

class FeedCard extends StatefulWidget {
  const FeedCard({
    required this.content,
    required this.isActive,
    required this.isLiked,
    required this.isFollowingPoster,
    required this.onShare,
    required this.onComment,
    required this.onToggleLike,
    required this.onOpenProfile,
    required this.onToggleFollow,
    super.key,
  });

  final FeedContent content;
  final bool isActive;
  final bool isLiked;
  final bool isFollowingPoster;
  final VoidCallback onShare;
  final VoidCallback onComment;
  final VoidCallback onToggleLike;
  final VoidCallback onOpenProfile;
  final VoidCallback onToggleFollow;

  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard> {
  bool _isDescriptionExpanded = false;
  bool _pendingToggleAnimation = false;

  @override
  void didUpdateWidget(covariant FeedCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isActive && _isDescriptionExpanded) {
      setState(() => _isDescriptionExpanded = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final descriptionTextStyle = theme.textTheme.bodyLarge?.copyWith(
      color: Colors.white,
      height: 1.4,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
              ),
              child: _FeedMedia(
                content: widget.content,
                isActive: widget.isActive,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),
          if (widget.content.overlays.isNotEmpty)
            Positioned.fill(
              child: _FeedOverlayLayer(overlays: widget.content.overlays),
            ),
          _buildActionRail(context),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.fromLTRB(
                20,
                _isDescriptionExpanded ? 18 : 24,
                20,
                MediaQuery.of(context).padding.bottom + 20,
              ),
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.black.withValues(alpha: 0.32),
                    Colors.black.withValues(alpha: 0.02),
                  ],
                ),
              ),
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundImage: _posterImageProvider(
                              widget.content.posterAvatarUrl),
                          backgroundColor: Colors.white.withValues(alpha: 0.15),
                          child: _posterImageProvider(
                                      widget.content.posterAvatarUrl) ==
                                  null
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.content.posterName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AnimatedCrossFade(
                      crossFadeState: _isDescriptionExpanded
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      duration: const Duration(milliseconds: 220),
                      firstChild: GestureDetector(
                        onTap: _toggleDescription,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 80),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Text(
                              widget.content.description,
                              style: descriptionTextStyle,
                            ),
                          ),
                        ),
                      ),
                      secondChild: GestureDetector(
                        onTap: _toggleDescription,
                        child: Text(
                          widget.content.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: descriptionTextStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _toggleDescription,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                        ),
                        icon: Icon(
                          _isDescriptionExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        label: Text(
                          _isDescriptionExpanded ? 'Collapse' : 'Read more',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRail(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = Colors.white;
    final railSpacing = 18.0;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: Colors.white,
      fontWeight: FontWeight.w600,
    );

    final likeCount = widget.content.interactionStats.likes;
    final commentCount = widget.content.interactionStats.comments;
    final shareCount = widget.content.interactionStats.shares;

    return Positioned(
      right: 16,
      bottom: MediaQuery.of(context).padding.bottom + 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        verticalDirection: VerticalDirection.up,
        children: [
          _ActionButton(
            icon: Icons.ios_share,
            color: iconColor,
            label: shareCount.toString(),
            labelStyle: labelStyle,
            onPressed: widget.onShare,
          ),
          SizedBox(height: railSpacing),
          _ActionButton(
            icon: Icons.mode_comment_outlined,
            color: iconColor,
            label: commentCount.toString(),
            labelStyle: labelStyle,
            onPressed: widget.onComment,
          ),
          SizedBox(height: railSpacing),
          _ActionButton(
            icon: widget.isLiked ? Icons.favorite : Icons.favorite_border,
            color: widget.isLiked ? Colors.redAccent : iconColor,
            label: likeCount.toString(),
            labelStyle: labelStyle,
            onPressed: widget.onToggleLike,
          ),
          SizedBox(height: railSpacing),
          _ProfileActionButton(
            isFollowing: widget.isFollowingPoster,
            onOpenProfile: widget.onOpenProfile,
            onToggleFollow: () {
              if (_pendingToggleAnimation) return;
              setState(() => _pendingToggleAnimation = true);
              widget.onToggleFollow();
              Future<void>.delayed(const Duration(milliseconds: 300)).then((_) {
                if (mounted) {
                  setState(() => _pendingToggleAnimation = false);
                }
              });
            },
            avatarUrl: widget.content.posterAvatarUrl,
            fallbackInitials: _initials(widget.content.posterName),
          ),
        ],
      ),
    );
  }

  ImageProvider<Object>? _posterImageProvider(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(source);
    }
    if (uri != null && uri.scheme == 'file') {
      return FileImage(File(uri.toFilePath()));
    }
    return FileImage(File(source));
  }

  void _toggleDescription() {
    setState(() => _isDescriptionExpanded = !_isDescriptionExpanded);
  }

  String _initials(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      return '';
    }
    final first = words.first[0];
    if (words.length == 1) {
      return first.toUpperCase();
    }
    final last = words.last[0];
    return '${first.toUpperCase()}${last.toUpperCase()}';
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.onPressed,
    this.color,
    this.label,
    this.labelStyle,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;
  final String? label;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(24),
          ),
          child: IconButton(
            onPressed: onPressed,
            icon: Icon(icon),
            color: color,
            tooltip: label,
          ),
        ),
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(label!, style: labelStyle),
          ),
      ],
    );
  }
}

class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.isFollowing,
    required this.onOpenProfile,
    required this.onToggleFollow,
    required this.fallbackInitials,
    this.avatarUrl,
  });

  final bool isFollowing;
  final VoidCallback onOpenProfile;
  final VoidCallback onToggleFollow;
  final String fallbackInitials;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpenProfile,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.black.withValues(alpha: 0.25),
            child: CircleAvatar(
              radius: 24,
              backgroundImage: _imageProvider(avatarUrl),
              backgroundColor: avatarUrl == null
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.white,
              child: avatarUrl == null
                  ? Text(
                      fallbackInitials,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                    )
                  : null,
            ),
          ),
          if (!isFollowing)
            Positioned(
              bottom: -2,
              right: -2,
              child: GestureDetector(
                onTap: () {
                  onToggleFollow();
                },
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.lightBlueAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.add,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  ImageProvider<Object>? _imageProvider(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(source);
    }
    if (uri != null && uri.scheme == 'file') {
      return FileImage(File(uri.toFilePath()));
    }
    return FileImage(File(source));
  }
}

class _FeedMedia extends StatefulWidget {
  const _FeedMedia({required this.content, required this.isActive});

  final FeedContent content;
  final bool isActive;

  @override
  State<_FeedMedia> createState() => _FeedMediaState();
}

class _FeedMediaState extends State<_FeedMedia> {
  @override
  Widget build(BuildContext context) {
    final content = widget.content;

    if (content.isVideo) {
      if (content.processingStatus == FeedMediaProcessingStatus.processing) {
        return _wrapWithTransform(
          _ProcessingPlaceholder(
            imageProvider: _maybeImageProvider(content.thumbnailUrl),
            title: 'Processing…',
            subtitle: 'We\'ll notify you when the video is ready.',
            icon: Icons.cloud_upload_outlined,
          ),
        );
      }

      if (content.processingStatus == FeedMediaProcessingStatus.failed) {
        return _wrapWithTransform(
          _ProcessingPlaceholder(
            imageProvider: _maybeImageProvider(content.thumbnailUrl),
            title: 'Processing failed',
            subtitle: content.processingError ??
                'Tap to retry once the issue is resolved.',
            icon: Icons.error_outline,
          ),
        );
      }

      final tracks = content.playbackTracks;
      if (tracks.isEmpty) {
        return _wrapWithTransform(
          _ProcessingPlaceholder(
            imageProvider: _maybeImageProvider(content.thumbnailUrl),
            title: 'Video unavailable',
            subtitle: 'We\'re unable to play this video right now.',
            icon: Icons.hourglass_empty,
          ),
        );
      }

      return _wrapWithTransform(
        AdaptiveVideoPlayer(
          tracks: tracks,
          posterImageUrl: content.thumbnailUrl,
          isActive: widget.isActive,
          autoPlay: true,
          loop: true,
          muted: true,
          aspectRatio: content.aspectRatio,
          showControls: false,
          cacheEnabled: true,
        ),
      );
    }

    return _wrapWithTransform(
      Image(
        image: _imageProvider(content.mediaUrl),
        fit: BoxFit.cover,
      ),
    );
  }

  ImageProvider<Object> _imageProvider(String source) {
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(source);
    }
    if (uri != null && uri.scheme == 'file') {
      return FileImage(File(uri.toFilePath()));
    }
    return FileImage(File(source));
  }

  ImageProvider<Object>? _maybeImageProvider(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    return _imageProvider(source);
  }

  Widget _wrapWithTransform(Widget child) {
    final transform = widget.content.compositionTransform;
    if (transform == null || transform.isEmpty) {
      return child;
    }
    return StaticTransformView(
      transformValues: transform,
      child: child,
    );
  }
}

class _ProcessingPlaceholder extends StatelessWidget {
  const _ProcessingPlaceholder({
    this.imageProvider,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final ImageProvider<Object>? imageProvider;
  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageProvider != null)
          Image(image: imageProvider!, fit: BoxFit.cover)
        else
          const DecoratedBox(
            decoration: BoxDecoration(color: Colors.black87),
          ),
        Container(color: Colors.black.withValues(alpha: 0.6)),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 40),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white70,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeedOverlayLayer extends StatelessWidget {
  const _FeedOverlayLayer({required this.overlays});

  final List<FeedTextOverlay> overlays;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (final overlay in overlays)
              Positioned(
                left:
                    overlay.position.dx.clamp(0.0, 1.0) * constraints.maxWidth,
                top:
                    overlay.position.dy.clamp(0.0, 1.0) * constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: overlay.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text(
                      overlay.text,
                      style: TextStyle(
                        color: overlay.color,
                        fontFamily: overlay.fontFamily,
                        fontWeight: overlay.fontWeight,
                        fontStyle: overlay.fontStyle,
                        fontSize: overlay.fontSize,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
