import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

import '../../../core/video/video_track.dart';

enum FeedMediaType { image, video }

enum FeedMediaProcessingStatus { ready, processing, failed }

enum FeedSourceType { candidate, event, creator }

enum FeedInteractionType { like, comment, share, follow }

class FeedInteractionStats extends Equatable {
  const FeedInteractionStats({
    this.likes = 0,
    this.comments = 0,
    this.shares = 0,
    this.follows = 0,
  });

  final int likes;
  final int comments;
  final int shares;
  final int follows;

  int get engagementScore =>
      (likes * 1) + (comments * 2) + (shares * 3) + (follows * 4);

  FeedInteractionStats copyWith({
    int? likes,
    int? comments,
    int? shares,
    int? follows,
  }) {
    return FeedInteractionStats(
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
      shares: shares ?? this.shares,
      follows: follows ?? this.follows,
    );
  }

  @override
  List<Object?> get props => [likes, comments, shares, follows];
}

class FeedContent extends Equatable {
  const FeedContent({
    required this.id,
    required this.mediaType,
    required this.mediaUrl,
    required this.posterId,
    required this.posterName,
    required this.posterAvatarUrl,
    required this.description,
    required this.sourceType,
    required this.publishedAt,
    this.thumbnailUrl,
    this.aspectRatio = 9 / 16,
    this.tags = const <String>{},
    this.interactionStats = const FeedInteractionStats(),
    this.overlays = const <FeedTextOverlay>[],
    this.compositionTransform,
    this.associatedCandidateIds = const <String>{},
    this.associatedEventIds = const <String>{},
    this.relatedCreatorIds = const <String>{},
    this.zipCode,
    this.distanceHint,
    this.isPromoted = false,
    this.adaptiveStream,
    this.fallbackStreams = const <VideoTrack>[],
    this.processingStatus = FeedMediaProcessingStatus.ready,
    this.processingJobId,
    this.processingError,
  });

  final String id;
  final FeedMediaType mediaType;
  final String mediaUrl;
  final String? thumbnailUrl;
  final double aspectRatio;
  final String posterId;
  final String posterName;
  final String? posterAvatarUrl;
  final String description;
  final FeedSourceType sourceType;
  final DateTime publishedAt;
  final Set<String> tags;
  final FeedInteractionStats interactionStats;
  final Set<String> associatedCandidateIds;
  final Set<String> associatedEventIds;
  final Set<String> relatedCreatorIds;
  final String? zipCode;
  final double? distanceHint;
  final bool isPromoted;
  final List<FeedTextOverlay> overlays;
  final List<double>? compositionTransform;
  final VideoTrack? adaptiveStream;
  final List<VideoTrack> fallbackStreams;
  final FeedMediaProcessingStatus processingStatus;
  final String? processingJobId;
  final String? processingError;

  bool get isVideo => mediaType == FeedMediaType.video;
  bool get isImage => mediaType == FeedMediaType.image;
  bool get isProcessing =>
      processingStatus == FeedMediaProcessingStatus.processing;
  bool get hasProcessingError =>
      processingStatus == FeedMediaProcessingStatus.failed;

  List<VideoTrack> get playbackTracks {
    if (processingStatus != FeedMediaProcessingStatus.ready) {
      return const <VideoTrack>[];
    }
    final added = <String>{};
    final tracks = <VideoTrack>[];

    void addTrack(VideoTrack track) {
      final key = track.uri.toString();
      if (key.isEmpty || added.contains(key)) {
        return;
      }
      added.add(key);
      tracks.add(track);
    }

    if (adaptiveStream != null) {
      addTrack(adaptiveStream!);
    }

    // Always seed the list with the primary media URL so we can fall back to
    // the original asset even if no processed renditions are present.
    final mediaUri = VideoTrack.ensureUri(mediaUrl);
    final fallbackMatch = fallbackStreams.firstWhere(
      (track) => track.uri.toString() == mediaUri.toString(),
      orElse: () => VideoTrack(uri: mediaUri, label: 'Source'),
    );
    addTrack(fallbackMatch);

    for (final track in fallbackStreams) {
      addTrack(track);
    }

    return tracks;
  }

  FeedContent copyWith({
    FeedMediaType? mediaType,
    String? mediaUrl,
    Object? thumbnailUrl = _sentinel,
    double? aspectRatio,
    String? posterId,
    String? posterName,
    Object? posterAvatarUrl = _sentinel,
    String? description,
    FeedSourceType? sourceType,
    DateTime? publishedAt,
    Set<String>? tags,
    FeedInteractionStats? interactionStats,
    Set<String>? associatedCandidateIds,
    Set<String>? associatedEventIds,
    Set<String>? relatedCreatorIds,
    Object? zipCode = _sentinel,
    double? distanceHint,
    bool? isPromoted,
    List<FeedTextOverlay>? overlays,
    Object? compositionTransform = _sentinel,
    Object? adaptiveStream = _sentinel,
    List<VideoTrack>? fallbackStreams,
    FeedMediaProcessingStatus? processingStatus,
    Object? processingJobId = _sentinel,
    Object? processingError = _sentinel,
  }) {
    return FeedContent(
      id: id,
      mediaType: mediaType ?? this.mediaType,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnailUrl: thumbnailUrl == _sentinel
          ? this.thumbnailUrl
          : thumbnailUrl as String?,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      posterId: posterId ?? this.posterId,
      posterName: posterName ?? this.posterName,
      posterAvatarUrl: posterAvatarUrl == _sentinel
          ? this.posterAvatarUrl
          : posterAvatarUrl as String?,
      description: description ?? this.description,
      sourceType: sourceType ?? this.sourceType,
      publishedAt: publishedAt ?? this.publishedAt,
      tags: tags ?? this.tags,
      interactionStats: interactionStats ?? this.interactionStats,
      associatedCandidateIds:
          associatedCandidateIds ?? this.associatedCandidateIds,
      associatedEventIds: associatedEventIds ?? this.associatedEventIds,
      relatedCreatorIds: relatedCreatorIds ?? this.relatedCreatorIds,
      zipCode: zipCode == _sentinel ? this.zipCode : zipCode as String?,
      distanceHint: distanceHint ?? this.distanceHint,
      isPromoted: isPromoted ?? this.isPromoted,
      overlays: overlays ?? this.overlays,
      compositionTransform: compositionTransform == _sentinel
          ? this.compositionTransform
          : compositionTransform as List<double>?,
      adaptiveStream: adaptiveStream == _sentinel
          ? this.adaptiveStream
          : adaptiveStream as VideoTrack?,
      fallbackStreams: fallbackStreams ?? this.fallbackStreams,
      processingStatus: processingStatus ?? this.processingStatus,
      processingJobId: processingJobId == _sentinel
          ? this.processingJobId
          : processingJobId as String?,
      processingError: processingError == _sentinel
          ? this.processingError
          : processingError as String?,
    );
  }

  static const _sentinel = Object();

  @override
  List<Object?> get props => [
        id,
        mediaType,
        mediaUrl,
        thumbnailUrl,
        aspectRatio,
        posterId,
        posterName,
        posterAvatarUrl,
        description,
        sourceType,
        publishedAt,
        tags,
        interactionStats,
        associatedCandidateIds,
        associatedEventIds,
        relatedCreatorIds,
        zipCode,
        distanceHint,
        isPromoted,
        overlays,
        compositionTransform,
        adaptiveStream,
        fallbackStreams,
        processingStatus,
        processingJobId,
        processingError,
      ];
}

class FeedTextOverlay extends Equatable {
  const FeedTextOverlay({
    required this.id,
    required this.text,
    required this.color,
    required this.position,
    this.fontFamily,
    this.fontWeight = FontWeight.w600,
    this.fontStyle = FontStyle.normal,
    this.fontSize = 20,
    this.backgroundColor,
  });

  final String id;
  final String text;
  final Color color;
  final Color? backgroundColor;
  final String? fontFamily;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final double fontSize;
  final Offset position;

  FeedTextOverlay copyWith({
    String? text,
    Color? color,
    String? fontFamily,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? fontSize,
    Offset? position,
    Color? backgroundColor,
    bool removeBackground = false,
  }) {
    return FeedTextOverlay(
      id: id,
      text: text ?? this.text,
      color: color ?? this.color,
      backgroundColor:
          removeBackground ? null : (backgroundColor ?? this.backgroundColor),
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      fontSize: fontSize ?? this.fontSize,
      position: position ?? this.position,
    );
  }

  @override
  List<Object?> get props => [
        id,
        text,
        color.toARGB32(),
        backgroundColor?.toARGB32(),
        fontFamily,
        fontWeight,
        fontStyle,
        fontSize,
        position.dx,
        position.dy,
      ];
}
