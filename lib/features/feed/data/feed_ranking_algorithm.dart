import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../candidates/domain/candidate.dart';
import '../../events/data/event_providers.dart';
import '../../events/domain/event.dart';
import '../domain/feed_content.dart';
import 'feed_content_store.dart';

class FeedRankingInputs {
  const FeedRankingInputs({
    required this.user,
    required this.availableContent,
    required this.candidates,
    required this.events,
  });

  final AppUser user;
  final List<FeedContent> availableContent;
  final List<Candidate> candidates;
  final List<CoalitionEvent> events;
}

class FeedRankingConfig {
  const FeedRankingConfig({
    this.trendingWeight = 26,
    this.recencyWeight = 18,
    this.recencyHalfLifeHours = 36,
    this.directFollowWeight = 32,
    this.relatedFollowWeight = 20,
    this.tagFollowWeight = 8,
    this.tagEngagementWeight = 5,
    this.locationExactWeight = 16,
    this.locationPrefixWeight = 9,
    this.promotedWeight = 14,
    this.rsvpWeight = 24,
    this.baseDiversityPenalty = 4,
  });

  final double trendingWeight;
  final double recencyWeight;
  final double recencyHalfLifeHours;
  final double directFollowWeight;
  final double relatedFollowWeight;
  final double tagFollowWeight;
  final double tagEngagementWeight;
  final double locationExactWeight;
  final double locationPrefixWeight;
  final double promotedWeight;
  final double rsvpWeight;
  final double baseDiversityPenalty;
}

class RankedFeedContent {
  const RankedFeedContent({
    required this.content,
    required this.score,
    required this.reasons,
  });

  final FeedContent content;
  final double score;
  final Map<String, double> reasons;
}

class FeedRankingService {
  const FeedRankingService({this.config = const FeedRankingConfig()});

  final FeedRankingConfig config;

  List<RankedFeedContent> rank(FeedRankingInputs inputs) {
    if (inputs.availableContent.isEmpty) {
      return const <RankedFeedContent>[];
    }

    final user = inputs.user;
    final likedIds = user.likedContentIds.toSet();
    final followedCandidates = user.followedCandidateIds;
    final followedCreators = user.followedCreatorIds;
    final followedTags = user.followedTags;
    final rsvpEvents = user.rsvpEventIds;

    final candidateLookup = {
      for (final candidate in inputs.candidates) candidate.id: candidate,
    };
    final eventLookup = {
      for (final event in inputs.events) event.id: event,
    };
    final contentLookup = {
      for (final item in inputs.availableContent) item.id: item,
    };

    final tagAffinity = <String, double>{};
    for (final tag in followedTags) {
      tagAffinity[tag] = (tagAffinity[tag] ?? 0) + config.tagFollowWeight;
    }
    for (final likedId in likedIds) {
      final content = contentLookup[likedId];
      if (content == null) continue;
      for (final tag in content.tags) {
        tagAffinity[tag] = (tagAffinity[tag] ?? 0) + config.tagEngagementWeight;
      }
    }

    final now = DateTime.now();
    final prefix = user.zipCode.length >= 3 ? user.zipCode.substring(0, 3) : '';

    final ranked = <RankedFeedContent>[];

    for (final content in inputs.availableContent) {
      var score = 0.0;
      final reasons = <String, double>{};

      final engagement = content.interactionStats.engagementScore.toDouble();
      final trendingScore = math.log(engagement + 1) * config.trendingWeight;
      if (trendingScore > 0) {
        reasons['trending'] = trendingScore;
        score += trendingScore;
      }

      final ageHours = now.difference(content.publishedAt).inMinutes / 60;
      final recencyScore = config.recencyWeight *
          math.exp(-math.max(0, ageHours) / config.recencyHalfLifeHours);
      reasons['fresh'] = recencyScore;
      score += recencyScore;

      if (content.isPromoted) {
        reasons['promoted'] = config.promotedWeight;
        score += config.promotedWeight;
      }

      final isFollowerOfCandidate = followedCandidates.contains(content.posterId) ||
          content.associatedCandidateIds
              .any((id) => followedCandidates.contains(id));
      final isFollowerOfCreator = followedCreators.contains(content.posterId) ||
          content.relatedCreatorIds.any((id) => followedCreators.contains(id));

      if (isFollowerOfCandidate || isFollowerOfCreator) {
        reasons['followed-source'] = config.directFollowWeight;
        score += config.directFollowWeight;
      } else {
        switch (content.sourceType) {
          case FeedSourceType.candidate:
            if (candidateLookup.containsKey(content.posterId)) {
              reasons['candidate'] = config.relatedFollowWeight;
              score += config.relatedFollowWeight;
            }
            break;
          case FeedSourceType.creator:
          case FeedSourceType.event:
            if (followedCreators.isNotEmpty) {
              final relatedBoost = config.relatedFollowWeight * 0.6;
              reasons['related-creator'] = relatedBoost;
              score += relatedBoost;
            }
            break;
        }
      }

      if (content.associatedEventIds
          .any((id) => rsvpEvents.contains(id))) {
        reasons['rsvp'] = config.rsvpWeight;
        score += config.rsvpWeight;
      }

      final tagScore = _scoreTags(content.tags, tagAffinity, config);
      if (tagScore > 0) {
        reasons['tags'] = tagScore;
        score += tagScore;
      }

      if (content.zipCode != null && content.zipCode!.isNotEmpty) {
        if (content.zipCode == user.zipCode) {
          reasons['nearby'] = config.locationExactWeight;
          score += config.locationExactWeight;
        } else if (prefix.isNotEmpty &&
            content.zipCode!.startsWith(prefix)) {
          reasons['regional'] = config.locationPrefixWeight;
          score += config.locationPrefixWeight;
        } else if (content.distanceHint != null) {
          final dampener = math.max(1, content.distanceHint!);
          final proximity = config.locationPrefixWeight / dampener;
          reasons['distance'] = proximity;
          score += proximity;
        }
      }

      if (likedIds.contains(content.id)) {
        // Down-weight slightly to avoid repeating content too often while keeping it visible.
        final penalty = config.baseDiversityPenalty;
        reasons['already-liked'] = -penalty;
        score -= penalty;
      }

      ranked.add(RankedFeedContent(content: content, score: score, reasons: reasons));
    }

    ranked.sort((a, b) {
      final cmp = b.score.compareTo(a.score);
      if (cmp != 0) {
        return cmp;
      }
      return b.content.publishedAt.compareTo(a.content.publishedAt);
    });

    // Guarantee a healthy mix: promote at least one trending item per 5 if absent.
    final results = <RankedFeedContent>[];
    var trendingCarry = ranked
        .where((entry) => (entry.reasons['trending'] ?? 0) > config.trendingWeight)
        .toList();
    final trendingIterator = trendingCarry.iterator;

    for (var i = 0; i < ranked.length; i++) {
      if (i > 0 && i % 5 == 0 && trendingIterator.moveNext()) {
        final candidate = trendingIterator.current;
        if (!results.any((entry) => entry.content.id == candidate.content.id)) {
          results.add(candidate);
          continue;
        }
      }
      results.add(ranked[i]);
    }

    final deduped = <RankedFeedContent>[];
    final seen = <String>{};
    for (final entry in results) {
      if (seen.add(entry.content.id)) {
        deduped.add(entry);
      }
    }

    return deduped;
  }

  double _scoreTags(Set<String> contentTags, Map<String, double> affinity,
      FeedRankingConfig config) {
    if (contentTags.isEmpty || affinity.isEmpty) {
      return 0;
    }
    var score = 0.0;
    for (final tag in contentTags) {
      score += affinity[tag] ?? 0;
    }
    return score;
  }
}

final feedRankingServiceProvider = Provider((ref) {
  return const FeedRankingService();
});

final personalizedFeedProvider = FutureProvider<List<RankedFeedContent>>((ref) async {
  final authState = ref.watch(authControllerProvider);
  final user = authState.user;
  if (user == null) {
    return const <RankedFeedContent>[];
  }

  final feedContent = ref.watch(feedContentCatalogProvider);

  final candidates = await ref.watch(candidateListProvider.future);
  final events = await ref.watch(eventsProvider.future);

  final ranked = ref.read(feedRankingServiceProvider).rank(
        FeedRankingInputs(
          user: user,
          availableContent: feedContent,
          candidates: candidates,
          events: events,
        ),
      );
  return ranked;
});
