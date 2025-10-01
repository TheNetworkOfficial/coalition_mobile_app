import 'dart:ui';

import 'package:coalition_mobile_app/features/video/models/video_timeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VideoTimeline round-trips through JSON', () {
    const timeline = VideoTimeline(
      trimStartMs: 1500,
      trimEndMs: 12_500,
      cropRect: Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
      speed: 1.5,
      coverTimeMs: 4000,
    );

    final json = timeline.toJson();
    final restored = VideoTimeline.fromJson(json);

    expect(restored.trimStartMs, timeline.trimStartMs);
    expect(restored.trimEndMs, timeline.trimEndMs);
    expect(restored.cropRect, timeline.cropRect);
    expect(restored.speed, timeline.speed);
    expect(restored.coverTimeMs, timeline.coverTimeMs);
  });

  test('VideoTimeline exports transformer compatible JSON', () {
    const timeline = VideoTimeline(
      trimStartMs: 1500,
      trimEndMs: 12_500,
      cropRect: Rect.fromLTRB(0.1, 0.2, 0.9, 0.8),
      speed: 1.25,
    );

    final transformerJson = timeline.toTransformerJson();

    expect(transformerJson['trim'], {
      'startSeconds': 1.5,
      'endSeconds': 12.5,
    });
    expect(transformerJson['crop'], {
      'left': 0.1,
      'top': 0.2,
      'right': 0.9,
      'bottom': 0.8,
    });
    expect(transformerJson['speed'], 1.25);
  });
}
