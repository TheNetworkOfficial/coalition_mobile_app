import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
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
            ),
            SwitchListTile(
              value: _isPrivate,
              title: const Text('Private'),
              onChanged: (value) {
                setState(() {
                  _isPrivate = value;
                });
              },
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: timeline == null
                    ? null
                    : () {
                        // In the real flow this would trigger upload logic.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Video posted!')),
                        );
                        Navigator.of(context).pop();
                      },
                child: const Text('Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
