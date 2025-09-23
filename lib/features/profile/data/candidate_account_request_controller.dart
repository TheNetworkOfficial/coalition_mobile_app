import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../domain/candidate_account_request.dart';
import 'candidate_account_request_store.dart';

class CandidateAccountRequestController
    extends StateNotifier<AsyncValue<List<CandidateAccountRequest>>> {
  CandidateAccountRequestController(this._ref, this._store)
      : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref _ref;
  final CandidateAccountRequestStore _store;
  static const _uuid = Uuid();

  List<CandidateAccountRequest> get _requests => state.maybeWhen(
        data: (value) => value,
        orElse: () => const <CandidateAccountRequest>[],
      );

  Future<void> _load() async {
    try {
      final loaded = await _store.loadRequests();
      loaded.sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
      state = AsyncValue.data(loaded);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<CandidateAccountRequest> submitRequest({
    required String userId,
    required String fullName,
    required String phone,
    required String email,
    required String campaignAddress,
    required String fecNumber,
  }) async {
    final authUser = _ref.read(authControllerProvider).user;
    if (authUser?.accountType == UserAccountType.candidate) {
      throw StateError('Account is already a candidate.');
    }
    if (_requests.any((request) =>
        request.userId == userId &&
        request.status == CandidateAccountRequestStatus.pending)) {
      throw StateError('A request is already pending review.');
    }

    final request = CandidateAccountRequest(
      id: _uuid.v4(),
      userId: userId,
      fullName: fullName,
      phone: phone,
      email: email,
      campaignAddress: campaignAddress,
      fecNumber: fecNumber,
      status: CandidateAccountRequestStatus.pending,
      submittedAt: DateTime.now(),
    );

    final updated = [..._requests, request]
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    await _persist(updated);
    return request;
  }

  Future<void> reviewRequest({
    required String requestId,
    required CandidateAccountRequestStatus status,
    String? reviewerId,
  }) async {
    final existingIndex =
        _requests.indexWhere((request) => request.id == requestId);
    if (existingIndex == -1) {
      throw StateError('Request not found');
    }
    final existing = _requests[existingIndex];
    final updatedRequest = existing.copyWith(
      status: status,
      reviewedAt: DateTime.now(),
      reviewedBy: reviewerId,
    );
    final updated = [..._requests]
      ..[existingIndex] = updatedRequest
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
    await _persist(updated);

    if (status == CandidateAccountRequestStatus.approved) {
      await _ref
          .read(authControllerProvider.notifier)
          .setUserAccountType(
            userId: existing.userId,
            accountType: UserAccountType.candidate,
          );
    }
  }

  CandidateAccountRequest? latestForUser(String userId) {
    CandidateAccountRequest? latest;
    for (final request in _requests) {
      if (request.userId != userId) continue;
      if (latest == null ||
          request.submittedAt.isAfter(latest.submittedAt)) {
        latest = request;
      }
    }
    return latest;
  }

  bool hasPendingRequest(String userId) {
    return _requests.any((request) =>
        request.userId == userId &&
        request.status == CandidateAccountRequestStatus.pending);
  }

  Future<void> _persist(List<CandidateAccountRequest> updated) async {
    final previous = state;
    state = AsyncValue.data(updated);
    try {
      await _store.saveRequests(updated);
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

final candidateAccountRequestStoreProvider = Provider<CandidateAccountRequestStore>((ref) {
  return CandidateAccountRequestStore();
});

final candidateAccountRequestControllerProvider = StateNotifierProvider<
    CandidateAccountRequestController,
    AsyncValue<List<CandidateAccountRequest>>>((ref) {
  final store = ref.watch(candidateAccountRequestStoreProvider);
  return CandidateAccountRequestController(ref, store);
});
