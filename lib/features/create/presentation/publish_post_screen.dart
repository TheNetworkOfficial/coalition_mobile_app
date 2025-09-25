import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../candidates/data/candidate_providers.dart';
import '../presentation/widgets/static_transform_view.dart';

import '../domain/create_post_request.dart';
import '../../feed/domain/feed_content.dart';
import 'widgets/media_composer_support.dart';

class EditedMediaResult {
  const EditedMediaResult();
}

class _FullscreenMediaEditor extends StatefulWidget {
  const _FullscreenMediaEditor({
    required this.mediaPath,
    required this.mediaType,
    required this.aspectRatio,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final double aspectRatio;
  // no controller required here

  @override
  State<_FullscreenMediaEditor> createState() => _FullscreenMediaEditorState();
}

class _FullscreenMediaEditorState extends State<_FullscreenMediaEditor> {
  final TransformationController _transformationController =
      TransformationController();
  bool _showGuides = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _toggleGuides(bool show) {
    setState(() => _showGuides = show);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit media'),
        actions: [
          IconButton(
            tooltip: 'Next',
            icon: const Icon(Icons.arrow_forward),
            onPressed: () async {
              // go to publish screen
              final localContext = context;
              final result =
                  await Navigator.of(localContext).push<CreatePostRequest>(
                MaterialPageRoute(
                  builder: (ctx) => PublishPostScreen(
                      mediaPath: widget.mediaPath,
                      mediaType: widget.mediaType,
                      aspectRatio: widget.aspectRatio),
                ),
              );
              if (result != null) {
                // return the CreatePostRequest to the original caller
                if (!localContext.mounted) return;
                Navigator.of(localContext).pop(const EditedMediaResult());
                // but posting itself is handled by CreatePostScreen after receiving the request
              }
            },
          ),
        ],
      ),
      body: Center(
        child: LayoutBuilder(builder: (context, constraints) {
          return GestureDetector(
            onPanDown: (_) => _toggleGuides(true),
            onPanEnd: (_) => _toggleGuides(false),
            child: Stack(
              fit: StackFit.expand,
              children: [
                InteractiveViewer(
                  transformationController: _transformationController,
                  clipBehavior: Clip.none,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: AspectRatio(
                    aspectRatio:
                        widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                    child: ClipRect(
                      child:
                          Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                    ),
                  ),
                ),
                // Guide lines
                if (_showGuides) ...[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GuideLinesPainter(),
                      ),
                    ),
                  ),
                ],
                // center indicator
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FloatingActionButton.small(
                    onPressed: () {
                      // recenter
                      _transformationController.value = Matrix4.identity();
                    },
                    child: const Icon(Icons.center_focus_strong),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _GuideLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 1.0;

    // vertical center
    final vx = size.width / 2;
    canvas.drawLine(Offset(vx, 0), Offset(vx, size.height), paint);
    // horizontal center
    final hy = size.height / 2;
    canvas.drawLine(Offset(0, hy), Offset(size.width, hy), paint);
    // mid vertical thirds
    final v1 = size.width / 3;
    final v2 = 2 * size.width / 3;
    final h1 = size.height / 3;
    final h2 = 2 * size.height / 3;
    canvas.drawLine(Offset(v1, 0), Offset(v1, size.height),
        paint..color = Colors.white.withValues(alpha: 0.35));
    canvas.drawLine(Offset(v2, 0), Offset(v2, size.height),
        paint..color = Colors.white.withValues(alpha: 0.35));
    canvas.drawLine(Offset(0, h1), Offset(size.width, h1),
        paint..color = Colors.white.withValues(alpha: 0.35));
    canvas.drawLine(Offset(0, h2), Offset(size.width, h2),
        paint..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PublishPostScreen extends ConsumerStatefulWidget {
  const PublishPostScreen({
    required this.mediaPath,
    required this.mediaType,
    required this.aspectRatio,
    this.composition,
    this.initialOverlays,
    this.overrideMediaPath,
    this.previewImagePath,
    super.key,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final double aspectRatio;
  final List<double>? composition;
  final List<EditableOverlay>? initialOverlays;
  final String? overrideMediaPath;
  final String? previewImagePath;
  // controller removed - playback not required on publish screen

  @override
  ConsumerState<PublishPostScreen> createState() => _PublishPostScreenState();
}

class _PublishPostScreenState extends ConsumerState<PublishPostScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final Set<String> _selectedTags = {};
  final bool _isPosting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // We avoid doing heavy integration here; parent will perform the actual post

    return Scaffold(
      appBar: AppBar(title: const Text('Publish')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // If an override (baked) media path is provided the image
                      // already includes overlays baked into it. In that case we
                      // should not draw the editable overlay layer on top again
                      // (this caused the duplicated text). Otherwise render the
                      // transform + overlay preview as before.
                      Builder(builder: (context) {
                        final previewPath = widget.previewImagePath ??
                            widget.overrideMediaPath ??
                            widget.mediaPath;
                        if (widget.mediaType == FeedMediaType.video &&
                            widget.previewImagePath == null) {
                          return const ColoredBox(
                            color: Colors.black54,
                            child: Center(
                              child: Icon(
                                Icons.videocam,
                                color: Colors.white54,
                                size: 48,
                              ),
                            ),
                          );
                        }
                        return Image.file(
                          File(previewPath),
                          fit: BoxFit.cover,
                        );
                      }),
                      if (widget.overrideMediaPath == null &&
                          (widget.composition != null ||
                              (widget.initialOverlays?.isNotEmpty ?? false)))
                        StaticTransformView(
                          transformValues: widget.composition,
                          child: Container(
                            color: Colors.transparent,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // transparent child so the StaticTransformView applies
                                const SizedBox.shrink(),
                                OverlayLayer(
                                  overlays: widget.initialOverlays ?? const [],
                                  onOverlayDragged: (_, __) {},
                                  onOverlayTapped: (_) {},
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 5,
                decoration:
                    const InputDecoration(hintText: 'Write a description...'),
              ),
              const SizedBox(height: 12),
              Consumer(builder: (context, ref, _) {
                final tagsAsync = ref.watch(candidateTagsProvider);
                final candidateTags = tagsAsync.maybeWhen(
                  data: (value) => value,
                  orElse: () => const <String>[],
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tags',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (candidateTags.isEmpty)
                      Text('No tags available',
                          style: Theme.of(context).textTheme.bodySmall)
                    else
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final tag in candidateTags)
                            FilterChip(
                              label: Text(tag),
                              selected: _selectedTags.contains(tag),
                              onSelected: _selectedTags.length >= 3 &&
                                      !_selectedTags.contains(tag)
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedTags.add(tag);
                                        } else {
                                          _selectedTags.remove(tag);
                                        }
                                      });
                                    },
                              disabledColor: Colors.white10,
                            ),
                        ],
                      ),
                    const SizedBox(height: 8),
                    Text('You may select up to 3 tags',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                );
              }),
              const SizedBox(height: 96),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isPosting
                ? null
                : () {
                    final request = CreatePostRequest(
                      mediaPath: widget.overrideMediaPath ?? widget.mediaPath,
                      mediaType: widget.mediaType,
                      description: _descriptionController.text.trim(),
                      tags: _selectedTags.toList(),
                      aspectRatio: widget.aspectRatio,
                      coverImagePath: widget.previewImagePath,
                      coverFramePosition: null,
                      overlays: (widget.initialOverlays
                              ?.map((e) => FeedTextOverlay(
                                    id: e.id,
                                    text: e.text,
                                    color: e.color,
                                    position: e.position,
                                    fontFamily: e.fontFamily,
                                    fontWeight: e.fontWeight,
                                    fontStyle: e.fontStyle,
                                    fontSize: e.fontSize,
                                    backgroundColor: e.backgroundColor,
                                  ))
                              .toList()) ??
                          const [],
                      compositionTransform: widget.composition,
                    );
                    Navigator.of(context).pop(request);
                  },
            child: _isPosting
                ? const CircularProgressIndicator()
                : const Text('Post'),
          ),
        ),
      ),
    );
  }

  // PublishPostScreen only collects the CreatePostRequest and returns it to the caller.
}
