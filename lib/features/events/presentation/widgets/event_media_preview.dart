import 'dart:io';

import 'package:flutter/material.dart';

import 'package:coalition_mobile_app/core/utils/media_type_utils.dart';

import '../../../../core/video/adaptive_video_player.dart';
import '../../../../core/video/video_track.dart';
import '../../../feed/domain/feed_content.dart';
import '../../domain/event.dart';

class EventMediaPreview extends StatelessWidget {
  const EventMediaPreview({
    required this.mediaUrl,
    required this.mediaType,
    required this.aspectRatio,
    required this.overlays,
    this.coverImagePath,
    this.autoplay = false,
    this.videoTracks = const <VideoTrack>[],
    super.key,
  });

  final String mediaUrl;
  final EventMediaType? mediaType;
  final double aspectRatio;
  final List<FeedTextOverlay> overlays;
  final String? coverImagePath;
  final bool autoplay;
  final List<VideoTrack> videoTracks;

  @override
  Widget build(BuildContext context) {
    final ratio = aspectRatio <= 0 ? 16 / 9 : aspectRatio;
    return AspectRatio(
      aspectRatio: ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMedia(),
            if (overlays.isNotEmpty)
              Positioned.fill(
                child: _OverlayLayer(overlays: overlays),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMedia() {
    if (mediaType == EventMediaType.video) {
      final tracks = videoTracks.isNotEmpty
          ? videoTracks
          : <VideoTrack>[
              VideoTrack(
                uri: VideoTrack.ensureUri(mediaUrl),
                label: 'Source',
              ),
            ];
      final posterImage =
          isLikelyImageSource(coverImagePath) ? coverImagePath : null;
      return AdaptiveVideoPlayer(
        tracks: tracks,
        posterImageUrl: posterImage,
        isActive: autoplay,
        autoPlay: autoplay,
        loop: true,
        muted: true,
        aspectRatio: aspectRatio,
        showControls: true,
        cacheEnabled: true,
      );
    }

    final imageSource = isLikelyImageSource(coverImagePath)
        ? coverImagePath
        : (isLikelyImageSource(mediaUrl) ? mediaUrl : null);
    if (imageSource == null) {
      return const _EventPreviewPlaceholder();
    }
    return Image(
      image: _imageProvider(imageSource),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const _EventPreviewPlaceholder(),
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
}

class _EventPreviewPlaceholder extends StatelessWidget {
  const _EventPreviewPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black26),
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          color: Colors.white60,
          size: 28,
        ),
      ),
    );
  }
}

class _OverlayLayer extends StatelessWidget {
  const _OverlayLayer({required this.overlays});

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
