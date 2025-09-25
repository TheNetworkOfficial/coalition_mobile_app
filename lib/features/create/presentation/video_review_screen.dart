import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoReviewResult {
  const VideoReviewResult({
    required this.mediaPath,
    required this.aspectRatio,
    required this.duration,
  });

  final String mediaPath;
  final double aspectRatio;
  final Duration duration;
}

class VideoReviewScreen extends StatefulWidget {
  const VideoReviewScreen({
    required this.mediaPath,
    required this.aspectRatio,
    super.key,
  });

  final String mediaPath;
  final double aspectRatio;

  @override
  State<VideoReviewScreen> createState() => _VideoReviewScreenState();
}

class _VideoReviewScreenState extends State<VideoReviewScreen> {
  late final VideoPlayerController _controller;
  Future<void>? _initialization;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.mediaPath))
      ..setLooping(true)
      ..setVolume(1.0);
    _initialization = _controller.initialize().then((_) {
      if (mounted) {
        _controller.play();
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          final isReady = snapshot.connectionState == ConnectionState.done;
          return Stack(
            children: [
              Positioned.fill(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.isInitialized
                        ? _controller.value.aspectRatio
                        : widget.aspectRatio,
                    child: _controller.value.isInitialized
                        ? VideoPlayer(_controller)
                        : const ColoredBox(color: Colors.black),
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                left: 12,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 48,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(32),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.music_note, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          'Add sound',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: MediaQuery.of(context).padding.top + 120,
                child: const Column(
                  children: [
                    _EditToolButton(icon: Icons.tune, label: 'Adjust'),
                    SizedBox(height: 16),
                    _EditToolButton(icon: Icons.text_fields, label: 'Text'),
                    SizedBox(height: 16),
                    _EditToolButton(icon: Icons.filter_none, label: 'Effects'),
                    SizedBox(height: 16),
                    _EditToolButton(icon: Icons.timer, label: 'Timer'),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildBottomBar(context, isReady),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isReady) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).padding.bottom + 12,
        top: 16,
      ),
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
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                ),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('AutoCut'),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
                ),
                child: const Text('Your Story'),
              ),
            ),
            const SizedBox(width: 16),
            FilledButton(
              onPressed: isReady ? _submit : null,
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                backgroundColor: const Color(0xfffe2c55),
              ),
              child: const Text('Next'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final controllerValue = _controller.value;
    final aspectRatio =
        controllerValue.isInitialized && controllerValue.aspectRatio > 0
            ? controllerValue.aspectRatio
            : widget.aspectRatio;
    final duration = controllerValue.isInitialized
        ? controllerValue.duration
        : const Duration(seconds: 1);

    Navigator.of(context).pop(
      VideoReviewResult(
        mediaPath: widget.mediaPath,
        aspectRatio: aspectRatio,
        duration: duration,
      ),
    );
  }
}

class _EditToolButton extends StatelessWidget {
  const _EditToolButton({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, color: Colors.white),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
