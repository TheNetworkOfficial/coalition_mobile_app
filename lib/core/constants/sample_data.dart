import '../../features/candidates/domain/candidate.dart';
import '../../features/events/domain/event.dart';

const sampleCandidates = <Candidate>[
  Candidate(
    id: 'lux-sam',
    name: 'Sam Lux',
    level: 'federal',
    region: 'Montana At-Large',
    bio:
        'Organizer, veteran, and community-builder running for Congress to put people over partisanship.',
    tags: ['Rural broadband', 'Veterans', 'Public lands'],
    headshotUrl:
        'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=400&q=80',
    websiteUrl: 'https://luxformontana.com',
    socialLinks: [
      SocialLink(label: 'Campaign Site', url: 'https://luxformontana.com'),
      SocialLink(
        label: 'Instagram',
        url: 'https://instagram.com/luxformontana',
      ),
    ],
  ),
  Candidate(
    id: 'jamison-halloway',
    name: 'Jamison Halloway',
    level: 'state',
    region: 'House District 76',
    bio:
        'Labor advocate focused on lowering health costs and protecting working families across the valley.',
    tags: ['Healthcare', 'Labor rights', 'Affordable housing'],
    headshotUrl:
        'https://images.unsplash.com/photo-1529665253569-6d01c0eaf7b6?auto=format&fit=crop&w=400&q=80',
    socialLinks: [
      SocialLink(label: 'Facebook', url: 'https://facebook.com/jamisonfor76'),
    ],
  ),
  Candidate(
    id: 'adriana-two-hearts',
    name: 'Adriana Two-Hearts',
    level: 'county',
    region: 'Yellowstone County Commission',
    bio:
        'Urban planner championing sustainable growth, safe water, and community-driven development.',
    tags: ['Clean water', 'Smart growth', 'Indigenous rights'],
    socialLinks: [
      SocialLink(label: 'Website', url: 'https://twoheartsformontana.org'),
      SocialLink(label: 'Twitter', url: 'https://twitter.com/twoheartsMT'),
    ],
  ),
  Candidate(
    id: 'maria-chen',
    name: 'Maria Chen',
    level: 'city',
    region: 'Missoula City Council',
    bio:
        'Missoula educator expanding early childhood programs and building climate-resilient housing.',
    tags: ['Education', 'Climate action', 'Affordable housing'],
    socialLinks: [
      SocialLink(label: 'Instagram', url: 'https://instagram.com/maria4missoula'),
      SocialLink(label: 'Threads', url: 'https://threads.net/@maria4missoula'),
    ],
  ),
];

final sampleEvents = <CoalitionEvent>[
  CoalitionEvent(
    id: 'field-launch',
    title: 'Field Launch Weekend',
    description:
        'Join the coalition for a weekend of door-knocking, phone banking, and community dinners.',
    startDate: DateTime.now().add(const Duration(days: 5)),
    location: 'Helena HQ',
    type: 'organizing',
    cost: 'Free',
    hostCandidateIds: ['lux-sam', 'jamison-halloway'],
    tags: ['Volunteering', 'Community'],
    timeSlots: [
      EventTimeSlot(
        id: 'field-launch-saturday',
        label: 'Saturday · 10:00 AM - 1:00 PM',
        capacity: 30,
      ),
      EventTimeSlot(
        id: 'field-launch-sunday',
        label: 'Sunday · 12:00 PM - 4:00 PM',
        capacity: 24,
      ),
    ],
  ),
  CoalitionEvent(
    id: 'public-lands-roundtable',
    title: 'Public Lands Roundtable',
    description:
        'Hear from candidates on protecting access to public lands and boosting outdoor economies.',
    startDate: DateTime.now().add(const Duration(days: 12)),
    location: 'Bozeman Outfitters Co-Op',
    type: 'town-hall',
    cost: 'Suggested donation: \$15',
    hostCandidateIds: ['lux-sam', 'adriana-two-hearts'],
    tags: ['Public lands', 'Economic development'],
    timeSlots: [
      EventTimeSlot(
        id: 'lands-roundtable-session',
        label: 'Wednesday · 6:00 PM - 7:30 PM',
        capacity: 120,
      ),
    ],
  ),
  CoalitionEvent(
    id: 'education-townhall',
    title: 'Education Future Town Hall',
    description:
        'A conversational town hall on early childhood education and classroom resources.',
    startDate: DateTime.now().add(const Duration(days: 21)),
    location: 'Missoula Public Library',
    type: 'town-hall',
    cost: 'Free with RSVP',
    hostCandidateIds: ['maria-chen'],
    tags: ['Education', 'Families'],
    timeSlots: [
      EventTimeSlot(
        id: 'education-townhall-session',
        label: 'Thursday · 5:30 PM - 7:00 PM',
      ),
    ],
  ),
];
