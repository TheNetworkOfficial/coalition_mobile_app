import 'dart:io';
import 'dart:ui';

import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffprobe_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'video_track.dart';

final videoTranscodeServiceProvider = Provider<VideoTranscodeService>((ref) {
  return VideoTranscodeService();
});

class VideoTranscodeService {
  VideoTranscodeService();

  static const Duration _artifactMaxAge = Duration(days: 7);

  Future<VideoProcessingBundle> prepareForUpload({
    required String sourcePath,
    bool preferCellularProfile = false,
  }) async {
    await purgeObsoleteArtifacts();

    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw VideoTranscodeException('Source video not found at $sourcePath');
    }

    final outputDir = await _ensureOutputDirectory();
    final jobId = DateTime.now().millisecondsSinceEpoch.toString();
    final profiles = preferCellularProfile
        ? _cellularProfiles
        : _defaultProfiles;

    final tracks = <VideoTrack>[];

    for (final profile in profiles) {
      final outputPath = p.join(outputDir.path, '${jobId}_${profile.id}.mp4');
      await _transcodeVariant(
        inputPath: sourcePath,
        outputPath: outputPath,
        profile: profile,
      );
      final metadata = await _probeVideo(outputPath);
      tracks.add(
        VideoTrack(
          uri: VideoTrack.ensureUri(outputPath),
          label: profile.label,
          bitrateKbps: profile.videoBitrateKbps,
          resolution: metadata.resolution,
          cacheKey: 'transcoded-${profile.id}-$jobId',
        ),
      );
    }

    // Preserve the original as a last-resort fallback so playback still
    // succeeds even if every transcode fails.
    tracks.add(
      VideoTrack(
        uri: VideoTrack.ensureUri(sourcePath),
        label: 'Source',
        cacheKey: 'original-$jobId',
      ),
    );

    return VideoProcessingBundle(
      jobId: jobId,
      sourcePath: sourcePath,
      tracks: tracks,
    );
  }

  Future<void> purgeObsoleteArtifacts() async {
    final directory = await _ensureOutputDirectory();
    if (!await directory.exists()) {
      return;
    }
    final now = DateTime.now();
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      final stats = await entity.stat();
      if (now.difference(stats.modified) > _artifactMaxAge) {
        try {
          await entity.delete();
        } catch (error) {
          debugPrint('Failed to delete old artifact ${entity.path}: $error');
        }
      }
    }
  }

  Future<Directory> _ensureOutputDirectory() async {
    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(docs.path, 'video_pipeline', 'processed'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _transcodeVariant({
    required String inputPath,
    required String outputPath,
    required _VariantProfile profile,
  }) async {
    final outputFile = File(outputPath);
    if (!await outputFile.parent.exists()) {
      await outputFile.parent.create(recursive: true);
    }

    final escapedInput = _escapePath(inputPath);
    final escapedOutput = _escapePath(outputPath);
    final scaleFilter =
        "scale=w=${profile.maxDimension}:h=${profile.maxDimension}:force_original_aspect_ratio=decrease:force_divisible_by=2";

    final videoBitrate = profile.videoBitrateKbps;
    final command = [
      '-y',
      '-i', "'$escapedInput'",
      '-vf', "'$scaleFilter'",
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-profile:v', 'high',
      '-level', '4.1',
      '-pix_fmt', 'yuv420p',
      '-movflags', '+faststart',
      '-vsync', 'cfr',
      '-r', '30',
      '-b:v', '${videoBitrate}k',
      '-maxrate', '${(videoBitrate * 1.1).round()}k',
      '-bufsize', '${(videoBitrate * 2).round()}k',
      '-c:a', 'aac',
      '-b:a', '${profile.audioBitrateKbps}k',
      '-ac', '2',
      "'$escapedOutput'",
    ].join(' ');

    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      return;
    }

    final logs = await session.getLogsAsString();
    throw VideoTranscodeException(
      'FFmpeg exited with ${returnCode?.getValue()}: $logs',
    );
  }

  Future<_VideoMetadata> _probeVideo(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) {
        return const _VideoMetadata();
      }

      Size? resolution;
      final streams = info.getStreams();
      if (streams != null) {
        for (final stream in streams) {
          if (stream.getType() == 'video') {
            final width = stream.getWidth();
            final height = stream.getHeight();
            if (width != null && height != null) {
              resolution = Size(width.toDouble(), height.toDouble());
              break;
            }
          }
        }
      }

      Duration? duration;
      final durationValue = info.getDuration();
      if (durationValue != null) {
        final seconds = double.tryParse(durationValue);
        if (seconds != null) {
          duration = Duration(milliseconds: (seconds * 1000).round());
        }
      }

      return _VideoMetadata(resolution: resolution, duration: duration);
    } catch (error, stackTrace) {
      debugPrint('FFprobe failed for $path: $error\n$stackTrace');
      return const _VideoMetadata();
    }
  }

  String _escapePath(String path) => path.replaceAll("'", r"\'");
}

class VideoProcessingBundle {
  const VideoProcessingBundle({
    required this.jobId,
    required this.sourcePath,
    required this.tracks,
  }) : assert(tracks.length > 0, 'VideoProcessingBundle requires tracks.');

  final String jobId;
  final String sourcePath;
  final List<VideoTrack> tracks;

  VideoTrack get primaryTrack => tracks.first;

  List<VideoTrack> get fallbackTracks =>
      tracks.length <= 1 ? const <VideoTrack>[] : tracks.sublist(1);

  VideoTrack? get adaptiveTrack {
    for (final track in tracks) {
      if (track.isAdaptive) {
        return track;
      }
    }
    return null;
  }
}

class VideoTranscodeException implements Exception {
  VideoTranscodeException(this.message);

  final String message;

  @override
  String toString() => 'VideoTranscodeException: $message';
}

class _VideoMetadata {
  const _VideoMetadata({this.resolution, this.duration});

  final Size? resolution;
  final Duration? duration;
}

class _VariantProfile {
  const _VariantProfile({
    required this.id,
    required this.label,
    required this.maxDimension,
    required this.videoBitrateKbps,
    required this.audioBitrateKbps,
  });

  final String id;
  final String label;
  final int maxDimension;
  final int videoBitrateKbps;
  final int audioBitrateKbps;
}

const _defaultProfiles = <_VariantProfile>[
  _VariantProfile(
    id: 'high',
    label: '1080p',
    maxDimension: 1920,
    videoBitrateKbps: 5200,
    audioBitrateKbps: 160,
  ),
  _VariantProfile(
    id: 'medium',
    label: '720p',
    maxDimension: 1280,
    videoBitrateKbps: 3200,
    audioBitrateKbps: 128,
  ),
  _VariantProfile(
    id: 'low',
    label: '480p',
    maxDimension: 854,
    videoBitrateKbps: 1600,
    audioBitrateKbps: 96,
  ),
];

const _cellularProfiles = <_VariantProfile>[
  _VariantProfile(
    id: 'medium',
    label: '720p',
    maxDimension: 1280,
    videoBitrateKbps: 2800,
    audioBitrateKbps: 128,
  ),
  _VariantProfile(
    id: 'low',
    label: '480p',
    maxDimension: 854,
    videoBitrateKbps: 1400,
    audioBitrateKbps: 96,
  ),
];
