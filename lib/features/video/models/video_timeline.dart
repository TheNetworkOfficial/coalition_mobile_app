import 'dart:ui';

class VideoTimeline {
  static const double _cropEpsilon = 1e-4;

  static bool _hasMeaningfulArea(Rect rect) {
    return rect.width > _cropEpsilon && rect.height > _cropEpsilon;
  }

  static bool _isApproximatelyFullFrame(Rect rect) {
    return rect.left <= _cropEpsilon &&
        rect.top <= _cropEpsilon &&
        (1.0 - rect.right) <= _cropEpsilon &&
        (1.0 - rect.bottom) <= _cropEpsilon;
  }

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
    final crop = cropRect;
    final includeCrop =
        crop != null && _hasMeaningfulArea(crop) && !_isApproximatelyFullFrame(crop);

    return {
      'trimStartMs': trimStartMs,
      'trimEndMs': trimEndMs,
      if (includeCrop)
        'cropRect': {
          'left': crop!.left,
          'top': crop.top,
          'right': crop.right,
          'bottom': crop.bottom,
        },
      'speed': speed,
      'coverTimeMs': coverTimeMs,
    };
  }

  Map<String, dynamic> toTransformerJson() {
    final trimStartSeconds = trimStartMs / 1000.0;
    final trimEndSeconds = trimEndMs / 1000.0;
    final crop = cropRect;
    final includeCrop =
        crop != null && _hasMeaningfulArea(crop) && !_isApproximatelyFullFrame(crop);
    return {
      'trim': {
        'startSeconds': trimStartSeconds,
        'endSeconds': trimEndSeconds,
      },
      if (includeCrop)
        'crop': {
          'left': crop!.left,
          'top': crop.top,
          'right': crop.right,
          'bottom': crop.bottom,
        },
      if (speed != 1.0) 'speed': speed,
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
