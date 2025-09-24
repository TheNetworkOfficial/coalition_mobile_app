import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
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
import '../../../core/video/video_transcode_service.dart';
import '../../../core/video/video_track.dart';
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

    var processedMediaPath = request.mediaPath;
    VideoTrack? adaptiveStream;
    List<VideoTrack> fallbackStreams = const <VideoTrack>[];

    if (request.isVideo) {
      try {
        final processed = await _prepareVideoForPublishing(request.mediaPath);
        processedMediaPath = _stringFromUri(processed.primaryTrack.uri);
        adaptiveStream = processed.adaptiveTrack;
        fallbackStreams = processed.fallbackTracks;
      } on VideoTranscodeException catch (error, stackTrace) {
        debugPrint('Video transcode failed: $error\n$stackTrace');
      }
    }

    final thumbnail = request.coverImagePath ??
        (request.mediaType == FeedMediaType.image
            ? request.mediaPath
            : null);

    final content = FeedContent(
      id: contentId,
      mediaType: request.mediaType,
      mediaUrl: processedMediaPath,
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
      adaptiveStream: adaptiveStream,
      fallbackStreams: fallbackStreams,
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

    String? processedMediaPath = request.mediaPath;
    VideoTrack? adaptiveStream;
    List<VideoTrack> fallbackStreams = const <VideoTrack>[];

    if (request.mediaType == FeedMediaType.video &&
        request.mediaPath != null) {
      try {
        final processed = await _prepareVideoForPublishing(request.mediaPath!);
        processedMediaPath = _stringFromUri(processed.primaryTrack.uri);
        adaptiveStream = processed.adaptiveTrack;
        fallbackStreams = processed.fallbackTracks;
      } on VideoTranscodeException catch (error, stackTrace) {
        debugPrint('Event video transcode failed: $error\n$stackTrace');
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

  Future<VideoProcessingBundle> _prepareVideoForPublishing(
    String mediaPath,
  ) async {
    final connectivity = await Connectivity().checkConnectivity();
    final preferCellular = connectivity == ConnectivityResult.mobile;
    return _ref
        .read(videoTranscodeServiceProvider)
        .prepareForUpload(
          sourcePath: mediaPath,
          preferCellularProfile: preferCellular,
        );
  }

  String _stringFromUri(Uri uri) {
    if (uri.scheme == 'file') {
      return uri.toFilePath();
    }
    if (uri.scheme.isEmpty) {
      return uri.toString();
    }
    return uri.toString();
  }
}
