import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/profile_connection.dart';

final profileConnectionsProvider = Provider<Map<String, ProfileConnection>>((ref) {
  return {
    for (final connection in _sampleConnections) connection.id: connection,
  };
});

const defaultFollowerConnectionIds = <String>[
  'ivy-cortez',
  'marcus-finley',
  'dani-wu',
  'amir-ali',
  'sutton-ray',
  'liam-ortega',
  'carmen-hart',
  'noah-ellis',
];

const defaultFollowingConnectionIds = <String>[
  'chloe-garrett',
  'remy-fernandez',
  'lucas-patel',
  'devin-montoya',
  'sasha-cho',
  'jules-howard',
];

const _sampleConnections = <ProfileConnection>[
  ProfileConnection(
    id: 'ivy-cortez',
    displayName: 'Ivy Cortez',
    username: 'ivyforchange',
    avatarUrl:
        'https://images.unsplash.com/photo-1544723795-3fb6469f5b39?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'marcus-finley',
    displayName: 'Marcus Finley',
    username: 'mfinley',
    avatarUrl:
        'https://images.unsplash.com/photo-1544723795-43253726b87c?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'dani-wu',
    displayName: 'Dani Wu',
    username: 'danifor406',
    avatarUrl:
        'https://images.unsplash.com/photo-1521579971123-1192931a1452?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'amir-ali',
    displayName: 'Amir Ali',
    username: 'amirorganizes',
    avatarUrl:
        'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'sutton-ray',
    displayName: 'Sutton Ray',
    username: 'suttonray',
    avatarUrl:
        'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'liam-ortega',
    displayName: 'Liam Ortega',
    username: 'liamworks',
    avatarUrl:
        'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'carmen-hart',
    displayName: 'Carmen Hart',
    username: 'carmenhart',
    avatarUrl:
        'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'noah-ellis',
    displayName: 'Noah Ellis',
    username: 'ellis4helena',
    avatarUrl:
        'https://images.unsplash.com/photo-1544723795-43253726b87c?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'chloe-garrett',
    displayName: 'Chloe Garrett',
    username: 'chloeg',
    avatarUrl:
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'remy-fernandez',
    displayName: 'Remy Fernandez',
    username: 'remyforrivers',
    avatarUrl:
        'https://images.unsplash.com/photo-1502685104226-ee32379fefbe?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'lucas-patel',
    displayName: 'Lucas Patel',
    username: 'lucaspatel',
    avatarUrl:
        'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'devin-montoya',
    displayName: 'Devin Montoya',
    username: 'devinmt',
    avatarUrl:
        'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'sasha-cho',
    displayName: 'Sasha Cho',
    username: 'sashafields',
    avatarUrl:
        'https://images.unsplash.com/photo-1502685104226-ee32379fefbe?auto=format&fit=crop&w=320&q=80',
  ),
  ProfileConnection(
    id: 'jules-howard',
    displayName: 'Jules Howard',
    username: 'juleshoward',
    avatarUrl:
        'https://images.unsplash.com/photo-1524504388940-b1c1722653e1?auto=format&fit=crop&w=320&q=80',
  ),
];
