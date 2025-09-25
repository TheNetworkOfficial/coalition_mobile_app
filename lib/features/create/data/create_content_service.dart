import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../events/domain/event.dart';
import '../../feed/data/feed_content_store.dart';
import '../../feed/domain/feed_content.dart';
import '../../../core/config/backend_config_loader.dart';
import '../../../core/config/backend_config_provider.dart';
import '../../../core/services/in_memory_coalition_repository.dart';
import '../../../core/video/video_track.dart';
import '../../../core/video/upload/video_upload_repository.dart';
import '../domain/create_event_request.dart';
import '../domain/create_post_request.dart';

final createContentServiceProvider = Provider<CreateContentService>((ref) {
  return CreateContentService(ref);
});

enum CreateUploadStage { preparing, uploading, processing, completed }

class ContentUploadException implements Exception {
  const ContentUploadException(this.message);

  final String message;

  @override
  String toString() => 'ContentUploadException: $message';
}

class CreateContentService {
  CreateContentService(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<String> createPost(
    CreatePostRequest request, {
    required AppUser author,
    ValueChanged<CreateUploadStage>? onProgress,
  }) async {
    final contentId = _uuid.v4();
    final now = DateTime.now();
    final sourceType = author.accountType == UserAccountType.candidate
        ? FeedSourceType.candidate
        : FeedSourceType.creator;

    FeedContent content;

    if (request.isVideo) {
      final uploadRepository = _ref.read(videoUploadRepositoryProvider);
      final backendConfig = _ref.read(backendConfigProvider);
      final videoFile = File(request.mediaPath);
      if (!videoFile.existsSync()) {
        throw const ContentUploadException('Selected video could not be located.');
      }

      onProgress?.call(CreateUploadStage.uploading);
      final job = await uploadRepository.uploadVideo(
        video: videoFile,
        cover: request.coverImagePath != null
            ? File(request.coverImagePath!)
            : null,
        request: VideoUploadRequest(
          description: request.description,
          hashtags: request.tags,
          mentions: request.mentions,
          location: request.location ?? '',
          visibility: request.visibility,
          allowComments: request.allowComments,
          allowSharing: request.allowSharing,
        ),
      );

      onProgress?.call(CreateUploadStage.processing);

      final coverUrl = _resolveMediaUrl(backendConfig, job.coverUrl) ??
          request.coverImagePath;

      content = FeedContent(
        id: contentId,
        mediaType: FeedMediaType.video,
        mediaUrl: request.mediaPath,
        thumbnailUrl: coverUrl,
        aspectRatio: request.aspectRatio,
        posterId: author.id,
        posterName: author.displayName,
        posterAvatarUrl: author.profileImagePath,
        description: request.description,
        sourceType: sourceType,
        publishedAt: now,
        tags: request.tags.toSet(),
        interactionStats: const FeedInteractionStats(),
        overlays: request.overlays,
        compositionTransform: request.compositionTransform,
        processingStatus: FeedMediaProcessingStatus.processing,
        processingJobId: job.id,
      );

      _ref.read(feedContentStoreProvider.notifier).addContent(content);
      unawaited(_watchUploadJob(
        contentId: contentId,
        jobId: job.id,
      ));
    } else {
      onProgress?.call(CreateUploadStage.uploading);
      final thumbnail = request.coverImagePath ?? request.mediaPath;
      content = FeedContent(
        id: contentId,
        mediaType: FeedMediaType.image,
        mediaUrl: request.mediaPath,
        thumbnailUrl: thumbnail,
        aspectRatio: request.aspectRatio,
        posterId: author.id,
        posterName: author.displayName,
        posterAvatarUrl: author.profileImagePath,
        description: request.description,
        sourceType: sourceType,
        publishedAt: now,
        tags: request.tags.toSet(),
        interactionStats: const FeedInteractionStats(),
        overlays: request.overlays,
        compositionTransform: request.compositionTransform,
      );
      _ref.read(feedContentStoreProvider.notifier).addContent(content);
    }

    onProgress?.call(CreateUploadStage.completed);

    await _ref
        .read(authControllerProvider.notifier)
        .registerCreatedContent(contentId);

    return contentId;
  }

  Future<String> createEvent(
    CreateEventRequest request, {
    required AppUser author,
  }) async {
    final repository = _ref.read(coalitionRepositoryProvider);
    final eventId = _uuid.v4();

    String? coverImage = request.coverImagePath ??
        (request.mediaType == FeedMediaType.image ? request.mediaPath : null);

    String? processedMediaPath = request.mediaPath;
    VideoTrack? adaptiveStream;
    List<VideoTrack> fallbackStreams = const <VideoTrack>[];

    if (request.mediaType == FeedMediaType.video && request.mediaPath != null) {
      final uploadRepository = _ref.read(videoUploadRepositoryProvider);
      final backendConfig = _ref.read(backendConfigProvider);
      final job = await uploadRepository.uploadVideo(
        video: File(request.mediaPath!),
        request: VideoUploadRequest(
          description: request.description,
          hashtags: request.tags,
          mentions: const <String>[],
          location: request.location,
          visibility: 'public',
          allowComments: true,
          allowSharing: true,
        ),
      );

      final result = await uploadRepository
          .pollJob(job.id)
          .lastWhere((job) => job.isComplete);

      if (result.isReady) {
        final playlistUrl =
            _resolveMediaUrl(backendConfig, result.playlistUrl);
        final coverUrl = _resolveMediaUrl(backendConfig, result.coverUrl);
        final fallbacks = _buildFallbackTracks(
          backendConfig,
          result,
          cachePrefix: 'event-${job.id}',
        );
        if (playlistUrl != null) {
          processedMediaPath = playlistUrl;
        } else if (fallbacks.isNotEmpty) {
          processedMediaPath = fallbacks.first.uri.toString();
        }
        adaptiveStream = playlistUrl != null
            ? VideoTrack(
                uri: Uri.parse(playlistUrl),
                label: 'Auto',
                isAdaptive: true,
                cacheKey: 'event-${job.id}-master',
              )
            : null;
        fallbackStreams = fallbacks;
        if (coverUrl != null) {
          coverImage = coverUrl;
        }
      } else {
        throw ContentUploadException(
          'Event video processing failed: ${result.error ?? 'unknown error'}',
        );
      }
    }

    final event = CoalitionEvent(
      id: eventId,
      title: request.title,
      description: request.description,
      startDate: request.primaryDate,
      location: request.location,
      type: request.eventType ?? 'general',
      cost: request.cost ?? 'Free',
      hostCandidateIds: request.hostCandidateIds,
      tags: request.tags,
      timeSlots: request.timeSlots,
      mediaUrl: processedMediaPath,
      mediaType:
          request.mediaType == null ? null : _mapMediaType(request.mediaType!),
      coverImagePath: coverImage,
      mediaAspectRatio: request.mediaAspectRatio,
      overlays: request.overlays,
      adaptiveMediaStream: adaptiveStream,
      mediaFallbackStreams: fallbackStreams,
    );

    await repository.addOrUpdateEvent(event);
    return eventId;
  }

  Future<String> generateCoverFromVideo({
    required String videoPath,
    required Duration position,
  }) async {
    try {
      final output = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        imageFormat: ImageFormat.PNG,
        timeMs: position.inMilliseconds,
        quality: 92,
        thumbnailPath: Directory.systemTemp.path,
        maxHeight: 720,
        maxWidth: 720,
      );
      if (output == null) {
        throw StateError('Unable to capture frame.');
      }
      return output;
    } catch (error, stackTrace) {
      debugPrint('Cover generation failed: $error\n$stackTrace');
      rethrow;
    }
  }

  EventMediaType _mapMediaType(FeedMediaType type) {
    switch (type) {
      case FeedMediaType.image:
        return EventMediaType.image;
      case FeedMediaType.video:
        return EventMediaType.video;
    }
  }

  Future<void> _watchUploadJob({
    required String contentId,
    required String jobId,
  }) async {
    final uploadRepository = _ref.read(videoUploadRepositoryProvider);
    final backendConfig = _ref.read(backendConfigProvider);
    await for (final job in uploadRepository.pollJob(jobId)) {
      final coverUrl = _resolveMediaUrl(backendConfig, job.coverUrl);
      if (job.status == VideoUploadJobStatus.processing) {
        _ref.read(feedContentStoreProvider.notifier).updateProcessingStatus(
              contentId,
              status: FeedMediaProcessingStatus.processing,
              thumbnailUrl: coverUrl,
              processingJobId: job.id,
            );
      } else if (job.status == VideoUploadJobStatus.ready) {
        final playlistUrl = _resolveMediaUrl(backendConfig, job.playlistUrl);
        final fallbackTracks = _buildFallbackTracks(
          backendConfig,
          job,
          cachePrefix: 'feed-${job.id}',
        );
        VideoTrack? adaptive;
        if (playlistUrl != null) {
          adaptive = VideoTrack(
            uri: Uri.parse(playlistUrl),
            label: 'Auto',
            isAdaptive: true,
            cacheKey: 'feed-${job.id}-master',
          );
        }
        _ref.read(feedContentStoreProvider.notifier).updateProcessingStatus(
              contentId,
              status: FeedMediaProcessingStatus.ready,
              mediaUrl: playlistUrl,
              thumbnailUrl: coverUrl,
              adaptiveStream: adaptive,
              fallbackStreams: fallbackTracks,
              processingJobId: job.id,
              processingError: null,
            );
      } else if (job.status == VideoUploadJobStatus.failed) {
        _ref.read(feedContentStoreProvider.notifier).updateProcessingStatus(
              contentId,
              status: FeedMediaProcessingStatus.failed,
              processingJobId: job.id,
              processingError: job.error,
            );
      }
    }
  }

  String? _resolveMediaUrl(BackendConfig config, String? path) {
    if (path == null || path.isEmpty) {
      return null;
    }
    final origin = config.baseUri.replace(path: '/');
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return origin.resolve(normalized).toString();
  }

  List<VideoTrack> _buildFallbackTracks(
    BackendConfig config,
    VideoUploadJob job, {
    required String cachePrefix,
  }) {
    final tracks = <VideoTrack>[];
    for (final rendition in job.renditions) {
      final url =
          _resolveMediaUrl(config, rendition.mp4Url ?? rendition.playlistUrl);
      if (url == null || url.isEmpty) {
        continue;
      }
      final width = rendition.width;
      final height = rendition.height;
      tracks.add(
        VideoTrack(
          uri: Uri.parse(url),
          label: rendition.label ?? rendition.id,
          bitrateKbps: rendition.bitrateKbps,
          resolution: width != null && height != null
              ? Size(width.toDouble(), height.toDouble())
              : null,
          isAdaptive: rendition.mp4Url == null && rendition.playlistUrl != null,
          cacheKey: rendition.mp4Url != null
              ? '$cachePrefix-${rendition.id}'
              : null,
        ),
      );
    }
    return tracks;
  }
}
