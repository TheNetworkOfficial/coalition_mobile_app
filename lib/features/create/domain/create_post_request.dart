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
    this.location,
    this.mentions = const <String>[],
    this.visibility = 'public',
    this.allowComments = true,
    this.allowSharing = true,
    this.externalLink,
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
  final String? location;
  final List<String> mentions;
  final String visibility;
  final bool allowComments;
  final bool allowSharing;
  final String? externalLink;

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
        location,
        mentions,
        visibility,
        allowComments,
        allowSharing,
        externalLink,
      ];
}
