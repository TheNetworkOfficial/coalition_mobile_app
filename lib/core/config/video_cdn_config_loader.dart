import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../video/cdn/video_cdn_service.dart';

Future<VideoCdnConfig?> loadVideoCdnConfig() async {
  try {
    final raw = await rootBundle.loadString('assets/config/cdn_config.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;

    final upload = map['uploadEndpoint'] as String?;
    final publicBase = map['publicBaseUrl'] as String?;
    if (upload == null || publicBase == null) {
      return null;
    }

    return VideoCdnConfig(
      uploadEndpoint: Uri.parse(upload),
      publicBaseUrl: Uri.parse(publicBase),
      authToken: map['authToken'] as String?,
      storagePrefix: map['storagePrefix'] as String?,
      additionalHeaders: (map['headers'] as Map?)?.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
    );
  } on FlutterError {
    return null;
  } catch (_) {
    return null;
  }
}
