import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
// uuid removed - overlays/features simplified
import 'package:video_player/video_player.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../feed/domain/feed_content.dart';
import '../data/create_content_service.dart';
import '../domain/create_post_request.dart';
import 'widgets/media_composer_support.dart';
import 'publish_post_screen.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  static const routeName = 'create-post';

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  static const _defaultVideoAspectRatio = 9 / 16;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocusNode = FocusNode();

  XFile? _mediaFile;
  FeedMediaType? _mediaType;
  double? _mediaAspectRatio;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;

  // overlays removed - using full-screen editor instead
  final Set<String> _selectedTags = <String>{};

  String? _generatedCoverPath;
  XFile? _customCoverFile;
  Duration? _coverFramePosition;
  bool _isGeneratingCover = false;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _disposeVideoController();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
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

    final tagsAsync = ref.watch(candidateTagsProvider);
    final candidateTags = tagsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <String>[],
    );

    final canSubmit = _mediaFile != null && !_isSubmitting;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create post'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Discard',
        ),
        actions: [
          TextButton(
            onPressed: canSubmit ? () => _handleSubmit(user) : null,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text('Post'),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildMediaSection(context)),
            // overlays removed: editing happens in full-screen editor after media selection
            SliverToBoxAdapter(child: _buildDescriptionSection(context)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Campaign tags',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (tagsAsync.isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (candidateTags.isEmpty)
                      Text(
                        'Tags will appear here once the campaign team adds them.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final tag in candidateTags)
                            FilterChip(
                              label: Text(tag),
                              selected: _selectedTags.contains(tag),
                              onSelected: (value) => setState(() {
                                if (value) {
                                  _selectedTags.add(tag);
                                } else {
                                  _selectedTags.remove(tag);
                                }
                              }),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    final theme = Theme.of(context);

    if (_mediaFile == null || _mediaType == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.add_a_photo_outlined,
                    size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Showcase your story',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Select a photo or video to start editing. You can add text, choose fonts, and layer colors just like TikTok or Instagram reels.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose photo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Choose video'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final aspectRatio = _mediaAspectRatio ??
        (_mediaType == FeedMediaType.video
            ? (_videoController?.value.aspectRatio ?? _defaultVideoAspectRatio)
            : _defaultVideoAspectRatio);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio:
                aspectRatio <= 0 ? _defaultVideoAspectRatio : aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: GestureDetector(
                onTap: () => _openMediaEditor(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned.fill(child: _buildMediaPreview()),
                    Positioned(
                      right: 12,
                      top: 12,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          tooltip: 'Edit media (pan/zoom)',
                          onPressed: () => _openMediaEditor(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_mediaType == FeedMediaType.video)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isGeneratingCover ? null : _openCoverEditor,
                    icon: _isGeneratingCover
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.photo_album_outlined),
                    label: Text(
                      _generatedCoverPath != null || _customCoverFile != null
                          ? 'Update cover photo'
                          : 'Edit cover photo',
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (_mediaType == FeedMediaType.video) {
      final controller = _videoController;
      if (controller == null) {
        return const ColoredBox(color: Colors.black12);
      }
      return FutureBuilder<void>(
        future: _videoInitialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!controller.value.isInitialized) {
            return const ColoredBox(color: Colors.black12);
          }
          if (!controller.value.isPlaying) {
            controller
              ..setLooping(true)
              ..setVolume(0)
              ..play();
          }
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          );
        },
      );
    }

    return Image.file(
      File(_mediaFile!.path),
      fit: BoxFit.cover,
    );
  }

  Widget _buildDescriptionSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Description',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descriptionController,
            focusNode: _descriptionFocusNode,
            maxLines: 5,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText:
                  'Share context, calls to action, or a quote. Hashtags are optional; tags below help voters find it.',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxHeight: 2160,
        maxWidth: 2160,
      );
      if (file == null) return;
      await _setMedia(file, FeedMediaType.image);
    } on PlatformException catch (error) {
      _showError('We could not access your gallery (${error.message}).');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      if (file == null) return;
      await _setMedia(file, FeedMediaType.video);
    } on PlatformException catch (error) {
      _showError('We could not access your gallery (${error.message}).');
    }
  }

  Future<void> _setMedia(XFile file, FeedMediaType type) async {
    _disposeVideoController();
    setState(() {
      _mediaFile = file;
      _mediaType = type;
      _generatedCoverPath = null;
      _customCoverFile = null;
      _coverFramePosition = null;
      // overlays removed
      _mediaAspectRatio = null;
    });

    if (type == FeedMediaType.image) {
      final fileBytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(fileBytes);
      setState(() {
        _mediaAspectRatio = decoded.width == 0
            ? _defaultVideoAspectRatio
            : decoded.width / decoded.height;
      });
    } else {
      final controller = VideoPlayerController.file(File(file.path));
      setState(() {
        _videoController = controller;
        _videoInitialization = controller.initialize().then((_) {
          setState(() {
            _mediaAspectRatio = controller.value.aspectRatio;
          });
          controller
            ..setLooping(true)
            ..setVolume(0)
            ..play();
        });
      });
      debugPrint('CreatePostScreen: created VideoPlayerController for ${file.path}');
    }

    // After setting the media, open the full-screen editor so the user can pan/zoom/recenter
    if (!mounted) return;
    // If video, ensure initialized first so playback is ready in the editor
    if (type == FeedMediaType.video) {
      if (_videoInitialization != null) {
        await _videoInitialization;
      }
    }
    await _openMediaEditor();
  }

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
    _videoInitialization = null;
  }

  // overlay positioning removed

  // Full-screen media editor: pan/zoom/recenter with guide lines
  Future<void> _openMediaEditor() async {
    if (_mediaFile == null || _mediaType == null) return;

    final request = await Navigator.of(context).push<CreatePostRequest>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => PublishPostScreen(
          mediaPath: _mediaFile!.path,
          mediaType: _mediaType!,
          aspectRatio: _mediaAspectRatio ?? _defaultVideoAspectRatio,
        ),
      ),
    );

    if (request == null) return;

    // When publish screen returns a CreatePostRequest, submit it using current user
    final authState = ref.read(authControllerProvider);
    final user = authState.user;
    if (user == null) {
      _showError('Sign in to share a story.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final newContentId = await ref
          .read(createContentServiceProvider)
          .createPost(request, author: user);
      if (!mounted) return;
      Navigator.of(context).pop(newContentId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post published to the feed.')),
      );
    } catch (error) {
      _showError('We could not publish your post. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openCoverEditor() async {
    if (_mediaType != FeedMediaType.video || _videoController == null) {
      return;
    }

    final controller = _videoController!;
    await controller.pause();

    if (!mounted) return;
    final result = await showModalBottomSheet<CoverEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => CoverEditorSheet(
        controller: controller,
        initialFrame: _coverFramePosition,
        initialCustomCoverPath: _customCoverFile?.path,
      ),
    );

    if (result == null) {
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (result.clear) {
      setState(() {
        _generatedCoverPath = null;
        _customCoverFile = null;
        _coverFramePosition = null;
      });
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (result.customCoverPath != null) {
      setState(() {
        _generatedCoverPath = null;
        _customCoverFile = XFile(result.customCoverPath!);
        _coverFramePosition = null;
      });
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (result.framePosition != null) {
      setState(() {
        _coverFramePosition = result.framePosition;
        _isGeneratingCover = true;
      });
      try {
        final generated =
            await ref.read(createContentServiceProvider).generateCoverFromVideo(
                  videoPath: _mediaFile!.path,
                  position: result.framePosition!,
                );
        if (!mounted) return;
        setState(() {
          _generatedCoverPath = generated;
          _customCoverFile = null;
        });
      } catch (error) {
        _showError('We could not save that frame as a cover. $error');
      } finally {
        if (mounted) {
          setState(() => _isGeneratingCover = false);
        }
      }
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (!mounted) return;
    await controller.play();
  }

  Future<void> _handleSubmit(AppUser user) async {
    if (_mediaFile == null || _mediaType == null) {
      _showError('Choose a photo or video first.');
      return;
    }

    final description = _descriptionController.text.trim();

    // overlays removed - send empty list
    final overlays = <FeedTextOverlay>[];

    final request = CreatePostRequest(
      mediaPath: _mediaFile!.path,
      mediaType: _mediaType!,
      description: description,
      tags: _selectedTags.toList(),
      aspectRatio: _mediaAspectRatio ?? _defaultVideoAspectRatio,
      coverImagePath: _customCoverFile?.path ?? _generatedCoverPath,
      coverFramePosition: _coverFramePosition,
      overlays: overlays,
    );

    setState(() => _isSubmitting = true);

    try {
      final newContentId = await ref
          .read(createContentServiceProvider)
          .createPost(request, author: user);

      if (!mounted) return;
      Navigator.of(context).pop(newContentId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post published to the feed.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to create post: $error\n$stackTrace');
      if (!mounted) return;
      _showError('We could not publish your post. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
