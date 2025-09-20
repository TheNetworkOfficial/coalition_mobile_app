import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_user.dart';

class StoredUserRecord {
  StoredUserRecord({required this.user, required this.passwordHash});

  final AppUser user;
  final String passwordHash;

  Map<String, dynamic> toJson() => {
        'user': user.toJson(),
        'passwordHash': passwordHash,
      };

  factory StoredUserRecord.fromJson(Map<String, dynamic> json) =>
      StoredUserRecord(
        user: AppUser.fromJson(
          Map<String, dynamic>.from(
            json['user'] as Map<dynamic, dynamic>,
          ),
        ),
        passwordHash: json['passwordHash'] as String,
      );
}

class LocalUserStore {
  static const _usersKey = 'auth_users';
  static const _activeUserKey = 'active_user_id';

  Future<List<StoredUserRecord>> loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey);
    if (raw == null || raw.isEmpty) {
      return <StoredUserRecord>[];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <StoredUserRecord>[];
      return decoded
          .map((entry) => StoredUserRecord.fromJson(
                Map<String, dynamic>.from(entry as Map<dynamic, dynamic>),
              ))
          .toList();
    } catch (_) {
      return <StoredUserRecord>[];
    }
  }

  Future<void> saveUsers(List<StoredUserRecord> users) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(users.map((user) => user.toJson()).toList());
    await prefs.setString(_usersKey, payload);
  }

  Future<String?> loadActiveUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(_activeUserKey);
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<void> saveActiveUserId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_activeUserKey);
      return;
    }
    await prefs.setString(_activeUserKey, id);
  }
}
