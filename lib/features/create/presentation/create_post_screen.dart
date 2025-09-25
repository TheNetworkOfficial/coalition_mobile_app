import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_controller.dart';
import '../data/create_content_service.dart';
import '../domain/create_post_request.dart';
import '../../feed/domain/feed_content.dart';
import 'media_picker_screen.dart';
import 'post_details_screen.dart';
import 'video_review_screen.dart';

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
  CreateUploadStage? _progressStage;
  String? _progressMessage;

  @override
  void initState() {
    super.initState();
  }

  String _progressLabelForStage(CreateUploadStage? stage) {
    switch (stage) {
      case CreateUploadStage.preparing:
        return 'Preparing media…';
      case CreateUploadStage.uploading:
        return 'Uploading…';
      case CreateUploadStage.processing:
        return 'Processing in background… You can keep browsing.';
      case CreateUploadStage.completed:
        return 'Finishing up…';
      case null:
        return 'Uploading…';
    }
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

        CreatePostRequest? request;

        if (pickerResult.mediaType == FeedMediaType.video) {
          final reviewResult = await navigator.push<VideoReviewResult>(
            MaterialPageRoute(
              builder: (ctx) => VideoReviewScreen(
                mediaPath: pickerResult.filePath,
                aspectRatio: pickerResult.aspectRatio,
              ),
            ),
          );

          if (!mounted) return;
          if (reviewResult == null) {
            navigator.maybePop();
            return;
          }

          request = await navigator.push<CreatePostRequest>(
            MaterialPageRoute(
              builder: (ctx) => PostDetailsScreen(
                mediaPath: reviewResult.mediaPath,
                mediaType: pickerResult.mediaType,
                aspectRatio: reviewResult.aspectRatio,
                videoDuration: reviewResult.duration,
              ),
            ),
          );
        } else {
          request = await navigator.push<CreatePostRequest>(
            MaterialPageRoute(
              builder: (ctx) => PostDetailsScreen(
                mediaPath: pickerResult.filePath,
                mediaType: pickerResult.mediaType,
                aspectRatio: pickerResult.aspectRatio,
                initialCoverPath: pickerResult.filePath,
              ),
            ),
          );
        }

        if (!mounted) return;
        if (request == null) {
          navigator.maybePop();
          return;
        }

        // Submit the request
        setState(() {
          _submitting = true;
          _progressStage = CreateUploadStage.preparing;
          _progressMessage = _progressLabelForStage(_progressStage);
        });
        try {
          final newContentId =
              await ref.read(createContentServiceProvider).createPost(
            request,
            author: user,
            onProgress: (stage) {
              if (!mounted) return;
              setState(() {
                _progressStage = stage;
                _progressMessage = _progressLabelForStage(stage);
              });
            },
          );
          if (!mounted) return;
          navigator.pop(newContentId);
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Post published! We\'ll finish processing your video shortly.',
              ),
            ),
          );
        } on ContentUploadException catch (error) {
          if (!mounted) return;
          messenger.showSnackBar(
            SnackBar(content: Text(error.message)),
          );
        } catch (error) {
          if (!mounted) return;
          messenger.showSnackBar(
              const SnackBar(content: Text('Failed to publish.')));
        } finally {
          if (mounted) {
            setState(() {
              _submitting = false;
              _progressStage = null;
              _progressMessage = null;
            });
          }
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed:
              _submitting ? null : () => Navigator.of(context).maybePop(),
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
      body: Stack(
        children: [
          const SafeArea(
            child: Center(child: SizedBox.shrink()),
          ),
          if (_submitting)
            _ProgressOverlay(
              message:
                  _progressMessage ?? _progressLabelForStage(_progressStage),
            ),
        ],
      ),
    );
  }
}

class _ProgressOverlay extends StatelessWidget {
  const _ProgressOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AbsorbPointer(
      absorbing: true,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 18,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      height: 36,
                      width: 36,
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
