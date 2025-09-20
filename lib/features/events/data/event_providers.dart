import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/in_memory_coalition_repository.dart';
import '../domain/event.dart';

final eventsProvider = StreamProvider<List<CoalitionEvent>>((ref) async* {
  final repository = ref.watch(coalitionRepositoryProvider);
  yield* repository.watchEvents();
});

final eventTagsProvider = StreamProvider<List<String>>((ref) async* {
  final repository = ref.watch(coalitionRepositoryProvider);
  yield* repository.watchEvents().map((events) {
    final tagSet = <String>{};
    for (final event in events) {
      tagSet.addAll(event.tags);
    }
    final sorted = tagSet.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  });
});

final eventByIdProvider = Provider.family<CoalitionEvent?, String>((ref, id) {
  final events = ref.watch(eventsProvider).maybeWhen(
        data: (value) => value,
        orElse: () => null,
      ) ??
      const <CoalitionEvent>[];
  for (final event in events) {
    if (event.id == id) return event;
  }
  return null;
});
