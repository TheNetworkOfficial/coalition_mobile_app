enum UserAccountType { constituent, candidate }

class AppUser {
  static const Object _noValue = Object();

  AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.zipCode,
    required this.username,
    this.isAdmin = false,
    this.googleLinked = false,
    this.accountType = UserAccountType.constituent,
    this.profileImagePath,
    String? bio,
    this.followersCount = 0,
    this.totalLikes = 0,
    List<String>? likedContentIds,
    List<String>? myContentIds,
    Set<String>? followedCandidateIds,
    Set<String>? followedCreatorIds,
    Set<String>? followedTags,
    Set<String>? rsvpEventIds,
    Map<String, List<String>>? eventRsvpSlotIds,
    this.lastUsernameChangeAt,
    List<String>? followerIds,
    List<String>? followingIds,
  })  : bio = bio ?? '',
        likedContentIds = likedContentIds ?? <String>[],
        myContentIds = myContentIds ?? <String>[],
        followedCandidateIds = followedCandidateIds ?? <String>{},
        followedCreatorIds = followedCreatorIds ?? <String>{},
        followedTags = followedTags ?? <String>{},
        rsvpEventIds = rsvpEventIds ?? <String>{},
        eventRsvpSlotIds = eventRsvpSlotIds ?? <String, List<String>>{},
        followerIds = followerIds ?? <String>[],
        followingIds = followingIds ?? <String>[];

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String zipCode;
  final String username;
  final bool isAdmin;
  final bool googleLinked;
  final UserAccountType accountType;
  final String? profileImagePath;
  final String bio;
  final int followersCount;
  final int totalLikes;
  Set<String> followedCandidateIds;
  Set<String> followedCreatorIds;
  Set<String> followedTags;
  Set<String> rsvpEventIds;
  Map<String, List<String>> eventRsvpSlotIds;
  List<String> likedContentIds;
  List<String> myContentIds;
  final DateTime? lastUsernameChangeAt;
  List<String> followerIds;
  List<String> followingIds;

  String get displayName => '$firstName $lastName'.trim();

  AppUser copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? zipCode,
    String? username,
    bool? isAdmin,
    bool? googleLinked,
    UserAccountType? accountType,
    Object? profileImagePath = _noValue,
    String? bio,
    int? followersCount,
    int? totalLikes,
    Set<String>? followedCandidateIds,
    Set<String>? followedCreatorIds,
    Set<String>? followedTags,
    Set<String>? rsvpEventIds,
    Map<String, List<String>>? eventRsvpSlotIds,
    List<String>? likedContentIds,
    List<String>? myContentIds,
    Object? lastUsernameChangeAt = _noValue,
    List<String>? followerIds,
    List<String>? followingIds,
  }) {
    return AppUser(
      id: id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      zipCode: zipCode ?? this.zipCode,
      username: username ?? this.username,
      isAdmin: isAdmin ?? this.isAdmin,
      googleLinked: googleLinked ?? this.googleLinked,
      accountType: accountType ?? this.accountType,
      profileImagePath: profileImagePath == _noValue
          ? this.profileImagePath
          : profileImagePath as String?,
      bio: bio ?? this.bio,
      followersCount: followersCount ?? this.followersCount,
      totalLikes: totalLikes ?? this.totalLikes,
      followedCandidateIds:
          followedCandidateIds ?? {...this.followedCandidateIds},
      followedCreatorIds: followedCreatorIds ?? {...this.followedCreatorIds},
      followedTags: followedTags ?? {...this.followedTags},
      rsvpEventIds: rsvpEventIds ?? {...this.rsvpEventIds},
      eventRsvpSlotIds: eventRsvpSlotIds ??
          {
            for (final entry in this.eventRsvpSlotIds.entries)
              entry.key: List<String>.from(entry.value),
          },
      likedContentIds:
          likedContentIds ?? List<String>.from(this.likedContentIds),
      myContentIds: myContentIds ?? List<String>.from(this.myContentIds),
      lastUsernameChangeAt: lastUsernameChangeAt == _noValue
          ? this.lastUsernameChangeAt
          : lastUsernameChangeAt as DateTime?,
      followerIds: followerIds ?? List<String>.from(this.followerIds),
      followingIds: followingIds ?? List<String>.from(this.followingIds),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'zipCode': zipCode,
        'username': username,
        'isAdmin': isAdmin,
        'googleLinked': googleLinked,
        'accountType': accountType.name,
        'profileImagePath': profileImagePath,
        'bio': bio,
        'followersCount': followersCount,
        'totalLikes': totalLikes,
        'followedCandidateIds': followedCandidateIds.toList(),
        'followedCreatorIds': followedCreatorIds.toList(),
        'followedTags': followedTags.toList(),
        'rsvpEventIds': rsvpEventIds.toList(),
        'likedContentIds': likedContentIds,
        'myContentIds': myContentIds,
        'eventRsvpSlotIds': {
          for (final entry in eventRsvpSlotIds.entries) entry.key: entry.value,
        },
        'lastUsernameChangeAt': lastUsernameChangeAt?.toIso8601String(),
        'followerIds': followerIds,
        'followingIds': followingIds,
      };

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      firstName: json['firstName'] as String? ?? '',
      lastName: json['lastName'] as String? ?? '',
      email: json['email'] as String? ?? '',
      zipCode: json['zipCode'] as String? ?? '',
      username: json['username'] as String? ?? '',
      isAdmin: json['isAdmin'] as bool? ?? false,
      googleLinked: json['googleLinked'] as bool? ?? false,
      accountType: _accountTypeFromJson(json['accountType']),
      profileImagePath: json['profileImagePath'] as String?,
      bio: json['bio'] as String? ?? '',
      followersCount: json['followersCount'] as int? ?? 0,
      totalLikes: json['totalLikes'] as int? ?? 0,
      followedCandidateIds: _asStringSet(json['followedCandidateIds']),
      followedCreatorIds: _asStringSet(json['followedCreatorIds']),
      followedTags: _asStringSet(json['followedTags']),
      rsvpEventIds: _asStringSet(json['rsvpEventIds']),
      eventRsvpSlotIds: _asEventSlotMap(json['eventRsvpSlotIds']),
      likedContentIds: _asStringList(json['likedContentIds']),
      myContentIds: _asStringList(json['myContentIds']),
      lastUsernameChangeAt: _asDateTime(json['lastUsernameChangeAt']),
      followerIds: _asStringList(json['followerIds']),
      followingIds: _asStringList(json['followingIds']),
    );
  }

  static Set<String> _asStringSet(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).toSet();
    }
    return <String>{};
  }

  static List<String> _asStringList(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).toList();
    }
    return <String>[];
  }

  static Map<String, List<String>> _asEventSlotMap(Object? value) {
    if (value is Map) {
      return value.map((key, dynamic val) {
        if (val is Iterable) {
          return MapEntry(
              key.toString(), val.map((item) => item.toString()).toList());
        }
        return MapEntry(key.toString(), <String>[]);
      });
    }
    return <String, List<String>>{};
  }

  static DateTime? _asDateTime(Object? value) {
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static UserAccountType _accountTypeFromJson(Object? value) {
    final raw = value?.toString();
    if (raw == null) {
      return UserAccountType.constituent;
    }
    for (final type in UserAccountType.values) {
      if (type.name == raw) {
        return type;
      }
    }
    return UserAccountType.constituent;
  }
}
