import 'dart:math';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_timeline.dart';

class VideoTimelineNotifier extends Notifier<VideoTimeline> {
  @override
  VideoTimeline build() => const VideoTimeline(
        trimStartMs: 0,
        trimEndMs: 0,
        cropRect: null,
        speed: 1.0,
        coverTimeMs: 0,
      );

  void initialize({required int durationMs}) {
    final safeDuration = max(0, durationMs);
    state = state.copyWith(
      trimStartMs: 0,
      trimEndMs: safeDuration,
      speed: 1.0,
      coverTimeMs: 0,
      resetCrop: true,
    );
  }

  void setTrim({int? startMs, int? endMs}) {
    var start = startMs ?? state.trimStartMs;
    var end = endMs ?? state.trimEndMs;
    if (start < 0) start = 0;
    if (end < start) {
      end = start;
    }
    state = state.copyWith(trimStartMs: start, trimEndMs: end);
  }

  void setCrop(Rect? cropRect) {
    if (cropRect == null) {
      state = state.copyWith(resetCrop: true);
    } else {
      state = state.copyWith(cropRect: cropRect);
    }
  }

  void setSpeed(double speed) {
    final clamped = speed.clamp(0.25, 4.0).toDouble();
    state = state.copyWith(speed: clamped);
  }

  void setCover(int timeMs) {
    final cover = max(0, timeMs);
    state = state.copyWith(coverTimeMs: cover);
  }

  void resetToDuration(int durationMs) {
    initialize(durationMs: durationMs);
  }
}

final videoTimelineProvider =
    NotifierProvider<VideoTimelineNotifier, VideoTimeline>(
  VideoTimelineNotifier.new,
);
