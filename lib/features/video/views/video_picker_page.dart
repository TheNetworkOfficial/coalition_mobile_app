import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/video_timeline_provider.dart';
import 'video_editor_page.dart';

class VideoPickerPage extends ConsumerWidget {
  const VideoPickerPage({super.key});

  static const routeName = 'video-picker';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select video')),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            // In a real implementation this would invoke a gallery picker.
            ref.read(videoTimelineProvider.notifier).loadSource('mock/path.mp4');
            context.goNamed(VideoEditorPage.routeName);
          },
          child: const Text('Pick from gallery'),
        ),
      ),
    );
  }
}
