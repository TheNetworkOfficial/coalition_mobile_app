import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/backend_config_loader.dart';
import 'core/config/backend_config_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final backendConfig = await loadBackendConfig();

  runApp(
    ProviderScope(
      overrides: [
        backendConfigProvider.overrideWithValue(backendConfig),
      ],
      child: const CoalitionApp(),
    ),
  );
}
