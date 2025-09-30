// Legacy AWS/S3 upload path preserved for reference. New video flows should use
// features/video/services/mux_upload_service.dart instead.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config/backend_config_loader.dart';
import '../core/config/backend_config_provider.dart';

final videoUploadRepositoryProvider = Provider<VideoUploadRepository>((ref) {
  final config = ref.watch(backendConfigProvider);
  final repository = VideoUploadRepository(
    client: http.Client(),
    config: config,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

class VideoUploadRepository {
  VideoUploadRepository(
      {required http.Client client, required BackendConfig config})
      : _client = client,
        _config = config;

  final http.Client _client;
  final BackendConfig _config;

  Uri get _videosUri =>
      _ensureTrailingSlash(_config.baseUri).resolve('videos/');

  Future<VideoUploadJob> uploadVideo({
    required File video,
    File? cover,
    required VideoUploadRequest request,
  }) async {
    final coverFile = cover;
    final includeCover = coverFile != null && await coverFile.exists();
    final session = await _createSession(
      request: request,
      includeCover: includeCover,
    );

    final uploaded = <VideoUploadAssetType, VideoUploadTarget>{};

    final videoTarget = session.targetFor(VideoUploadAssetType.video);
    if (videoTarget == null) {
      throw HttpException('Upload session missing video target.',
          uri: _videosUri);
    }
    await _uploadToSignedUrl(target: videoTarget, file: video);
    uploaded[VideoUploadAssetType.video] = videoTarget;

    if (includeCover) {
      final coverTarget = session.targetFor(VideoUploadAssetType.cover);
      if (coverTarget == null) {
        throw HttpException('Upload session missing cover target.',
            uri: _videosUri);
      }
      await _uploadToSignedUrl(target: coverTarget, file: coverFile);
      uploaded[VideoUploadAssetType.cover] = coverTarget;
    }

    return _completeSession(
      sessionId: session.id,
      uploaded: uploaded,
    );
  }

  Future<VideoUploadJob> fetchJob(String jobId) async {
    final uri = _videosUri.resolve(jobId);
    final response = await _client.get(uri);
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return VideoUploadJob.fromJson(decoded);
    }
    throw HttpException('Failed to fetch job $jobId: ${response.statusCode}',
        uri: uri);
  }

  Stream<VideoUploadJob> pollJob(
    String jobId, {
    Duration interval = const Duration(seconds: 2),
  }) async* {
    while (true) {
      final job = await fetchJob(jobId);
      yield job;
      if (job.isComplete) {
        break;
      }
      await Future<void>.delayed(interval);
    }
  }

  void dispose() {
    _client.close();
  }

  Future<VideoUploadSession> _createSession({
    required VideoUploadRequest request,
    required bool includeCover,
  }) async {
    final uri = _videosUri.resolve('sessions');
    final payload = request.toJson(includeCover: includeCover);
    final response = await _client.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return VideoUploadSession.fromJson(decoded);
    }

    throw HttpException(
      'Failed to create upload session: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
      uri: uri,
    );
  }

  Future<void> _uploadToSignedUrl({
    required VideoUploadTarget target,
    required File file,
  }) async {
    if (!await file.exists()) {
      throw FileSystemException('Upload source missing', file.path);
    }

    final request = http.Request('PUT', target.putUrl);
    request.headers['content-type'] = target.contentType;
    if (target.headers.isNotEmpty) {
      request.headers.addAll(target.headers);
    }
    request.bodyBytes = await file.readAsBytes();

    final response = await _client.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      throw HttpException(
        'Failed to upload ${target.type.name}: ${response.statusCode} ${response.reasonPhrase}\n$body',
        uri: target.putUrl,
      );
    }
    await response.stream.drain();
  }

  Future<VideoUploadJob> _completeSession({
    required String sessionId,
    required Map<VideoUploadAssetType, VideoUploadTarget> uploaded,
  }) async {
    final uri = _videosUri.resolve('sessions/$sessionId/complete');
    final payload = {
      'uploaded': {
        for (final entry in uploaded.entries)
          entry.key.name: entry.value.objectKey,
      },
    };
    final response = await _client.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return VideoUploadJob.fromJson(decoded);
    }

    throw HttpException(
      'Failed to finalize upload session $sessionId: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
      uri: uri,
    );
  }

  Map<String, String> get _jsonHeaders =>
      const {'content-type': 'application/json'};
}

class VideoUploadRequest {
  const VideoUploadRequest({
    required this.description,
    required this.hashtags,
    required this.mentions,
    required this.location,
    required this.visibility,
    required this.allowComments,
    required this.allowSharing,
  });

  final String description;
  final List<String> hashtags;
  final List<String> mentions;
  final String location;
  final String visibility;
  final bool allowComments;
  final bool allowSharing;

  Map<String, dynamic> toJson({required bool includeCover}) {
    return {
      'description': description,
      'hashtags': hashtags,
      'mentions': mentions,
      'location': location,
      'visibility': visibility,
      'allowComments': allowComments,
      'allowSharing': allowSharing,
      'includeCover': includeCover,
    };
  }
}

enum VideoUploadAssetType { video, cover }

class VideoUploadTarget {
  const VideoUploadTarget({
    required this.type,
    required this.putUrl,
    required this.contentType,
    required this.objectKey,
    Map<String, String>? headers,
  }) : headers = headers ?? const {};

  factory VideoUploadTarget.fromJson(Map<String, dynamic> json) {
    final typeValue = json['type'] as String?;
    final putUrlValue = json['putUrl'] as String? ?? json['url'] as String?;
    if (putUrlValue == null || putUrlValue.isEmpty) {
      throw const FormatException('Upload target missing putUrl');
    }
    final headerMap = <String, String>{};
    final rawHeaders = json['headers'];
    if (rawHeaders is Map) {
      for (final entry in rawHeaders.entries) {
        headerMap[entry.key.toString()] = entry.value.toString();
      }
    }
    return VideoUploadTarget(
      type: _assetTypeFromJson(typeValue),
      putUrl: Uri.parse(putUrlValue),
      contentType:
          (json['contentType'] as String?) ?? 'application/octet-stream',
      objectKey: (json['objectKey'] as String?) ?? '',
      headers: headerMap,
    );
  }

  final VideoUploadAssetType type;
  final Uri putUrl;
  final String contentType;
  final String objectKey;
  final Map<String, String> headers;
}

class VideoUploadSession {
  const VideoUploadSession({
    required this.id,
    required this.targets,
  });

  factory VideoUploadSession.fromJson(Map<String, dynamic> json) {
    final uploads = <VideoUploadAssetType, VideoUploadTarget>{};
    final rawUploads = json['uploads'];
    if (rawUploads is List) {
      for (final item in rawUploads) {
        if (item is Map<String, dynamic>) {
          final target = VideoUploadTarget.fromJson(item);
          uploads[target.type] = target;
        }
      }
    } else if (rawUploads is Map) {
      for (final entry in rawUploads.entries) {
        final value = entry.value;
        if (value is Map<String, dynamic>) {
          final targetJson = Map<String, dynamic>.from(value);
          targetJson.putIfAbsent('type', () => entry.key.toString());
          final target = VideoUploadTarget.fromJson(targetJson);
          uploads[target.type] = target;
        }
      }
    }

    final sessionId = json['sessionId'] as String? ?? json['id'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      throw const FormatException('Upload session missing sessionId');
    }

    return VideoUploadSession(
      id: sessionId,
      targets: uploads,
    );
  }

  final String id;
  final Map<VideoUploadAssetType, VideoUploadTarget> targets;

  VideoUploadTarget? targetFor(VideoUploadAssetType type) => targets[type];
}

enum VideoUploadJobStatus { processing, ready, failed }

class VideoUploadRendition {
  const VideoUploadRendition({
    required this.id,
    this.label,
    this.playlistUrl,
    this.mp4Url,
    this.width,
    this.height,
    this.bitrateKbps,
  });

  factory VideoUploadRendition.fromJson(Map<String, dynamic> json) {
    return VideoUploadRendition(
      id: json['id'] as String? ?? 'rendition',
      label: json['label'] as String?,
      playlistUrl: json['playlistUrl'] as String?,
      mp4Url: json['mp4Url'] as String?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      bitrateKbps: json['bitrateKbps'] as int?,
    );
  }

  final String id;
  final String? label;
  final String? playlistUrl;
  final String? mp4Url;
  final int? width;
  final int? height;
  final int? bitrateKbps;
}

class VideoUploadJob {
  const VideoUploadJob({
    required this.id,
    required this.status,
    required this.playlistUrl,
    required this.coverUrl,
    required this.error,
    required this.renditions,
  });

  factory VideoUploadJob.fromJson(Map<String, dynamic> json) {
    final outputs = (json['outputs'] as Map<String, dynamic>?) ?? const {};
    final renditionList = outputs['renditions'];
    final renditions = <VideoUploadRendition>[];
    if (renditionList is List) {
      for (final item in renditionList) {
        if (item is Map<String, dynamic>) {
          renditions.add(VideoUploadRendition.fromJson(item));
        }
      }
    }
    return VideoUploadJob(
      id: json['jobId'] as String? ?? json['id'] as String,
      status: _parseStatus(json['status'] as String? ?? 'processing'),
      playlistUrl: outputs['playlistUrl'] as String?,
      coverUrl: outputs['coverUrl'] as String?,
      error: json['error'] as String?,
      renditions: renditions,
    );
  }

  final String id;
  final VideoUploadJobStatus status;
  final String? playlistUrl;
  final String? coverUrl;
  final String? error;
  final List<VideoUploadRendition> renditions;

  bool get isComplete =>
      status == VideoUploadJobStatus.ready ||
      status == VideoUploadJobStatus.failed;
  bool get isReady => status == VideoUploadJobStatus.ready;
  bool get isFailed => status == VideoUploadJobStatus.failed;
}

VideoUploadJobStatus _parseStatus(String value) {
  switch (value.toLowerCase()) {
    case 'ready':
      return VideoUploadJobStatus.ready;
    case 'failed':
      return VideoUploadJobStatus.failed;
    default:
      return VideoUploadJobStatus.processing;
  }
}

VideoUploadAssetType _assetTypeFromJson(String? value) {
  switch (value?.toLowerCase()) {
    case 'cover':
      return VideoUploadAssetType.cover;
    default:
      return VideoUploadAssetType.video;
  }
}

Uri _ensureTrailingSlash(Uri uri) {
  if (uri.path.endsWith('/')) {
    return uri;
  }
  final path = uri.path.isEmpty ? '/' : '${uri.path}/';
  return uri.replace(path: path);
}
