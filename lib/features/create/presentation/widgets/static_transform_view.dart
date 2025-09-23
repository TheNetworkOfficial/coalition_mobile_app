import 'package:flutter/material.dart';

/// Displays a non-interactive viewport that preserves the transform produced by
/// the media composer. The widget reuses the same [InteractiveViewer]
/// configuration as the editor but disables gestures so that the composed media
/// can be previewed anywhere in the app (publish screen, feed, etc.).
class StaticTransformView extends StatefulWidget {
  const StaticTransformView({
    required this.child,
    this.transformValues,
    this.minScale = 0.8,
    this.maxScale = 4.0,
    this.boundaryMargin = const EdgeInsets.all(240),
    super.key,
  });

  /// Child to display within the transformation viewport. Typically an image or
  /// a video widget sized to the media's natural dimensions.
  final Widget child;

  /// Serialized matrix values representing the final transformation applied in
  /// the composer. When null, the child is rendered without additional
  /// transformation.
  final List<double>? transformValues;

  /// Minimum and maximum scale values that match the composer configuration so
  /// that the stored matrix renders identically wherever it is displayed.
  final double minScale;
  final double maxScale;

  /// Boundary margin used to allow generous panning in the composer. This is
  /// replicated here to faithfully apply the saved transformation.
  final EdgeInsets boundaryMargin;

  @override
  State<StaticTransformView> createState() => _StaticTransformViewState();
}

class _StaticTransformViewState extends State<StaticTransformView> {
  late TransformationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TransformationController(
      widget.transformValues == null
          ? Matrix4.identity()
          : Matrix4.fromList(widget.transformValues!),
    );
  }

  @override
  void didUpdateWidget(covariant StaticTransformView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transformValues != oldWidget.transformValues) {
      _controller.value = widget.transformValues == null
          ? Matrix4.identity()
          : Matrix4.fromList(widget.transformValues!);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      panEnabled: false,
      scaleEnabled: false,
      clipBehavior: Clip.hardEdge,
      boundaryMargin: widget.boundaryMargin,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
      child: widget.child,
    );
  }
}
