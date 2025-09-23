import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../auth/data/auth_controller.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../feed/domain/feed_content.dart';
import '../data/create_content_service.dart';
import '../domain/create_post_request.dart';
import 'widgets/media_composer_support.dart';
import 'widgets/static_transform_view.dart';

class PublishPostScreen extends ConsumerStatefulWidget {
  const PublishPostScreen({
    required this.mediaPath,
    required this.mediaType,
    required this.aspectRatio,
    required this.composition,
    required this.initialOverlays,
    super.key,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final double aspectRatio;
  final List<double> composition;
  final List<EditableOverlay> initialOverlays;

  @override
  ConsumerState<PublishPostScreen> createState() => _PublishPostScreenState();
}

class _PublishPostScreenState extends ConsumerState<PublishPostScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final Set<String> _selectedTags = <String>{};

  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;

  String? _generatedCoverPath;
  XFile? _customCoverFile;
  Duration? _coverFramePosition;
  bool _isGeneratingCover = false;
  bool _isPosting = false;

  late List<EditableOverlay> _overlays;

  @override
  void initState() {
    super.initState();
    _overlays = List<EditableOverlay>.from(widget.initialOverlays);
    if (widget.mediaType == FeedMediaType.video) {
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _initializeVideo() {
    final controller = VideoPlayerController.file(File(widget.mediaPath))
      ..setLooping(true)
      ..setVolume(0);
    _videoInitialization = controller.initialize().then((_) {
      if (mounted) {
        setState(() {
          controller.play();
        });
      }
    });
    _videoController = controller;
  }

  @override
  Widget build(BuildContext context) {
    final candidateTagsAsync = ref.watch(candidateTagsProvider);
    final candidateTags = candidateTagsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <String>[],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post details'),
        actions: [
          TextButton(
            onPressed: _isPosting ? null : _handleSubmit,
            child: _isPosting
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
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: AspectRatio(
                aspectRatio: widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildPreview(),
                      if (_overlays.isNotEmpty)
                        Positioned.fill(
                          child: _PreviewOverlayLayer(overlays: _overlays),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.mediaType == FeedMediaType.video)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                    _customCoverFile != null || _generatedCoverPath != null
                        ? 'Update cover image'
                        : 'Edit cover image',
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _descriptionController,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Write a caption',
                      hintText: 'Share context, credits, or a call to action.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Campaign tags',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  if (candidateTagsAsync.isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else if (candidateTags.isEmpty)
                    Text(
                      'Tags help voters discover your story once your campaign team adds them.',
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
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    final transform = widget.composition;
    final aspectRatio = widget.aspectRatio <= 0 ? 1.0 : widget.aspectRatio;

    return StaticTransformView(
      transformValues: transform,
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: _buildMediaForPreview(),
      ),
    );
  }

  Widget _buildMediaForPreview() {
    switch (widget.mediaType) {
      case FeedMediaType.image:
        return Image.file(
          File(widget.mediaPath),
          fit: BoxFit.cover,
        );
      case FeedMediaType.video:
        final controller = _videoController;
        if (controller == null) {
          return const ColoredBox(color: Colors.black);
        }
        return FutureBuilder<void>(
          future: _videoInitialization,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const ColoredBox(
                color: Colors.black,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (!controller.value.isPlaying) {
              controller.play();
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
  }

  Future<void> _openCoverEditor() async {
    final controller = _videoController;
    if (controller == null) return;

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
        _customCoverFile = XFile(result.customCoverPath!);
        _generatedCoverPath = null;
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
        final generated = await ref
            .read(createContentServiceProvider)
            .generateCoverFromVideo(
              videoPath: widget.mediaPath,
              position: result.framePosition!,
            );
        if (!mounted) return;
        setState(() {
          _generatedCoverPath = generated;
          _customCoverFile = null;
        });
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('We could not save that frame as a cover.')),
        );
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

  Future<void> _handleSubmit() async {
    if (_isPosting) return;

    final authState = ref.read(authControllerProvider);
    final user = authState.user;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to publish your story.')),
      );
      return;
    }

    final description = _descriptionController.text.trim();
    final overlays = _overlays
        .map(
          (overlay) => FeedTextOverlay(
            id: overlay.id,
            text: overlay.text,
            color: overlay.color,
            backgroundColor: overlay.backgroundColor,
            fontFamily: overlay.fontFamily,
            fontWeight: overlay.fontWeight,
            fontStyle: overlay.fontStyle,
            fontSize: overlay.fontSize,
            position: overlay.position,
          ),
        )
        .toList();

    final request = CreatePostRequest(
      mediaPath: widget.mediaPath,
      mediaType: widget.mediaType,
      description: description,
      tags: _selectedTags.toList(),
      aspectRatio: widget.aspectRatio,
      coverImagePath: _customCoverFile?.path ?? _generatedCoverPath,
      coverFramePosition: _coverFramePosition,
      overlays: overlays,
      compositionTransform: List<double>.unmodifiable(widget.composition),
    );

    setState(() => _isPosting = true);

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
      debugPrint('Failed to publish post: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not publish your post. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPosting = false);
      }
    }
  }
}

class _PreviewOverlayLayer extends StatelessWidget {
  const _PreviewOverlayLayer({required this.overlays});

  final List<EditableOverlay> overlays;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (final overlay in overlays)
              Positioned(
                left: overlay.position.dx.clamp(0.0, 1.0) * constraints.maxWidth,
                top: overlay.position.dy.clamp(0.0, 1.0) * constraints.maxHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: overlay.backgroundColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      overlay.text,
                      style: TextStyle(
                        color: overlay.color,
                        fontFamily: overlay.fontFamily,
                        fontWeight: overlay.fontWeight,
                        fontStyle: overlay.fontStyle,
                        fontSize: overlay.fontSize,
                        height: 1.1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
