import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../feed/domain/feed_content.dart';
import '../../domain/event.dart';

class EventMediaPreview extends StatefulWidget {
  const EventMediaPreview({
    required this.mediaUrl,
    required this.mediaType,
    required this.aspectRatio,
    required this.overlays,
    this.coverImagePath,
    this.autoplay = false,
    super.key,
  });

  final String mediaUrl;
  final EventMediaType? mediaType;
  final double aspectRatio;
  final List<FeedTextOverlay> overlays;
  final String? coverImagePath;
  final bool autoplay;

  @override
  State<EventMediaPreview> createState() => _EventMediaPreviewState();
}

class _EventMediaPreviewState extends State<EventMediaPreview> {
  VideoPlayerController? _controller;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    if (widget.mediaType == EventMediaType.video) {
      _initializeVideo();
    }
  }

  @override
  void didUpdateWidget(covariant EventMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mediaUrl != oldWidget.mediaUrl &&
        widget.mediaType == EventMediaType.video) {
      _disposeController();
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = widget.aspectRatio <= 0 ? 16 / 9 : widget.aspectRatio;
    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildMedia(),
            if (widget.overlays.isNotEmpty)
              Positioned.fill(
                child: _OverlayLayer(overlays: widget.overlays),
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
    if (widget.mediaType == EventMediaType.video) {
      final controller = _controller;
      return FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done ||
              controller == null) {
            return _buildFallback();
          }
          if (widget.autoplay && !controller.value.isPlaying) {
            controller.play();
          }
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          );
        },
      );
    }

    return Image(
      image: _imageProvider(widget.coverImagePath ?? widget.mediaUrl),
      fit: BoxFit.cover,
    );
  }

  Widget _buildFallback() {
    if (widget.coverImagePath != null) {
      return Image(
        image: _imageProvider(widget.coverImagePath!),
        fit: BoxFit.cover,
      );
    }
    return const ColoredBox(
      color: Colors.black12,
      child: Center(child: CircularProgressIndicator.adaptive()),
    );
  }

  void _initializeVideo() {
    final controller = _buildVideoController(widget.mediaUrl)
      ..setLooping(true)
      ..setVolume(0);
    _initialization = controller.initialize().then((_) {
      if (mounted && widget.autoplay) {
        controller.play();
      }
    });
    _controller = controller;
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _initialization = null;
  }

  VideoPlayerController _buildVideoController(String source) {
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return VideoPlayerController.networkUrl(uri);
    }
    if (uri != null && uri.scheme == 'file') {
      return VideoPlayerController.file(File(uri.toFilePath()));
    }
    return VideoPlayerController.file(File(source));
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
