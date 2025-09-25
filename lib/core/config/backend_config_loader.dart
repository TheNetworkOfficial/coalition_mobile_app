import 'dart:convert';

import 'package:flutter/services.dart';

class BackendConfig {
  const BackendConfig({required this.baseUri});

  final Uri baseUri;
}

Future<BackendConfig> loadBackendConfig() async {
  final raw = await rootBundle.loadString('assets/config/backend_config.json');
  final map = jsonDecode(raw) as Map<String, dynamic>;
  final baseUrl = map['baseUrl'] as String?;
  if (baseUrl == null || baseUrl.isEmpty) {
    throw StateError('backend_config.json missing baseUrl');
  }
  return BackendConfig(baseUri: Uri.parse(baseUrl));
}
