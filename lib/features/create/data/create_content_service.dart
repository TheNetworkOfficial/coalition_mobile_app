import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../events/domain/event.dart';
import '../../feed/data/feed_content_store.dart';
import '../../feed/domain/feed_content.dart';
import '../../../core/services/in_memory_coalition_repository.dart';
import '../../../core/video/video_track.dart';
import '../../video/platform/video_native.dart';
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

    if (request.isVideo) {
      throw const ContentUploadException(
        'Video posts must be created via the new video flow (/create/video).',
      );
    }

    onProgress?.call(CreateUploadStage.uploading);
    final thumbnail = request.coverImagePath ?? request.mediaPath;
    final content = FeedContent(
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
      processingStatus: FeedMediaProcessingStatus.ready,
      processingJobId: null,
    );
    _ref.read(feedContentStoreProvider.notifier).addContent(content);

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
      throw const ContentUploadException(
        'Event videos must be uploaded via the new video flow before publishing.',
      );
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
    final milliseconds = position.inMilliseconds;
    final seconds = milliseconds <= 0 ? 0.0 : milliseconds / 1000.0;
    try {
      final native = _ref.read(videoNativeProvider);
      return await native.generateCoverImage(
        videoPath,
        seconds: seconds,
      );
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
}
