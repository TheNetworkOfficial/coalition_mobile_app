import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

  bool _useFallbackStore = false;
  final _InMemoryUserStore _fallback = _InMemoryUserStore();

  bool get isUsingFallbackStore => _useFallbackStore;

  Future<List<StoredUserRecord>> loadUsers() async {
    if (_useFallbackStore) {
      return _fallback.loadUsers();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_usersKey);
      if (raw == null || raw.isEmpty) {
        return <StoredUserRecord>[];
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) return <StoredUserRecord>[];
      return decoded
          .map((entry) => StoredUserRecord.fromJson(
                Map<String, dynamic>.from(entry as Map<dynamic, dynamic>),
              ))
          .toList();
    } on MissingPluginException catch (error) {
      _switchToFallback(error);
      return _fallback.loadUsers();
    } on PlatformException catch (error) {
      _switchToFallback(error);
      return _fallback.loadUsers();
    } catch (_) {
      return <StoredUserRecord>[];
    }
  }

  Future<void> saveUsers(List<StoredUserRecord> users) async {
    if (_useFallbackStore) {
      await _fallback.saveUsers(users);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(users.map((user) => user.toJson()).toList());
      await prefs.setString(_usersKey, payload);
    } on MissingPluginException catch (error) {
      _switchToFallback(error);
      await _fallback.saveUsers(users);
    } on PlatformException catch (error) {
      _switchToFallback(error);
      await _fallback.saveUsers(users);
    }
  }

  Future<String?> loadActiveUserId() async {
    if (_useFallbackStore) {
      return _fallback.loadActiveUserId();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(_activeUserKey);
      return (id == null || id.isEmpty) ? null : id;
    } on MissingPluginException catch (error) {
      _switchToFallback(error);
      return _fallback.loadActiveUserId();
    } on PlatformException catch (error) {
      _switchToFallback(error);
      return _fallback.loadActiveUserId();
    }
  }

  Future<void> saveActiveUserId(String? id) async {
    if (_useFallbackStore) {
      await _fallback.saveActiveUserId(id);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(_activeUserKey);
        return;
      }
      await prefs.setString(_activeUserKey, id);
    } on MissingPluginException catch (error) {
      _switchToFallback(error);
      await _fallback.saveActiveUserId(id);
    } on PlatformException catch (error) {
      _switchToFallback(error);
      await _fallback.saveActiveUserId(id);
    }
  }

  void _switchToFallback(Object exception) {
    if (_useFallbackStore) return;
    _useFallbackStore = true;
    debugPrint(
      'LocalUserStore: falling back to in-memory storage because ${exception.runtimeType} was thrown. Persistent login will be unavailable until the SharedPreferences plugin is registered.',
    );
  }
}

class _InMemoryUserStore {
  static List<StoredUserRecord> _users = <StoredUserRecord>[];
  static String? _activeUserId;

  Future<List<StoredUserRecord>> loadUsers() async {
    return _users
        .map((record) => StoredUserRecord(
              user: record.user,
              passwordHash: record.passwordHash,
            ))
        .toList();
  }

  Future<void> saveUsers(List<StoredUserRecord> users) async {
    _users = users
        .map((record) => StoredUserRecord(
              user: record.user,
              passwordHash: record.passwordHash,
            ))
        .toList();
  }

  Future<String?> loadActiveUserId() async {
    return _activeUserId;
  }

  Future<void> saveActiveUserId(String? id) async {
    _activeUserId = id;
  }
}
