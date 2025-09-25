import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_timeline.dart';
import '../platform/video_native.dart';
import '../providers/video_timeline_provider.dart';

class VideoPostPage extends ConsumerStatefulWidget {
  const VideoPostPage({super.key});

  static const routeName = 'video-post';

  @override
  ConsumerState<VideoPostPage> createState() => _VideoPostPageState();
}

class _VideoPostPageState extends ConsumerState<VideoPostPage> {
  final _captionController = TextEditingController();
  bool _isPrivate = false;
  bool _isExporting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _onPostPressed(VideoTimeline timeline) async {
    setState(() {
      _isExporting = true;
      _errorMessage = null;
    });

    try {
      final timelineJson = _buildTimelineJson(timeline);
      final exportedPath = await VideoNative.exportEdits(
        filePath: timeline.sourcePath,
        timelineJson: timelineJson,
        targetBitrateBps: 6_000_000,
      );

      final coverPath = timeline.coverImagePath;

      await _uploadVideo(exportedPath, coverPath);

      if (!mounted) return;
      setState(() {
        _isExporting = false;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video posted!')),
      );
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      // In a production environment this would be reported to crash logging.
      debugPrint('Failed to export video: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _isExporting = false;
        _errorMessage = 'Failed to export video. Please try again.';
      });
    }
  }

  Map<String, dynamic> _buildTimelineJson(VideoTimeline timeline) {
    final map = <String, dynamic>{};

    final trimStart = timeline.trimStartMs;
    final trimEnd = timeline.trimEndMs;
    if (trimStart != null || trimEnd != null) {
      map['trim'] = <String, dynamic>{
        if (trimStart != null) 'startSeconds': trimStart / 1000,
        if (trimEnd != null) 'endSeconds': trimEnd / 1000,
      };
    }

    final crop = timeline.cropRect;
    if (crop != null) {
      map['crop'] = <String, dynamic>{
        'left': crop.left,
        'top': crop.top,
        'right': crop.right,
        'bottom': crop.bottom,
      };
    }

    // Additional effects, filters, and overlays can be serialized here as they
    // are implemented in the editing flow.

    return map;
  }

  Future<void> _uploadVideo(String videoPath, String? coverImagePath) {
    // TODO: Replace with upload service integration. This will hand off the
    // exported MP4 at [videoPath] and the optional PNG cover at [coverImagePath].
    return Future<void>.value();
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(videoTimelineProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Post video')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(labelText: 'Caption'),
              enabled: !_isExporting,
            ),
            SwitchListTile(
              value: _isPrivate,
              title: const Text('Private'),
              onChanged: _isExporting
                  ? null
                  : (value) {
                      setState(() {
                        _isPrivate = value;
                      });
                    },
            ),
            if (_isExporting) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Exporting video...'),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: timeline == null || _isExporting
                    ? null
                    : () => _onPostPressed(timeline),
                child: const Text('Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
