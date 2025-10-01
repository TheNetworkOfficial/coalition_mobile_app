import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class VideoNativeBridge {
  const VideoNativeBridge();

  Future<String> generateCoverImage(String filePath, {required double seconds});

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
  Future<String> generateCoverImage(String filePath,
      {required double seconds}) async {
    final result = await _ch.invokeMethod<String>('generateCoverImage', {
      'filePath': filePath,
      'seconds': seconds,
    });
    return result ?? '';
  }

  @override
  Future<String> exportEdits({
    required String filePath,
    required Map<String, dynamic> timelineJson,
    required int targetBitrateBps,
  }) async {
    final result = await _ch.invokeMethod<String>('exportEdits', {
      'filePath': filePath,
      'timeline': timelineJson,
      'bitrate': targetBitrateBps,
    });
    return result ?? '';
  }

  @override
  Future<void> cancelExport() async {
    await _ch.invokeMethod<void>('cancelExport');
  }
}
