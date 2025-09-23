import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../feed/domain/feed_content.dart';
import 'widgets/media_composer_support.dart';

class MediaCompositionResult {
  const MediaCompositionResult({
    required this.transformValues,
    required this.overlays,
    required this.aspectRatio,
  });

  final List<double> transformValues;
  final List<EditableOverlay> overlays;
  final double aspectRatio;
}

class MediaComposerScreen extends StatefulWidget {
  const MediaComposerScreen({
    required this.mediaPath,
    required this.mediaType,
    required this.initialAspectRatio,
    this.initialTransformValues,
    this.initialOverlays = const <EditableOverlay>[],
    super.key,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final double initialAspectRatio;
  final List<double>? initialTransformValues;
  final List<EditableOverlay> initialOverlays;

  @override
  State<MediaComposerScreen> createState() => _MediaComposerScreenState();
}

class _MediaComposerScreenState extends State<MediaComposerScreen> {
  static const _uuid = Uuid();
  static const _boundaryMargin = EdgeInsets.all(240);

  final TransformationController _transformationController =
      TransformationController();

  final List<EditableOverlay> _overlays = <EditableOverlay>[];

  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;

  bool _showGuides = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialTransformValues != null) {
      _transformationController.value =
          Matrix4.fromList(widget.initialTransformValues!);
    }
    _overlays.addAll(widget.initialOverlays);
    if (widget.mediaType == FeedMediaType.video) {
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _transformationController.dispose();
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
    final aspectRatio =
        widget.initialAspectRatio <= 0 ? (9 / 16) : widget.initialAspectRatio;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'Edit post',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: _onNextPressed,
            child: const Text(
              'Next',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: GestureDetector(
                            onTap: () => setState(() => _showGuides = !_showGuides),
                            child: RepaintBoundary(
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  InteractiveViewer(
                                    transformationController:
                                        _transformationController,
                                    boundaryMargin: _boundaryMargin,
                                    minScale: 0.8,
                                    maxScale: 4.5,
                                    onInteractionStart: (_) =>
                                        setState(() => _showGuides = true),
                                    onInteractionEnd: (_) =>
                                        setState(() => _showGuides = false),
                                    child: _buildMediaContent(),
                                  ),
                                  if (_showGuides)
                                    const Positioned.fill(
                                      child: IgnorePointer(
                                        child: _GuideOverlay(),
                                      ),
                                    ),
                                  Positioned.fill(
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return OverlayLayer(
                                          overlays: _overlays,
                                          onOverlayDragged: (id, delta) =>
                                              _updateOverlayPosition(
                                            id,
                                            delta,
                                            constraints.biggest,
                                          ),
                                          onOverlayTapped: _openOverlayEditor,
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          right: 16,
                          top: 16,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: IconButton(
                              onPressed: _resetTransform,
                              icon: const Icon(
                                Icons.center_focus_strong,
                                color: Colors.white,
                              ),
                              tooltip: 'Recenter',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _buildToolbar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaContent() {
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
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
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

  Widget _buildToolbar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _ComposerToolButton(
                  icon: Icons.text_fields,
                  label: 'Text',
                  onPressed: () => _openOverlayEditor(),
                ),
                _ComposerToolButton(
                  icon: Icons.brush_outlined,
                  label: 'Style',
                  onPressed: _overlays.isEmpty
                      ? null
                      : () => _openOverlayEditor(existing: _overlays.last),
                ),
                _ComposerToolButton(
                  icon: Icons.delete_sweep_outlined,
                  label: 'Clear',
                  onPressed:
                      _overlays.isEmpty ? null : () => _confirmClearOverlays(),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Pinch to zoom, drag to reframe, and tap overlays to edit fonts and colors.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmClearOverlays() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove all overlays?'),
          content: const Text(
            'This will delete every text overlay you added to the post.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (shouldClear == true) {
      setState(_overlays.clear);
    }
  }

  void _resetTransform() {
    setState(() {
      _showGuides = false;
      _transformationController.value = Matrix4.identity();
    });
  }

  void _updateOverlayPosition(String id, Offset delta, Size canvasSize) {
    final index = _overlays.indexWhere((element) => element.id == id);
    if (index == -1 || canvasSize.width == 0 || canvasSize.height == 0) {
      return;
    }

    final overlay = _overlays[index];
    final dx = delta.dx / canvasSize.width;
    final dy = delta.dy / canvasSize.height;

    final updated = overlay.copyWith(
      position: Offset(
        (overlay.position.dx + dx).clamp(0.0, 1.0),
        (overlay.position.dy + dy).clamp(0.0, 1.0),
      ),
    );

    setState(() => _overlays[index] = updated);
  }

  Future<void> _openOverlayEditor({EditableOverlay? existing}) async {
    final initial = existing ??
        EditableOverlay(
          id: _uuid.v4(),
          text: 'Add a headline',
          color: Colors.white,
          fontFamily: overlayFontOptions.first.fontFamily,
          fontLabel: overlayFontOptions.first.label,
          fontWeight: overlayFontOptions.first.fontWeight,
          fontStyle: overlayFontOptions.first.fontStyle,
          fontSize: 26,
          position: const Offset(0.32, 0.28),
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

    if (result == null) return;

    if (result.delete && existing != null) {
      setState(() => _overlays.removeWhere((o) => o.id == existing.id));
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

  void _onNextPressed() {
    final matrix =
        List<double>.unmodifiable(_transformationController.value.storage);
    Navigator.of(context).pop(
      MediaCompositionResult(
        transformValues: matrix,
        overlays: List<EditableOverlay>.unmodifiable(_overlays),
        aspectRatio: widget.initialAspectRatio,
      ),
    );
  }
}

class _ComposerToolButton extends StatelessWidget {
  const _ComposerToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: enabled
                  ? Colors.white.withValues(alpha: 0.12)
                  : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _GuideOverlay extends StatelessWidget {
  const _GuideOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _GuideOverlayPainter(),
    );
  }
}

class _GuideOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final primary = Paint()
      ..color = Colors.white.withOpacity(0.6)
      ..strokeWidth = 1;

    final secondary = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1;

    final midX = size.width / 2;
    final midY = size.height / 2;
    canvas.drawLine(Offset(midX, 0), Offset(midX, size.height), primary);
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), primary);

    final thirdX = size.width / 3;
    final thirdY = size.height / 3;
    canvas.drawLine(Offset(thirdX, 0), Offset(thirdX, size.height), secondary);
    canvas.drawLine(
        Offset(2 * thirdX, 0), Offset(2 * thirdX, size.height), secondary);
    canvas.drawLine(Offset(0, thirdY), Offset(size.width, thirdY), secondary);
    canvas.drawLine(
        Offset(0, 2 * thirdY), Offset(size.width, 2 * thirdY), secondary);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
