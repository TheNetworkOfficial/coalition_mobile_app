import 'video_timeline.dart';

class VideoDraft {
  const VideoDraft({
    required this.id,
    required this.timeline,
  });

  final String id;
  final VideoTimeline timeline;

  String get sourcePath => timeline.sourcePath;

  VideoDraft copyWith({
    VideoTimeline? timeline,
  }) {
    return VideoDraft(
      id: id,
      timeline: timeline ?? this.timeline,
    );
  }
}

class VideoDraftState {
  const VideoDraftState({
    this.activeDraftId,
    this.drafts = const <String, VideoDraft>{},
  });

  final String? activeDraftId;
  final Map<String, VideoDraft> drafts;

  VideoDraft? get activeDraft =>
      activeDraftId == null ? null : drafts[activeDraftId];

  VideoDraftState copyWith({
    String? activeDraftId,
    Map<String, VideoDraft>? drafts,
  }) {
    return VideoDraftState(
      activeDraftId: activeDraftId ?? this.activeDraftId,
      drafts: drafts ?? this.drafts,
    );
  }
}
