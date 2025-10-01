import 'dart:ui';

/// Minimal, single coherent VideoTimeline model used by the video feature.
/// Keeps only the fields needed by the provider and roadmap: trims, crop,
/// cover time, and a cached cover image path. Serializable to JSON.

class VideoOverlayItem {
  const VideoOverlayItem({required this.id, this.label});

  final String id;
  final String? label;

  Map<String, dynamic> toJson() => {
        'id': id,
        if (label != null) 'label': label,
      };

  static VideoOverlayItem fromJson(Map<String, dynamic> j) =>
      VideoOverlayItem(id: j['id'] as String, label: j['label'] as String?);
}

class VideoTimeline {
  const VideoTimeline({
    required this.sourcePath,
    required this.trimStartMs,
    required this.trimEndMs,
    this.cropRect,
    this.playbackSpeed = 1.0,
    this.filterId,
    this.overlayItems = const <VideoOverlayItem>[],
    required this.coverTimeMs,
    this.coverImagePath,
  });

  final String sourcePath;
  final int? trimStartMs;
  final int? trimEndMs;
  final Rect? cropRect;
  final double playbackSpeed;
  final String? filterId;
  final List<VideoOverlayItem> overlayItems;
  final int? coverTimeMs;
  final String? coverImagePath;

  /// Create an initial timeline for a source file (no trims, cover at 0ms).
  static VideoTimeline initial(String sourcePath) => VideoTimeline(
        sourcePath: sourcePath,
        trimStartMs: null,
        trimEndMs: null,
        cropRect: null,
        playbackSpeed: 1.0,
        overlayItems: const [],
        coverTimeMs: null,
        coverImagePath: null,
      );

  VideoTimeline copyWith({
    String? sourcePath,
    int? trimStartMs,
    int? trimEndMs,
    Rect? cropRect,
    double? playbackSpeed,
    String? filterId,
    List<VideoOverlayItem>? overlayItems,
    int? coverTimeMs,
    Object? coverImagePath = _unset,
  }) {
    return VideoTimeline(
      sourcePath: sourcePath ?? this.sourcePath,
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      cropRect: cropRect ?? this.cropRect,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      filterId: filterId ?? this.filterId,
      overlayItems: overlayItems ?? this.overlayItems,
      coverTimeMs: coverTimeMs ?? this.coverTimeMs,
      coverImagePath: identical(coverImagePath, _unset)
          ? this.coverImagePath
          : coverImagePath as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourcePath': sourcePath,
        'trimStartMs': trimStartMs,
        'trimEndMs': trimEndMs,
        if (cropRect != null)
          'cropRect': {
            'left': cropRect!.left,
            'top': cropRect!.top,
            'right': cropRect!.right,
            'bottom': cropRect!.bottom,
          },
        'playbackSpeed': playbackSpeed,
        if (filterId != null) 'filterId': filterId,
        'overlayItems': overlayItems.map((e) => e.toJson()).toList(),
        'coverTimeMs': coverTimeMs,
        if (coverImagePath != null) 'coverImagePath': coverImagePath,
      };

  static VideoTimeline fromJson(Map<String, dynamic> j) {
    Rect? rect;
    final crop = j['cropRect'];
    if (crop is Map<String, dynamic>) {
      rect = Rect.fromLTRB(
        (crop['left'] as num).toDouble(),
        (crop['top'] as num).toDouble(),
        (crop['right'] as num).toDouble(),
        (crop['bottom'] as num).toDouble(),
      );
    }

    final overlaysJson = j['overlayItems'];
    final overlays = overlaysJson is List
        ? overlaysJson
            .whereType<Map<String, dynamic>>()
            .map(VideoOverlayItem.fromJson)
            .toList(growable: false)
        : const <VideoOverlayItem>[];

    return VideoTimeline(
      sourcePath: j['sourcePath'] as String,
      trimStartMs: (j['trimStartMs'] as num?)?.toInt() ?? 0,
      trimEndMs: (j['trimEndMs'] as num?)?.toInt() ?? -1,
      cropRect: rect,
      playbackSpeed: (j['playbackSpeed'] as num?)?.toDouble() ?? 1.0,
      filterId: j['filterId'] as String?,
      overlayItems: overlays,
      coverTimeMs: (j['coverTimeMs'] as num?)?.toInt() ?? 0,
      coverImagePath: j['coverImagePath'] as String?,
    );
  }
}

const Object _unset = Object();
