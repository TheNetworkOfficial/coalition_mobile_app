import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../video_transcode_service.dart';
import '../video_track.dart';

final videoCdnServiceProvider = Provider<VideoCdnService>((ref) {
  final config = ref.watch(videoCdnConfigProvider);
  if (config == null) {
    return const NotConfiguredVideoCdnService();
  }
  return HttpVideoCdnService(config: config);
});

final videoCdnConfigProvider = Provider<VideoCdnConfig?>((ref) {
  return null; // Override in app bootstrap with real configuration.
});

abstract class VideoCdnService {
  const VideoCdnService();

  Future<VideoCdnUploadResult> uploadBundle(VideoProcessingBundle bundle);
}

class VideoCdnUploadResult {
  const VideoCdnUploadResult({
    required this.adaptiveTrack,
    required this.fallbackTracks,
    required this.masterPlaylistUri,
  });

  final VideoTrack adaptiveTrack;
  final List<VideoTrack> fallbackTracks;
  final Uri masterPlaylistUri;
}

class NotConfiguredVideoCdnService extends VideoCdnService {
  const NotConfiguredVideoCdnService();

  @override
  Future<VideoCdnUploadResult> uploadBundle(VideoProcessingBundle bundle) async {
    throw StateError(
      'Video CDN configuration is missing. Provide a VideoCdnConfig via videoCdnConfigProvider.',
    );
  }
}

class HttpVideoCdnService extends VideoCdnService {
  HttpVideoCdnService({required this.config});

  static const int _maxParallelUploads = 4;
  final VideoCdnConfig config;

  @override
  Future<VideoCdnUploadResult> uploadBundle(VideoProcessingBundle bundle) async {
    final hlsPackage = bundle.hlsPackage;
    if (hlsPackage == null) {
      throw StateError('HLS package missing for bundle ${bundle.jobId}.');
    }

    final plan = _buildUploadPlan(bundle);
    final signResponse = await _requestSignatures(
      jobId: bundle.jobId,
      tasks: plan.tasks,
    );

    await _uploadInBatches(plan.tasks, signResponse.assets);

    final publicBase = signResponse.publicBaseUrl ?? config.publicBaseUrl;
    final masterSigned = signResponse.assets[plan.masterPlaylistPath];
    if (masterSigned == null) {
      throw StateError('Master playlist not returned by signer.');
    }
    final masterUri = _publicUriForKey(publicBase, masterSigned.key);
    final adaptiveTrack = hlsPackage.adaptiveTrack.copyWith(
      uri: masterUri,
      isAdaptive: true,
    );

    final fallbackTracks = <VideoTrack>[];
    for (final task in plan.tasks) {
      final track = task.associatedTrack;
      if (track == null) {
        continue;
      }
      final signed = signResponse.assets[task.relativePath]!;
      final remoteUri = _publicUriForKey(publicBase, signed.key);
      fallbackTracks.add(
        track.copyWith(
          uri: remoteUri,
          isAdaptive: false,
        ),
      );
    }

    await _cleanupArtifacts(plan);

    return VideoCdnUploadResult(
      adaptiveTrack: adaptiveTrack,
      fallbackTracks: fallbackTracks,
      masterPlaylistUri: masterUri,
    );
  }

  _UploadPlan _buildUploadPlan(VideoProcessingBundle bundle) {
    final hlsPackage = bundle.hlsPackage!;
    final tasks = <_UploadTask>[];
    final directoriesToPrune = <String>{hlsPackage.rootDirectoryPath};

    final masterRelative = p
        .join(
          'hls',
          p.relative(
            hlsPackage.masterPlaylistPath,
            from: hlsPackage.rootDirectoryPath,
          ),
        )
        .replaceAll('\\', '/');

    for (final assetPath in hlsPackage.assetPaths) {
      final relative = p
          .join(
            'hls',
            p.relative(assetPath, from: hlsPackage.rootDirectoryPath),
          )
          .replaceAll('\\', '/');
      tasks.add(
        _UploadTask(
          localPath: assetPath,
          relativePath: relative,
          contentType: _detectContentType(assetPath),
          isMasterPlaylist: relative == masterRelative,
          deleteAfterUpload: true,
          fileSizeBytes: _fileSizeBytes(assetPath),
        ),
      );
    }

    for (final rendition in bundle.renditions) {
      final filename = p.basename(rendition.localPath);
      final relative = p.join('mp4', filename).replaceAll('\\', '/');
      tasks.add(
        _UploadTask(
          localPath: rendition.localPath,
          relativePath: relative,
          contentType: _detectContentType(rendition.localPath),
          associatedTrack: rendition.track,
          deleteAfterUpload: rendition.profile.id != 'source',
          fileSizeBytes: _fileSizeBytes(rendition.localPath),
        ),
      );
    }

    final masterTask = tasks.firstWhere(
      (task) => task.isMasterPlaylist,
      orElse: () => throw StateError('Master playlist not found in upload plan.'),
    );

    return _UploadPlan(
      tasks: tasks,
      masterPlaylistPath: masterTask.relativePath,
      directoriesToPrune: directoriesToPrune,
    );
  }

  Future<_SignResponse> _requestSignatures({
    required String jobId,
    required List<_UploadTask> tasks,
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (config.authToken != null && config.authToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer ${config.authToken}';
    }
    if (config.additionalHeaders != null) {
      headers.addAll(config.additionalHeaders!);
    }

    final payload = {
      'jobId': jobId,
      'files': [
        for (final task in tasks)
          {
            'path': task.relativePath,
            'contentType': task.contentType,
          },
      ],
    };

    final response = await http.post(
      config.uploadEndpoint,
      headers: headers,
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw StateError(
        'Signer request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    if (decoded['ok'] != true) {
      final error = decoded['error'] ?? 'unknown error';
      throw StateError('Signer response rejected: $error');
    }

    return _SignResponse.fromJson(decoded, fallbackBaseUrl: config.publicBaseUrl);
  }

  Future<void> _putSignedFile(_UploadTask task, _SignedAsset signed) async {
    final file = File(task.localPath);
    if (!await file.exists()) {
      throw StateError('Local file missing for CDN upload: ${task.localPath}');
    }

    final bytes = await file.readAsBytes();
    final response = await http.put(
      signed.putUri,
      headers: {
        'content-type': task.contentType,
      },
      body: bytes,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Failed to PUT ${task.relativePath}: ${response.statusCode} ${response.reasonPhrase}',
      );
    }

    if (task.deleteAfterUpload) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _uploadInBatches(
    List<_UploadTask> tasks,
    Map<String, _SignedAsset> signedAssets,
  ) async {
    if (tasks.isEmpty) {
      return;
    }

    for (var index = 0; index < tasks.length; index += _maxParallelUploads) {
      final batch = tasks.skip(index).take(_maxParallelUploads).toList();
      await Future.wait(batch.map((task) async {
        final signed = signedAssets[task.relativePath];
        if (signed == null) {
          throw StateError('Signer response missing entry for ${task.relativePath}');
        }
        if (kDebugMode) {
          debugPrint(
            'Uploading ${task.relativePath} '
            '(${_formatBytes(task.fileSizeBytes)}) -> ${signed.key}',
          );
        }
        await _putSignedFile(task, signed);
      }));
    }
  }

  Future<void> _cleanupArtifacts(_UploadPlan plan) async {
    for (final dirPath in plan.directoriesToPrune) {
      final directory = Directory(dirPath);
      if (await directory.exists()) {
        try {
          await directory.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  int _fileSizeBytes(String path) {
    try {
      return File(path).lengthSync();
    } catch (_) {
      return 0;
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

  Uri _publicUriForKey(Uri base, String key) {
    final normalizedKey = key.startsWith('/') ? key.substring(1) : key;
    final baseStr = base.toString().endsWith('/')
        ? base.toString()
        : '${base.toString()}/';
    return Uri.parse('$baseStr$normalizedKey');
  }

  String _detectContentType(String path) {
    final ext = p.extension(path).toLowerCase();
    switch (ext) {
      case '.m3u8':
        return 'application/vnd.apple.mpegurl';
      case '.ts':
        return 'video/mp2t';
      case '.mp4':
        return 'video/mp4';
      case '.aac':
        return 'audio/aac';
      case '.mp3':
        return 'audio/mpeg';
      case '.json':
        return 'application/json';
      default:
        return 'application/octet-stream';
    }
  }
}

class VideoCdnConfig {
  const VideoCdnConfig({
    required this.uploadEndpoint,
    required this.publicBaseUrl,
    this.authToken,
    this.storagePrefix,
    this.additionalHeaders,
  });

  final Uri uploadEndpoint;
  final Uri publicBaseUrl;
  final String? authToken;
  final String? storagePrefix;
  final Map<String, String>? additionalHeaders;
}

class _UploadPlan {
  const _UploadPlan({
    required this.tasks,
    required this.masterPlaylistPath,
    this.directoriesToPrune = const <String>{},
  });

  final List<_UploadTask> tasks;
  final String masterPlaylistPath;
  final Set<String> directoriesToPrune;
}

class _UploadTask {
  const _UploadTask({
    required this.localPath,
    required this.relativePath,
    required this.contentType,
    this.associatedTrack,
    this.isMasterPlaylist = false,
    this.deleteAfterUpload = false,
    this.fileSizeBytes = 0,
  });

  final String localPath;
  final String relativePath;
  final String contentType;
  final VideoTrack? associatedTrack;
  final bool isMasterPlaylist;
  final bool deleteAfterUpload;
  final int fileSizeBytes;
}

class _SignResponse {
  _SignResponse({
    required this.assets,
    required this.jobId,
    required this.prefix,
    required this.publicBaseUrl,
  });

  final Map<String, _SignedAsset> assets;
  final String jobId;
  final String? prefix;
  final Uri? publicBaseUrl;

  factory _SignResponse.fromJson(
    Map<String, dynamic> json, {
    required Uri fallbackBaseUrl,
  }) {
    final results = json['results'] as List<dynamic>?;
    if (results == null || results.isEmpty) {
      throw StateError('Signer response missing results array.');
    }

    final assets = <String, _SignedAsset>{};
    for (final item in results) {
      final map = item as Map<String, dynamic>;
      final path = map['path'] as String?;
      final key = map['key'] as String?;
      final putUrl = map['putUrl'] as String?;
      if (path == null || key == null || putUrl == null) {
        throw StateError('Signer result missing required fields: $map');
      }
      assets[path] = _SignedAsset(
        path: path,
        key: key,
        putUri: Uri.parse(putUrl),
      );
    }

    final publicBase = json['publicBaseUrl'] as String?;

    return _SignResponse(
      assets: assets,
      jobId: json['jobId'] as String? ?? '',
      prefix: json['prefix'] as String?,
      publicBaseUrl:
          publicBase != null ? Uri.tryParse(publicBase) ?? fallbackBaseUrl : fallbackBaseUrl,
    );
  }
}

class _SignedAsset {
  const _SignedAsset({
    required this.path,
    required this.key,
    required this.putUri,
  });

  final String path;
  final String key;
  final Uri putUri;
}
