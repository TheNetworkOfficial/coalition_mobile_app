import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/candidates/domain/candidate.dart';
import '../../features/events/domain/event.dart';
import '../constants/sample_data.dart';
import 'coalition_repository.dart';

class InMemoryCoalitionRepository implements CoalitionRepository {
  InMemoryCoalitionRepository()
      : _candidates = List<Candidate>.from(sampleCandidates),
        _events = List<CoalitionEvent>.from(sampleEvents);

  static const Uuid _uuid = Uuid();

  final _candidateController =
      StreamController<List<Candidate>>.broadcast(sync: true);
  final _eventController =
      StreamController<List<CoalitionEvent>>.broadcast(sync: true);

  List<Candidate> _candidates;
  List<CoalitionEvent> _events;

  void dispose() {
    _candidateController.close();
    _eventController.close();
  }

  @override
  Stream<List<Candidate>> watchCandidates() {
    scheduleMicrotask(() => _candidateController.add(_candidates));
    return _candidateController.stream;
  }

  @override
  Stream<List<String>> watchAvailableTags() {
    return watchCandidates().map((candidates) {
      final tagSet = <String>{};
      for (final candidate in candidates) {
        tagSet.addAll(candidate.tags);
      }
      final sorted = tagSet.toList()..sort();
      return sorted;
    });
  }

  @override
  Stream<List<CoalitionEvent>> watchEvents() {
    scheduleMicrotask(() => _eventController.add(_events));
    return _eventController.stream;
  }

  @override
  Future<void> addOrUpdateCandidate(Candidate candidate) async {
    final existingIndex =
        _candidates.indexWhere((element) => element.id == candidate.id);
    if (existingIndex >= 0) {
      _candidates[existingIndex] = candidate;
    } else {
      _candidates = [..._candidates, candidate];
    }
    _candidateController.add(List.unmodifiable(_candidates));
  }

  @override
  Future<void> addOrUpdateEvent(CoalitionEvent event) async {
    final existingIndex = _events.indexWhere((element) => element.id == event.id);
    if (existingIndex >= 0) {
      _events[existingIndex] = event;
    } else {
      _events = [..._events, event];
    }
    _eventController.add(List.unmodifiable(_events));
  }

  @override
  Future<CoalitionEvent> submitEventRsvp(EventRsvpSubmission submission) async {
    final index = _events.indexWhere((event) => event.id == submission.eventId);
    if (index == -1) {
      throw StateError('Event not found');
    }
    if (submission.selectedSlotIds.isEmpty) {
      throw StateError('Select at least one time slot.');
    }

    final now = DateTime.now();
    final event = _events[index];
    final sanitizedSlots = event.timeSlots.map((slot) {
      final attendees = slot.attendees
          .map((attendee) => attendee.userId == submission.userId &&
                  attendee.status == EventRsvpStatus.confirmed
              ? attendee.copyWith(status: EventRsvpStatus.cancelled)
              : attendee)
          .toList(growable: true);
      return slot.copyWith(attendees: attendees);
    }).toList(growable: false);

    for (final slotId in submission.selectedSlotIds) {
      final idx = sanitizedSlots.indexWhere((slot) => slot.id == slotId);
      if (idx == -1) {
        throw StateError('That time slot is no longer available.');
      }
      final slot = sanitizedSlots[idx];
      final remaining = slot.remainingCapacity;
      if (remaining != null && remaining <= 0) {
        throw StateError('That time slot is now full.');
      }
    }

    final updatedSlots = sanitizedSlots.map((slot) {
      if (!submission.selectedSlotIds.contains(slot.id)) {
        return slot;
      }
      final attendee = EventAttendee(
        id: _uuid.v4(),
        userId: submission.userId,
        firstName: submission.firstName,
        lastName: submission.lastName,
        email: submission.email,
        phone: submission.phone,
        zipCode: submission.zipCode,
        status: EventRsvpStatus.confirmed,
        submittedAt: now,
      );
      final attendees = [
        for (final existing in slot.attendees)
          if (!(existing.userId == submission.userId &&
              existing.status == EventRsvpStatus.confirmed))
            existing,
        attendee,
      ];
      return slot.copyWith(attendees: attendees);
    }).toList(growable: false);

    final updatedEvent = event.copyWith(timeSlots: updatedSlots);
    _events[index] = updatedEvent;
    _eventController.add(List.unmodifiable(_events));
    return updatedEvent;
  }

  @override
  Future<CoalitionEvent> cancelEventRsvp({
    required String eventId,
    required String userId,
  }) async {
    final index = _events.indexWhere((event) => event.id == eventId);
    if (index == -1) {
      throw StateError('Event not found');
    }

    final event = _events[index];
    final updatedSlots = event.timeSlots.map((slot) {
      final attendees = slot.attendees
          .map((attendee) => attendee.userId == userId &&
                  attendee.status == EventRsvpStatus.confirmed
              ? attendee.copyWith(status: EventRsvpStatus.cancelled)
              : attendee)
          .toList(growable: false);
      return slot.copyWith(attendees: attendees);
    }).toList(growable: false);

    final updatedEvent = event.copyWith(timeSlots: updatedSlots);
    _events[index] = updatedEvent;
    _eventController.add(List.unmodifiable(_events));
    return updatedEvent;
  }
}

final coalitionRepositoryProvider = Provider<CoalitionRepository>((ref) {
  final repository = InMemoryCoalitionRepository();
  ref.onDispose(repository.dispose);
  return repository;
});
