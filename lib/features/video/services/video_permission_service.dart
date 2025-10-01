import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

final videoPermissionServiceProvider = Provider<VideoPermissionService>((ref) {
  return VideoPermissionService();
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
  int? _cachedAndroidSdkInt;
  DeviceInfoPlugin? _deviceInfo;

  Future<VideoPermissionResult> ensureGranted({
    bool requestIfDenied = true,
  }) async {
    if (!_requiresRuntimePermission) {
      return const VideoPermissionResult(
        granted: true,
        permanentlyDenied: false,
      );
    }

    final statuses = await _runPermissionQuery(_currentStatuses);
    if (_anyGranted(statuses)) {
      return const VideoPermissionResult(
        granted: true,
        permanentlyDenied: false,
      );
    }

    if (!requestIfDenied) {
      final permanentlyDenied = statuses.isNotEmpty &&
          statuses.every((status) => status.isPermanentlyDenied);
      return VideoPermissionResult(
        granted: false,
        permanentlyDenied: permanentlyDenied,
      );
    }

    final requested = await _runPermissionQuery(_requestPermissions);
    if (_anyGranted(requested)) {
      return const VideoPermissionResult(
        granted: true,
        permanentlyDenied: false,
      );
    }

    final permanentlyDenied = requested.isNotEmpty &&
        requested.every((status) => status.isPermanentlyDenied);
    return VideoPermissionResult(
      granted: false,
      permanentlyDenied: permanentlyDenied,
    );
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
    final permissions = await _relevantPermissions();
    if (permissions.isEmpty) {
      return const <PermissionStatus>[];
    }

    final futures = permissions.map((permission) => permission.status);
    return Future.wait(futures);
  }

  Future<List<PermissionStatus>> _requestPermissions() async {
    final permissions = await _relevantPermissions();
    if (permissions.isEmpty) {
      return const <PermissionStatus>[];
    }

    final results = await permissions.request();
    return permissions
        .map((permission) => results[permission] ?? PermissionStatus.denied)
        .toList();
  }

  Future<List<PermissionStatus>> _runPermissionQuery(
    Future<List<PermissionStatus>> Function() callback,
  ) async {
    try {
      return await callback();
    } on MissingPluginException catch (error, stackTrace) {
      _throwPermissionError(error, stackTrace); // throws, never returns
    } on PlatformException catch (error, stackTrace) {
      _throwPermissionError(error, stackTrace); // throws, never returns
    }
  }

  Never _throwPermissionError(Object error, StackTrace stackTrace) {
    final message = error is PlatformException &&
            error.message != null &&
            error.message!.isNotEmpty
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

  Future<List<Permission>> _relevantPermissions() async {
    if (kIsWeb) {
      return const <Permission>[];
    }
    if (Platform.isAndroid) {
      final sdkInt = await _androidSdkInt();
      if (sdkInt != null && sdkInt >= 33) {
        // Android 13+ (API 33/34): use READ_MEDIA_VIDEO
        return [Permission.videos];
      } else {
        // Android 12 and below: fall back to legacy storage
        return [Permission.storage];
      }
    }
    if (Platform.isIOS) {
      // iOS requires Photos permission for picking videos
      return [Permission.photos];
    }
    // Fallback: no relevant permission
    return [];
  }

  Future<int?> _androidSdkInt() async {
    if (!Platform.isAndroid) {
      return null;
    }
    final cached = _cachedAndroidSdkInt;
    if (cached != null) {
      return cached;
    }

    try {
      final plugin = _deviceInfo ??= DeviceInfoPlugin();
      final info = await plugin.androidInfo;
      _cachedAndroidSdkInt = info.version.sdkInt;
      if (_cachedAndroidSdkInt != null) {
        return _cachedAndroidSdkInt;
      }
    } catch (_) {
      // Fall through to secondary detection.
    }

    final parsed = _parseSdkFromPlatformVersion();
    if (parsed != null) {
      _cachedAndroidSdkInt = parsed;
    }
    return _cachedAndroidSdkInt;
  }

  int? _parseSdkFromPlatformVersion() {
    final version = Platform.operatingSystemVersion;
    final match = RegExp(r'Android\s+(\d+)(?:\.(\d+))?').firstMatch(version);
    if (match == null) {
      return null;
    }
    final major = int.tryParse(match.group(1) ?? '');
    if (major == null) {
      return null;
    }
    switch (major) {
      case 14:
        return 34; // Android 14
      case 13:
        return 33;
      case 12:
        return 31; // 12L maps to 32 but storage perms remain required
      case 11:
        return 30;
      case 10:
        return 29;
      case 9:
        return 28;
      case 8:
        return 26; // Approximate for Oreo
      default:
        return null;
    }
  }
}
