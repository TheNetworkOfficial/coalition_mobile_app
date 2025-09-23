import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

class EditableOverlay {
  const EditableOverlay({
    required this.id,
    required this.text,
    required this.color,
    required this.position,
    required this.fontFamily,
    required this.fontLabel,
    required this.fontWeight,
    required this.fontStyle,
    required this.fontSize,
    this.backgroundColor,
  });

  final String id;
  final String text;
  final Color color;
  final Offset position;
  final String? fontFamily;
  final String fontLabel;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final double fontSize;
  final Color? backgroundColor;

  EditableOverlay copyWith({
    String? text,
    Color? color,
    Offset? position,
    String? fontFamily,
    String? fontLabel,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? fontSize,
    Color? backgroundColor,
    bool changeBackground = false,
  }) {
    return EditableOverlay(
      id: id,
      text: text ?? this.text,
      color: color ?? this.color,
      position: position ?? this.position,
      fontFamily: fontFamily ?? this.fontFamily,
      fontLabel: fontLabel ?? this.fontLabel,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      fontSize: fontSize ?? this.fontSize,
      backgroundColor:
          changeBackground ? backgroundColor : this.backgroundColor,
    );
  }

  String get displayFontLabel => fontLabel;
}

class OverlayLayer extends StatelessWidget {
  const OverlayLayer({
    required this.overlays,
    required this.onOverlayDragged,
    required this.onOverlayTapped,
    super.key,
  });

  final List<EditableOverlay> overlays;
  final void Function(String id, Offset delta) onOverlayDragged;
  final void Function(EditableOverlay overlay) onOverlayTapped;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (final overlay in overlays)
              Positioned(
                left: overlay.position.dx * constraints.maxWidth,
                top: overlay.position.dy * constraints.maxHeight,
                child: GestureDetector(
                  onTap: () => onOverlayTapped(overlay),
                  onPanUpdate: (details) =>
                      onOverlayDragged(overlay.id, details.delta),
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
              ),
          ],
        );
      },
    );
  }
}

class OverlayEditorResult {
  const OverlayEditorResult({this.overlay, this.delete = false});

  final EditableOverlay? overlay;
  final bool delete;
}

class OverlayEditorSheet extends StatefulWidget {
  const OverlayEditorSheet({
    required this.initial,
    required this.allowDelete,
    this.overlayColors = _overlayColors,
    this.fontOptions = overlayFontOptions,
    super.key,
  });

  final EditableOverlay initial;
  final bool allowDelete;
  final List<Color> overlayColors;
  final List<OverlayFontOption> fontOptions;

  @override
  State<OverlayEditorSheet> createState() => _OverlayEditorSheetState();
}

class _OverlayEditorSheetState extends State<OverlayEditorSheet> {
  late TextEditingController _textController;
  late EditableOverlay _overlay;

  @override
  void initState() {
    super.initState();
    _overlay = widget.initial;
    _textController = TextEditingController(text: widget.initial.text);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _textController,
            maxLines: 3,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Overlay text',
            ),
            onChanged: (value) => setState(() => _overlay =
                _overlay.copyWith(text: value.trim().isEmpty ? ' ' : value)),
          ),
          const SizedBox(height: 18),
          Text('Font style', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final option in widget.fontOptions)
                ChoiceChip(
                  label: Text(option.label),
                  selected: _overlay.fontFamily == option.fontFamily &&
                      _overlay.fontWeight == option.fontWeight &&
                      _overlay.fontStyle == option.fontStyle,
                  onSelected: (_) =>
                      setState(() => _overlay = _overlay.copyWith(
                            fontFamily: option.fontFamily,
                            fontWeight: option.fontWeight,
                            fontStyle: option.fontStyle,
                            fontLabel: option.label,
                          )),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Color', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in widget.overlayColors)
                GestureDetector(
                  onTap: () => setState(
                      () => _overlay = _overlay.copyWith(color: color)),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: color,
                    child: _overlay.color == color
                        ? const Icon(Icons.check, color: Colors.black)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('Background', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            children: [
              FilterChip(
                selected: _overlay.backgroundColor != null,
                label: const Text('Add background pill'),
                onSelected: (selected) =>
                    setState(() => _overlay = _overlay.copyWith(
                          backgroundColor: selected
                              ? _overlay.color.withValues(alpha: 0.15)
                              : null,
                          changeBackground: true,
                        )),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Size', style: Theme.of(context).textTheme.titleSmall),
          Slider(
            min: 16.0,
            max: 48.0,
            value: _overlay.fontSize.toDouble(),
            label: _overlay.fontSize.toStringAsFixed(0),
            onChanged: (value) =>
                setState(() => _overlay = _overlay.copyWith(fontSize: value)),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (widget.allowDelete)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop(
                      const OverlayEditorResult(delete: true),
                    );
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () {
                  Navigator.of(context).pop(
                    OverlayEditorResult(overlay: _overlay),
                  );
                },
                child: const Text('Apply'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class OverlayFontOption {
  const OverlayFontOption({
    required this.label,
    required this.fontFamily,
    required this.fontWeight,
    this.fontStyle = FontStyle.normal,
  });

  final String label;
  final String? fontFamily;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
}

const overlayFontOptions = <OverlayFontOption>[
  OverlayFontOption(
      label: 'Classic', fontFamily: null, fontWeight: FontWeight.w600),
  OverlayFontOption(
      label: 'Bold', fontFamily: null, fontWeight: FontWeight.w800),
  OverlayFontOption(
    label: 'Serif',
    fontFamily: 'Georgia',
    fontWeight: FontWeight.w600,
  ),
  OverlayFontOption(
    label: 'Mono',
    fontFamily: 'Courier',
    fontWeight: FontWeight.w600,
  ),
  OverlayFontOption(
    label: 'Script',
    fontFamily: null,
    fontWeight: FontWeight.w500,
    fontStyle: FontStyle.italic,
  ),
];

const _overlayColors = <Color>[
  Colors.white,
  Colors.black,
  Color(0xFF0EA5E9),
  Color(0xFFF97316),
  Color(0xFF14B8A6),
  Color(0xFFE11D48),
  Color(0xFF8B5CF6),
  Color(0xFFEC4899),
  Color(0xFFFACC15),
];

class CoverEditorResult {
  const CoverEditorResult({
    this.framePosition,
    this.customCoverPath,
    this.clear = false,
  });

  final Duration? framePosition;
  final String? customCoverPath;
  final bool clear;
}

class CoverEditorSheet extends StatefulWidget {
  const CoverEditorSheet({
    required this.controller,
    this.initialFrame,
    this.initialCustomCoverPath,
    super.key,
  });

  final VideoPlayerController controller;
  final Duration? initialFrame;
  final String? initialCustomCoverPath;

  @override
  State<CoverEditorSheet> createState() => _CoverEditorSheetState();
}

class _CoverEditorSheetState extends State<CoverEditorSheet> {
  Duration _currentPosition = Duration.zero;
  bool _isUploading = false;
  String? _customCoverPath;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.initialFrame ?? Duration.zero;
    _customCoverPath = widget.initialCustomCoverPath;
    if (widget.initialFrame != null) {
      widget.controller.seekTo(widget.initialFrame!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final duration = controller.value.duration.inMilliseconds == 0
        ? const Duration(seconds: 1)
        : controller.value.duration;

    final sliderMax = duration.inMilliseconds.toDouble();

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 12,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Edit cover photo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: controller.value.aspectRatio == 0
                ? 1
                : controller.value.aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, child) {
                  return VideoPlayer(controller);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Slider(
            min: 0,
            max: sliderMax,
            value: _currentPosition.inMilliseconds
                .toDouble()
                .clamp(0.0, sliderMax),
            onChanged: (value) {
              final newPosition = Duration(milliseconds: value.round());
              setState(() => _currentPosition = newPosition);
              controller.seekTo(newPosition);
            },
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(Duration.zero)),
              Text(_formatDuration(duration)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).pop(
                    CoverEditorResult(framePosition: _currentPosition),
                  );
                },
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Use this frame'),
              ),
              OutlinedButton.icon(
                onPressed: _isUploading
                    ? null
                    : () async {
                        setState(() => _isUploading = true);
                        try {
                          final picker = ImagePicker();
                          final localContext = context;
                          final image = await picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 92,
                          );
                          if (image == null) return;
                          if (!mounted || !localContext.mounted) return;
                          setState(() => _customCoverPath = image.path);
                          Navigator.of(localContext).pop(
                            CoverEditorResult(customCoverPath: image.path),
                          );
                        } finally {
                          if (mounted) {
                            setState(() => _isUploading = false);
                          }
                        }
                      },
                icon: const Icon(Icons.image_outlined),
                label: const Text('Upload photo'),
              ),
              if (widget.initialFrame != null ||
                  widget.initialCustomCoverPath != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context)
                        .pop(const CoverEditorResult(clear: true));
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove cover'),
                ),
            ],
          ),
          if (_customCoverPath != null) ...[
            const SizedBox(height: 16),
            Text('Selected cover preview',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(_customCoverPath!),
                fit: BoxFit.cover,
                height: 160,
                width: double.infinity,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

enum MediaSwapAction { photo, video, remove }
