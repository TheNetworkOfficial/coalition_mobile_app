import '../domain/feed_content.dart';

final sampleFeedContent = <FeedContent>[
  FeedContent(
    id: 'organizing-first-shift',
    mediaType: FeedMediaType.video,
    mediaUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    thumbnailUrl:
        'https://images.unsplash.com/photo-1526948128573-703ee1aeb6fa?auto=format&fit=crop&w=900&q=80',
    aspectRatio: 9 / 16,
    posterId: 'lux-sam',
    posterName: 'Sam Lux for Congress',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=200&q=80',
    description:
        'First canvass shift in the Bitterroot! We knocked 220 doors today talking rural broadband, healthcare, and veterans services. Meet the crew making it happen. 💪',
    sourceType: FeedSourceType.candidate,
    publishedAt: DateTime.now().subtract(const Duration(hours: 8)),
    tags: {'Rural broadband', 'Healthcare', 'Veterans'},
    associatedCandidateIds: {'lux-sam'},
    zipCode: '59840',
    interactionStats: const FeedInteractionStats(
      likes: 482,
      comments: 64,
      shares: 53,
      follows: 12,
    ),
  ),
  FeedContent(
    id: 'townhall-highlights',
    mediaType: FeedMediaType.image,
    mediaUrl:
        'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?auto=format&fit=crop&w=1400&q=80',
    aspectRatio: 3 / 4,
    posterId: 'public-lands-roundtable',
    posterName: 'Public Lands Roundtable',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=200&q=80',
    description:
        'Full house in Bozeman for the public lands roundtable. We heard from hunters, outfitters, and tribal leaders on what access means to their communities. Watch for the policy commitments we made in the final 10 minutes.',
    sourceType: FeedSourceType.event,
    publishedAt: DateTime.now().subtract(const Duration(hours: 30)),
    tags: {'Public lands', 'Economic development'},
    associatedEventIds: {'public-lands-roundtable'},
    associatedCandidateIds: {'lux-sam', 'adriana-two-hearts'},
    zipCode: '59715',
    interactionStats: const FeedInteractionStats(
      likes: 611,
      comments: 112,
      shares: 87,
      follows: 8,
    ),
  ),
  FeedContent(
    id: 'community-roundtable',
    mediaType: FeedMediaType.image,
    mediaUrl:
        'https://images.unsplash.com/photo-1492725764893-90b379c2b6e7?auto=format&fit=crop&w=1400&q=80',
    aspectRatio: 4 / 5,
    posterId: 'adriana-two-hearts',
    posterName: 'Adriana Two-Hearts',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1530023367847-a683933f4177?auto=format&fit=crop&w=200&q=80',
    description:
        'Listening session with ranchers and water managers in Hardin tonight. We left with six follow-up actions to protect irrigation access this summer. Drop your water priorities so our team can follow up.',
    sourceType: FeedSourceType.candidate,
    publishedAt: DateTime.now().subtract(const Duration(hours: 20)),
    tags: {'Clean water', 'Indigenous rights'},
    associatedCandidateIds: {'adriana-two-hearts'},
    zipCode: '59034',
    interactionStats: const FeedInteractionStats(
      likes: 318,
      comments: 47,
      shares: 39,
      follows: 21,
    ),
  ),
  FeedContent(
    id: 'door-to-door-day',
    mediaType: FeedMediaType.video,
    mediaUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    aspectRatio: 9 / 16,
    posterId: 'jamison-halloway',
    posterName: 'Jamison for HD76',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1529665253569-6d01c0eaf7b6?auto=format&fit=crop&w=200&q=80',
    description:
        'Spent the afternoon in Anaconda with labor families. We talked cost-of-living and the hospital closure. Solidarity to everyone showing up for their neighbors every weekend.',
    sourceType: FeedSourceType.candidate,
    publishedAt: DateTime.now().subtract(const Duration(hours: 3)),
    tags: {'Labor rights', 'Healthcare'},
    associatedCandidateIds: {'jamison-halloway'},
    zipCode: '59711',
    interactionStats: const FeedInteractionStats(
      likes: 908,
      comments: 142,
      shares: 126,
      follows: 42,
    ),
    isPromoted: true,
  ),
  FeedContent(
    id: 'parent-roundtable-snippet',
    mediaType: FeedMediaType.image,
    mediaUrl:
        'https://images.unsplash.com/photo-1511512578047-dfb367046420?auto=format&fit=crop&w=1400&q=80',
    aspectRatio: 4 / 5,
    posterId: 'maria-chen',
    posterName: 'Maria Chen',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1498139947040-06ac5be294e1?auto=format&fit=crop&w=200&q=80',
    description:
        'Preschool teachers reminding us that wrap-around care is make-or-break. Full clip includes the funding plan we rolled out at the forum tonight.',
    sourceType: FeedSourceType.candidate,
    publishedAt: DateTime.now().subtract(const Duration(hours: 15)),
    tags: {'Education', 'Childcare'},
    associatedCandidateIds: {'maria-chen'},
    zipCode: '59801',
    interactionStats: const FeedInteractionStats(
      likes: 272,
      comments: 58,
      shares: 41,
      follows: 17,
    ),
  ),
  FeedContent(
    id: 'organizer-spotlight-latoya',
    mediaType: FeedMediaType.image,
    mediaUrl:
        'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?auto=format&fit=crop&w=1400&q=80',
    aspectRatio: 4 / 5,
    posterId: 'coalition-volunteers',
    posterName: 'Coalition Volunteer Stories',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1521737604893-d14cc237f11d?auto=format&fit=crop&w=200&q=80',
    description:
        'Latoya started leading our Missoula canvasses this winter. She pulls the biggest volunteer phone banks every Tuesday. Want to co-host with her? Tap the link to join the organizer cohort.',
    sourceType: FeedSourceType.creator,
    publishedAt: DateTime.now().subtract(const Duration(hours: 48)),
    tags: {'Volunteering', 'Community'},
    relatedCreatorIds: {'coalition-volunteers'},
    zipCode: '59802',
    interactionStats: const FeedInteractionStats(
      likes: 124,
      comments: 18,
      shares: 34,
      follows: 55,
    ),
  ),
  FeedContent(
    id: 'climate-lab-update',
    mediaType: FeedMediaType.video,
    mediaUrl:
        'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    thumbnailUrl:
        'https://images.unsplash.com/photo-1489515217757-5fd1be406fef?auto=format&fit=crop&w=1400&q=80',
    aspectRatio: 16 / 9,
    posterId: 'big-sky-climate-lab',
    posterName: 'Big Sky Climate Lab',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1448932223592-d1fc686e76ea?auto=format&fit=crop&w=200&q=80',
    description:
        'New carbon capture pilot in Butte just hit a 47% efficiency mark. Here’s what that means for our grid and union jobs.',
    sourceType: FeedSourceType.creator,
    publishedAt: DateTime.now().subtract(const Duration(hours: 6)),
    tags: {'Climate action', 'Smart growth'},
    relatedCreatorIds: {'big-sky-climate-lab'},
    zipCode: '59701',
    interactionStats: const FeedInteractionStats(
      likes: 689,
      comments: 203,
      shares: 181,
      follows: 76,
    ),
  ),
  FeedContent(
    id: 'coalition-voter-drives',
    mediaType: FeedMediaType.image,
    mediaUrl:
        'https://images.unsplash.com/photo-1511497584788-876760111969?auto=format&fit=crop&w=1400&q=80',
    aspectRatio: 3 / 4,
    posterId: 'coalition-staff',
    posterName: 'Coalition Field Team',
    posterAvatarUrl:
        'https://images.unsplash.com/photo-1530023367847-a683933f4177?auto=format&fit=crop&w=200&q=80',
    description:
        'Zip code 59102 you showed up! 42 new voters registered at the weekend pop-up. We’re heading to Billings Heights next—tag a friend who should come volunteer.',
    sourceType: FeedSourceType.creator,
    publishedAt: DateTime.now().subtract(const Duration(hours: 12)),
    tags: {'Community', 'Voting rights'},
    zipCode: '59102',
    interactionStats: const FeedInteractionStats(
      likes: 354,
      comments: 41,
      shares: 62,
      follows: 19,
    ),
  ),
];
