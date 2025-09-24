import 'dart:ui';

import 'package:equatable/equatable.dart';

/// Describes a playable video rendition, including metadata that can help the
/// UI present quality choices to the user.
class VideoTrack extends Equatable {
  const VideoTrack({
    required this.uri,
    required this.label,
    this.bitrateKbps,
    this.resolution,
    this.isAdaptive = false,
    this.cacheKey,
  });

  /// Location of the media. Supports both local files (`file://`) and
  /// network/HTTPS resources.
  final Uri uri;

  /// User-facing label such as `Auto`, `1080p`, or `720p`.
  final String label;

  /// Target video bitrate in kilobits per second, if known.
  final int? bitrateKbps;

  /// Optional resolution for the rendition. The width component is stored in
  /// [resolution.width] and the height component in [resolution.height].
  final Size? resolution;

  /// Whether this track represents an adaptive manifest (e.g. HLS/DASH).
  final bool isAdaptive;

  /// Optional cache key so the player can persist downloaded segments.
  final String? cacheKey;

  /// Returns `true` when [uri] points to a remote resource.
  bool get isNetwork => uri.scheme == 'http' || uri.scheme == 'https';

  /// Returns `true` when [uri] points to a local file on disk.
  bool get isFile => uri.scheme == 'file' || uri.scheme.isEmpty;

  /// Best-effort human friendly quality label based on the resolution/bitrate.
  String get qualityLabel {
    if (resolution != null && resolution!.height > 0) {
      return '${resolution!.height.round()}p';
    }
    if (bitrateKbps != null && bitrateKbps! > 0) {
      final mbps = (bitrateKbps! / 1000).toStringAsFixed(1);
      return '${mbps}Mbps';
    }
    return label;
  }

  /// Utility that converts a raw string path into a [Uri] that is safe to use
  /// with [VideoTrack].
  static Uri ensureUri(String raw) {
    final parsed = Uri.tryParse(raw);
    if (parsed == null || parsed.scheme.isEmpty) {
      return Uri.file(raw);
    }
    return parsed;
  }

  VideoTrack copyWith({
    Uri? uri,
    String? label,
    int? bitrateKbps,
    Size? resolution,
    bool? isAdaptive,
    String? cacheKey,
  }) {
    return VideoTrack(
      uri: uri ?? this.uri,
      label: label ?? this.label,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      resolution: resolution ?? this.resolution,
      isAdaptive: isAdaptive ?? this.isAdaptive,
      cacheKey: cacheKey ?? this.cacheKey,
    );
  }

  @override
  List<Object?> get props => [
        uri.toString(),
        label,
        bitrateKbps,
        resolution?.width,
        resolution?.height,
        isAdaptive,
        cacheKey,
      ];
}
