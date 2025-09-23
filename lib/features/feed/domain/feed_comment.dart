class FeedComment {
  const FeedComment({
    required this.id,
    required this.authorName,
    required this.avatarUrl,
    required this.message,
    required this.likeCount,
    required this.createdAt,
    this.parentId,
  });

  final String id;
  final String? parentId;
  final String authorName;
  final String? avatarUrl;
  final String message;
  final int likeCount;
  final DateTime createdAt;
}
