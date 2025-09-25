import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../config/backend_config_loader.dart';
import '../../config/backend_config_provider.dart';

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

  Uri get _videosUri => _ensureTrailingSlash(_config.baseUri).resolve('videos');

  Future<VideoUploadJob> uploadVideo({
    required File video,
    File? cover,
    required VideoUploadRequest request,
  }) async {
    final uri = _videosUri;
    final multipart = http.MultipartRequest('POST', uri);

    multipart.fields.addAll(request.toFields());
    multipart.files.add(await http.MultipartFile.fromPath('video', video.path));
    if (cover != null && await cover.exists()) {
      multipart.files
          .add(await http.MultipartFile.fromPath('cover', cover.path));
    }

    final streamed = await multipart.send();
    final response = await http.Response.fromStream(streamed);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return VideoUploadJob.fromJson(decoded);
    }

    throw HttpException(
      'Upload failed: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
      uri: uri,
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

  Map<String, String> toFields() {
    return {
      'description': description,
      'hashtags': hashtags.join(','),
      'mentions': mentions.join(','),
      'location': location,
      'visibility': visibility,
      'allowComments': allowComments.toString(),
      'allowSharing': allowSharing.toString(),
    };
  }
}

enum VideoUploadJobStatus { processing, ready, failed }

class VideoUploadJob {
  const VideoUploadJob({
    required this.id,
    required this.status,
    required this.playlistUrl,
    required this.coverUrl,
    required this.error,
  });

  factory VideoUploadJob.fromJson(Map<String, dynamic> json) {
    final outputs = (json['outputs'] as Map<String, dynamic>?) ?? const {};
    return VideoUploadJob(
      id: json['jobId'] as String? ?? json['id'] as String,
      status: _parseStatus(json['status'] as String? ?? 'processing'),
      playlistUrl: outputs['playlistUrl'] as String?,
      coverUrl: outputs['coverUrl'] as String?,
      error: json['error'] as String?,
    );
  }

  final String id;
  final VideoUploadJobStatus status;
  final String? playlistUrl;
  final String? coverUrl;
  final String? error;

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

Uri _ensureTrailingSlash(Uri uri) {
  if (uri.path.endsWith('/')) {
    return uri;
  }
  final path = uri.path.isEmpty ? '/' : '${uri.path}/';
  return uri.replace(path: path);
}
