import 'package:equatable/equatable.dart';

import '../../events/domain/event.dart';
import '../../feed/domain/feed_content.dart';

class CreateEventRequest extends Equatable {
  const CreateEventRequest({
    required this.title,
    required this.description,
    required this.primaryDate,
    required this.location,
    required this.tags,
    this.cost,
    this.eventType,
    this.hostCandidateIds = const <String>[],
    this.timeSlots = const <EventTimeSlot>[],
    this.mediaPath,
    this.mediaType,
    this.coverImagePath,
    this.mediaAspectRatio,
    this.overlays = const <FeedTextOverlay>[],
  });

  final String title;
  final String description;
  final DateTime primaryDate;
  final String location;
  final String? cost;
  final String? eventType;
  final List<String> tags;
  final List<String> hostCandidateIds;
  final List<EventTimeSlot> timeSlots;
  final String? mediaPath;
  final FeedMediaType? mediaType;
  final String? coverImagePath;
  final double? mediaAspectRatio;
  final List<FeedTextOverlay> overlays;

  bool get hasMedia => mediaPath != null;

  @override
  List<Object?> get props => [
        title,
        description,
        primaryDate,
        location,
        cost,
        eventType,
        tags,
        hostCandidateIds,
        timeSlots,
        mediaPath,
        mediaType,
        coverImagePath,
        mediaAspectRatio,
        overlays,
      ];
}
