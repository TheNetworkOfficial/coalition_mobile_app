import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_editor/video_editor.dart';

import '../models/video_timeline.dart';
import '../platform/video_native.dart';
import '../providers/video_timeline_provider.dart';

class VideoEditorPage extends ConsumerStatefulWidget {
  const VideoEditorPage({
    super.key,
    required this.filePath,
    this.controllerFactory,
  });

  static const routeName = 'video-editor';

  final String filePath;
  final VideoEditorController Function()? controllerFactory;

  @override
  ConsumerState<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends ConsumerState<VideoEditorPage> {
  late final VideoEditorController _controller;
  bool _isInitialized = false;
  bool _isGeneratingCover = false;
  Rect? _lastCrop;
  int _lastTrimStart = -1;
  int _lastTrimEnd = -1;
  int? _lastCoverTimeMs;
  String? _coverPath;

  @override
  void initState() {
    super.initState();
    _controller = widget.controllerFactory?.call() ??
        VideoEditorController.file(
          File(widget.filePath),
          maxDuration: const Duration(minutes: 10),
        );
    _initializeController();
  }

  Future<void> _initializeController() async {
    try {
      await _controller.initialize();
      if (!mounted) return;
      final durationMs = _controller.videoDuration.inMilliseconds;
      ref.read(videoTimelineProvider.notifier).initialize(
            durationMs: durationMs,
          );
      _controller.addListener(_syncFromController);
      _controller.selectedCoverNotifier.addListener(_handleCoverSelection);
      _syncFromController();
      _handleCoverSelection();
      await _controller.video.setLooping(true);
      await _controller.video.play();
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to initialize editor: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load video editor.')),
      );
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFromController);
    _controller.selectedCoverNotifier.removeListener(_handleCoverSelection);
    _controller.dispose();
    super.dispose();
  }

  void _syncFromController() {
    if (!_controller.initialized) {
      return;
    }
    final durationMs = math.max(0, _controller.videoDuration.inMilliseconds);
    if (durationMs == 0) {
      return;
    }
    final startMs = (_controller.minTrim * durationMs).round();
    final endMs = (_controller.maxTrim * durationMs).round();
    if (startMs != _lastTrimStart || endMs != _lastTrimEnd) {
      _lastTrimStart = startMs;
      _lastTrimEnd = endMs;
      ref.read(videoTimelineProvider.notifier).setTrim(
            startMs: startMs,
            endMs: endMs,
          );
    }

    final rect = Rect.fromLTRB(
      _controller.minCrop.dx,
      _controller.minCrop.dy,
      _controller.maxCrop.dx,
      _controller.maxCrop.dy,
    );
    if (_lastCrop == null || !_rectEquals(_lastCrop!, rect)) {
      _lastCrop = rect;
      ref.read(videoTimelineProvider.notifier).setCrop(rect);
    }
  }

  void _handleCoverSelection() {
    final cover = _controller.selectedCoverVal;
    if (cover == null) {
      return;
    }
    final timeMs = cover.timeMs;
    if (_lastCoverTimeMs == timeMs) {
      return;
    }
    _lastCoverTimeMs = timeMs;
    ref.read(videoTimelineProvider.notifier).setCover(timeMs);
    unawaited(_generateCover(timeMs));
  }

  Future<void> _generateCover(int timeMs) async {
    setState(() => _isGeneratingCover = true);
    try {
      final native = ref.read(videoNativeProvider);
      final path = await native.generateCoverImage(
        widget.filePath,
        seconds: timeMs / 1000.0,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _coverPath = path;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to generate cover: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate cover image.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCover = false);
      }
    }
  }

  bool _rectEquals(Rect a, Rect b) {
    const precision = 0.0005;
    return (a.left - b.left).abs() < precision &&
        (a.top - b.top).abs() < precision &&
        (a.right - b.right).abs() < precision &&
        (a.bottom - b.bottom).abs() < precision;
  }

  void _onContinue(VideoTimeline timeline) {
    final extras = {
      'filePath': widget.filePath,
      'timelineJson': timeline.toJson(),
      if (_coverPath != null && _coverPath!.isNotEmpty) 'coverPath': _coverPath!,
    };
    context.go('/create/video/post', extra: extras);
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(videoTimelineProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit video'),
        actions: [
          IconButton(
            onPressed: _isInitialized
                ? () {
                    if (_controller.isPlaying) {
                      _controller.video.pause();
                    } else {
                      _controller.video.play();
                    }
                    setState(() {});
                  }
                : null,
            icon: Icon(
              _controller.isPlaying ? Icons.pause : Icons.play_arrow,
            ),
          ),
        ],
      ),
      body: !_isInitialized
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _buildEditorBody(timeline),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: ElevatedButton(
            onPressed: _isInitialized ? () => _onContinue(timeline) : null,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Continue'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEditorBody(VideoTimeline timeline) {
    final videoValue = _controller.video.value;
    final aspectRatio = videoValue.isInitialized && videoValue.aspectRatio > 0
        ? videoValue.aspectRatio
        : 9 / 16;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CropGridViewer.edit(controller: _controller),
                if (_isGeneratingCover)
                  const Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Trim',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TrimSlider(
                  controller: _controller,
                  height: 72,
                  horizontalMargin: 0,
                  child: TrimTimeline(controller: _controller),
                ),
                const SizedBox(height: 24),
                Text(
                  'Cover',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                CoverSelection(
                  controller: _controller,
                  size: 72,
                  quantity: 6,
                  selectedCoverBuilder: (cover, size) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: size.width,
                            height: size.height,
                            child: cover,
                          ),
                        ),
                        if (_isGeneratingCover)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Speed ${timeline.speed.toStringAsFixed(2)}×',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Slider(
                  min: 0.25,
                  max: 4.0,
                  divisions: 15,
                  label: '${timeline.speed.toStringAsFixed(2)}×',
                  value: timeline.speed.clamp(0.25, 4.0),
                  onChanged: (value) {
                    ref
                        .read(videoTimelineProvider.notifier)
                        .setSpeed(value);
                    _controller.video.setPlaybackSpeed(value);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
