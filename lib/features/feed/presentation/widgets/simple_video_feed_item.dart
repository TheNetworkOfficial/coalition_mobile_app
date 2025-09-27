import 'package:flutter/material.dart';

import '../../../video/widgets/video_card.dart';

class SimpleVideoFeedItem extends StatelessWidget {
  const SimpleVideoFeedItem({
    super.key,
    required this.isActive,
  });

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
        ),
        child: VideoCard(
          thumbnailUrl:
              'https://storage.googleapis.com/gtv-videos-bucket/sample/images/BigBuckBunny.jpg',
          playbackUrl:
              'https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.m3u8',
          caption: 'See how we are investing in Montana\'s outdoor economy.',
          isActive: isActive,
        ),
      ),
    );
  }
}
