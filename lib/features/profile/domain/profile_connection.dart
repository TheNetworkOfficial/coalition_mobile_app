class ProfileConnection {
  const ProfileConnection({
    required this.id,
    required this.displayName,
    required this.username,
    this.avatarUrl,
  });

  final String id;
  final String displayName;
  final String username;
  final String? avatarUrl;
}
