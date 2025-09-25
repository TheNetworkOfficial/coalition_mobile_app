import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

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
          onPressed: () async {
            final picker = ImagePicker();

            try {
              final pickedFile = await picker.pickVideo(
                source: ImageSource.gallery,
              );

              if (pickedFile == null) {
                return;
              }

              ref
                  .read(videoTimelineProvider.notifier)
                  .loadSource(pickedFile.path);

              if (!context.mounted) {
                return;
              }

              context.goNamed(
                VideoEditorPage.routeName,
                extra: pickedFile.path,
              );
            } on PlatformException catch (error) {
              if (!context.mounted) {
                return;
              }

              final message = error.message ?? 'Unable to pick video.';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            }
          },
          child: const Text('Pick from gallery'),
        ),
      ),
    );
  }
}
