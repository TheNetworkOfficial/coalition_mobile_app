class Candidate {
  const Candidate({
    required this.id,
    required this.name,
    required this.level,
    required this.region,
    required this.bio,
    required this.tags,
    this.headshotUrl,
    this.pronouns,
    this.websiteUrl,
    this.socialLinks = const <SocialLink>[],
    this.isVerified = false,
    this.isCoalitionMember = false,
    this.isNonCoalitionMember = false,
  }) : assert(
          !(isCoalitionMember && isNonCoalitionMember),
          'Candidate cannot be both coalition and non-coalition member',
        );

  final String id;
  final String name;
  final String level;
  final String region;
  final String bio;
  final List<String> tags;
  final String? headshotUrl;
  final String? pronouns;
  final String? websiteUrl;
  final List<SocialLink> socialLinks;
  final bool isVerified;
  final bool isCoalitionMember;
  final bool isNonCoalitionMember;
}

class SocialLink {
  const SocialLink({required this.label, required this.url});

  final String label;
  final String url;
}
