import 'dart:io';

import 'package:coalition_mobile_app/features/video/services/video_permission_service.dart';
import 'package:coalition_mobile_app/features/video/views/video_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakePermissionService extends VideoPermissionService {
  @override
  Future<VideoPermissionResult> ensureGranted({
    bool requestIfDenied = true,
  }) async {
    return const VideoPermissionResult(granted: true, permanentlyDenied: false);
  }

  @override
  Future<VideoPermissionResult> ensureCameraGranted({
    bool requestIfDenied = true,
  }) async {
    return const VideoPermissionResult(granted: true, permanentlyDenied: false);
  }
}

void main() {
  testWidgets('VideoPickerPage navigates to editor after picking', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('video_picker_test');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final pickedFile = File('${tempDir.path}/input.mp4')
      ..writeAsBytesSync(List<int>.filled(8, 0));

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => VideoPickerPage(
            galleryPickerOverride: (_) async => pickedFile,
          ),
        ),
        GoRoute(
          path: '/create/video/editor',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>;
            final filePath = extra['filePath'] as String;
            return Scaffold(body: Text('Editor:$filePath'));
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoPermissionServiceProvider.overrideWithValue(_FakePermissionService()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.pump();

    await tester.tap(find.text('Pick from gallery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Editor:${pickedFile.path}'), findsOneWidget);
  });
}
