import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../events/domain/event.dart';
import '../../feed/data/feed_content_store.dart';
import '../../feed/domain/feed_content.dart';
import '../../../core/services/in_memory_coalition_repository.dart';
import '../domain/create_event_request.dart';
import '../domain/create_post_request.dart';

final createContentServiceProvider = Provider<CreateContentService>((ref) {
  return CreateContentService(ref);
});

class CreateContentService {
  CreateContentService(this._ref);

  final Ref _ref;
  static const _uuid = Uuid();

  Future<String> createPost(
    CreatePostRequest request, {
    required AppUser author,
  }) async {
    final contentId = _uuid.v4();
    final now = DateTime.now();
    final sourceType = author.accountType == UserAccountType.candidate
        ? FeedSourceType.candidate
        : FeedSourceType.creator;

    final thumbnail = request.coverImagePath ??
        (request.mediaType == FeedMediaType.image ? request.mediaPath : null);

    final content = FeedContent(
      id: contentId,
      mediaType: request.mediaType,
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

    final coverImage = request.coverImagePath ??
        (request.mediaType == FeedMediaType.image ? request.mediaPath : null);

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
      mediaUrl: request.mediaPath,
      mediaType:
          request.mediaType == null ? null : _mapMediaType(request.mediaType!),
      coverImagePath: coverImage,
      mediaAspectRatio: request.mediaAspectRatio,
      overlays: request.overlays,
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
}
