import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_config_loader.dart';

final backendConfigProvider = Provider<BackendConfig>((ref) {
  throw StateError('BackendConfig has not been loaded.');
});
