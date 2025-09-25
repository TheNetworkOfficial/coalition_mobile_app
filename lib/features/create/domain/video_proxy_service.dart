import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:video_compress/video_compress.dart';

class VideoProxyResult {
  VideoProxyResult({required this.originalPath, required this.proxyPath});

  final String originalPath;
  final String proxyPath;
}

class VideoProxyService {
  VideoProxyService._() {
    VideoCompress.setLogLevel(0);
  }

  static final VideoProxyService instance = VideoProxyService._();

  static const int _maxSafeDimension = 1080;
  static const int _maxSafeBytes = 60 * 1024 * 1024; // 60 MB

  final Map<String, VideoProxyResult> _cache = <String, VideoProxyResult>{};
  final Map<String, _ProxyJob> _jobs = <String, _ProxyJob>{};

  Future<bool> shouldTranscode({
    required String path,
    int? width,
    int? height,
    int? fileLengthBytes,
  }) async {
    int? resolvedSize = fileLengthBytes;
    if (resolvedSize == null) {
      try {
        resolvedSize = await File(path).length();
      } catch (_) {
        resolvedSize = null;
      }
    }
    if (resolvedSize != null && resolvedSize > _maxSafeBytes) {
      return true;
    }

    final resolvedWidth = width;
    final resolvedHeight = height;
    if (resolvedWidth != null && resolvedHeight != null) {
      final maxDimension = math.max(resolvedWidth, resolvedHeight);
      if (maxDimension > _maxSafeDimension) {
        return true;
      }
    }

    if (resolvedWidth != null && resolvedHeight != null) {
      return false;
    }

    MediaInfo info;
    try {
      info = await VideoCompress.getMediaInfo(path);
    } catch (_) {
      return false;
    }
    final infoWidth = info.width;
    final infoHeight = info.height;
    if (info.filesize != null && info.filesize! > _maxSafeBytes) {
      return true;
    }
    if (infoWidth != null && infoHeight != null) {
      final maxDimension = math.max(infoWidth, infoHeight);
      if (maxDimension > _maxSafeDimension) {
        return true;
      }
    }
    return false;
  }

  VideoProxyResult? getCachedProxy(String originalPath) {
    return _cache[originalPath];
  }

  Future<VideoProxyResult> ensureProxy(
    String originalPath, {
    void Function(double progress)? onProgress,
  }) {
    final cached = _cache[originalPath];
    if (cached != null) {
      onProgress?.call(1);
      return Future<VideoProxyResult>.value(cached);
    }

    final existing = _jobs[originalPath];
    if (existing != null) {
      if (onProgress != null) {
        existing.listeners.add(onProgress);
      }
      return existing.completer.future;
    }

    final job = _ProxyJob();
    if (onProgress != null) {
      job.listeners.add(onProgress);
    }
    _jobs[originalPath] = job;

    job.subscription = VideoCompress.compressProgress$.listen((progress) {
      final clamped = (progress.clamp(0, 100)) / 100;
      for (final listener in List<void Function(double progress)>.of(job.listeners)) {
        listener(clamped);
      }
    });

    () async {
      try {
        final info = await VideoCompress.compressVideo(
          originalPath,
          quality: VideoQuality.MediumQuality,
          includeAudio: true,
        );
        if (info == null || info.path == null) {
          throw Exception('Unable to generate proxy for $originalPath');
        }
        final result =
            VideoProxyResult(originalPath: originalPath, proxyPath: info.path!);
        _cache[originalPath] = result;
        for (final listener in List<void Function(double progress)>.of(job.listeners)) {
          listener(1);
        }
        job.completer.complete(result);
      } catch (error, stackTrace) {
        job.completer.completeError(error, stackTrace);
      } finally {
        await job.subscription?.cancel();
        _jobs.remove(originalPath);
      }
    }();

    return job.completer.future;
  }
}

class _ProxyJob {
  _ProxyJob();

  final Completer<VideoProxyResult> completer = Completer<VideoProxyResult>();
  final List<void Function(double progress)> listeners =
      <void Function(double progress)>[];
  StreamSubscription<double>? subscription;
}
