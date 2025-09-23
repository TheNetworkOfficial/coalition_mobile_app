import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/candidate_account_request.dart';

class CandidateAccountRequestStore {
  static const _requestsKey = 'candidate_account_requests';

  bool _useFallbackStore = false;
  final _InMemoryCandidateAccountRequestStore _fallback =
      _InMemoryCandidateAccountRequestStore();

  bool get isUsingFallbackStore => _useFallbackStore;

  Future<List<CandidateAccountRequest>> loadRequests() async {
    if (_useFallbackStore) {
      return _fallback.loadRequests();
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_requestsKey);
      if (raw == null || raw.isEmpty) {
        return <CandidateAccountRequest>[];
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return <CandidateAccountRequest>[];
      }
      return decoded
          .map((entry) => CandidateAccountRequest.fromJson(
                Map<String, dynamic>.from(entry as Map<dynamic, dynamic>),
              ))
          .toList();
    } on MissingPluginException catch (error) {
      _switchToFallback(error);
      return _fallback.loadRequests();
    } on PlatformException catch (error) {
      _switchToFallback(error);
      return _fallback.loadRequests();
    } catch (_) {
      return <CandidateAccountRequest>[];
    }
  }

  Future<void> saveRequests(List<CandidateAccountRequest> requests) async {
    if (_useFallbackStore) {
      await _fallback.saveRequests(requests);
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = jsonEncode(requests.map((r) => r.toJson()).toList());
      await prefs.setString(_requestsKey, payload);
    } on MissingPluginException catch (error) {
      _switchToFallback(error);
      await _fallback.saveRequests(requests);
    } on PlatformException catch (error) {
      _switchToFallback(error);
      await _fallback.saveRequests(requests);
    }
  }

  void _switchToFallback(Object exception) {
    if (_useFallbackStore) return;
    _useFallbackStore = true;
    debugPrint(
      'CandidateAccountRequestStore: falling back to in-memory storage because ${exception.runtimeType} was thrown. Requests will not persist between sessions until SharedPreferences is available.',
    );
  }
}

class _InMemoryCandidateAccountRequestStore {
  static List<CandidateAccountRequest> _requests =
      <CandidateAccountRequest>[];

  Future<List<CandidateAccountRequest>> loadRequests() async {
    return _requests.map((request) => request).toList();
  }

  Future<void> saveRequests(List<CandidateAccountRequest> requests) async {
    _requests = requests.map((request) => request).toList();
  }
}
