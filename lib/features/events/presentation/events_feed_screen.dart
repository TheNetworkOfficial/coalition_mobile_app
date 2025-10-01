import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/in_memory_coalition_repository.dart';
import '../../auth/data/auth_controller.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../candidates/domain/candidate.dart';
import '../data/event_providers.dart';
import '../domain/event.dart';
import 'widgets/event_media_preview.dart';
import 'widgets/event_rsvp_sheet.dart';

const _fallbackCategoryLabel = 'Other priorities';

const _tagCategoryOrder = <String>[
  'Cost of living',
  'Environmental',
  'Families & education',
  'Community & justice',
  'Infrastructure & growth',
  _fallbackCategoryLabel,
];

const Map<String, String> _tagCategoryLookup = {
  'Affordable housing': 'Cost of living',
  'Inflation reduction': 'Cost of living',
  'Labor rights': 'Cost of living',
  'Healthcare': 'Cost of living',
  'Living wages': 'Cost of living',
  'Tax fairness': 'Cost of living',
  'Climate action': 'Environmental',
  'Clean air': 'Environmental',
  'Clean water': 'Environmental',
  'Water rights': 'Environmental',
  'Carbon capture': 'Environmental',
  'Public lands': 'Environmental',
  'Wildfire resilience': 'Environmental',
  'Education': 'Families & education',
  'Childcare': 'Families & education',
  'Early learning': 'Families & education',
  'Families': 'Families & education',
  'Indigenous rights': 'Community & justice',
  'Veterans': 'Community & justice',
  'Voting rights': 'Community & justice',
  'Public safety': 'Community & justice',
  'Justice reform': 'Community & justice',
  'Rural broadband': 'Infrastructure & growth',
  'Smart growth': 'Infrastructure & growth',
  'Public transit': 'Infrastructure & growth',
  'Economic development': 'Infrastructure & growth',
  'Small business': 'Infrastructure & growth',
};

Map<String, List<String>> _groupTagsByCategory(List<String> tags) {
  final grouped = <String, List<String>>{};
  for (final category in _tagCategoryOrder) {
    grouped[category] = <String>[];
  }
  final sortedTags = [...tags]
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  for (final tag in sortedTags) {
    final category = _tagCategoryLookup[tag] ?? _fallbackCategoryLabel;
    grouped.putIfAbsent(category, () => <String>[]).add(tag);
  }

  return LinkedHashMap<String, List<String>>.fromEntries(
    grouped.entries.where((entry) => entry.value.isNotEmpty),
  );
}

class EventsFeedScreen extends ConsumerStatefulWidget {
  const EventsFeedScreen({super.key});

  static const routeName = 'events';

  @override
  ConsumerState<EventsFeedScreen> createState() => _EventsFeedScreenState();
}

class _EventsFeedScreenState extends ConsumerState<EventsFeedScreen> {
  static const _eventTypes = <String, String>{
    'all': 'All event types',
    'organizing': 'Organizing & field',
    'town-hall': 'Town halls & forums',
    'fundraiser': 'Fundraisers',
    'training': 'Trainings & workshops',
    'general': 'Community gatherings',
  };

  String _searchTerm = '';
  String _typeFilter = 'all';
  final Set<String> _selectedTags = <String>{};
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _handleRsvpAction(
    BuildContext context,
    CoalitionEvent event,
    bool attending,
  ) async {
    final user = ref.read(authControllerProvider).user;
    if (user == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to RSVP for coalition events.')),
      );
      return;
    }

    if (!attending) {
      await showEventRsvpSheet(context: context, ref: ref, event: event);
      return;
    }

    final shouldCancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel RSVP'),
        content: Text(
          'Are you sure you want to cancel your RSVP for "${event.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep RSVP'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel RSVP'),
          ),
        ],
      ),
    );

    if (shouldCancel != true) return;

    try {
      await ref
          .read(coalitionRepositoryProvider)
          .cancelEventRsvp(eventId: event.id, userId: user.id);
      await ref.read(authControllerProvider.notifier).cancelEventRsvp(event.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your RSVP has been cancelled.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is StateError
                ? error.message
                : 'We could not cancel your RSVP. Please try again or contact support.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(eventsProvider);
    final tagsAsync = ref.watch(eventTagsProvider);
    final authState = ref.watch(authControllerProvider);
    final candidatesAsync = ref.watch(candidateListProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // Placeholder for real refresh logic when API is connected.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
      child: NestedScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: _EventFilterSection(
                searchTerm: _searchTerm,
                onSearchChanged: (value) {
                  setState(() => _searchTerm = value);
                  _resetPager();
                },
                typeFilter: _typeFilter,
                onTypeChanged: (value) {
                  if (value == null) return;
                  setState(() => _typeFilter = value);
                  _resetPager();
                },
                types: _eventTypes,
                hasSelectedTags: _selectedTags.isNotEmpty,
                onClearTags: () {
                  setState(_selectedTags.clear);
                  _resetPager();
                },
                tagsAsync: tagsAsync,
                selectedTags: _selectedTags,
                onTagToggled: (tag, selected) {
                  setState(() {
                    if (selected) {
                      _selectedTags.add(tag);
                    } else {
                      _selectedTags.remove(tag);
                    }
                  });
                  _resetPager();
                },
              ),
            ),
          ),
        ],
        body: Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: eventsAsync.when(
            data: (events) {
              final candidates = candidatesAsync.maybeWhen(
                data: (value) => value,
                orElse: () => const <Candidate>[],
              );
              final candidateLookup = {
                for (final candidate in candidates) candidate.id: candidate,
              };

              final filtered = _filterEvents(
                events,
                searchTerm: _searchTerm,
                type: _typeFilter,
                tags: _selectedTags,
              )
                ..sort((a, b) => a.startDate.compareTo(b.startDate));

              if (filtered.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No events matched those filters yet. Try adjusting your search or tag filters.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_pageController.hasClients &&
                    _pageController.positions.isNotEmpty &&
                    _pageController.page != null &&
                    _pageController.page! >= filtered.length) {
                  _pageController.jumpToPage(0);
                }
              });

              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Theme.of(context).colorScheme.surfaceContainerLowest,
                      Theme.of(context).colorScheme.surface,
                    ],
                  ),
                ),
                child: PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final event = filtered[index];
                    final attending = authState.user?.rsvpEventIds
                            .contains(event.id) ??
                        false;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: EventCard(
                        event: event,
                        attending: attending,
                        candidateLookup: candidateLookup,
                        onPrimaryAction: () =>
                            _handleRsvpAction(context, event, attending),
                        onOpenDetail: () => context.push('/events/${event.id}'),
                      ),
                    );
                  },
                ),
              );
            },
            loading: () => const Center(
              child: CircularProgressIndicator.adaptive(),
            ),
            error: (err, _) => Center(
              child: Text('Could not load events: $err'),
            ),
          ),
        ),
      ),
    );
  }

  List<CoalitionEvent> _filterEvents(
    List<CoalitionEvent> events, {
    required String searchTerm,
    required String type,
    required Set<String> tags,
  }) {
    final needle = searchTerm.trim().toLowerCase();
    return events.where((event) {
      if (type != 'all' && event.type != type) return false;
      if (tags.isNotEmpty) {
        final matchesAll = tags.every(event.tags.contains);
        if (!matchesAll) return false;
      }
      if (needle.isEmpty) return true;
      final haystack = [
        event.title,
        event.location,
        event.description,
        event.tags.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(needle);
    }).toList();
  }

  void _resetPager() {
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }
}

class _EventFilterSection extends StatefulWidget {
  const _EventFilterSection({
    required this.searchTerm,
    required this.onSearchChanged,
    required this.typeFilter,
    required this.onTypeChanged,
    required this.types,
    required this.hasSelectedTags,
    required this.onClearTags,
    required this.tagsAsync,
    required this.selectedTags,
    required this.onTagToggled,
  });

  final String searchTerm;
  final ValueChanged<String> onSearchChanged;
  final String typeFilter;
  final ValueChanged<String?> onTypeChanged;
  final Map<String, String> types;
  final bool hasSelectedTags;
  final VoidCallback onClearTags;
  final AsyncValue<List<String>> tagsAsync;
  final Set<String> selectedTags;
  final void Function(String tag, bool selected) onTagToggled;

  @override
  State<_EventFilterSection> createState() => _EventFilterSectionState();
}

class _EventFilterSectionState extends State<_EventFilterSection> {
  final Set<String> _expandedCategories = <String>{};
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  bool _isSearchExpanded = false;
  bool _isBrowseOverlayOpen = false;
  final LayerLink _browseLayerLink = LayerLink();
  final GlobalKey _browseButtonKey = GlobalKey();
  OverlayEntry? _browseOverlayEntry;
  double _browseOverlayWidth = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchTerm);
    _searchFocusNode = FocusNode();
    _isSearchExpanded = widget.searchTerm.isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant _EventFilterSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchTerm != widget.searchTerm &&
        _searchController.text != widget.searchTerm) {
      _searchController.text = widget.searchTerm;
    }
    _isSearchExpanded = _isSearchExpanded || widget.searchTerm.isNotEmpty;
    if (widget.searchTerm.isEmpty &&
        !_isSearchExpanded &&
        _searchController.text.isNotEmpty) {
      _searchController.clear();
    }
    if (_browseOverlayEntry != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _browseOverlayEntry?.markNeedsBuild();
        }
      });
    }
  }

  @override
  void dispose() {
    _browseOverlayEntry?.remove();
    _browseOverlayEntry = null;
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _expandSearch() {
    if (_isSearchExpanded) return;
    _hideBrowseOverlay();
    setState(() {
      _isSearchExpanded = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _collapseSearch() {
    if (!_isSearchExpanded && _searchController.text.isEmpty) {
      return;
    }
    setState(() {
      _isSearchExpanded = false;
    });
    _searchFocusNode.unfocus();
  }

  void _toggleBrowseOverlay() {
    if (_browseOverlayEntry != null) {
      _hideBrowseOverlay();
    } else {
      _showBrowseOverlay();
    }
  }

  void _showBrowseOverlay() {
    if (_browseOverlayEntry != null) return;
    _collapseSearch();
    final overlayState = Overlay.of(context, rootOverlay: true);
    final renderBox =
        _browseButtonKey.currentContext?.findRenderObject() as RenderBox?;
    final mediaWidth = MediaQuery.of(context).size.width;
    final fallbackWidth = mediaWidth - 40;
    var targetWidth = renderBox?.size.width ?? fallbackWidth;
    if (targetWidth <= 0) {
      targetWidth = fallbackWidth;
    } else if (fallbackWidth > 0 && targetWidth > fallbackWidth) {
      targetWidth = fallbackWidth;
    }
    _browseOverlayWidth = targetWidth;
    final entry = OverlayEntry(builder: (_) => _buildBrowseOverlay());
    overlayState.insert(entry);
    setState(() {
      _browseOverlayEntry = entry;
      _isBrowseOverlayOpen = true;
    });
  }

  void _hideBrowseOverlay() {
    if (_browseOverlayEntry == null) return;
    _browseOverlayEntry!.remove();
    _browseOverlayEntry = null;
    if (mounted) {
      setState(() {
        _isBrowseOverlayOpen = false;
      });
    } else {
      _isBrowseOverlayOpen = false;
    }
  }

  void _markBrowseOverlayNeedsBuild() {
    _browseOverlayEntry?.markNeedsBuild();
  }

  Widget _buildCollapsedSearchButton({required bool isEnabled}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: isEnabled ? 1 : 0,
        child: IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search events or tags',
          onPressed: isEnabled ? _expandSearch : null,
        ),
      ),
    );
  }

  Widget _buildBrowseTriggerButton(
    BuildContext context, {
    required String summaryText,
    required bool hasActiveFilters,
  }) {
    final theme = Theme.of(context);
    const placeholderText = 'Filter by event type or focus area tags';
    final displaySummary = summaryText.isEmpty ? placeholderText : summaryText;
    final backgroundColor = hasActiveFilters
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : theme.colorScheme.surfaceContainerLow;
    final borderColor = hasActiveFilters
        ? theme.colorScheme.primary.withValues(alpha: 0.4)
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.6);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor, width: 1.2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _toggleBrowseOverlay,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: summaryText.isEmpty ? 10 : 6,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Browse event focus',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        displaySummary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isBrowseOverlayOpen
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrowseOverlay() {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final fallbackWidth = mediaQuery.size.width - 40;
    var width = _browseOverlayWidth;
    if (width <= 0) {
      width = fallbackWidth;
    } else if (fallbackWidth > 0 && width > fallbackWidth) {
      width = fallbackWidth;
    }
    final maxHeight = mediaQuery.size.height * 0.7;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _hideBrowseOverlay,
            child: const SizedBox.shrink(),
          ),
        ),
        Positioned(
          width: width,
          child: CompositedTransformFollower(
            link: _browseLayerLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 8),
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(28),
              clipBehavior: Clip.antiAlias,
              color: theme.colorScheme.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight,
                ),
                child: _buildBrowseOverlayContent(theme),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrowseOverlayContent(ThemeData theme) {
    return widget.tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Event focus tags will appear here once events include them.',
              style: theme.textTheme.bodyMedium,
            ),
          );
        }

        final grouped = _groupTagsByCategory(tags);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      'Filter events',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: _hideBrowseOverlay,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownMenu<String>(
                initialSelection: widget.typeFilter,
                label: const Text('Event type'),
                expandedInsets: EdgeInsets.zero,
                dropdownMenuEntries: [
                  for (final entry in widget.types.entries)
                    DropdownMenuEntry<String>(
                      value: entry.key,
                      label: entry.value,
                    ),
                ],
                onSelected: (value) {
                  if (value == null) return;
                  widget.onTypeChanged(value);
                  _markBrowseOverlayNeedsBuild();
                },
              ),
              const SizedBox(height: 20),
              if (grouped.isNotEmpty)
                ...grouped.entries.map(
                  (entry) => _buildTagCategorySection(
                    theme,
                    category: entry.key,
                    tags: entry.value,
                  ),
                ),
              if (widget.hasSelectedTags)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: widget.onClearTags,
                    icon: const Icon(Icons.clear_all),
                    label: const Text('Clear selected tags'),
                  ),
                ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator.adaptive()),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Could not load event tags: $err'),
      ),
    );
  }

  Widget _buildTagCategorySection(
    ThemeData theme, {
    required String category,
    required List<String> tags,
  }) {
    final selectedCount = tags.where(widget.selectedTags.contains).length;
    final isHighlighted = selectedCount > 0;

    return ExpansionTile(
      key: PageStorageKey<String>('event_tag_category_$category'),
      onExpansionChanged: (value) {
        setState(() {
          if (value) {
            _expandedCategories.add(category);
          } else {
            _expandedCategories.remove(category);
          }
        });
        _markBrowseOverlayNeedsBuild();
      },
      initiallyExpanded: _expandedCategories.contains(category),
      title: Text(
        category,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: isHighlighted ? FontWeight.w700 : null,
        ),
      ),
      subtitle: selectedCount > 0 ? Text('$selectedCount selected') : null,
      childrenPadding: const EdgeInsets.only(
        left: 8,
        right: 8,
        bottom: 12,
      ),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in tags)
              FilterChip(
                label: Text(tag),
                selected: widget.selectedTags.contains(tag),
                onSelected: (selected) {
                  widget.onTagToggled(tag, selected);
                  _markBrowseOverlayNeedsBuild();
                },
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasTypeFilterApplied = widget.typeFilter != 'all';
    final selectionSummary = <String>[];
    if (hasTypeFilterApplied) {
      selectionSummary.add(
        widget.types[widget.typeFilter] ?? widget.typeFilter,
      );
    }
    if (widget.selectedTags.isNotEmpty) {
      final tagCount = widget.selectedTags.length;
      selectionSummary.add(
        '$tagCount tag${tagCount == 1 ? '' : 's'} selected',
      );
    }
    final summaryText = selectionSummary.join(' • ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isSearchFieldActive =
                (_isSearchExpanded || _searchController.text.isNotEmpty) &&
                    !_isBrowseOverlayOpen;
            final searchWidth =
                isSearchFieldActive ? constraints.maxWidth : 48.0;

            if (!isSearchFieldActive) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                final renderBox = _browseButtonKey.currentContext
                    ?.findRenderObject() as RenderBox?;
                final targetWidth = renderBox?.size.width ?? 0;
                if (targetWidth > 0 &&
                    (_browseOverlayWidth - targetWidth).abs() > 0.5) {
                  _browseOverlayWidth = targetWidth;
                  _browseOverlayEntry?.markNeedsBuild();
                }
              });
            }

            return SizedBox(
              height: 60,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    width: searchWidth,
                    child: isSearchFieldActive
                        ? TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            decoration: InputDecoration(
                              hintText: 'Search events or tags',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Clear search',
                                onPressed: () {
                                  if (_searchController.text.isNotEmpty) {
                                    _searchController.clear();
                                    widget.onSearchChanged('');
                                  }
                                  _collapseSearch();
                                },
                              ),
                            ),
                            onChanged: (value) {
                              if (!_isSearchExpanded) {
                                setState(() {
                                  _isSearchExpanded = true;
                                });
                              }
                              widget.onSearchChanged(value);
                            },
                          )
                        : _buildCollapsedSearchButton(
                            isEnabled: !_isBrowseOverlayOpen,
                          ),
                  ),
                  if (!isSearchFieldActive) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: CompositedTransformTarget(
                        link: _browseLayerLink,
                        child: SizedBox.expand(
                          key: _browseButtonKey,
                          child: _buildBrowseTriggerButton(
                            context,
                            summaryText: summaryText,
                            hasActiveFilters: hasTypeFilterApplied ||
                                widget.selectedTags.isNotEmpty,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class EventCard extends StatelessWidget {
  const EventCard({
    required this.event,
    required this.attending,
    required this.candidateLookup,
    required this.onPrimaryAction,
    required this.onOpenDetail,
    super.key,
  });

  static const double _scrollActivationHeight = 540;

  final CoalitionEvent event;
  final bool attending;
  final Map<String, Candidate> candidateLookup;
  final VoidCallback onPrimaryAction;
  final VoidCallback onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hostCandidates = event.hostCandidateIds
        .map((id) => candidateLookup[id])
        .whereType<Candidate>()
        .toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.surfaceContainerHighest.withValues(alpha: 0.96),
                colorScheme.surface,
              ],
            ),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.28),
              width: 1.2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shouldEnableScroll = constraints.maxHeight.isFinite &&
                    constraints.maxHeight < _scrollActivationHeight;
                final mainSection = _buildMainSection(
                  context,
                  theme,
                  hostCandidates,
                );
                final footerChildren = <Widget>[
                  _buildActionRow(context),
                ];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        physics: shouldEnableScroll
                            ? const ClampingScrollPhysics()
                            : const NeverScrollableScrollPhysics(),
                        child: mainSection,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ...footerChildren,
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainSection(
    BuildContext context,
    ThemeData theme,
    List<Candidate> hostCandidates,
  ) {
    final localStart = event.startDate.toLocal();
    final dateLabel = _formatDate(localStart);
    final timeLabel = _formatTime(localStart);
    final media = event.mediaUrl;

    Widget? mediaSection;
    if (media != null && media.isNotEmpty) {
      mediaSection = Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: EventMediaPreview(
          mediaUrl: media,
          mediaType: event.mediaType,
          aspectRatio: event.mediaAspectRatio ?? 16 / 9,
          coverImagePath: event.coverImagePath,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (mediaSection != null) mediaSection,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                event.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _EventPill(label: event.type),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: -6,
          children: [
            Chip(
              avatar: const Icon(Icons.calendar_today_outlined, size: 18),
              label: Text('$dateLabel • $timeLabel'),
              visualDensity: VisualDensity.compact,
            ),
            Chip(
              avatar: const Icon(Icons.confirmation_number_outlined, size: 18),
              label: Text(event.cost),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.place_outlined, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                event.location,
                style: theme.textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          event.description,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
        ),
        const SizedBox(height: 16),
        if (event.tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in event.tags)
                Chip(
                  label: Text(tag),
                ),
            ],
          ),
        if (hostCandidates.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            'Featuring',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final candidate in hostCandidates)
                _CandidateChip(candidate: candidate),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionRow(BuildContext context) {
    return Row(
      children: [
        FilledButton.icon(
          onPressed: onPrimaryAction,
          icon: Icon(attending ? Icons.check : Icons.event_available),
          label: Text(attending ? 'Attending' : 'RSVP'),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: onOpenDetail,
          icon: const Icon(Icons.arrow_forward),
          label: const Text('View details'),
        ),
      ],
    );
  }

  String _formatDate(DateTime value) {
    const weekdayNames = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final weekday = weekdayNames[value.weekday - 1];
    final month = monthNames[value.month - 1];
    return '$weekday, $month ${value.day}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

class _EventPill extends StatelessWidget {
  const _EventPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final display = label
        .replaceAll('-', ' ')
        .split(' ')
        .map((part) =>
            part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          display,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _CandidateChip extends StatelessWidget {
  const _CandidateChip({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/candidates/${candidate.id}'),
      child: Chip(
        avatar: CircleAvatar(
          child: Text(
            candidate.name.isNotEmpty
                ? candidate.name[0].toUpperCase()
                : '?',
          ),
        ),
        label: Text(candidate.name),
      ),
    );
  }
}
