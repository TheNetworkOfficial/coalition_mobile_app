import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/auth/data/auth_controller.dart';
import '../../features/auth/presentation/auth_gate.dart';
import '../../features/candidates/presentation/candidate_detail_screen.dart';
import '../../features/candidates/presentation/candidate_list_screen.dart';
import '../../features/create/presentation/create_event_screen.dart';
import '../../features/create/presentation/create_post_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/events/presentation/event_detail_screen.dart';
import '../../features/events/presentation/events_feed_screen.dart';
import '../../features/home/presentation/home_shell.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/video/views/video_editor_page.dart';
import '../../features/video/views/video_picker_page.dart';
import '../../features/video/views/video_post_page.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'section-shell');

final goRouterProvider = Provider<GoRouter>((ref) {
  final authSnapshot = ref.watch(
    authControllerProvider.select(
      (state) => (state.user?.id, state.user?.isAdmin ?? false),
    ),
  );
  final isAuthenticated = authSnapshot.$1 != null;
  final isAdmin = authSnapshot.$2;

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/auth',
    debugLogDiagnostics: false,
    refreshListenable: GoRouterRefreshStream(
        ref.watch(authControllerProvider.notifier).stream),
    redirect: (context, state) {
      final loggingIn = state.matchedLocation == '/auth';
      final viewingAdmin = state.matchedLocation == '/admin';

      if (!isAuthenticated && !loggingIn) {
        return '/auth';
      }

      if (isAuthenticated && loggingIn) {
        return '/feed';
      }

      if (viewingAdmin && !isAdmin) {
        return '/candidates';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/auth',
        builder: (context, state) => const AuthGate(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => HomeShell(
          state: state,
          child: child,
        ),
        routes: [
          GoRoute(
            path: '/feed',
            name: FeedScreen.routeName,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: FeedScreen(),
            ),
          ),
          GoRoute(
            path: '/candidates',
            name: CandidateListScreen.routeName,
            pageBuilder: (context, state) => NoTransitionPage(
              child: CandidateListScreen(tag: state.uri.queryParameters['tag']),
            ),
          ),
          GoRoute(
            path: '/events',
            name: EventsFeedScreen.routeName,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: EventsFeedScreen(),
            ),
          ),
          GoRoute(
            path: '/profile',
            name: ProfileScreen.routeName,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ProfileScreen(),
            ),
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/candidates/:id',
        name: CandidateDetailScreen.routeName,
        builder: (context, state) {
          final candidateId = state.pathParameters['id']!;
          return CandidateDetailScreen(candidateId: candidateId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/events/:id',
        name: EventDetailScreen.routeName,
        builder: (context, state) {
          final eventId = state.pathParameters['id']!;
          return EventDetailScreen(eventId: eventId);
        },
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/create/post',
        name: CreatePostScreen.routeName,
        builder: (context, state) => const CreatePostScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/create/event',
        name: CreateEventScreen.routeName,
        builder: (context, state) => const CreateEventScreen(),
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/create/video',
        name: VideoPickerPage.routeName,
        builder: (context, state) => const VideoPickerPage(),
        routes: [
          GoRoute(
            path: 'editor',
            name: VideoEditorPage.routeName,
            builder: (context, state) {
              final extra = state.extra;
              final filePath = extra is Map<String, dynamic>
                  ? extra['filePath'] as String?
                  : null;
              if (filePath == null || filePath.isEmpty) {
                return const Scaffold(
                  body: Center(child: Text('Select a video to edit.')),
                );
              }
              return VideoEditorPage(filePath: filePath);
            },
          ),
          GoRoute(
            path: 'post',
            name: VideoPostPage.routeName,
            builder: (context, state) {
              final extra = state.extra;
              if (extra is Map<String, dynamic>) {
                final filePath = extra['filePath'] as String? ?? '';
                final timelineJson =
                    (extra['timelineJson'] as Map<String, dynamic>?) ?? const {};
                final coverPath = extra['coverPath'] as String?;
                if (filePath.isEmpty || timelineJson.isEmpty) {
                  return const Scaffold(
                    body: Center(child: Text('Missing video context.')),
                  );
                }
                return VideoPostPage(
                  filePath: filePath,
                  timelineJson: timelineJson,
                  coverPath: coverPath,
                );
              }
              return const Scaffold(
                body: Center(child: Text('Missing video context.')),
              );
            },
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: _rootNavigatorKey,
        path: '/admin',
        name: AdminDashboardScreen.routeName,
        builder: (context, state) => const AdminDashboardScreen(),
      ),
    ],
  );
});

class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
