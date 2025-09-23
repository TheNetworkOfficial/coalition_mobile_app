import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
// state_notifier types are provided transitively through flutter_riverpod/legacy

import '../domain/feed_content.dart';
import 'feed_sample_content.dart';

class FeedContentStore extends StateNotifier<List<FeedContent>> {
  FeedContentStore() : super(List<FeedContent>.from(sampleFeedContent));

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
}

final feedContentStoreProvider =
    StateNotifierProvider<FeedContentStore, List<FeedContent>>((ref) {
  return FeedContentStore();
});

final feedContentCatalogProvider = Provider<List<FeedContent>>((ref) {
  return ref.watch(feedContentStoreProvider);
});
