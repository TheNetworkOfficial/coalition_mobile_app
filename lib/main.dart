import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/backend_config_loader.dart';
import 'core/config/backend_config_provider.dart';
import 'core/config/video_cdn_config_loader.dart';
import 'core/video/cdn/video_cdn_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backendConfig = await loadBackendConfig();
  final cdnConfig = await loadVideoCdnConfig();

  runApp(
    ProviderScope(
      overrides: [
        backendConfigProvider.overrideWithValue(backendConfig),
        if (cdnConfig != null)
          videoCdnConfigProvider.overrideWithValue(cdnConfig),
      ],
      child: const CoalitionApp(),
    ),
  );
}
