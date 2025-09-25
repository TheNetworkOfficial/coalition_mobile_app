import 'dart:io';
import 'dart:ui';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'video_track.dart';

final videoTranscodeServiceProvider = Provider<VideoTranscodeService>((ref) {
  return VideoTranscodeService();
});

class VideoTranscodeService {
  VideoTranscodeService();

  static const Duration _artifactMaxAge = Duration(days: 7);
  static const _uuid = Uuid();
  static const int _segmentDurationSeconds = 6;
  static const int _targetFps = 30;

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
    final jobId = _uuid.v4();

    final sourceMetadata = await _probeVideo(sourcePath);
    if (sourceMetadata.duration == null ||
        sourceMetadata.duration == Duration.zero) {
      throw VideoTranscodeException('Selected media is not a valid video.');
    }
    if (sourceMetadata.resolution == null) {
      throw VideoTranscodeException(
          'Unable to determine the video resolution.');
    }

    final profiles = _selectProfilesForSource(
      resolution: sourceMetadata.resolution,
      preferCellular: preferCellularProfile,
    );

    if (kDebugMode) {
      final sourceWidth = sourceMetadata.resolution?.width;
      final sourceHeight = sourceMetadata.resolution?.height;
      final widthLabel = sourceWidth?.toStringAsFixed(0) ?? '?';
      final heightLabel = sourceHeight?.toStringAsFixed(0) ?? '?';
      final bitrateLabel = sourceMetadata.bitrateKbps ?? 0;
      final durationLabel = sourceMetadata.duration ?? Duration.zero;
      final resolutionLabel = '${widthLabel}x$heightLabel';
      debugPrint(
          'Transcode job $jobId — source: $resolutionLabel $bitrateLabel kbps, duration $durationLabel');
      final selectedRenditions =
          profiles.map((profile) => profile.label).join(', ');
      debugPrint('Selected renditions: $selectedRenditions');
    }

    final variantResults = <_VariantResult>[];

    for (final profile in profiles) {
      final outputPath = p.join(outputDir.path, '${jobId}_${profile.id}.mp4');
      await _transcodeVariant(
        inputPath: sourcePath,
        outputPath: outputPath,
        profile: profile,
      );

      final metadata = await _probeVideo(outputPath);
      final track = VideoTrack(
        uri: VideoTrack.ensureUri(outputPath),
        label: profile.label,
        bitrateKbps: metadata.bitrateKbps,
        resolution: metadata.resolution,
        cacheKey: 'transcoded-${profile.id}-$jobId',
      );

      variantResults.add(_VariantResult(
        profile: profile,
        filePath: outputPath,
        track: track,
      ));

      if (kDebugMode) {
        final sizeBytes = File(outputPath).lengthSync();
        final resolution = metadata.resolution;
        final resWidth =
            resolution != null ? resolution.width.toStringAsFixed(0) : '?';
        final resHeight =
            resolution != null ? resolution.height.toStringAsFixed(0) : '?';
        final bitrateLabel = metadata.bitrateKbps ?? 0;
        final profileLabel = profile.label;
        debugPrint(
          ' • $profileLabel: ${resWidth}x$resHeight '
          '$bitrateLabel kbps (${_formatBytes(sizeBytes)})',
        );
      }
    }

    // Preserve the original as a last-resort fallback so playback still
    // succeeds even if every transcode fails.
    final sourceTrack = VideoTrack(
      uri: VideoTrack.ensureUri(sourcePath),
      label: 'Source',
      resolution: sourceMetadata.resolution,
      bitrateKbps: sourceMetadata.bitrateKbps,
      cacheKey: 'original-$jobId',
    );

    HlsPackage? hlsPackage;
    try {
      hlsPackage = await _buildHlsPackage(
        jobId: jobId,
        outputDirectory: outputDir,
        variants: variantResults,
      );
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to package HLS for job $jobId: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      hlsPackage = null;
    }

    if (kDebugMode && hlsPackage != null) {
      _logHlsDiagnostics(
        jobId: jobId,
        package: hlsPackage,
        variants: variantResults,
      );
    }

    final renditions = <ProcessedVideoFile>[
      for (final result in variantResults)
        ProcessedVideoFile(
          track: result.track,
          localPath: result.filePath,
          profile: result.profile,
        ),
      ProcessedVideoFile(
        track: sourceTrack,
        localPath: sourcePath,
        profile: const VariantProfile(
          id: 'source',
          label: 'Source',
          maxDimension: 0,
          crf: 0,
          preset: 'copy',
          maxVideoBitrateKbps: 0,
          audioBitrateKbps: 0,
        ),
      ),
    ];

    return VideoProcessingBundle(
      jobId: jobId,
      sourcePath: sourcePath,
      renditions: renditions,
      hlsPackage: hlsPackage,
    );
  }

  List<VariantProfile> _selectProfilesForSource({
    required Size? resolution,
    required bool preferCellular,
  }) {
    final base = preferCellular ? _cellularProfiles : _defaultProfiles;
    if (resolution == null) {
      return [base.first];
    }

    final longestDimension = resolution.longestSide;
    final viable = [
      for (final profile in base)
        if (profile.maxDimension <= longestDimension + 1) profile,
    ];

    if (viable.isEmpty) {
      return [base.last];
    }

    return viable;
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
    final directory =
        Directory(p.join(docs.path, 'video_pipeline', 'processed'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> _transcodeVariant({
    required String inputPath,
    required String outputPath,
    required VariantProfile profile,
  }) async {
    final outputFile = File(outputPath);
    if (!await outputFile.parent.exists()) {
      await outputFile.parent.create(recursive: true);
    }

    final escapedInput = _escapePath(inputPath);
    final escapedOutput = _escapePath(outputPath);
    final scaleFilter =
        'scale=if(gt(iw,ih),min(${profile.maxDimension},iw),-2):'
        'if(gt(iw,ih),-2,min(${profile.maxDimension},ih))';

    final maxrate = profile.maxVideoBitrateKbps;
    final bufsize = maxrate * 2;
    final int gopSize =
        (_segmentDurationSeconds * _targetFps).clamp(30, 240).toInt();
    final command = [
      '-y',
      '-i',
      "'$escapedInput'",
      '-vf',
      "'$scaleFilter'",
      '-c:v',
      'libx264',
      '-preset',
      profile.preset,
      '-profile:v',
      'high',
      '-level',
      '4.1',
      '-pix_fmt',
      'yuv420p',
      '-movflags',
      '+faststart',
      '-vsync',
      'cfr',
      '-r',
      '$_targetFps',
      '-crf',
      '${profile.crf}',
      '-g',
      '$gopSize',
      '-keyint_min',
      '$gopSize',
      '-sc_threshold',
      '0',
      '-force_key_frames',
      '"expr:gte(t,n_forced*$_segmentDurationSeconds)"',
      '-maxrate',
      '${maxrate}k',
      '-bufsize',
      '${bufsize}k',
      '-c:a',
      'aac',
      '-b:a',
      '${profile.audioBitrateKbps}k',
      '-ac',
      '2',
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

  Future<HlsPackage> _buildHlsPackage({
    required String jobId,
    required Directory outputDirectory,
    required List<_VariantResult> variants,
  }) async {
    if (variants.isEmpty) {
      throw VideoTranscodeException('No variants available for HLS packaging.');
    }

    final hlsRoot = Directory(p.join(outputDirectory.path, '${jobId}_hls'));
    if (!await hlsRoot.exists()) {
      await hlsRoot.create(recursive: true);
    }

    final variantManifests = <HlsVariantStream>[];
    final assetPaths = <String>[];

    for (final variant in variants) {
      final variantDir = Directory(p.join(hlsRoot.path, variant.profile.id));
      if (!await variantDir.exists()) {
        await variantDir.create(recursive: true);
      }

      final manifestPath = p.join(variantDir.path, 'playlist.m3u8');
      final segmentPattern = p.join(variantDir.path, 'segment_%05d.ts');

      final command = [
        '-y',
        '-i',
        "'${_escapePath(variant.filePath)}'",
        '-c:v',
        'copy',
        '-c:a',
        'copy',
        '-bsf:v',
        'h264_mp4toannexb',
        '-hls_time',
        '$_segmentDurationSeconds',
        '-hls_list_size',
        '0',
        '-hls_playlist_type',
        'vod',
        '-hls_flags',
        'independent_segments+iframe_index',
        '-hls_segment_filename',
        "'${_escapePath(segmentPattern)}'",
        "'${_escapePath(manifestPath)}'",
      ].join(' ');

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (!ReturnCode.isSuccess(returnCode)) {
        final logs = await session.getLogsAsString();
        throw VideoTranscodeException(
          'FFmpeg HLS packaging failed with ${returnCode?.getValue()}: $logs',
        );
      }

      final manifestFile = File(manifestPath);
      if (!await manifestFile.exists()) {
        throw VideoTranscodeException('HLS manifest missing at $manifestPath');
      }

      final relativeManifestPath = p.relative(manifestPath, from: hlsRoot.path);
      final videoBitrateKbps = variant.track.bitrateKbps ??
          variant.profile.estimatedVideoBitrateKbps;
      final bandwidth =
          (videoBitrateKbps + variant.profile.audioBitrateKbps) * 1000;

      final hlsVariant = HlsVariantStream(
        profileId: variant.profile.id,
        playlistPath: manifestPath,
        relativePlaylistPath: relativeManifestPath.replaceAll('\\', '/'),
        bandwidth: bandwidth,
        resolution: variant.track.resolution,
      );
      variantManifests.add(hlsVariant);

      // Collect manifest + segment assets
      assetPaths.add(manifestPath);
      final iframeVariantPath =
          manifestPath.replaceFirst('.m3u8', '_iframes.m3u8');
      final iframeFile = File(iframeVariantPath);
      if (await iframeFile.exists()) {
        assetPaths.add(iframeVariantPath);
      }
      final segmentFiles = variantDir
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.ts'));
      for (final file in segmentFiles) {
        assetPaths.add(file.path);
      }
    }

    variantManifests
        .sort((a, b) => b.bandwidth.compareTo(a.bandwidth)); // highest first

    final masterPlaylistPath = p.join(hlsRoot.path, 'master.m3u8');
    final buffer = StringBuffer(
      '#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-INDEPENDENT-SEGMENTS\n',
    );
    for (final variant in variantManifests) {
      final resolution = variant.resolution;
      final resolutionValue = resolution == null
          ? ''
          : 'RESOLUTION=${resolution.width.round()}x${resolution.height.round()},';
      buffer.writeln(
          '#EXT-X-STREAM-INF:BANDWIDTH=${variant.bandwidth},${resolutionValue}CODECS="avc1.64001f,mp4a.40.2"');
      buffer.writeln(variant.relativePlaylistPath);
    }

    final masterFile = File(masterPlaylistPath);
    await masterFile.writeAsString(buffer.toString());
    assetPaths.add(masterPlaylistPath);

    final masterTrack = VideoTrack(
      uri: VideoTrack.ensureUri(masterPlaylistPath),
      label: 'Auto',
      isAdaptive: true,
      cacheKey: 'hls-master-$jobId',
    );

    return HlsPackage(
      rootDirectoryPath: hlsRoot.path,
      masterPlaylistPath: masterPlaylistPath,
      variantManifests: variantManifests,
      assetPaths: assetPaths,
      masterTrack: masterTrack,
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
      int? bitrateKbps;
      for (final stream in info.getStreams()) {
        if (stream.getType() == 'video') {
          final width = stream.getWidth();
          final height = stream.getHeight();
          if (width != null && height != null) {
            resolution = Size(width.toDouble(), height.toDouble());
            break;
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
      final infoBitrate = info.getBitrate();
      if (infoBitrate != null) {
        final parsed = int.tryParse(infoBitrate);
        if (parsed != null && parsed > 0) {
          bitrateKbps = (parsed / 1000).round();
        }
      }

      if (bitrateKbps == null) {
        for (final stream in info.getStreams()) {
          final streamBitrate = stream.getBitrate();
          if (streamBitrate == null) continue;
          final parsed = int.tryParse(streamBitrate);
          if (parsed != null && parsed > 0) {
            bitrateKbps = (parsed / 1000).round();
            break;
          }
        }
      }

      return _VideoMetadata(
        resolution: resolution,
        duration: duration,
        bitrateKbps: bitrateKbps,
      );
    } catch (error, stackTrace) {
      debugPrint('FFprobe failed for $path: $error\n$stackTrace');
      return const _VideoMetadata();
    }
  }

  String _escapePath(String path) => path.replaceAll("'", r"\'");

  void _logHlsDiagnostics({
    required String jobId,
    required HlsPackage package,
    required List<_VariantResult> variants,
  }) {
    if (!kDebugMode) {
      return;
    }
    try {
      debugPrint(
          'HLS summary for job $jobId (master: ${package.masterPlaylistPath})');
      for (final variant in variants) {
        final manifest = package.variantManifests.firstWhere(
          (item) => item.profileId == variant.profile.id,
          orElse: () => package.variantManifests.first,
        );
        final manifestFile = File(manifest.playlistPath);
        final lines = manifestFile.readAsLinesSync();
        final durations = <double>[];
        for (final line in lines) {
          if (line.startsWith('#EXTINF:')) {
            final trimmed = line.substring('#EXTINF:'.length);
            final value = double.tryParse(trimmed.split(',').first);
            if (value != null) {
              durations.add(value);
            }
          }
        }
        durations.sort();
        final avg = durations.isEmpty
            ? 0
            : durations.reduce((a, b) => a + b) / durations.length;
        final sizeBytes = variant.filePath.isNotEmpty
            ? File(variant.filePath).lengthSync()
            : 0;
        final minDur = durations.isEmpty
            ? 'n/a'
            : '${durations.first.toStringAsFixed(2)}s';
        final maxDur =
            durations.isEmpty ? 'n/a' : '${durations.last.toStringAsFixed(2)}s';
        debugPrint(
          ' • ${variant.profile.label}: segments=${durations.length}, '
          'avg=${avg.toStringAsFixed(2)}s, '
          'min=$minDur, max=$maxDur, '
          'mp4=${_formatBytes(sizeBytes)}, '
          'manifest=${manifest.relativePlaylistPath}',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to compute HLS diagnostics for $jobId: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final fractionDigits = unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(fractionDigits)} ${units[unit]}';
  }
}

class ProcessedVideoFile {
  const ProcessedVideoFile({
    required this.track,
    required this.localPath,
    required this.profile,
  });

  final VideoTrack track;
  final String localPath;
  final VariantProfile profile;
}

class HlsPackage {
  const HlsPackage({
    required this.rootDirectoryPath,
    required this.masterPlaylistPath,
    required this.variantManifests,
    required this.assetPaths,
    required this.masterTrack,
  });

  final String rootDirectoryPath;
  final String masterPlaylistPath;
  final List<HlsVariantStream> variantManifests;
  final List<String> assetPaths;
  final VideoTrack masterTrack;

  VideoTrack get adaptiveTrack => masterTrack;
}

class HlsVariantStream {
  const HlsVariantStream({
    required this.profileId,
    required this.playlistPath,
    required this.relativePlaylistPath,
    required this.bandwidth,
    required this.resolution,
  });

  final String profileId;
  final String playlistPath;
  final String relativePlaylistPath;
  final int bandwidth;
  final Size? resolution;
}

class VideoProcessingBundle {
  const VideoProcessingBundle({
    required this.jobId,
    required this.sourcePath,
    required this.renditions,
    this.hlsPackage,
  }) : assert(renditions.length > 0,
            'VideoProcessingBundle requires renditions.');

  final String jobId;
  final String sourcePath;
  final List<ProcessedVideoFile> renditions;
  final HlsPackage? hlsPackage;

  List<VideoTrack> get tracks => [for (final item in renditions) item.track];

  VideoTrack get primaryTrack => renditions.first.track;

  List<VideoTrack> get fallbackTracks => renditions.length <= 1
      ? const <VideoTrack>[]
      : renditions.sublist(1).map((r) => r.track).toList();

  VideoTrack? get adaptiveTrack => hlsPackage?.adaptiveTrack;
}

class VideoTranscodeException implements Exception {
  VideoTranscodeException(this.message);

  final String message;

  @override
  String toString() => 'VideoTranscodeException: $message';
}

class _VideoMetadata {
  const _VideoMetadata({this.resolution, this.duration, this.bitrateKbps});

  final Size? resolution;
  final Duration? duration;
  final int? bitrateKbps;
}

class VariantProfile {
  const VariantProfile({
    required this.id,
    required this.label,
    required this.maxDimension,
    required this.crf,
    required this.preset,
    required this.maxVideoBitrateKbps,
    required this.audioBitrateKbps,
  });

  final String id;
  final String label;
  final int maxDimension;
  final int crf;
  final String preset;
  final int maxVideoBitrateKbps;
  final int audioBitrateKbps;

  int get estimatedVideoBitrateKbps => maxVideoBitrateKbps;
}

class _VariantResult {
  const _VariantResult({
    required this.profile,
    required this.filePath,
    required this.track,
  });

  final VariantProfile profile;
  final String filePath;
  final VideoTrack track;
}

const _defaultProfiles = <VariantProfile>[
  VariantProfile(
    id: 'high',
    label: '1080p',
    maxDimension: 1080,
    crf: 21,
    preset: 'veryfast',
    maxVideoBitrateKbps: 5200,
    audioBitrateKbps: 160,
  ),
  VariantProfile(
    id: 'medium',
    label: '720p',
    maxDimension: 720,
    crf: 22,
    preset: 'veryfast',
    maxVideoBitrateKbps: 3500,
    audioBitrateKbps: 128,
  ),
  VariantProfile(
    id: 'low',
    label: '540p',
    maxDimension: 540,
    crf: 23,
    preset: 'faster',
    maxVideoBitrateKbps: 1800,
    audioBitrateKbps: 96,
  ),
];

const _cellularProfiles = <VariantProfile>[
  VariantProfile(
    id: 'medium',
    label: '720p',
    maxDimension: 720,
    crf: 24,
    preset: 'veryfast',
    maxVideoBitrateKbps: 2800,
    audioBitrateKbps: 128,
  ),
  VariantProfile(
    id: 'low',
    label: '540p',
    maxDimension: 540,
    crf: 25,
    preset: 'veryfast',
    maxVideoBitrateKbps: 1500,
    audioBitrateKbps: 96,
  ),
];
