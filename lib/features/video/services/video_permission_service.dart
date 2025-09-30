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

    final statuses = await _currentStatuses();
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

    final requested = await _requestPermissions();
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
    try {
      final futures = permissions.map((permission) => permission.status);
      return await Future.wait(futures);
    } on MissingPluginException catch (_) {
      return const <PermissionStatus>[PermissionStatus.granted];
    } on PlatformException catch (_) {
      return const <PermissionStatus>[PermissionStatus.granted];
    }
  }

  Future<List<PermissionStatus>> _requestPermissions() async {
    final permissions = _relevantPermissions;
    if (permissions.isEmpty) {
      return const <PermissionStatus>[];
    }
    try {
      final results = await permissions.request();
      return permissions
          .map((permission) => results[permission] ?? PermissionStatus.denied)
          .toList();
    } on MissingPluginException catch (_) {
      return const <PermissionStatus>[PermissionStatus.granted];
    } on PlatformException catch (_) {
      return const <PermissionStatus>[PermissionStatus.granted];
    }
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
