import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/data/feed_content_store.dart';
import '../../feed/domain/feed_content.dart';
import '../domain/user_content.dart';

final userContentCatalogProvider = Provider<List<UserContent>>((ref) {
  final feedCatalog = ref.watch(feedContentCatalogProvider);
  final entries = {
    for (final item in _sampleUserContent) item.id: item,
  };

  for (final content in feedCatalog) {
    entries.putIfAbsent(content.id, () => _fromFeedContent(content));
  }

  return entries.values.toList(growable: false);
});

final userContentByIdProvider = Provider<Map<String, UserContent>>((ref) {
  final catalog = ref.watch(userContentCatalogProvider);
  return {
    for (final item in catalog) item.id: item,
  };
});

const _sampleUserContent = <UserContent>[
  UserContent(
    id: 'organizing-first-shift',
    title: 'Organizing kickoff',
    description: 'Volunteers canvassing on opening weekend.',
    thumbnailUrl: 'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?auto=format&fit=crop&w=400&q=80',
    category: 'Field work',
  ),
  UserContent(
    id: 'door-to-door-day',
    title: 'Door to door',
    description: 'Meeting neighbors in Livingston.',
    thumbnailUrl: 'https://images.unsplash.com/photo-1530023367847-a683933f4177?auto=format&fit=crop&w=400&q=80',
    category: 'Community',
  ),
  UserContent(
    id: 'community-roundtable',
    title: 'Community roundtable',
    description: 'Small business owners talking policy.',
    thumbnailUrl: 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=400&q=80',
    category: 'Town hall',
  ),
  UserContent(
    id: 'bluebird-bus-tour',
    title: 'Bus tour in the valley',
    description: 'Highlight from the latest county tour stop.',
    thumbnailUrl: 'https://images.unsplash.com/photo-1471306224500-6d0e0d1c0f5c?auto=format&fit=crop&w=400&q=80',
    category: 'Campaign trail',
  ),
  UserContent(
    id: 'weekend-rally',
    title: 'Weekend rally',
    description: 'Packed house in Helena.',
    thumbnailUrl: 'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80',
    category: 'Rally',
  ),
  UserContent(
    id: 'policy-explainer',
    title: 'Policy explainer',
    description: 'Breaking down rural broadband plans.',
    thumbnailUrl: 'https://images.unsplash.com/photo-1522202176988-66273c2fd55f?auto=format&fit=crop&w=400&q=80',
    category: 'Issues',
  ),
];

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
