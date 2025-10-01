import 'dart:ui';

class VideoTimeline {
  final int trimStartMs;
  final int trimEndMs;
  final Rect? cropRect;
  final double speed;
  final int coverTimeMs;

  const VideoTimeline({
    required this.trimStartMs,
    required this.trimEndMs,
    this.cropRect,
    this.speed = 1.0,
    this.coverTimeMs = 0,
  });

  VideoTimeline copyWith({
    int? trimStartMs,
    int? trimEndMs,
    Rect? cropRect,
    bool resetCrop = false,
    double? speed,
    int? coverTimeMs,
  }) {
    return VideoTimeline(
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      cropRect: resetCrop ? null : (cropRect ?? this.cropRect),
      speed: speed ?? this.speed,
      coverTimeMs: coverTimeMs ?? this.coverTimeMs,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trimStartMs': trimStartMs,
      'trimEndMs': trimEndMs,
      if (cropRect != null)
        'cropRect': {
          'left': cropRect!.left,
          'top': cropRect!.top,
          'right': cropRect!.right,
          'bottom': cropRect!.bottom,
        },
      'speed': speed,
      'coverTimeMs': coverTimeMs,
    };
  }

  static VideoTimeline fromJson(Map<String, dynamic> json) {
    Rect? rect;
    final crop = json['cropRect'];
    if (crop is Map<String, dynamic>) {
      rect = Rect.fromLTRB(
        (crop['left'] as num).toDouble(),
        (crop['top'] as num).toDouble(),
        (crop['right'] as num).toDouble(),
        (crop['bottom'] as num).toDouble(),
      );
    }

    return VideoTimeline(
      trimStartMs: (json['trimStartMs'] as num? ?? 0).toInt(),
      trimEndMs: (json['trimEndMs'] as num? ?? 0).toInt(),
      cropRect: rect,
      speed: (json['speed'] as num? ?? 1.0).toDouble(),
      coverTimeMs: (json['coverTimeMs'] as num? ?? 0).toInt(),
    );
  }
}
