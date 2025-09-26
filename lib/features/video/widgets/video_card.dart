import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoCard extends StatefulWidget {
  const VideoCard({
    super.key,
    required this.thumbnailUrl,
    required this.playbackUrl,
    required this.caption,
    this.isActive = true,
  });

  final String thumbnailUrl;
  final String playbackUrl;
  final String caption;
  final bool isActive;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard>
    with AutomaticKeepAliveClientMixin<VideoCard> {
  VideoPlayerController? _controller;
  bool _showPoster = true;
  bool _isBuffering = true;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeController());
  }

  @override
  void didUpdateWidget(covariant VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playbackUrl != oldWidget.playbackUrl) {
      unawaited(_initializeController());
    }

    final controller = _controller;
    if (controller != null && widget.isActive != oldWidget.isActive) {
      if (widget.isActive) {
        if (controller.value.isInitialized) {
          controller.play();
        }
      } else {
        controller.pause();
      }
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_handleControllerUpdate);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final controller = _controller;
    final isInitialized = controller?.value.isInitialized ?? false;
    final aspectRatio = isInitialized ? controller!.value.aspectRatio : 9 / 16;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isInitialized)
            VideoPlayer(controller!)
          else
            const ColoredBox(color: Colors.black),
          AnimatedOpacity(
            opacity: _showPoster ? 1 : 0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  widget.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, _, __) => const ColoredBox(
                    color: Colors.black,
                  ),
                ),
                if (_isBuffering)
                  const Center(
                    child: SizedBox(
                      height: 40,
                      width: 40,
                      child: CircularProgressIndicator.adaptive(),
                    ),
                  ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                child: Text(
                  widget.caption,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ) ??
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _initializeController() async {
    final oldController = _controller;
    oldController?.removeListener(_handleControllerUpdate);
    await oldController?.dispose();

    if (!mounted) {
      return;
    }

    setState(() {
      _controller = null;
      _showPoster = true;
      _isBuffering = true;
    });

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.playbackUrl),
      videoPlayerOptions: const VideoPlayerOptions(mixWithOthers: true),
    );

    await controller.initialize();
    await controller.setVolume(0);
    await controller.setLooping(true);
    controller.addListener(_handleControllerUpdate);

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _updatePosterState(controller.value);
    });

    if (widget.isActive) {
      await controller.play();
    }
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    _updatePosterState(controller.value);
  }

  void _updatePosterState(VideoPlayerValue value) {
    final shouldShowPoster = !value.isInitialized || value.isBuffering;
    final isBuffering = value.isBuffering;
    if (shouldShowPoster != _showPoster || isBuffering != _isBuffering) {
      setState(() {
        _showPoster = shouldShowPoster;
        _isBuffering = isBuffering;
      });
    }
  }

  @override
  bool get wantKeepAlive => true;
}
