import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final videoNativeProvider =
    Provider<VideoNativeBridge>((_) => const VideoNativeBridge());

class VideoNativeBridge {
  const VideoNativeBridge();

  static const MethodChannel _channel = MethodChannel('video_native');

  Future<String> generateCoverImage(
    String filePath, {
    required double seconds,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'generateCoverImage',
      <String, dynamic>{
        'filePath': filePath,
        'seconds': seconds,
      },
    );
    return result!;
  }

  Future<String> exportEdits({
    required String filePath,
    required Map<String, dynamic> timelineJson,
    required int targetBitrateBps,
  }) async {
    final result = await _channel.invokeMethod<String>(
      'exportEdits',
      <String, dynamic>{
        'filePath': filePath,
        'timelineJson': timelineJson,
        'targetBitrateBps': targetBitrateBps,
      },
    );
    return result!;
  }

  Future<void> cancelExport() {
    return _channel.invokeMethod<void>('cancelExport');
  }
}
