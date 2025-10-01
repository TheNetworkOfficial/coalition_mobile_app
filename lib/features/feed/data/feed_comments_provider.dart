import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/feed_comment.dart';
final feedCommentsProvider =
    Provider.family<List<FeedComment>, String>((ref, contentId) {
  return const <FeedComment>[];
});
