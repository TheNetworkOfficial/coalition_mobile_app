class UserContent {
  const UserContent({
    required this.id,
    required this.title,
    this.description,
    this.thumbnailUrl,
    this.category,
  });

  final String id;
  final String title;
  final String? description;
  final String? thumbnailUrl;
  final String? category;
}
