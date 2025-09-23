import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../auth/data/auth_controller.dart';
import '../../feed/domain/feed_content.dart';
import 'media_composer_screen.dart';
import 'publish_post_screen.dart';
import 'widgets/media_composer_support.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  static const routeName = 'create-post';

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {

  final ImagePicker _picker = ImagePicker();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Sign in to share stories with the coalition.'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Close',
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Share a moment',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                'Choose a photo or video from your gallery. You’ll be able to crop, add overlays, and write a caption before posting.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              Expanded(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined,
                              size: 72,
                              color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 24),
                          Text(
                            'What would you like to share?',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap a button below to pick from your gallery. Pinch, swipe, and layer text just like TikTok or Instagram Reels.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.black.withOpacity(0.6)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 28),
                          Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            alignment: WrapAlignment.center,
                            children: [
                              FilledButton.icon(
                                onPressed: _isProcessing ? null : () => _startFlow(FeedMediaType.image),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: const Text('Photo from gallery'),
                              ),
                              OutlinedButton.icon(
                                onPressed: _isProcessing ? null : () => _startFlow(FeedMediaType.video),
                                icon: const Icon(Icons.video_library_outlined),
                                label: const Text('Video from gallery'),
                              ),
                            ],
                          ),
                          if (_isProcessing) ...[
                            const SizedBox(height: 24),
                            const CircularProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startFlow(FeedMediaType type) async {
    if (_isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final pickedFile = await _pickMedia(type);
      if (pickedFile == null) {
        return;
      }

      final aspectRatio = await _resolveAspectRatio(pickedFile, type);
      if (!mounted) return;

      final compositionResult = await Navigator.of(context)
          .push<MediaCompositionResult>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => MediaComposerScreen(
            mediaPath: pickedFile.path,
            mediaType: type,
            initialAspectRatio: aspectRatio,
            initialOverlays: const <EditableOverlay>[],
          ),
        ),
      );

      if (compositionResult == null) {
        return;
      }

      if (!mounted) return;
      final publishResult = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => PublishPostScreen(
            mediaPath: pickedFile.path,
            mediaType: type,
            aspectRatio: compositionResult.aspectRatio,
            composition: compositionResult.transformValues,
            initialOverlays: compositionResult.overlays,
          ),
        ),
      );

      if (publishResult != null && mounted) {
        Navigator.of(context).pop(publishResult);
      }
    } on PlatformException catch (error) {
      _showError('We could not access your gallery (${error.message}).');
    } catch (error, stackTrace) {
      debugPrint('CreatePostScreen flow failed: $error\n$stackTrace');
      _showError('Something went wrong while preparing your post.');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<XFile?> _pickMedia(FeedMediaType type) {
    switch (type) {
      case FeedMediaType.image:
        return _picker.pickImage(
          source: ImageSource.gallery,
          imageQuality: 92,
          maxHeight: 2160,
          maxWidth: 2160,
        );
      case FeedMediaType.video:
        return _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(minutes: 5),
        );
    }
  }

  Future<double> _resolveAspectRatio(XFile file, FeedMediaType type) async {
    if (type == FeedMediaType.image) {
      final decoded = await decodeImageFromList(await file.readAsBytes());
      if (decoded.width == 0 || decoded.height == 0) {
        return 9 / 16;
      }
      return decoded.width / decoded.height;
    }

    final controller = VideoPlayerController.file(File(file.path));
    try {
      await controller.initialize();
      return controller.value.aspectRatio == 0
          ? 9 / 16
          : controller.value.aspectRatio;
    } finally {
      await controller.dispose();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
