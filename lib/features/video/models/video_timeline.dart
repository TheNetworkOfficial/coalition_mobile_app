import 'dart:ui';

/// Describes a set of non-destructive edits that can be applied to a video.
class VideoTimeline {
  const VideoTimeline({
    required this.sourcePath,
    this.trimStartMs,
    this.trimEndMs,
    this.cropRect,
    this.filterId,
    this.playbackSpeed = 1.0,
    this.overlayItems = const <VideoOverlayItem>[],
    this.coverTimeMs,
  });

  /// Creates an empty timeline for the provided [sourcePath].
  factory VideoTimeline.initial(String sourcePath) => VideoTimeline(
        sourcePath: sourcePath,
        trimStartMs: 0,
        coverTimeMs: 0,
      );

  /// Location of the original video on disk.
  final String sourcePath;

  /// Inclusive start trim position in milliseconds.
  final int? trimStartMs;

  /// Exclusive end trim position in milliseconds.
  final int? trimEndMs;

  /// The crop rectangle applied to the source video, if any.
  final Rect? cropRect;

  /// Identifier for the selected filter or LUT.
  final String? filterId;

  /// Playback speed multiplier.
  final double playbackSpeed;

  /// Overlays (stickers, text, etc.) positioned on the timeline.
  final List<VideoOverlayItem> overlayItems;

  /// Cover frame time in milliseconds.
  final int? coverTimeMs;

  VideoTimeline copyWith({
    String? sourcePath,
    int? trimStartMs,
    int? trimEndMs,
    Rect? cropRect,
    String? filterId,
    double? playbackSpeed,
    List<VideoOverlayItem>? overlayItems,
    int? coverTimeMs,
  }) {
    return VideoTimeline(
      sourcePath: sourcePath ?? this.sourcePath,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      cropRect: cropRect ?? this.cropRect,
      filterId: filterId ?? this.filterId,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      overlayItems: overlayItems ?? this.overlayItems,
      coverTimeMs: coverTimeMs ?? this.coverTimeMs,
    );
  }
}

/// Describes a single overlay element applied on top of the video timeline.
class VideoOverlayItem {
  const VideoOverlayItem({
    required this.id,
    this.label,
  });

  /// Unique identifier for the overlay.
  final String id;

  /// Optional developer-friendly label.
  final String? label;
}
