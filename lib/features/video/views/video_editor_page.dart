import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/video_timeline_provider.dart';
import 'video_post_page.dart';

class VideoEditorPage extends ConsumerWidget {
  const VideoEditorPage({super.key});

  static const routeName = 'video-editor';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeline = ref.watch(videoTimelineProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit video')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (timeline == null)
              const Text('Select a clip to begin editing')
            else
              Text('Editing ${timeline.sourcePath}'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: timeline == null
                  ? null
                  : () => context.goNamed(VideoPostPage.routeName),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }
}
