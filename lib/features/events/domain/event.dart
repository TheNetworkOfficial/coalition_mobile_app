import 'dart:math' as math;

import '../../feed/domain/feed_content.dart';
import '../../../core/video/video_track.dart';

enum EventRsvpStatus { confirmed, cancelled }

enum EventMediaType { image, video }

class EventAttendee {
  const EventAttendee({
    required this.id,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.zipCode,
    required this.status,
    required this.submittedAt,
  });

  final String id;
  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String zipCode;
  final EventRsvpStatus status;
  final DateTime submittedAt;

  EventAttendee copyWith({
    EventRsvpStatus? status,
  }) {
    return EventAttendee(
      id: id,
      userId: userId,
      firstName: firstName,
      lastName: lastName,
      email: email,
      phone: phone,
      zipCode: zipCode,
      status: status ?? this.status,
      submittedAt: submittedAt,
    );
  }
}

class EventTimeSlot {
  const EventTimeSlot({
    required this.id,
    required this.label,
    this.capacity,
    this.attendees = const <EventAttendee>[],
  });

  final String id;
  final String label;
  final int? capacity;
  final List<EventAttendee> attendees;

  int get confirmedCount => attendees
      .where((attendee) => attendee.status == EventRsvpStatus.confirmed)
      .length;

  int? get remainingCapacity =>
      capacity == null ? null : math.max(0, capacity! - confirmedCount);

  EventTimeSlot copyWith({
    String? id,
    String? label,
    int? capacity,
    List<EventAttendee>? attendees,
  }) {
    return EventTimeSlot(
      id: id ?? this.id,
      label: label ?? this.label,
      capacity: capacity ?? this.capacity,
      attendees: attendees ?? this.attendees,
    );
  }
}

class CoalitionEvent {
  const CoalitionEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.startDate,
    required this.location,
    this.type = 'general',
    this.cost = 'Free',
    this.hostCandidateIds = const <String>[],
    this.tags = const <String>[],
    this.timeSlots = const <EventTimeSlot>[],
    this.mediaUrl,
    this.mediaType,
    this.coverImagePath,
    this.mediaAspectRatio,
    this.overlays = const <FeedTextOverlay>[],
    this.adaptiveMediaStream,
    this.mediaFallbackStreams = const <VideoTrack>[],
  });

  final String id;
  final String title;
  final String description;
  final DateTime startDate;
  final String location;
  final String type;
  final String cost;
  final List<String> hostCandidateIds;
  final List<String> tags;
  final List<EventTimeSlot> timeSlots;
  final String? mediaUrl;
  final EventMediaType? mediaType;
  final String? coverImagePath;
  final double? mediaAspectRatio;
  final List<FeedTextOverlay> overlays;
  final VideoTrack? adaptiveMediaStream;
  final List<VideoTrack> mediaFallbackStreams;

  CoalitionEvent copyWith({
    String? title,
    String? description,
    DateTime? startDate,
    String? location,
    String? type,
    String? cost,
    List<String>? hostCandidateIds,
    List<String>? tags,
    List<EventTimeSlot>? timeSlots,
    String? mediaUrl,
    Object? coverImagePath = _sentinel,
    EventMediaType? mediaType,
    double? mediaAspectRatio,
    List<FeedTextOverlay>? overlays,
    Object? adaptiveMediaStream = _sentinel,
    List<VideoTrack>? mediaFallbackStreams,
  }) {
    return CoalitionEvent(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      location: location ?? this.location,
      type: type ?? this.type,
      cost: cost ?? this.cost,
      hostCandidateIds: hostCandidateIds ?? this.hostCandidateIds,
      tags: tags ?? this.tags,
      timeSlots: timeSlots ?? this.timeSlots,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      coverImagePath: coverImagePath == _sentinel
          ? this.coverImagePath
          : coverImagePath as String?,
      mediaType: mediaType ?? this.mediaType,
      mediaAspectRatio: mediaAspectRatio ?? this.mediaAspectRatio,
      overlays: overlays ?? this.overlays,
      adaptiveMediaStream: adaptiveMediaStream == _sentinel
          ? this.adaptiveMediaStream
          : adaptiveMediaStream as VideoTrack?,
      mediaFallbackStreams:
          mediaFallbackStreams ?? this.mediaFallbackStreams,
    );
  }

  bool get hasLimitedCapacity =>
      timeSlots.any((slot) => slot.capacity != null && slot.capacity! > 0);

  static const _sentinel = Object();
}

class EventRsvpSubmission {
  const EventRsvpSubmission({
    required this.eventId,
    required this.userId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.zipCode,
    required this.selectedSlotIds,
  });

  final String eventId;
  final String userId;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String zipCode;
  final List<String> selectedSlotIds;
}
