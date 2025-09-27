import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_timeline.dart';

class VideoTimelineNotifier extends Notifier<VideoTimeline> {
  @override
  VideoTimeline build() => const VideoTimeline();

  void setTrimStart(int value) {
    state = state.copyWith(trimStartMs: value);
  }

  void setTrimEnd(int value) {
    state = state.copyWith(trimEndMs: value);
  }

  void setCropRect(Rect? rect) {
    state = state.copyWith(cropRect: rect);
  }

  void setSpeed(double value) {
    state = state.copyWith(speed: value);
  }

  void setLutId(String? value) {
    state = state.copyWith(lutId: value);
  }

  void setOverlays(List<OverlayItem> overlays) {
    state = state.copyWith(overlays: overlays);
  }

  void setCoverTime(int value) {
    state = state.copyWith(coverTimeMs: value);
  }
}

final videoTimelineProvider =
    NotifierProvider<VideoTimelineNotifier, VideoTimeline>(
  VideoTimelineNotifier.new,
);
