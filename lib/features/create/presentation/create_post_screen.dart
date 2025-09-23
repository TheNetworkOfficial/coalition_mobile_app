import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_controller.dart';
import '../data/create_content_service.dart';
import '../domain/create_post_request.dart';
import 'media_composer_screen.dart';
import 'widgets/media_composer_support.dart';
import 'media_picker_screen.dart';
import 'publish_post_screen.dart';

/// A thin orchestration screen that immediately opens the media picker.
///
/// Flow:
/// 1) MediaPickerScreen (full-screen) -> returns filePath, mediaType, aspectRatio
/// 2) MediaComposerScreen (full-screen) -> returns transform/overlays/baked path
/// 3) PublishPostScreen -> returns CreatePostRequest
/// 4) This screen submits the request and pops with the new content id.
class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  static const routeName = 'create-post';

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  bool _pickerPresented = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to share a story.')),
      );
    }

    if (!_pickerPresented) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        _pickerPresented = true;
        final navigator = Navigator.of(context);
        final messenger = ScaffoldMessenger.of(context);

        final pickerResult = await navigator.push<MediaPickerResult>(
          MaterialPageRoute(builder: (ctx) => const MediaPickerScreen()),
        );

        if (!mounted) return;
        if (pickerResult == null) {
          navigator.maybePop();
          return;
        }

        // Open composer
        final compositionResult = await navigator.push<MediaCompositionResult>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (ctx) => MediaComposerScreen(
              mediaPath: pickerResult.filePath,
              mediaType: pickerResult.mediaType,
              initialAspectRatio: pickerResult.aspectRatio,
              initialTransformValues: null,
              initialOverlays: const <EditableOverlay>[],
            ),
          ),
        );

        if (!mounted) return;
        if (compositionResult == null) return;

        final request = await navigator.push<CreatePostRequest>(
          MaterialPageRoute(
            builder: (ctx) => PublishPostScreen(
              mediaPath: pickerResult.filePath,
              mediaType: pickerResult.mediaType,
              aspectRatio: compositionResult.aspectRatio,
              composition: compositionResult.transformValues,
              initialOverlays: compositionResult.overlays,
              overrideMediaPath: compositionResult.bakedFilePath,
            ),
          ),
        );

        if (!mounted) return;
        if (request == null) return;

        // Submit the request
        setState(() => _submitting = true);
        try {
          final newContentId = await ref
              .read(createContentServiceProvider)
              .createPost(request, author: user);
          if (!mounted) return;
          navigator.pop(newContentId);
          messenger.showSnackBar(
            const SnackBar(content: Text('Post published to the feed.')),
          );
        } catch (error) {
          if (!mounted) return;
          messenger.showSnackBar(
              const SnackBar(content: Text('Failed to publish.')));
        } finally {
          if (mounted) setState(() => _submitting = false);
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (_submitting)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
        ],
      ),
      body: const SafeArea(
        child: Center(child: SizedBox.shrink()),
      ),
    );
  }
}
