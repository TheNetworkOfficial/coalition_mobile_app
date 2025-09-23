import '../domain/feed_comment.dart';

final sampleFeedComments = <String, List<FeedComment>>{
  'organizing-first-shift': [
    FeedComment(
      id: 'c1',
      authorName: 'Avery M.',
      avatarUrl:
          'https://images.unsplash.com/photo-1502685104226-ee32379fefbe?auto=format&fit=crop&w=100&q=80',
      message:
          'Team Lux always brings the fire. Anybody in Hamilton wanna ride share to the Sunday shift? DM me!',
      likeCount: 19,
      createdAt: DateTime.now().subtract(const Duration(minutes: 42)),
    ),
    FeedComment(
      id: 'c2',
      authorName: 'Devon C.',
      avatarUrl:
          'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=100&q=80',
      message:
          'Appreciate the accessibility notes you all added. Makes bringing my grandpa along way easier.',
      likeCount: 11,
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ],
  'townhall-highlights': [
    FeedComment(
      id: 'c3',
      authorName: 'Jessie P.',
      avatarUrl:
          'https://images.unsplash.com/photo-1544723795-3fb6469f5b39?auto=format&fit=crop&w=100&q=80',
      message:
          'Huge thank you for spotlighting the Crow leadership. Could we get the slides shared out?',
      likeCount: 33,
      createdAt: DateTime.now().subtract(const Duration(hours: 4)),
    ),
  ],
  'door-to-door-day': [
    FeedComment(
      id: 'c4',
      authorName: 'Labor MT',
      avatarUrl:
          'https://images.unsplash.com/photo-1504595403659-9088ce801e29?auto=format&fit=crop&w=100&q=80',
      message:
          'Proud of this crew. Contract action circle is meeting Wednesday at 6 for anybody inspired by this.',
      likeCount: 58,
      createdAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 12)),
    ),
    FeedComment(
      id: 'c5',
      authorName: 'Morgan B.',
      avatarUrl:
          'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=100&q=80',
      message:
          'Pinning this energy for our weekend turf. Text me if you need clipboards or walk cards.',
      likeCount: 21,
      createdAt: DateTime.now().subtract(const Duration(minutes: 24)),
    ),
  ],
};
