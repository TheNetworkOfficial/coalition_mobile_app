import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_controller.dart';
import '../data/candidate_providers.dart';
import '../domain/candidate.dart';

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

class CandidateListScreen extends ConsumerStatefulWidget {
  const CandidateListScreen({this.tag, super.key});

  static const routeName = 'candidates';

  final String? tag;

  @override
  ConsumerState<CandidateListScreen> createState() =>
      _CandidateListScreenState();
}

class _CandidateListScreenState extends ConsumerState<CandidateListScreen> {
  static const _levels = <String, String>{
    'all': 'All levels',
    'federal': 'Federal',
    'state': 'State',
    'county': 'County',
    'city': 'City',
  };

  String _searchTerm = '';
  String _levelFilter = 'all';
  final Set<String> _selectedTags = <String>{};
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    if (widget.tag != null) {
      _selectedTags.add(widget.tag!);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final candidatesAsync = ref.watch(candidateListProvider);
    final tagsAsync = ref.watch(candidateTagsProvider);
    final authState = ref.watch(authControllerProvider);

    return RefreshIndicator(
      onRefresh: () async {
        // Placeholder for real refresh logic when API is connected.
        await Future<void>.delayed(const Duration(milliseconds: 500));
      },
      child: NestedScrollView(
        physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics()),
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: _FilterSection(
                searchTerm: _searchTerm,
                onSearchChanged: (value) {
                  setState(() => _searchTerm = value);
                  _resetPager();
                },
                levelFilter: _levelFilter,
                onLevelChanged: (value) {
                  if (value == null) return;
                  setState(() => _levelFilter = value);
                  _resetPager();
                },
                levels: _levels,
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
          child: candidatesAsync.when(
            data: (candidates) {
              final filtered = _filterCandidates(
                candidates,
                searchTerm: _searchTerm,
                level: _levelFilter,
                tags: _selectedTags,
              );

              if (filtered.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No candidates matched those filters yet. Try adjusting your search or tag filters.',
                      style: Theme.of(context).textTheme.bodyLarge,
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
                    final candidate = filtered[index];
                    final isFollowing = authState.user?.followedCandidateIds
                            .contains(candidate.id) ??
                        false;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: CandidateCard(
                        candidate: candidate,
                        isFollowing: isFollowing,
                        onFollowToggle: () {
                          ref
                              .read(authControllerProvider.notifier)
                              .toggleFollowCandidate(candidate.id);
                        },
                        onOpenProfile: () =>
                            context.push('/candidates/${candidate.id}'),
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
              child: Text('Could not load candidates: $err'),
            ),
          ),
        ),
      ),
    );
  }

  List<Candidate> _filterCandidates(
    List<Candidate> candidates, {
    required String searchTerm,
    required String level,
    required Set<String> tags,
  }) {
    return candidates.where((candidate) {
      if (level != 'all' && candidate.level != level) return false;
      if (tags.isNotEmpty) {
        final matchesAll = tags.every(candidate.tags.contains);
        if (!matchesAll) return false;
      }
      if (searchTerm.isEmpty) return true;
      final haystack = [
        candidate.name,
        candidate.region,
        candidate.bio,
        candidate.tags.join(' '),
      ].join(' ').toLowerCase();
      return haystack.contains(searchTerm.toLowerCase());
    }).toList();
  }

  void _resetPager() {
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }
}

class _FilterSection extends StatefulWidget {
  const _FilterSection({
    required this.searchTerm,
    required this.onSearchChanged,
    required this.levelFilter,
    required this.onLevelChanged,
    required this.levels,
    required this.hasSelectedTags,
    required this.onClearTags,
    required this.tagsAsync,
    required this.selectedTags,
    required this.onTagToggled,
  });

  final String searchTerm;
  final ValueChanged<String> onSearchChanged;
  final String levelFilter;
  final ValueChanged<String?> onLevelChanged;
  final Map<String, String> levels;
  final bool hasSelectedTags;
  final VoidCallback onClearTags;
  final AsyncValue<List<String>> tagsAsync;
  final Set<String> selectedTags;
  final void Function(String tag, bool selected) onTagToggled;

  @override
  State<_FilterSection> createState() => _FilterSectionState();
}

class _FilterSectionState extends State<_FilterSection> {
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
  void didUpdateWidget(covariant _FilterSection oldWidget) {
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
          tooltip: 'Search candidates or priorities',
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
    const placeholderText = 'Filter by government level or focus area tags';
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
                        'Browse by focus area',
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
        CompositedTransformFollower(
          link: _browseLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 8),
          child: SizedBox(
            width: width,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              color: theme.colorScheme.surface,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: _buildBrowseOverlayBody(theme),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrowseOverlayBody(ThemeData theme) {
    final scrollable = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownMenu<String>(
            initialSelection: widget.levelFilter,
            label: const Text('Government level'),
            expandedInsets: EdgeInsets.zero,
            dropdownMenuEntries: [
              for (final entry in widget.levels.entries)
                DropdownMenuEntry<String>(
                  value: entry.key,
                  label: entry.value,
                ),
            ],
            onSelected: (value) {
              if (value == null) return;
              widget.onLevelChanged(value);
              _markBrowseOverlayNeedsBuild();
            },
          ),
          const SizedBox(height: 16),
          _buildTagsSection(theme),
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: scrollable),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: FilledButton.tonal(
            onPressed: widget.hasSelectedTags
                ? () {
                    widget.onClearTags();
                    _markBrowseOverlayNeedsBuild();
                  }
                : null,
            child: const Text('Clear tags'),
          ),
        ),
      ],
    );
  }

  Widget _buildTagsSection(ThemeData theme) {
    return widget.tagsAsync.when(
      data: (tags) {
        if (tags.isEmpty) {
          return Text(
            'Tag filters will appear here once candidates are tagged.',
            style: theme.textTheme.bodySmall,
          );
        }
        final grouped = _groupTagsByCategory(tags);
        final selectedCategories = widget.selectedTags
            .map((tag) => _tagCategoryLookup[tag] ?? _fallbackCategoryLabel)
            .toSet();
        final effectiveExpanded = {
          ..._expandedCategories,
          ...selectedCategories,
        };
        return Theme(
          data: theme.copyWith(
            dividerColor: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in grouped.entries)
                _buildTagCategoryTile(
                  theme,
                  category: entry.key,
                  tags: entry.value,
                  initiallyExpanded: effectiveExpanded.contains(entry.key),
                ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator.adaptive()),
      ),
      error: (err, _) => Text(
        'Failed to load tags: $err',
        style: theme.textTheme.bodySmall,
      ),
    );
  }

  Widget _buildTagCategoryTile(
    ThemeData theme, {
    required String category,
    required List<String> tags,
    required bool initiallyExpanded,
  }) {
    final selectedCount = tags.where(widget.selectedTags.contains).length;
    final isHighlighted = selectedCount > 0;
    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('category-$category-$initiallyExpanded'),
        tilePadding: EdgeInsets.zero,
        maintainState: true,
        initiallyExpanded: initiallyExpanded,
        onExpansionChanged: (expanded) {
          setState(() {
            if (expanded) {
              _expandedCategories.add(category);
            } else {
              _expandedCategories.remove(category);
            }
          });
          _markBrowseOverlayNeedsBuild();
        },
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasLevelFilterApplied = widget.levelFilter != 'all';
    final selectionSummary = <String>[];
    if (hasLevelFilterApplied) {
      selectionSummary.add(
        widget.levels[widget.levelFilter] ?? widget.levelFilter,
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
                              hintText: 'Search candidates or priorities',
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
                            hasActiveFilters: hasLevelFilterApplied ||
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
        const SizedBox(height: 16),
        const _FollowedTagsBar(),
      ],
    );
  }
}

class CandidateCard extends StatelessWidget {
  const CandidateCard({
    required this.candidate,
    required this.isFollowing,
    required this.onFollowToggle,
    required this.onOpenProfile,
    super.key,
  });

  static const double _scrollActivationHeight = 540;

  final Candidate candidate;
  final bool isFollowing;
  final VoidCallback onFollowToggle;
  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
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
                final mainSection = _buildMainSection(context, theme);
                final socialRow = _buildSocialLinksRow(context);
                final footerChildren = <Widget>[
                  if (socialRow != null) ...[
                    socialRow,
                    const SizedBox(height: 16),
                  ],
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

  Widget _buildMainSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CandidateAvatar(candidate: candidate),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          candidate.name,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            height: 1.1,
                          ),
                        ),
                      ),
                      if (candidate.isVerified)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Icon(
                            Icons.verified,
                            color: Colors.blue.shade500,
                            size: 22,
                            semanticLabel: 'Verified candidate',
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: -6,
                    children: [
                      Chip(
                        label: Text(_levelLabel(candidate.level)),
                        visualDensity: VisualDensity.compact,
                      ),
                      Chip(
                        label: Text(candidate.region),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (candidate.pronouns != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        candidate.pronouns!,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    candidate.bio,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (candidate.isCoalitionMember ||
                candidate.isNonCoalitionMember) ...[
              const SizedBox(width: 12),
              _MembershipBadge(candidate: candidate),
            ],
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in candidate.tags)
              InputChip(
                label: Text(tag),
                onPressed: () => context.push(
                  '/candidates/${candidate.id}',
                  extra: {'highlightTag': tag},
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget? _buildSocialLinksRow(BuildContext context) {
    if (candidate.socialLinks.isEmpty) {
      return null;
    }

    final theme = Theme.of(context);

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        for (final link in candidate.socialLinks)
          Tooltip(
            message: link.label,
            child: IconButton(
              onPressed: () {
                // Launching URLs will be wired up when deep links are enabled.
              },
              icon: Icon(_iconForSocialLabel(link.label)),
              iconSize: 28,
              color: _colorForSocialLabel(theme, link.label),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: onFollowToggle,
            icon: Icon(isFollowing ? Icons.check : Icons.add),
            label: Text(
              isFollowing ? 'Following candidate' : 'Follow candidate',
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton(
            onPressed: onOpenProfile,
            child: const Text('Open profile'),
          ),
        ),
      ],
    );
  }

  IconData _iconForSocialLabel(String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('instagram')) return Icons.camera_alt;
    if (normalized.contains('facebook')) return Icons.facebook;
    if (normalized.contains('twitter') || normalized.contains('x')) {
      return Icons.alternate_email;
    }
    if (normalized.contains('threads')) return Icons.chat_bubble;
    if (normalized.contains('tiktok')) return Icons.music_note;
    if (normalized.contains('youtube')) return Icons.ondemand_video;
    if (normalized.contains('website') || normalized.contains('campaign')) {
      return Icons.link;
    }
    return Icons.public;
  }

  Color _colorForSocialLabel(ThemeData theme, String label) {
    final normalized = label.toLowerCase();
    if (normalized.contains('instagram')) return Colors.pinkAccent;
    if (normalized.contains('facebook')) return const Color(0xFF1877F2);
    if (normalized.contains('twitter') || normalized.contains('x')) {
      return Colors.lightBlue;
    }
    if (normalized.contains('threads')) return Colors.black87;
    if (normalized.contains('tiktok')) return Colors.black;
    if (normalized.contains('youtube')) return Colors.redAccent;
    return theme.colorScheme.primary;
  }

  String _levelLabel(String level) {
    return {
          'federal': 'Federal',
          'state': 'State',
          'county': 'County',
          'city': 'City',
        }[level] ??
        'Community';
  }
}

class _CandidateAvatar extends StatelessWidget {
  const _CandidateAvatar({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final placeholder =
        Text(candidate.name.isNotEmpty ? candidate.name[0].toUpperCase() : '?');
    final borderRadius = BorderRadius.circular(16);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: 92,
        height: 92,
        child: candidate.headshotUrl != null
            ? Image.network(
                candidate.headshotUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (context, error, stackTrace) => _AvatarFallback(
                  placeholder: placeholder,
                ),
              )
            : _AvatarFallback(placeholder: placeholder),
      ),
    );
  }
}

class _MembershipBadge extends StatelessWidget {
  const _MembershipBadge({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final isCoalition = candidate.isCoalitionMember;
    final color =
        isCoalition ? const Color(0xFFFBC02D) : const Color(0xFFE53935);
    final icon = isCoalition ? Icons.workspace_premium : Icons.gpp_bad;
    final label = isCoalition ? 'Coalition member' : 'Non-coalition candidate';

    return Tooltip(
      message: label,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.16),
          border: Border.all(color: color.withValues(alpha: 0.7), width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 26,
          color: color,
        ),
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback({required this.placeholder});

  final Widget placeholder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Center(child: placeholder),
    );
  }
}

class _FollowedTagsBar extends ConsumerWidget {
  const _FollowedTagsBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    if (user == null || user.followedTags.isEmpty) {
      return Text(
        'Follow tags from candidate profiles to personalize your feed.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tags you follow',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final tag in user.followedTags)
              InputChip(
                label: Text(tag),
                avatar: const Icon(Icons.tag, size: 16),
                onPressed: () =>
                    context.go('/candidates?tag=${Uri.encodeComponent(tag)}'),
                onDeleted: () {
                  ref
                      .read(authControllerProvider.notifier)
                      .toggleFollowTag(tag);
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Tap a tag to filter, or remove it with the close icon.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
