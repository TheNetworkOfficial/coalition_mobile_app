import 'dart:ui';

class OverlayItem {
  const OverlayItem({required this.data});

  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => Map<String, dynamic>.from(data);

  factory OverlayItem.fromJson(Map<String, dynamic> json) =>
      OverlayItem(data: Map<String, dynamic>.from(json));
}

class VideoTimeline {
  const VideoTimeline({
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.cropRect,
    this.speed = 1.0,
    this.lutId,
    this.overlays = const <OverlayItem>[],
    this.coverTimeMs = 0,
  }) : assert(speed >= 0.25 && speed <= 4.0);

  final int trimStartMs;
  final int trimEndMs;
  final Rect? cropRect; // logical coordinates [0..1]
  final double speed; // 0.25..4.0
  final String? lutId; // future filters
  final List<OverlayItem> overlays; // text/stickers; optional v1
  final int coverTimeMs;

  static const Object _sentinel = Object();

  VideoTimeline copyWith({
    int? trimStartMs,
    int? trimEndMs,
    Object? cropRect = _sentinel,
    double? speed,
    Object? lutId = _sentinel,
    List<OverlayItem>? overlays,
    int? coverTimeMs,
  }) {
    return VideoTimeline(
      trimStartMs: trimStartMs ?? this.trimStartMs,
      trimEndMs: trimEndMs ?? this.trimEndMs,
      cropRect: identical(cropRect, _sentinel) ? this.cropRect : cropRect as Rect?,
      speed: speed ?? this.speed,
      lutId: identical(lutId, _sentinel) ? this.lutId : lutId as String?,
      overlays: overlays ?? this.overlays,
      coverTimeMs: coverTimeMs ?? this.coverTimeMs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'trimStartMs': trimStartMs,
        'trimEndMs': trimEndMs,
        'cropRect': cropRect == null
            ? null
            : <String, double>{
                'left': cropRect!.left,
                'top': cropRect!.top,
                'right': cropRect!.right,
                'bottom': cropRect!.bottom,
              },
        'speed': speed,
        'lutId': lutId,
        'overlays': overlays.map((item) => item.toJson()).toList(),
        'coverTimeMs': coverTimeMs,
      };

  static VideoTimeline fromJson(Map<String, dynamic> json) {
    final cropRectJson = json['cropRect'] as Map<String, dynamic>?;
    return VideoTimeline(
      trimStartMs: (json['trimStartMs'] as int?) ?? 0,
      trimEndMs: (json['trimEndMs'] as int?) ?? 0,
      cropRect: cropRectJson == null
          ? null
          : Rect.fromLTRB(
              (cropRectJson['left'] as num).toDouble(),
              (cropRectJson['top'] as num).toDouble(),
              (cropRectJson['right'] as num).toDouble(),
              (cropRectJson['bottom'] as num).toDouble(),
            ),
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      lutId: json['lutId'] as String?,
      overlays: (json['overlays'] as List<dynamic>? ?? <dynamic>[]) 
          .map((dynamic item) => OverlayItem.fromJson(
                Map<String, dynamic>.from(item as Map<dynamic, dynamic>),
              ))
          .toList(growable: false),
      coverTimeMs: (json['coverTimeMs'] as int?) ?? 0,
    );
  }
}
