import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/media_type_utils.dart';

class EventMediaPreview extends StatelessWidget {
  const EventMediaPreview({
    required this.mediaUrl,
    required this.aspectRatio,
    this.coverImagePath,
    super.key,
  });

  final String mediaUrl;
  final double aspectRatio;
  final String? coverImagePath;

  @override
  Widget build(BuildContext context) {
    final ratio = aspectRatio <= 0 ? 16 / 9 : aspectRatio;
    return AspectRatio(
      aspectRatio: ratio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: _buildMedia(),
      ),
    );
  }

  Widget _buildMedia() {
    final imageSource = isLikelyImageSource(coverImagePath)
        ? coverImagePath
        : (isLikelyImageSource(mediaUrl) ? mediaUrl : null);
    if (imageSource == null || imageSource.isEmpty) {
      return const _EventPreviewPlaceholder();
    }

    return Image(
      image: _imageProvider(imageSource),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) =>
          const _EventPreviewPlaceholder(),
    );
  }

  ImageProvider<Object> _imageProvider(String source) {
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(source);
    }
    if (uri != null && uri.scheme == 'file') {
      return FileImage(File(uri.toFilePath()));
    }
    return FileImage(File(source));
  }
}

class _EventPreviewPlaceholder extends StatelessWidget {
  const _EventPreviewPlaceholder({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final label = message ?? 'No media available';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurface),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
