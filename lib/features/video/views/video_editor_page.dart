import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../models/video_draft.dart';
import '../models/video_timeline.dart';
import '../providers/video_draft_provider.dart';
import 'video_post_page.dart';

class VideoEditorPage extends ConsumerStatefulWidget {
  const VideoEditorPage({super.key, this.draftId});

  static const routeName = 'video-editor';

  final String? draftId;

  @override
  ConsumerState<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends ConsumerState<VideoEditorPage> {
  VideoPlayerController? _controller;
  bool _isGeneratingCover = false;

  @override
  void initState() {
    super.initState();

    if (widget.draftId != null) {
      ref.read(videoDraftsProvider.notifier).setActiveDraft(widget.draftId);
    }

    final draft = ref.read(activeVideoDraftProvider);
    if (draft != null) {
      _initializeController(draft.timeline);
    }

    ref.listen<VideoTimeline?>(
      activeVideoTimelineProvider,
      (previous, next) {
        if (!mounted) {
          return;
        }
        if (next == null) {
          _disposeController();
          return;
        }
        if (previous?.sourcePath != next.sourcePath) {
          _initializeController(next);
        }
      },
    );
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  Future<void> _initializeController(VideoTimeline timeline) async {
    await _controller?.dispose();
    final controller = VideoPlayerController.file(File(timeline.sourcePath));
    setState(() {
      _controller = controller;
    });
    try {
      await controller.initialize();
      if (!mounted) {
        return;
      }
      await controller.setLooping(true);
      await controller.play();
      setState(() {});
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to load video preview.')),
      );
    }
  }

  void _disposeController() {
    final controller = _controller;
    _controller = null;
    controller?.dispose();
  }

  Future<void> _handleCoverSelection(
    VideoTimeline timeline,
    double positionSeconds,
  ) async {
    setState(() {
      _isGeneratingCover = true;
    });
    final timeMs = (positionSeconds * 1000).round();
    try {
      await ref
          .read(videoDraftsProvider.notifier)
          .generateCover(timeMs: timeMs);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate cover image: $error'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingCover = false;
        });
      }
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildPreview(VideoPlayerController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),
              Positioned(
                bottom: 8,
                right: 8,
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                  ),
                  icon: Icon(
                    controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    if (controller.value.isPlaying) {
                      controller.pause();
                    } else {
                      controller.play();
                    }
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(activeVideoDraftProvider);
    final timeline = draft?.timeline;
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit video')),
      body: timeline == null
          ? const Center(
              child: Text('Select a clip to begin editing'),
            )
          : _buildEditor(context, draft!, controller),
    );
  }

  Widget _buildEditor(
    BuildContext context,
    VideoDraft draft,
    VideoPlayerController? controller,
  ) {
    final timeline = draft.timeline;
    final isInitialized = controller?.value.isInitialized ?? false;
    final duration = isInitialized ? controller!.value.duration : Duration.zero;
    final durationSeconds =
        duration.inMilliseconds > 0 ? duration.inMilliseconds / 1000 : 0.0;
    final sliderMax = durationSeconds <= 0 ? 1.0 : durationSeconds;
    final readyController = isInitialized ? controller : null;

    final trimStartSeconds =
        ((timeline.trimStartMs ?? 0) / 1000).clamp(0, sliderMax).toDouble();
    final trimEndSeconds =
        ((timeline.trimEndMs ?? duration.inMilliseconds) / 1000)
            .clamp(trimStartSeconds, sliderMax)
            .toDouble();
    final coverSeconds =
        ((timeline.coverTimeMs ?? 0) / 1000).clamp(0, sliderMax).toDouble();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller == null)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (!isInitialized)
            const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            )
          else
            _buildPreview(readyController!),
          const SizedBox(height: 24),
          Text(
            'Trim',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!isInitialized)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            RangeSlider(
              values: RangeValues(trimStartSeconds, trimEndSeconds),
              min: 0,
              max: sliderMax,
              divisions: durationSeconds > 0 ? duration.inSeconds : null,
              labels: RangeLabels(
                _formatDuration(
                  Duration(milliseconds: (trimStartSeconds * 1000).round()),
                ),
                _formatDuration(
                  Duration(milliseconds: (trimEndSeconds * 1000).round()),
                ),
              ),
              onChanged: (values) {
                final startMs = (values.start * 1000).round();
                final endMs = (values.end * 1000).round();
                ref.read(videoDraftsProvider.notifier).updateTrim(
                      startMs: startMs,
                      endMs: endMs,
                    );
                readyController!.seekTo(Duration(milliseconds: startMs));
                setState(() {});
              },
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Start: ${_formatDuration(Duration(milliseconds: (trimStartSeconds * 1000).round()))}',
                ),
                Text(
                  'End: ${_formatDuration(Duration(milliseconds: (trimEndSeconds * 1000).round()))}',
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
          Text(
            'Cover frame',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (!isInitialized)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            Slider(
              value: coverSeconds,
              min: 0,
              max: sliderMax,
              divisions: durationSeconds > 0 ? duration.inSeconds : null,
              label: _formatDuration(
                Duration(milliseconds: (coverSeconds * 1000).round()),
              ),
              onChanged: (value) {
                final ms = (value * 1000).round();
                ref.read(videoDraftsProvider.notifier).setCoverTime(ms);
                readyController!.seekTo(Duration(milliseconds: ms));
                setState(() {});
              },
              onChangeEnd: (value) => _handleCoverSelection(
                timeline,
                value,
              ),
            ),
            if (_isGeneratingCover)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(),
              ),
            if (timeline.coverImagePath != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cover preview',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  AspectRatio(
                    aspectRatio: readyController!.value.aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(timeline.coverImagePath!),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
          ],
          const SizedBox(height: 32),
          Text(
            'Editing ${timeline.sourcePath}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context.goNamed(
              VideoPostPage.routeName,
              extra: draft.id,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
