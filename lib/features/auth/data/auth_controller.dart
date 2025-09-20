import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:uuid/uuid.dart';

import '../domain/app_user.dart';
import '../domain/auth_state.dart';
import 'local_user_store.dart';

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

  const GoogleSignInResult.signedIn()
      : this._(GoogleSignInStatus.signedIn);

  const GoogleSignInResult.cancelled()
      : this._(GoogleSignInStatus.cancelled);

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
  AuthController(this._store, this._googleSignIn)
      : super(const AuthState(isLoading: true)) {
    _initialization = _restoreSession();
  }

  final LocalUserStore _store;
  final GoogleSignIn _googleSignIn;

  static const _uuid = Uuid();

  late final Future<void> _initialization;
  List<StoredUserRecord> _users = <StoredUserRecord>[];

  Future<void> _restoreSession() async {
    try {
      _users = await _store.loadUsers();
      final activeId = await _store.loadActiveUserId();
      if (activeId != null) {
        final existing =
            _users.firstWhereOrNull((record) => record.user.id == activeId);
        if (existing != null) {
          state = AuthState(user: existing.user);
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
    );

    final record = StoredUserRecord(
      user: user,
      passwordHash: _hashPassword(credentials.password),
    );

    _users = [..._users, record];
    await _persistUsers();
    await _store.saveActiveUserId(user.id);

    state = AuthState(user: user);
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

    await _store.saveActiveUserId(record.user.id);
    state = AuthState(user: record.user);
  }

  Future<GoogleSignInResult> signInWithGoogle() async {
    await _initialization;
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        return const GoogleSignInResult.cancelled();
      }

      final email = account.email;
      final existing = _findByEmail(email);
      if (existing != null) {
        await _store.saveActiveUserId(existing.user.id);
        state = AuthState(user: existing.user);
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

  Future<void> toggleFollowTag(String tag) async {
    final user = state.user;
    if (user == null) return;
    final updated = {...user.followedTags};
    if (!updated.add(tag)) {
      updated.remove(tag);
    }
    await _updateActiveUser(user.copyWith(followedTags: updated));
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
    final index = _users.indexWhere((record) => record.user.id == updatedUser.id);
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

  StoredUserRecord? _findByIdentifier(String input) {
    final normalized = input.toLowerCase();
    return _users.firstWhereOrNull(
      (record) => record.user.email.toLowerCase() == normalized ||
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
  return GoogleSignIn(scopes: const ['email']);
});

final authControllerProvider =
    StateNotifierProvider<AuthController, AuthState>((ref) {
  final store = ref.watch(localUserStoreProvider);
  final googleSignIn = ref.watch(googleSignInProvider);
  return AuthController(store, googleSignIn);
});
