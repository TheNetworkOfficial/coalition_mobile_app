import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/create_post_request.dart';
import '../../feed/domain/feed_content.dart';

// Single-source, clean implementation for the fullscreen editor + publish flow.

class EditedMediaResult {
  const EditedMediaResult();
}

class FullscreenMediaEditor extends StatefulWidget {
  const FullscreenMediaEditor({
    required this.mediaPath,
    required this.mediaType,
    required this.aspectRatio,
    super.key,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final double aspectRatio;

  @override
  State<FullscreenMediaEditor> createState() => _FullscreenMediaEditorState();
}

class _FullscreenMediaEditorState extends State<FullscreenMediaEditor> {
  final TransformationController _transformationController = TransformationController();
  bool _showGuides = false;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _toggleGuides(bool show) => setState(() => _showGuides = show);

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
              final localCtx = context;
              final request = await Navigator.of(localCtx).push<CreatePostRequest>(
                MaterialPageRoute(
                  fullscreenDialog: true,
                  builder: (_) => PublishPostScreen(
                    mediaPath: widget.mediaPath,
                    mediaType: widget.mediaType,
                    aspectRatio: widget.aspectRatio,
                  ),
                ),
              );

              if (request != null) {
                if (!localCtx.mounted) return;
                Navigator.of(localCtx).pop(const EditedMediaResult());
              }
            },
          )
        ],
      ),
      body: GestureDetector(
        onPanDown: (_) => _toggleGuides(true),
        onPanEnd: (_) => _toggleGuides(false),
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              transformationController: _transformationController,
              minScale: 0.5,
              maxScale: 4.0,
              child: AspectRatio(
                aspectRatio: widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                child: ClipRect(
                  child: Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                ),
              ),
            ),
            if (_showGuides)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _GuideLinesPainter()),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 12,
              child: FloatingActionButton.small(
                onPressed: () => _transformationController.value = Matrix4.identity(),
                child: const Icon(Icons.center_focus_strong),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideLinesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 1;

    final vx = size.width / 2;
    canvas.drawLine(Offset(vx, 0), Offset(vx, size.height), paint);

    final hy = size.height / 2;
    canvas.drawLine(Offset(0, hy), Offset(size.width, hy), paint);

    final v1 = size.width / 3;
    final v2 = 2 * size.width / 3;
    final h1 = size.height / 3;
    final h2 = 2 * size.height / 3;

    final paint2 = paint..color = Colors.white.withOpacity(0.35);
    canvas.drawLine(Offset(v1, 0), Offset(v1, size.height), paint2);
    canvas.drawLine(Offset(v2, 0), Offset(v2, size.height), paint2);
    canvas.drawLine(Offset(0, h1), Offset(size.width, h1), paint2);
    canvas.drawLine(Offset(0, h2), Offset(size.width, h2), paint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PublishPostScreen extends ConsumerStatefulWidget {
  const PublishPostScreen({
    required this.mediaPath,
    required this.mediaType,
    required this.aspectRatio,
    super.key,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final double aspectRatio;

  @override
  ConsumerState<PublishPostScreen> createState() => _PublishPostScreenState();
}

class _PublishPostScreenState extends ConsumerState<PublishPostScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final Set<String> _selectedTags = {};
  bool _isPosting = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Publish')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: AspectRatio(
                  aspectRatio: widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _descriptionController,
                      maxLines: 5,
                      decoration: const InputDecoration(hintText: 'Write a description...'),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, children: const [Chip(label: Text('Tag1'))]),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isPosting
                            ? null
                            : () {
                                final request = CreatePostRequest(
                                  mediaPath: widget.mediaPath,
                                  mediaType: widget.mediaType,
                                  description: _descriptionController.text.trim(),
                                  tags: _selectedTags.toList(),
                                  aspectRatio: widget.aspectRatio,
                                  coverImagePath: null,
                                  coverFramePosition: null,
                                  overlays: const [],
                                );
                                Navigator.of(context).pop(request);
                              },
                        child: _isPosting ? const CircularProgressIndicator() : const Text('Post'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/create_post_request.dart';
import '../../feed/domain/feed_content.dart';

class EditedMediaResult {
  const EditedMediaResult();
}

class _FullscreenMediaEditor extends StatefulWidget {
  const _FullscreenMediaEditor({
    required this.mediaPath,
    required this.mediaType,
    required this.aspectRatio,
  });

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: AspectRatio(
                    aspectRatio: widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                    child: ClipRRect(
                      import 'dart:io';

                      import 'package:flutter/material.dart';
                      import 'package:flutter_riverpod/flutter_riverpod.dart';

                      import '../domain/create_post_request.dart';
                      import '../../feed/domain/feed_content.dart';

                      class EditedMediaResult {
                        const EditedMediaResult();
                      }

                      class FullscreenMediaEditor extends StatefulWidget {
                        const FullscreenMediaEditor({
                          required this.mediaPath,
                          required this.mediaType,
                          required this.aspectRatio,
                          super.key,
                        });

                        final String mediaPath;
                        final FeedMediaType mediaType;
                        final double aspectRatio;

                        @override
                        State<FullscreenMediaEditor> createState() => _FullscreenMediaEditorState();
                      }

                      class _FullscreenMediaEditorState extends State<FullscreenMediaEditor> {
                        final TransformationController _transformationController = TransformationController();
                        bool _showGuides = false;

                        @override
                        void dispose() {
                          _transformationController.dispose();
                          super.dispose();
                        }

                        void _toggleGuides(bool show) => setState(() => _showGuides = show);

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
                                    final localCtx = context;
                                    final request = await Navigator.of(localCtx).push<CreatePostRequest>(
                                      MaterialPageRoute(
                                        fullscreenDialog: true,
                                        builder: (_) => PublishPostScreen(
                                          mediaPath: widget.mediaPath,
                                          mediaType: widget.mediaType,
                                          aspectRatio: widget.aspectRatio,
                                        ),
                                      ),
                                    );

                                    if (request != null) {
                                      if (!localCtx.mounted) return;
                                      Navigator.of(localCtx).pop(const EditedMediaResult());
                                    }
                                  },
                                )
                              ],
                            ),
                            body: GestureDetector(
                              onPanDown: (_) => _toggleGuides(true),
                              onPanEnd: (_) => _toggleGuides(false),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  InteractiveViewer(
                                    transformationController: _transformationController,
                                    minScale: 0.5,
                                    maxScale: 4.0,
                                    child: AspectRatio(
                                      aspectRatio: widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                                      child: ClipRect(
                                        child: Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                                      ),
                                    ),
                                  ),
                                  if (_showGuides)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        child: CustomPaint(painter: _GuideLinesPainter()),
                                      ),
                                    ),
                                  Positioned(
                                    right: 12,
                                    bottom: 12,
                                    child: FloatingActionButton.small(
                                      onPressed: () => _transformationController.value = Matrix4.identity(),
                                      child: const Icon(Icons.center_focus_strong),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                      }

                      class _GuideLinesPainter extends CustomPainter {
                        @override
                        void paint(Canvas canvas, Size size) {
                          final paint = Paint()
                            ..color = Colors.white.withOpacity(0.7)
                            ..strokeWidth = 1;

                          final vx = size.width / 2;
                          canvas.drawLine(Offset(vx, 0), Offset(vx, size.height), paint);

                          final hy = size.height / 2;
                          canvas.drawLine(Offset(0, hy), Offset(size.width, hy), paint);

                          final v1 = size.width / 3;
                          final v2 = 2 * size.width / 3;
                          final h1 = size.height / 3;
                          final h2 = 2 * size.height / 3;

                          final paint2 = paint..color = Colors.white.withOpacity(0.35);
                          canvas.drawLine(Offset(v1, 0), Offset(v1, size.height), paint2);
                          canvas.drawLine(Offset(v2, 0), Offset(v2, size.height), paint2);
                          canvas.drawLine(Offset(0, h1), Offset(size.width, h1), paint2);
                          canvas.drawLine(Offset(0, h2), Offset(size.width, h2), paint2);
                        }

                        @override
                        bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
                      }

                      class PublishPostScreen extends ConsumerStatefulWidget {
                        const PublishPostScreen({
                          required this.mediaPath,
                          required this.mediaType,
                          required this.aspectRatio,
                          super.key,
                        });

                        final String mediaPath;
                        final FeedMediaType mediaType;
                        final double aspectRatio;

                        @override
                        ConsumerState<PublishPostScreen> createState() => _PublishPostScreenState();
                      }

                      class _PublishPostScreenState extends ConsumerState<PublishPostScreen> {
                        final TextEditingController _descriptionController = TextEditingController();
                        final Set<String> _selectedTags = {};
                        bool _isPosting = false;

                        @override
                        void dispose() {
                          _descriptionController.dispose();
                          super.dispose();
                        }

                        @override
                        Widget build(BuildContext context) {
                          return Scaffold(
                            appBar: AppBar(title: const Text('Publish')),
                            body: SafeArea(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: AspectRatio(
                                        aspectRatio: widget.aspectRatio <= 0 ? 1 : widget.aspectRatio,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(12),
                                          child: Image.file(File(widget.mediaPath), fit: BoxFit.cover),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          TextField(
                                            controller: _descriptionController,
                                            maxLines: 5,
                                            decoration: const InputDecoration(hintText: 'Write a description...'),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(spacing: 8, children: const [Chip(label: Text('Tag1'))]),
                                          const SizedBox(height: 12),
                                          SizedBox(
                                            width: double.infinity,
                                            child: ElevatedButton(
                                              onPressed: _isPosting
                                                  ? null
                                                  : () {
                                                      final request = CreatePostRequest(
                                                        mediaPath: widget.mediaPath,
                                                        mediaType: widget.mediaType,
                                                        description: _descriptionController.text.trim(),
                                                        tags: _selectedTags.toList(),
                                                        aspectRatio: widget.aspectRatio,
                                                        coverImagePath: null,
                                                        coverFramePosition: null,
                                                        overlays: const [],
                                                      );
                                                      Navigator.of(context).pop(request);
                                                    },
                                              child: _isPosting ? const CircularProgressIndicator() : const Text('Post'),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                      }
                                ),
