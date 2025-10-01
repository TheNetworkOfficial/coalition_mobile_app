import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({
    required this.state,
    required this.child,
    super.key,
  });

  final GoRouterState state;
  final Widget child;

  static const _destinations = [
    _HomeDestination('Candidates', Icons.people_alt_outlined, '/candidates'),
    _HomeDestination('Events', Icons.event_outlined, '/events'),
    _HomeDestination('Profile', Icons.person_outline, '/profile'),
  ];

  static const _createDestinationIndex = 1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocation = state.uri.toString();
    final currentIndex = _destinations.indexWhere(
      (dest) => currentLocation.startsWith(dest.route),
    );
    final fallbackIndex = currentIndex >= 0 ? currentIndex : 0;
    final isProfile = currentLocation.startsWith('/profile');

    final title = switch (fallbackIndex) {
      0 => 'Candidates',
      1 => 'Events',
      2 => 'Profile',
      _ => 'Coalition for Montana',
    };

    return Scaffold(
      appBar: isProfile
          ? null
          : AppBar(
              title: Text(title),
            ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndexWithCreate(fallbackIndex),
        destinations: _buildDestinations(),
        onDestinationSelected: (index) {
          if (index == _createDestinationIndex) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Creation tools are coming soon.'),
              ),
            );
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

  List<NavigationDestination> _buildDestinations() {
    final destinations = <NavigationDestination>[];
    for (var i = 0; i < _destinations.length; i++) {
      if (i == _createDestinationIndex) {
        destinations.add(
          NavigationDestination(
            icon: const Icon(Icons.add_circle_outline, size: 30),
            selectedIcon: const Icon(Icons.add_circle, size: 30),
            label: 'Create',
            tooltip: 'Create',
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
}

class _HomeDestination {
  const _HomeDestination(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}
