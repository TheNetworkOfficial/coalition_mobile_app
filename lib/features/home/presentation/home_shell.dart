import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({
    required this.state,
    required this.child,
    super.key,
  });

  final GoRouterState state;
  final Widget child;

  static const _destinations = [
    _HomeDestination('Feed', Icons.dynamic_feed_outlined, '/feed'),
    _HomeDestination('Candidates', Icons.people_alt_outlined, '/candidates'),
    _HomeDestination('Events', Icons.event_outlined, '/events'),
    _HomeDestination('Profile', Icons.person_outline, '/profile'),
  ];

  static const _createDestinationIndex = 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocation = state.uri.toString();
    final currentIndex = _destinations.indexWhere(
      (dest) => currentLocation.startsWith(dest.route),
    );
    final fallbackIndex = currentIndex >= 0 ? currentIndex : 0;
    final authState = ref.watch(authControllerProvider);
    final isAdmin = authState.user?.isAdmin ?? false;
    final isProfile = currentLocation.startsWith('/profile');
    final userAccountType = authState.user?.accountType;
    final canCreateEvents = userAccountType == UserAccountType.candidate;
    final createLabel = canCreateEvents ? 'Post or event' : 'Post';

    final title = switch (fallbackIndex) {
      0 => 'Coalition Feed',
      1 => 'Candidates',
      2 => 'Events',
      _ => 'Coalition for Montana',
    };

    return Scaffold(
      appBar: isProfile
          ? null
          : AppBar(
              title: Text(title),
              actions: [
                if (isAdmin)
                  IconButton(
                    onPressed: () => context.push('/admin'),
                    icon: const Icon(Icons.shield_outlined),
                    tooltip: 'Admin dashboard',
                  ),
              ],
            ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndexWithCreate(fallbackIndex),
        destinations: _buildDestinations(createLabel),
        onDestinationSelected: (index) {
          if (index == _createDestinationIndex) {
            _openCreateSheet(context, canCreateEvents: canCreateEvents);
            return;
          }
          final navIndex = index > _createDestinationIndex ? index - 1 : index;
          final destination = _destinations[navIndex];
          context.go(destination.route);
        },
      ),
    );
  }

  static int _selectedIndexWithCreate(int fallbackIndex) {
    if (fallbackIndex >= _createDestinationIndex) {
      return fallbackIndex + 1;
    }
    return fallbackIndex;
  }

  List<NavigationDestination> _buildDestinations(String createLabel) {
    final destinations = <NavigationDestination>[];
    for (var i = 0; i < _destinations.length; i++) {
      if (i == _createDestinationIndex) {
        destinations.add(
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline, size: 30),
            selectedIcon: const Icon(Icons.add_circle, size: 30),
            label: 'Create',
            tooltip: createLabel,
          ),
        );
      }
      final destination = _destinations[i];
      destinations.add(
        NavigationDestination(
          icon: Icon(destination.icon),
          label: destination.label,
        ),
      );
    }
    return destinations;
  }

  void _openCreateSheet(
    BuildContext context, {
    required bool canCreateEvents,
  }) {
    showModalBottomSheet<_CreateAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final options = <_CreateAction>[_CreateAction.post];
        if (canCreateEvents) {
          options.add(_CreateAction.event);
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final action in options)
                ListTile(
                  leading: Icon(
                    action == _CreateAction.post
                        ? Icons.movie_creation_outlined
                        : Icons.event_available_outlined,
                  ),
                  title: Text(
                    action == _CreateAction.post
                        ? 'Create post'
                        : 'Create event',
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop(action);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    ).then((action) {
      if (!context.mounted || action == null) {
        return;
      }
      switch (action) {
        case _CreateAction.post:
          context.push('/create/post');
          break;
        case _CreateAction.event:
          context.push('/create/event');
          break;
      }
    });
  }
}

class _HomeDestination {
  const _HomeDestination(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}

enum _CreateAction { post, event }
