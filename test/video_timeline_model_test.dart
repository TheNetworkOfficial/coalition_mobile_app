import 'dart:ui';

import 'package:coalition_mobile_app/features/video/models/video_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VideoTimeline round-trips through JSON', () {
    const timeline = VideoTimeline(
      sourcePath: '/tmp/source.mp4',
      trimStartMs: 1500,
      trimEndMs: 12_500,
      cropRect: Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
      filterId: 'warm',
      playbackSpeed: 1.5,
      overlayItems: <VideoOverlayItem>[
        VideoOverlayItem(id: 'text-1', label: 'Title'),
      ],
      coverTimeMs: 4000,
      coverImagePath: '/tmp/cover.png',
    );

    final json = timeline.toJson();
    final restored = VideoTimeline.fromJson(json);

    expect(restored.sourcePath, timeline.sourcePath);
    expect(restored.trimStartMs, timeline.trimStartMs);
    expect(restored.trimEndMs, timeline.trimEndMs);
    expect(restored.cropRect, timeline.cropRect);
    expect(restored.filterId, timeline.filterId);
    expect(restored.playbackSpeed, timeline.playbackSpeed);
    expect(restored.overlayItems.length, timeline.overlayItems.length);
    expect(restored.coverTimeMs, timeline.coverTimeMs);
  });
}
