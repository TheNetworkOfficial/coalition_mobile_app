import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/in_memory_coalition_repository.dart';
import '../domain/candidate.dart';

final candidateListProvider =
    StreamProvider<List<Candidate>>((ref) async* {
  final repository = ref.watch(coalitionRepositoryProvider);
  yield* repository.watchCandidates();
});

final candidateTagsProvider = StreamProvider<List<String>>((ref) async* {
  final repository = ref.watch(coalitionRepositoryProvider);
  yield* repository.watchAvailableTags();
});


final candidateByIdProvider = Provider.family<Candidate?, String>((ref, id) {
  final candidates = ref.watch(candidateListProvider).maybeWhen(
        data: (value) => value,
        orElse: () => null,
      ) ??
      const <Candidate>[];
  for (final candidate in candidates) {
    if (candidate.id == id) return candidate;
  }
  return null;
});
