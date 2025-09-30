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
    this.coverImagePath,
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

  /// Cached path to the generated PNG cover image on disk.
  final String? coverImagePath;


  Map<String, dynamic> toJson() => <String, dynamic>{
        'sourcePath': sourcePath,
        if (trimStartMs != null) 'trimStartMs': trimStartMs,
        if (trimEndMs != null) 'trimEndMs': trimEndMs,
        if (cropRect != null)
          'cropRect': <String, double>{
            'left': cropRect!.left,
            'top': cropRect!.top,
            'right': cropRect!.right,
            'bottom': cropRect!.bottom,
          },
        if (filterId != null) 'filterId': filterId,
        'playbackSpeed': playbackSpeed,
        'overlayItems': overlayItems.map((item) => item.toJson()).toList(),
        if (coverTimeMs != null) 'coverTimeMs': coverTimeMs,
        if (coverImagePath != null) 'coverImagePath': coverImagePath,
      };

  factory VideoTimeline.fromJson(Map<String, dynamic> json) {
    final crop = json['cropRect'];
    Rect? rect;
    if (crop is Map<String, dynamic>) {
      rect = Rect.fromLTRB(
        (crop['left'] as num).toDouble(),
        (crop['top'] as num).toDouble(),
        (crop['right'] as num).toDouble(),
        (crop['bottom'] as num).toDouble(),
      );
    }
    final overlaysJson = json['overlayItems'];
    final overlays = overlaysJson is List
        ? overlaysJson
            .whereType<Map<String, dynamic>>()
            .map(VideoOverlayItem.fromJson)
            .toList(growable: false)
        : const <VideoOverlayItem>[];
    return VideoTimeline(
      sourcePath: json['sourcePath'] as String,
      trimStartMs: (json['trimStartMs'] as num?)?.toInt(),
      trimEndMs: (json['trimEndMs'] as num?)?.toInt(),
      cropRect: rect,
      filterId: json['filterId'] as String?,
      playbackSpeed: (json['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      overlayItems: overlays,
      coverTimeMs: (json['coverTimeMs'] as num?)?.toInt(),
      coverImagePath: json['coverImagePath'] as String?,
    );
  }
  VideoTimeline copyWith({
    String? sourcePath,
    int? trimStartMs,
    int? trimEndMs,
    Rect? cropRect,
    String? filterId,
    double? playbackSpeed,
    List<VideoOverlayItem>? overlayItems,
    int? coverTimeMs,
    Object? coverImagePath = _unset,
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
      coverImagePath: identical(coverImagePath, _unset)
          ? this.coverImagePath
          : coverImagePath as String?,
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

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        if (label != null) 'label': label,
      };

  factory VideoOverlayItem.fromJson(Map<String, dynamic> json) =>
      VideoOverlayItem(
        id: json['id'] as String,
        label: json['label'] as String?,
      );
}

const Object _unset = Object();
