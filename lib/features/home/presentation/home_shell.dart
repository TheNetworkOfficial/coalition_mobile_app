import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../auth/data/auth_controller.dart';

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLocation = state.uri.toString();
    final currentIndex = _destinations.indexWhere(
      (dest) => currentLocation.startsWith(dest.route),
    );
    final fallbackIndex = currentIndex >= 0 ? currentIndex : 0;
    final authState = ref.watch(authControllerProvider);
    final isAdmin = authState.user?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Coalition for Montana'),
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
        selectedIndex: fallbackIndex,
        onDestinationSelected: (index) {
          final destination = _destinations[index];
          context.go(destination.route);
        },
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}

class _HomeDestination {
  const _HomeDestination(this.label, this.icon, this.route);

  final String label;
  final IconData icon;
  final String route;
}
