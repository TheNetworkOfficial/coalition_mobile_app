class AppUser {
  AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.zipCode,
    required this.username,
    this.isAdmin = false,
    this.googleLinked = false,
    Set<String>? followedCandidateIds,
    Set<String>? followedTags,
    Set<String>? rsvpEventIds,
    Map<String, List<String>>? eventRsvpSlotIds,
  })  : followedCandidateIds = followedCandidateIds ?? <String>{},
        followedTags = followedTags ?? <String>{},
        rsvpEventIds = rsvpEventIds ?? <String>{},
        eventRsvpSlotIds = eventRsvpSlotIds ?? <String, List<String>>{};

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String zipCode;
  final String username;
  final bool isAdmin;
  final bool googleLinked;
  Set<String> followedCandidateIds;
  Set<String> followedTags;
  Set<String> rsvpEventIds;
  Map<String, List<String>> eventRsvpSlotIds;

  String get displayName => '$firstName $lastName'.trim();

  AppUser copyWith({
    String? firstName,
    String? lastName,
    String? email,
    String? zipCode,
    String? username,
    bool? isAdmin,
    bool? googleLinked,
    Set<String>? followedCandidateIds,
    Set<String>? followedTags,
    Set<String>? rsvpEventIds,
    Map<String, List<String>>? eventRsvpSlotIds,
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
      followedCandidateIds:
          followedCandidateIds ?? {...this.followedCandidateIds},
      followedTags: followedTags ?? {...this.followedTags},
      rsvpEventIds: rsvpEventIds ?? {...this.rsvpEventIds},
      eventRsvpSlotIds: eventRsvpSlotIds ??
          {
            for (final entry in this.eventRsvpSlotIds.entries)
              entry.key: List<String>.from(entry.value),
          },
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
        'followedCandidateIds': followedCandidateIds.toList(),
        'followedTags': followedTags.toList(),
        'rsvpEventIds': rsvpEventIds.toList(),
        'eventRsvpSlotIds': {
          for (final entry in eventRsvpSlotIds.entries)
            entry.key: entry.value,
        },
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
      followedCandidateIds: _asStringSet(json['followedCandidateIds']),
      followedTags: _asStringSet(json['followedTags']),
      rsvpEventIds: _asStringSet(json['rsvpEventIds']),
      eventRsvpSlotIds: _asEventSlotMap(json['eventRsvpSlotIds']),
    );
  }

  static Set<String> _asStringSet(Object? value) {
    if (value is Iterable) {
      return value.map((item) => item.toString()).toSet();
    }
    return <String>{};
  }

  static Map<String, List<String>> _asEventSlotMap(Object? value) {
    if (value is Map) {
      return value.map((key, dynamic val) {
        if (val is Iterable) {
          return MapEntry(key.toString(), val.map((item) => item.toString()).toList());
        }
        return MapEntry(key.toString(), <String>[]);
      });
    }
    return <String, List<String>>{};
  }
}
