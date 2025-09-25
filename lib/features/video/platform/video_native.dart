import 'package:flutter/services.dart';

class VideoNative {
  static const _ch = MethodChannel('video_native');

  static Future<String> generateCoverImage(
    String filePath, {
    required double seconds,
  }) async {
    final result = await _ch.invokeMethod<String>(
      'generateCoverImage',
      <String, dynamic>{
        'filePath': filePath,
        'seconds': seconds,
      },
    );
    return result!;
  }

  static Future<String> exportEdits({
    required String filePath,
    required Map<String, dynamic> timelineJson,
    required int targetBitrateBps,
  }) async {
    final result = await _ch.invokeMethod<String>(
      'exportEdits',
      <String, dynamic>{
        'filePath': filePath,
        'timelineJson': timelineJson,
        'targetBitrateBps': targetBitrateBps,
      },
    );
    return result!;
  }

  static Future<void> cancelExport() {
    return _ch.invokeMethod<void>('cancelExport');
  }
}
