import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/video_timeline.dart';

class VideoTimelineNotifier extends Notifier<VideoTimeline?> {
  @override
  VideoTimeline? build() => null;

  void loadSource(String sourcePath) {
    state = VideoTimeline.initial(sourcePath);
  }

  void updateTimeline(VideoTimeline timeline) {
    state = timeline;
  }

  void updateTrim({int? startMs, int? endMs}) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(
      trimStartMs: startMs ?? current.trimStartMs,
      trimEndMs: endMs ?? current.trimEndMs,
    );
  }

  void setPlaybackSpeed(double speed) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(playbackSpeed: speed);
  }

  void setFilter(String? filterId) {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.copyWith(filterId: filterId);
  }

  void reset() {
    final current = state;
    if (current == null) {
      return;
    }
    state = VideoTimeline.initial(current.sourcePath);
  }
}

final videoTimelineProvider =
    NotifierProvider<VideoTimelineNotifier, VideoTimeline?>(
  VideoTimelineNotifier.new,
);
