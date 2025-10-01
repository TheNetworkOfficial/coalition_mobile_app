import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
// state_notifier types are provided transitively through flutter_riverpod/legacy

import '../../../core/video/video_track.dart';
import '../domain/feed_content.dart';

class FeedContentStore extends StateNotifier<List<FeedContent>> {
  FeedContentStore() : super(const <FeedContent>[]);

  void addContent(FeedContent content) {
    final existingIndex = state.indexWhere((item) => item.id == content.id);
    if (existingIndex >= 0) {
      final updated = [...state]
        ..removeAt(existingIndex)
        ..insert(0, content);
      state = updated;
    } else {
      state = [content, ...state];
    }
  }

  void updateContent(FeedContent content) {
    final updated = [
      for (final item in state)
        if (item.id == content.id) content else item,
    ];
    state = updated;
  }

  void updateProcessingStatus(
    String contentId, {
    required FeedMediaProcessingStatus status,
    String? mediaUrl,
    String? thumbnailUrl,
    VideoTrack? adaptiveStream,
    List<VideoTrack>? fallbackStreams,
    String? processingJobId,
    String? processingError,
  }) {
    final updated = [
      for (final item in state)
        if (item.id == contentId)
          item.copyWith(
            mediaUrl: mediaUrl ?? item.mediaUrl,
            thumbnailUrl: thumbnailUrl ?? item.thumbnailUrl,
            adaptiveStream: adaptiveStream ?? item.adaptiveStream,
            fallbackStreams: fallbackStreams ?? item.fallbackStreams,
            processingStatus: status,
            processingJobId: processingJobId ?? item.processingJobId,
            processingError: processingError ?? item.processingError,
          )
        else
          item,
    ];
    state = updated;
  }
}

final feedContentStoreProvider =
    StateNotifierProvider<FeedContentStore, List<FeedContent>>((ref) {
  return FeedContentStore();
});

final feedContentCatalogProvider = Provider<List<FeedContent>>((ref) {
  return ref.watch(feedContentStoreProvider);
});
