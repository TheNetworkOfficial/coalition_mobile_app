import 'package:equatable/equatable.dart';

import '../../feed/domain/feed_content.dart';

class CreatePostRequest extends Equatable {
  const CreatePostRequest({
    required this.mediaPath,
    required this.mediaType,
    required this.description,
    required this.tags,
    required this.aspectRatio,
    this.coverImagePath,
    this.coverFramePosition,
    this.overlays = const <FeedTextOverlay>[],
    this.compositionTransform,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final String description;
  final List<String> tags;
  final double aspectRatio;
  final String? coverImagePath;
  final Duration? coverFramePosition;
  final List<FeedTextOverlay> overlays;
  final List<double>? compositionTransform;

  bool get isVideo => mediaType == FeedMediaType.video;

  @override
  List<Object?> get props => [
        mediaPath,
        mediaType,
        description,
        tags,
        aspectRatio,
        coverImagePath,
        coverFramePosition?.inMilliseconds,
        overlays,
        compositionTransform,
      ];
}
