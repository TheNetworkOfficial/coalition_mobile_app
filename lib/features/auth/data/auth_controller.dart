import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';

import '../domain/app_user.dart';
import '../domain/auth_state.dart';
import 'local_user_store.dart';
import '../../profile/data/profile_connections_provider.dart';
import '../../feed/data/feed_content_store.dart';

class AuthCredentials {
  AuthCredentials({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.zipCode,
    required this.username,
    required this.password,
    required this.confirmPassword,
    this.isGoogleUser = false,
  });

  final String firstName;
  final String lastName;
  final String email;
  final String zipCode;
  final String username;
  final String password;
  final String confirmPassword;
  final bool isGoogleUser;
}

enum GoogleSignInStatus { signedIn, cancelled, needsRegistration, failure }

class GoogleSignInResult {
  const GoogleSignInResult._(
    this.status, {
    this.email,
    this.firstName,
    this.lastName,
    this.message,
  });

  final GoogleSignInStatus status;
  final String? email;
  final String? firstName;
  final String? lastName;
  final String? message;

  const GoogleSignInResult.signedIn() : this._(GoogleSignInStatus.signedIn);

  const GoogleSignInResult.cancelled() : this._(GoogleSignInStatus.cancelled);

  const GoogleSignInResult.failure(String message)
      : this._(GoogleSignInStatus.failure, message: message);

  const GoogleSignInResult.needsRegistration({
    required String email,
    String? firstName,
    String? lastName,
  }) : this._(
          GoogleSignInStatus.needsRegistration,
          email: email,
          firstName: firstName,
          lastName: lastName,
        );
}

class AuthController extends StateNotifier<AuthState> {
  AuthController(this._ref, this._store, this._googleSignIn)
      : super(const AuthState(isLoading: true)) {
    _initialization = _initialize();
  }

  final Ref _ref;
  final LocalUserStore _store;
  final GoogleSignIn _googleSignIn;

  static const _uuid = Uuid();
  // cSpell:ignore roundtable
  static const List<String> _defaultLikedContentIds = [
    'organizing-first-shift',
    'community-roundtable',
    'bluebird-bus-tour',
  ];
  static const List<String> _defaultMyContentIds = [
    'door-to-door-day',
  ];

  late final Future<void> _initialization;
  List<StoredUserRecord> _users = <StoredUserRecord>[];

  Future<void> _initialize() async {
    try {
      await _googleSignIn.initialize();
    } catch (error) {
      debugPrint('GoogleSignIn initialization failed: $error');
    }
    await _restoreSession();
  }

  Future<void> _restoreSession() async {
    try {
      _users = await _store.loadUsers();
      final activeId = await _store.loadActiveUserId();
      if (activeId != null) {
        final existing =
            _users.firstWhereOrNull((record) => record.user.id == activeId);
        if (existing != null) {
          var activeUser = existing.user;
          var needsPersist = false;
          if (activeUser.followerIds.isEmpty &&
              defaultFollowerConnectionIds.isNotEmpty) {
            activeUser = activeUser.copyWith(
              followerIds: List<String>.from(defaultFollowerConnectionIds),
              followersCount: defaultFollowerConnectionIds.length,
            );
            needsPersist = true;
          }
          if (activeUser.followingIds.isEmpty &&
              defaultFollowingConnectionIds.isNotEmpty) {
            activeUser = activeUser.copyWith(
              followingIds: List<String>.from(defaultFollowingConnectionIds),
            );
            needsPersist = true;
          }
          if (needsPersist) {
            final index =
                _users.indexWhere((record) => record.user.id == activeUser.id);
            if (index != -1) {
              _users[index] = StoredUserRecord(
                user: activeUser,
                passwordHash: existing.passwordHash,
              );
              await _persistUsers();
            }
          }
          state = AuthState(user: activeUser);
          return;
        }
      }
    } catch (_) {
      // Ignore restore errors and fall back to unauthenticated state.
    }
    state = const AuthState();
  }

  Future<void> register(AuthCredentials credentials) async {
    await _initialization;
    state = state.copyWith(isLoading: true, clearError: true);

    final validationError = _validateRegistration(credentials);
    if (validationError != null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: validationError,
      );
      return;
    }

    final trimmedFirst = credentials.firstName.trim();
    final trimmedLast = credentials.lastName.trim();
    final trimmedEmail = credentials.email.trim();
    final trimmedZip = credentials.zipCode.trim();
    final trimmedUsername = credentials.username.trim();

    final user = AppUser(
      id: _uuid.v4(),
      firstName: trimmedFirst,
      lastName: trimmedLast,
      email: trimmedEmail,
      zipCode: trimmedZip,
      username: trimmedUsername,
      googleLinked: credentials.isGoogleUser,
      followersCount: defaultFollowerConnectionIds.length,
      totalLikes: 1289,
      likedContentIds: List<String>.from(_defaultLikedContentIds),
      myContentIds: List<String>.from(_defaultMyContentIds),
      followerIds: List<String>.from(defaultFollowerConnectionIds),
      followingIds: List<String>.from(defaultFollowingConnectionIds),
    );

    final record = StoredUserRecord(
      user: user,
      passwordHash: _hashPassword(credentials.password),
    );

    _users = [..._users, record];
    try {
      await _persistUsers();
      await _store.saveActiveUserId(user.id);

      final warning = _store.isUsingFallbackStore
          ? 'Signed in, but local storage is unavailable. This session will reset after a full restart.'
          : null;

      state = AuthState(user: user, errorMessage: warning);
    } catch (error, stackTrace) {
      _users = _users.where((entry) => entry.user.id != user.id).toList();
      _handlePersistenceFailure(error, stackTrace);
    }
  }

  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    await _initialization;
    state = state.copyWith(isLoading: true, clearError: true);

    final trimmedIdentifier = identifier.trim();
    if (trimmedIdentifier.isEmpty || password.isEmpty) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Enter your email or username and password.',
      );
      return;
    }

    final record = _findByIdentifier(trimmedIdentifier);
    if (record == null) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No account matches that email or username.',
      );
      return;
    }

    final hashed = _hashPassword(password);
    if (record.passwordHash != hashed) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Incorrect password.',
      );
      return;
    }

    try {
      await _store.saveActiveUserId(record.user.id);

      final warning = _store.isUsingFallbackStore
          ? 'Signed in, but local storage is unavailable. This session will reset after a full restart.'
          : null;

      state = AuthState(user: record.user, errorMessage: warning);
    } catch (error, stackTrace) {
      _handlePersistenceFailure(error, stackTrace);
    }
  }

  Future<GoogleSignInResult> signInWithGoogle() async {
    await _initialization;
    try {
      if (!_googleSignIn.supportsAuthenticate()) {
        const message =
            'Google Sign-In is not fully supported on this device. Please try another sign-in method.';
        state = state.copyWith(errorMessage: message);
        return const GoogleSignInResult.failure(message);
      }

      final account = await _googleSignIn.authenticate();

      final email = account.email;
      final existing = _findByEmail(email);
      if (existing != null) {
        await _store.saveActiveUserId(existing.user.id);

        final warning = _store.isUsingFallbackStore
            ? 'Signed in, but local storage is unavailable. This session will reset after a full restart.'
            : null;

        state = AuthState(user: existing.user, errorMessage: warning);
        return const GoogleSignInResult.signedIn();
      }

      final displayName = account.displayName;
      final parsedName = _splitDisplayName(displayName);
      final firstName = parsedName.$1;
      final lastName = parsedName.$2;

      return GoogleSignInResult.needsRegistration(
        email: email,
        firstName: firstName,
        lastName: lastName,
      );
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        return const GoogleSignInResult.cancelled();
      }
      state = state.copyWith(
        errorMessage: 'Unable to sign in with Google. Please try again.',
      );
      return const GoogleSignInResult.failure(
        'Unable to sign in with Google. Please try again.',
      );
    } catch (error) {
      state = state.copyWith(
        errorMessage: 'Unable to sign in with Google. Please try again.',
      );
      return const GoogleSignInResult.failure(
        'Unable to sign in with Google. Please try again.',
      );
    }
  }

  Future<void> toggleFollowCandidate(String candidateId) async {
    final user = state.user;
    if (user == null) return;
    final updated = {...user.followedCandidateIds};
    if (!updated.add(candidateId)) {
      updated.remove(candidateId);
    }
    await _updateActiveUser(user.copyWith(followedCandidateIds: updated));
  }

  Future<void> toggleFollowCreator(String creatorId) async {
    final user = state.user;
    if (user == null) return;
    final updated = {...user.followedCreatorIds};
    if (!updated.add(creatorId)) {
      updated.remove(creatorId);
    }
    await _updateActiveUser(user.copyWith(followedCreatorIds: updated));
  }

  Future<void> toggleFollowTag(String tag) async {
    final user = state.user;
    if (user == null) return;
    final updated = {...user.followedTags};
    if (!updated.add(tag)) {
      updated.remove(tag);
    }
    await _updateActiveUser(user.copyWith(followedTags: updated));
  }

  Future<void> toggleLikeContent(String contentId) async {
    final user = state.user;
    if (user == null) return;
    final updated = List<String>.from(user.likedContentIds);
    if (updated.contains(contentId)) {
      updated.remove(contentId);
    } else {
      updated.add(contentId);
    }
    await _updateActiveUser(user.copyWith(likedContentIds: updated));

    // Also update the feed content store so UI that displays counts updates
    try {
      final catalog = _ref.read(feedContentCatalogProvider);
      final index = catalog.indexWhere((c) => c.id == contentId);
      if (index != -1) {
        final existing = catalog[index];
        final currentlyLiked = updated.contains(contentId);
        final likesDelta = currentlyLiked ? 1 : -1;
        final newLikes =
            (existing.interactionStats.likes + likesDelta).clamp(0, 1 << 30);
        final updatedStats =
            existing.interactionStats.copyWith(likes: newLikes);
        _ref
            .read(feedContentStoreProvider.notifier)
            .updateContent(existing.copyWith(interactionStats: updatedStats));
      }
    } catch (e) {
      // Non-fatal - leave user likes updated even if feed update fails
      debugPrint('Failed to update feed content likes: $e');
    }
  }

  Future<void> recordEventRsvp({
    required String eventId,
    required List<String> slotIds,
  }) async {
    final user = state.user;
    if (user == null) return;
    final updatedEvents = {...user.rsvpEventIds}..add(eventId);
    final updatedSlotMap = {
      ...user.eventRsvpSlotIds,
      eventId: slotIds,
    };
    await _updateActiveUser(
      user.copyWith(
        rsvpEventIds: updatedEvents,
        eventRsvpSlotIds: updatedSlotMap,
      ),
    );
  }

  Future<void> cancelEventRsvp(String eventId) async {
    final user = state.user;
    if (user == null) return;
    final updatedEvents = {...user.rsvpEventIds}..remove(eventId);
    final updatedSlotMap = {...user.eventRsvpSlotIds}..remove(eventId);
    await _updateActiveUser(
      user.copyWith(
        rsvpEventIds: updatedEvents,
        eventRsvpSlotIds: updatedSlotMap,
      ),
    );
  }

  Future<void> setUserAccountType({
    required String userId,
    required UserAccountType accountType,
  }) async {
    final index = _users.indexWhere((record) => record.user.id == userId);
    if (index == -1) {
      return;
    }

    final existing = _users[index];
    final updatedUser = existing.user.copyWith(accountType: accountType);
    _users[index] = StoredUserRecord(
      user: updatedUser,
      passwordHash: existing.passwordHash,
    );

    if (state.user?.id == userId) {
      state = state.copyWith(user: updatedUser);
    }

    await _persistUsers();
  }

  Future<String?> updateProfileDetails({
    String? firstName,
    String? lastName,
    String? username,
    String? bio,
  }) async {
    final user = state.user;
    if (user == null) {
      return 'You need to be signed in to update your profile.';
    }

    final trimmedFirst = firstName?.trim();
    final trimmedLast = lastName?.trim();
    final trimmedUsername = username?.trim();
    final trimmedBio = bio?.trim();

    final now = DateTime.now();
    bool usernameChanged = false;
    if (trimmedUsername != null) {
      if (trimmedUsername.isEmpty) {
        return 'Username is required.';
      }
      if (!_usernameRegExp.hasMatch(trimmedUsername)) {
        return 'Usernames may only include letters, numbers, underscores, and periods.';
      }
      final normalizedNew = trimmedUsername.toLowerCase();
      final normalizedCurrent = user.username.toLowerCase();
      if (normalizedNew != normalizedCurrent) {
        usernameChanged = true;
        final lastChange = user.lastUsernameChangeAt;
        if (lastChange != null) {
          final nextAllowed = lastChange.add(const Duration(days: 30));
          if (now.isBefore(nextAllowed)) {
            final remaining = nextAllowed.difference(now);
            final remainingDays =
                remaining.inDays + (remaining.inHours % 24 > 0 ? 1 : 0);
            final message = remainingDays > 0
                ? 'You can change your username again in $remainingDays day${remainingDays == 1 ? '' : 's'}.'
                : 'You can change your username again soon. Please try again later.';
            return message;
          }
        }
        final usernameTaken = _users.any(
          (record) => record.user.username.toLowerCase() == normalizedNew,
        );
        if (usernameTaken) {
          return 'That username is already taken.';
        }
      }
    }

    final updatedUser = user.copyWith(
      firstName: trimmedFirst ?? user.firstName,
      lastName: trimmedLast ?? user.lastName,
      username: trimmedUsername ?? user.username,
      bio: trimmedBio ?? user.bio,
      lastUsernameChangeAt: usernameChanged ? now : user.lastUsernameChangeAt,
    );

    await _updateActiveUser(updatedUser);
    return null;
  }

  Future<void> updateProfileImage(String? imagePath) async {
    final user = state.user;
    if (user == null) return;
    await _updateActiveUser(user.copyWith(profileImagePath: imagePath));
  }

  Future<void> registerCreatedContent(String contentId) async {
    final user = state.user;
    if (user == null) return;
    if (user.myContentIds.contains(contentId)) return;
    final nextIds = [contentId, ...user.myContentIds];
    await _updateActiveUser(user.copyWith(myContentIds: nextIds));
  }

  Future<void> signOut() async {
    await _store.saveActiveUserId(null);
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore Google sign-out failures.
    }
    state = const AuthState();
  }

  Future<void> _updateActiveUser(AppUser updatedUser) async {
    state = AuthState(user: updatedUser);
    final index =
        _users.indexWhere((record) => record.user.id == updatedUser.id);
    if (index == -1) return;
    final existing = _users[index];
    _users[index] = StoredUserRecord(
      user: updatedUser,
      passwordHash: existing.passwordHash,
    );
    await _persistUsers();
  }

  Future<void> _persistUsers() async {
    await _store.saveUsers(_users);
  }

  void _handlePersistenceFailure(Object error, StackTrace stackTrace) {
    debugPrint('Auth persistence failure: $error\n$stackTrace');
    state = state.copyWith(
      isLoading: false,
      errorMessage:
          'We couldn\'t save your account just yet. Please try again in a moment.',
    );
  }

  StoredUserRecord? _findByIdentifier(String input) {
    final normalized = input.toLowerCase();
    return _users.firstWhereOrNull(
      (record) =>
          record.user.email.toLowerCase() == normalized ||
          record.user.username.toLowerCase() == normalized,
    );
  }

  StoredUserRecord? _findByEmail(String email) {
    final normalized = email.toLowerCase();
    return _users.firstWhereOrNull(
      (record) => record.user.email.toLowerCase() == normalized,
    );
  }

  String? _validateRegistration(AuthCredentials credentials) {
    final firstName = credentials.firstName.trim();
    final lastName = credentials.lastName.trim();
    final email = credentials.email.trim();
    final username = credentials.username.trim();
    final zip = credentials.zipCode.trim();
    final password = credentials.password;
    final confirmPassword = credentials.confirmPassword;

    if (firstName.isEmpty) return 'First name is required.';
    if (lastName.isEmpty) return 'Last name is required.';
    if (email.isEmpty) return 'Email address is required.';
    if (!_emailRegExp.hasMatch(email)) return 'Enter a valid email address.';
    if (username.isEmpty) return 'Username is required.';
    if (!_usernameRegExp.hasMatch(username)) {
      return 'Usernames may only include letters, numbers, underscores, and periods.';
    }
    if (zip.isEmpty) return 'ZIP code is required.';
    if (!_zipRegExp.hasMatch(zip)) return 'Enter a valid ZIP code.';
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }
    if (password != confirmPassword) {
      return 'Passwords do not match.';
    }

    final existingEmail = _findByEmail(email);
    if (existingEmail != null) {
      return 'An account with that email already exists.';
    }

    final existingUsername = _users.firstWhereOrNull(
      (record) => record.user.username.toLowerCase() == username.toLowerCase(),
    );
    if (existingUsername != null) {
      return 'That username is already taken.';
    }

    return null;
  }

  static String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static (String?, String?) _splitDisplayName(String? text) {
    if (text == null) return (null, null);
    final trimmed = text.trim();
    if (trimmed.isEmpty) return (null, null);
    final parts = trimmed.split(RegExp(r'\s+'));
    if (parts.isEmpty) return (null, null);
    final first = parts.first;
    if (parts.length == 1) {
      return (first, null);
    }
    final last = parts.sublist(1).join(' ');
    return (first, last.isEmpty ? null : last);
  }

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _zipRegExp = RegExp(r'^\d{5}(?:-\d{4})?$');
  static final _usernameRegExp = RegExp(r'^[A-Za-z0-9_.]{3,}$');
}

extension _StoredUserIterableX on Iterable<StoredUserRecord> {
  StoredUserRecord? firstWhereOrNull(
    bool Function(StoredUserRecord element) test,
  ) {
    for (final record in this) {
      if (test(record)) return record;
    }
    return null;
  }
}

final localUserStoreProvider = Provider<LocalUserStore>((ref) {
  return LocalUserStore();
});

final googleSignInProvider = Provider<GoogleSignIn>((ref) {
  return GoogleSignIn.instance;
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final store = ref.watch(localUserStoreProvider);
  final googleSignIn = ref.watch(googleSignInProvider);
  return AuthController(ref, store, googleSignIn);
});
