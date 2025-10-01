import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/data/feed_content_store.dart';
import '../../feed/domain/feed_content.dart';
import '../domain/user_content.dart';

final userContentCatalogProvider = Provider<List<UserContent>>((ref) {
  final feedCatalog = ref.watch(feedContentCatalogProvider);
  return feedCatalog
      .map(_fromFeedContent)
      .toList(growable: false);
});

final userContentByIdProvider = Provider<Map<String, UserContent>>((ref) {
  final catalog = ref.watch(userContentCatalogProvider);
  return {
    for (final item in catalog) item.id: item,
  };
});

UserContent _fromFeedContent(FeedContent content) {
  final description = content.description.trim();
  final firstSentence = description.split(RegExp(r'[\n\.!?]')).first.trim();
  final title = firstSentence.isNotEmpty ? firstSentence : content.posterName;
  final thumbnail = content.thumbnailUrl ?? content.mediaUrl;

  return UserContent(
    id: content.id,
    title: title,
    description: description.isEmpty ? null : description,
    thumbnailUrl: thumbnail,
    category: switch (content.sourceType) {
      FeedSourceType.event => 'Events',
      FeedSourceType.candidate => 'Campaign stories',
      FeedSourceType.creator => 'Community',
    },
  );
}
