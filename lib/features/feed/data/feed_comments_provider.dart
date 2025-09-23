import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/feed_comment.dart';
import 'sample_comments.dart';

final feedCommentsProvider =
    Provider.family<List<FeedComment>, String>((ref, contentId) {
  final comments = sampleFeedComments[contentId] ?? const <FeedComment>[];
  final sorted = comments.toList()..sort(_compareComments);
  return sorted;
});

int _compareComments(FeedComment a, FeedComment b) {
  final likeComparison = b.likeCount.compareTo(a.likeCount);
  if (likeComparison != 0) return likeComparison;
  return a.createdAt.compareTo(b.createdAt);
}
