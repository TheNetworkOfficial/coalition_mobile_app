import 'dart:ui';

import 'package:coalition_mobile_app/features/video/providers/video_timeline_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('VideoTimelineNotifier initializes and updates values', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(videoTimelineProvider.notifier);
    notifier.initialize(durationMs: 20_000);

    expect(container.read(videoTimelineProvider).trimStartMs, 0);
    expect(container.read(videoTimelineProvider).trimEndMs, 20_000);

    notifier.setTrim(startMs: 1_500, endMs: 8_500);
    expect(container.read(videoTimelineProvider).trimStartMs, 1_500);
    expect(container.read(videoTimelineProvider).trimEndMs, 8_500);

    notifier.setCrop(const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));
    expect(container.read(videoTimelineProvider).cropRect,
        const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));

    notifier.setSpeed(2.0);
    expect(container.read(videoTimelineProvider).speed, closeTo(2.0, 0.001));

    notifier.setCover(3500);
    expect(container.read(videoTimelineProvider).coverTimeMs, 3500);
  });
}
