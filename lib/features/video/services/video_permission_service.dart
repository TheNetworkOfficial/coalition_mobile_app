import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final videoPermissionServiceProvider = Provider<VideoPermissionService>((ref) {
  final service = VideoPermissionService();
  service.ensureRequestedOnLaunch();
  return service;
});

class VideoPermissionResult {
  const VideoPermissionResult({
    required this.granted,
    required this.permanentlyDenied,
  });

  final bool granted;
  final bool permanentlyDenied;
}

class VideoPermissionException implements Exception {
  VideoPermissionException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() {
    return 'VideoPermissionException($message)';
  }
}

class VideoPermissionService {
  bool _launchRequestScheduled = false;

  void ensureRequestedOnLaunch() {
    if (_launchRequestScheduled) {
      return;
    }
    _launchRequestScheduled = true;
    Future<void>.microtask(() async {
      await ensureGranted();
    });
  }

  Future<VideoPermissionResult> ensureGranted(
      {bool requestIfDenied = true}) async {
    if (!_requiresRuntimePermission) {
      return const VideoPermissionResult(
          granted: true, permanentlyDenied: false);
    }

    final statuses = await _runPermissionQuery(_currentStatuses);
    if (_anyGranted(statuses)) {
      return const VideoPermissionResult(
          granted: true, permanentlyDenied: false);
    }

    if (!requestIfDenied) {
      final permanentlyDenied = statuses.isNotEmpty &&
          statuses.every((status) => status.isPermanentlyDenied);
      return VideoPermissionResult(
          granted: false, permanentlyDenied: permanentlyDenied);
    }

    final requested = await _runPermissionQuery(_requestPermissions);
    if (_anyGranted(requested)) {
      return const VideoPermissionResult(
          granted: true, permanentlyDenied: false);
    }

    final permanentlyDenied = requested.isNotEmpty &&
        requested.every((status) => status.isPermanentlyDenied);
    return VideoPermissionResult(
        granted: false, permanentlyDenied: permanentlyDenied);
  }

  Future<void> openAppSettingsPage() async {
    try {
      await openAppSettings();
    } catch (_) {
      // Ignore errors when the platform cannot open the settings screen.
    }
  }

  bool get _requiresRuntimePermission {
    if (kIsWeb) {
      return false;
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return true;
    }
    return false;
  }

  Future<List<PermissionStatus>> _currentStatuses() async {
    final permissions = _relevantPermissions;
    if (permissions.isEmpty) {
      return const <PermissionStatus>[];
    }

    final futures = permissions.map((permission) => permission.status);
    return Future.wait(futures);
  }

  Future<List<PermissionStatus>> _requestPermissions() async {
    final permissions = _relevantPermissions;
    if (permissions.isEmpty) {
      return const <PermissionStatus>[];
    }

    final results = await permissions.request();
    return permissions
        .map((permission) => results[permission] ?? PermissionStatus.denied)
        .toList();
  }

  Future<List<PermissionStatus>> _runPermissionQuery(
      Future<List<PermissionStatus>> Function() callback) async {
    try {
      return await callback();
    } on MissingPluginException catch (error, stackTrace) {
      _throwPermissionError(error, stackTrace);
    } on PlatformException catch (error, stackTrace) {
      _throwPermissionError(error, stackTrace);
    }

    throw StateError('Video permission query failed without an error.');
  }

  Never _throwPermissionError(Object error, StackTrace stackTrace) {
    final message =
        error is PlatformException && error.message != null && error.message!.isNotEmpty
            ? error.message!
            : 'Unable to verify video permissions. Please try again later.';
    Error.throwWithStackTrace(
      VideoPermissionException(message, cause: error),
      stackTrace,
    );
  }

  bool _anyGranted(List<PermissionStatus> statuses) {
    return statuses.any((status) =>
        status == PermissionStatus.granted ||
        status == PermissionStatus.limited);
  }

  List<Permission> get _relevantPermissions {
    if (kIsWeb) {
      return const <Permission>[];
    }
    if (Platform.isAndroid) {
      final permissions = <Permission>{
        Permission.storage,
      };
      try {
        permissions.add(Permission.videos);
      } catch (_) {
        // Some plugin builds expose Permission.videos only on newer SDKs.
      }
      return permissions.toList();
    }
    if (Platform.isIOS) {
      return const <Permission>[Permission.photos];
    }
    return const <Permission>[];
  }
}
