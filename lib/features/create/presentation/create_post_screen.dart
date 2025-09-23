import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../feed/domain/feed_content.dart';
import '../data/create_content_service.dart';
import '../domain/create_post_request.dart';
import 'widgets/media_composer_support.dart';

class CreatePostScreen extends ConsumerStatefulWidget {
  const CreatePostScreen({super.key});

  static const routeName = 'create-post';

  @override
  ConsumerState<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends ConsumerState<CreatePostScreen> {
  static const _uuid = Uuid();
  static const _defaultVideoAspectRatio = 9 / 16;

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocusNode = FocusNode();

  XFile? _mediaFile;
  FeedMediaType? _mediaType;
  double? _mediaAspectRatio;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;

  final List<EditableOverlay> _overlays = <EditableOverlay>[];
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
            SliverToBoxAdapter(child: _buildOverlaySection(context)),
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(child: _buildMediaPreview()),
                      if (_overlays.isNotEmpty)
                        Positioned.fill(
                          child: OverlayLayer(
                            overlays: _overlays,
                            onOverlayDragged: (id, delta) {
                              _updateOverlayPosition(
                                  id, delta, constraints.biggest);
                            },
                            onOverlayTapped: (overlay) {
                              _openOverlayEditor(existing: overlay);
                            },
                          ),
                        ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.photo_camera_back_outlined,
                                color: Colors.white),
                            tooltip: 'Change media',
                            onPressed: () => _showMediaSwapSheet(context),
                          ),
                        ),
                      ),
                    ],
                  );
                },
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

  Widget _buildOverlaySection(BuildContext context) {
    if (_mediaFile == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Text overlays',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Text(
            'Layer campaign headlines, calls to action, or quick stats. Drag to reposition and tap to edit fonts and colors.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _openOverlayEditor(),
                icon: const Icon(Icons.text_fields_outlined),
                label: const Text('Add text'),
              ),
              if (_overlays.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _overlays.clear());
                  },
                  icon: const Icon(Icons.layers_clear),
                  label: const Text('Clear overlays'),
                ),
            ],
          ),
          if (_overlays.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final overlay in _overlays)
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                child: ListTile(
                  title: Text(
                    overlay.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: overlay.fontFamily,
                      fontWeight: overlay.fontWeight,
                      fontStyle: overlay.fontStyle,
                      fontSize: overlay.fontSize,
                      color: overlay.color,
                    ),
                  ),
                  subtitle: Text(
                    'Font: ${overlay.displayFontLabel} · Color: #${overlay.color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: IconButton(
                    tooltip: 'Edit overlay',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _openOverlayEditor(existing: overlay),
                  ),
                ),
              ),
          ],
        ],
      ),
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
      _overlays.clear();
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
    }
  }

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
    _videoInitialization = null;
  }

  Future<void> _showMediaSwapSheet(BuildContext context) async {
    final action = await showModalBottomSheet<MediaSwapAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Replace with photo'),
              onTap: () => Navigator.of(ctx).pop(MediaSwapAction.photo),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Replace with video'),
              onTap: () => Navigator.of(ctx).pop(MediaSwapAction.video),
            ),
            if (_mediaFile != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove media'),
                onTap: () => Navigator.of(ctx).pop(MediaSwapAction.remove),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    switch (action) {
      case MediaSwapAction.photo:
        await _pickImage();
        break;
      case MediaSwapAction.video:
        await _pickVideo();
        break;
      case MediaSwapAction.remove:
        setState(() {
          _mediaFile = null;
          _mediaType = null;
          _overlays.clear();
          _generatedCoverPath = null;
          _customCoverFile = null;
          _coverFramePosition = null;
        });
        _disposeVideoController();
        break;
      case null:
        break;
    }
  }

  void _updateOverlayPosition(
    String id,
    Offset delta,
    Size canvasSize,
  ) {
    final overlayIndex = _overlays.indexWhere((element) => element.id == id);
    if (overlayIndex == -1) {
      return;
    }
    final overlay = _overlays[overlayIndex];
    if (canvasSize.width == 0 || canvasSize.height == 0) {
      return;
    }

    final dx = delta.dx / canvasSize.width;
    final dy = delta.dy / canvasSize.height;

    final next = overlay.copyWith(
      position: Offset(
        (overlay.position.dx + dx).clamp(0.0, 1.0),
        (overlay.position.dy + dy).clamp(0.0, 1.0),
      ),
    );

    setState(() => _overlays[overlayIndex] = next);
  }

  Future<void> _openOverlayEditor({EditableOverlay? existing}) async {
    final initial = existing ??
        EditableOverlay(
          id: _uuid.v4(),
          text: 'Campaign message',
          color: Colors.white,
          fontFamily: overlayFontOptions.first.fontFamily,
          fontLabel: overlayFontOptions.first.label,
          fontWeight: overlayFontOptions.first.fontWeight,
          fontStyle: overlayFontOptions.first.fontStyle,
          fontSize: 24,
          position: const Offset(0.4, 0.35),
        );

    final result = await showModalBottomSheet<OverlayEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => OverlayEditorSheet(
        initial: initial,
        allowDelete: existing != null,
      ),
    );

    if (result == null) {
      return;
    }

    if (result.delete && existing != null) {
      setState(
          () => _overlays.removeWhere((element) => element.id == existing.id));
      return;
    }

    final overlay = result.overlay;
    if (overlay == null) return;

    setState(() {
      final index = _overlays.indexWhere((element) => element.id == overlay.id);
      if (index == -1) {
        _overlays.add(overlay);
      } else {
        _overlays[index] = overlay;
      }
    });
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

    final overlays = [
      for (final overlay in _overlays)
        FeedTextOverlay(
          id: overlay.id,
          text: overlay.text,
          color: overlay.color,
          fontFamily: overlay.fontFamily,
          fontWeight: overlay.fontWeight,
          fontStyle: overlay.fontStyle,
          fontSize: overlay.fontSize,
          position: overlay.position,
        ),
    ];

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
