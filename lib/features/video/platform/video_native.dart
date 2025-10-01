import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class VideoNativeBridge {
  const VideoNativeBridge();

  Future<String> generateCoverImage(String filePath, {required double seconds});

  Future<void> persistUriPermission(String uri);

  Future<String> exportEdits({
    required String filePath,
    required Map<String, dynamic> timelineJson,
    required int targetBitrateBps,
  });

  Future<void> cancelExport();
}

final videoNativeProvider = Provider<VideoNativeBridge>((ref) => VideoNative());

/// Minimal Dart bridge for native video helpers described in the roadmap.
/// Methods use platform channels and return local file paths.
class VideoNative implements VideoNativeBridge {
  static const MethodChannel _ch = MethodChannel('video_native');

  @override
  Future<String> generateCoverImage(
    String filePath, {
    required double seconds,
  }) async {
    final result = await _ch.invokeMethod<String>('generateCoverImage', {
      'filePath': filePath,
      'seconds': seconds,
    });
    return result ?? '';
  }

  @override
  Future<void> persistUriPermission(String uri) async {
    await _ch.invokeMethod<void>('persistUriPermission', {
      'uri': uri,
    });
  }

  @override
  Future<String> exportEdits({
    required String filePath,
    required Map<String, dynamic> timelineJson,
    required int targetBitrateBps,
  }) async {
    // Defensive clamp: ensure crop coordinates are valid before sending to
    // native code. Some timeline generators may produce equal or inverted
    // coordinates which cause native exporters to throw. We'll nudge invalid
    // values by a small epsilon to avoid platform errors.
    final mutableTimeline = Map<String, dynamic>.from(timelineJson);
    try {
      final crop = mutableTimeline['crop'] as Map<String, dynamic>?;
      if (crop != null) {
        final double left =
            ((crop['left'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0).toDouble();
        final double top =
            ((crop['top'] as num?)?.toDouble() ?? 0.0).clamp(0.0, 1.0).toDouble();
        var right =
            ((crop['right'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0).toDouble();
        var bottom =
            ((crop['bottom'] as num?)?.toDouble() ?? 1.0).clamp(0.0, 1.0).toDouble();
        const eps = 1e-4;

        var width = right - left;
        var height = bottom - top;
        final isFullFrame =
            left <= eps && top <= eps && (1.0 - right) <= eps && (1.0 - bottom) <= eps;

        if (width <= eps || height <= eps || isFullFrame) {
          mutableTimeline.remove('crop');
        } else {
          if (right <= left) {
            right = (left + eps).clamp(0.0, 1.0).toDouble();
          }
          if (bottom <= top) {
            bottom = (top + eps).clamp(0.0, 1.0).toDouble();
          }

          width = right - left;
          height = bottom - top;
          if (width <= eps || height <= eps) {
            mutableTimeline.remove('crop');
          } else {
            mutableTimeline['crop'] = {
              'left': left,
              'top': top,
              'right': right,
              'bottom': bottom,
            };
          }
        }
      }
    } catch (_) {}

    // Send the timeline as a JSON string to avoid platform codec edge-cases
    // with nested maps containing only primitive types. Add diagnostic logging
    // so failures on-device can be correlated with platform logs.
    final timelineStr = jsonEncode(mutableTimeline);
    try {
      // Shorten the timeline string for logs to avoid flooding.
      final preview = timelineStr.length > 1000
          ? '${timelineStr.substring(0, 1000)}...(${timelineStr.length} chars)'
          : timelineStr;
      debugPrint(
        'VideoNative(Dart): exportEdits -> filePath=$filePath, targetBitrateBps=$targetBitrateBps, timelinePreview=$preview',
      );
    } catch (_) {}

    final result = await _ch.invokeMethod<String>('exportEdits', {
      'filePath': filePath,
      'timelineJson': timelineStr,
      'targetBitrateBps': targetBitrateBps,
    });

    debugPrint(
      'VideoNative(Dart): exportEdits returned ${result ?? "null"}',
    );
    return result ?? '';
  }

  @override
  Future<void> cancelExport() async {
    await _ch.invokeMethod<void>('cancelExport');
  }
}
