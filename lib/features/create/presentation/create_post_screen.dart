import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_controller.dart';
import '../../video/views/video_picker_page.dart';

/// Legacy entry point retained for deep links; surfaces a guard so we can
/// detect lingering links and point folks to the new non-destructive workflow.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  static const routeName = 'create-post';

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to share a story.')),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Legacy create flow')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Heads up – this page should be unreachable.',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            const Text(
              'If you landed here from a button or deep link, please file an issue '
              'so we can update that entry point. The legacy transcoding flow is '
              'gone; use the new instant video editor instead.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => context.goNamed(VideoPickerPage.routeName),
              child: const Text('Open new video flow'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
