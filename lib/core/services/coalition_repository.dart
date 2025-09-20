import '../../features/candidates/domain/candidate.dart';
import '../../features/events/domain/event.dart';

abstract class CoalitionRepository {
  Stream<List<Candidate>> watchCandidates();
  Stream<List<String>> watchAvailableTags();
  Stream<List<CoalitionEvent>> watchEvents();

  Future<void> addOrUpdateCandidate(Candidate candidate);
  Future<void> addOrUpdateEvent(CoalitionEvent event);
  Future<CoalitionEvent> submitEventRsvp(EventRsvpSubmission submission);
  Future<CoalitionEvent> cancelEventRsvp({
    required String eventId,
    required String userId,
  });
}
