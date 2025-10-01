// removed unused dart:ui import

import 'package:coalition_mobile_app/features/video/platform/video_native.dart';
import 'package:coalition_mobile_app/features/video/providers/video_timeline_provider.dart';
import 'package:coalition_mobile_app/features/video/views/video_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:video_editor/video_editor.dart';
import 'package:video_editor/src/models/cover_data.dart';
import 'package:video_player/video_player.dart';

class _MockVideoEditorController extends Mock
    implements VideoEditorController {}

class _MockVideoPlayerController extends Mock
    implements VideoPlayerController {}

class _StubVideoNative extends VideoNativeBridge {
  int coverCalls = 0;

  @override
  Future<void> cancelExport() async {}

  @override
  Future<void> persistUriPermission(String uri, {int intentFlags = 0}) async {}

  @override
  Future<String> exportEdits({
    required String filePath,
    required Map<String, dynamic> timelineJson,
    required int targetBitrateBps,
  }) async =>
      '';

  @override
  Future<String> generateCoverImage(String filePath,
      {required double seconds}) async {
    coverCalls += 1;
    return 'cover.png';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(const VideoPlayerValue.uninitialized());
    registerFallbackValue(const Rect.fromLTRB(0, 0, 1, 1));
  });

  testWidgets('VideoEditorPage updates timeline provider on controller changes',
      (tester) async {
    final mockController = _MockVideoEditorController();
    final mockVideo = _MockVideoPlayerController();
    final coverNotifier = ValueNotifier<CoverData?>(const CoverData(timeMs: 0));
    final listeners = <VoidCallback>[];

    when(() => mockController.initialize()).thenAnswer((_) async {});
    when(() => mockController.dispose()).thenAnswer((_) async {});

    int currentDurationMs = 16_000;
    double currentMinTrim = 0.0;
    double currentMaxTrim = 1.0;
    Offset currentMinCrop = Offset.zero;
    Offset currentMaxCrop = const Offset(1, 1);

    when(() => mockController.videoDuration)
        .thenAnswer((_) => Duration(milliseconds: currentDurationMs));
    // The video_editor package expects additional properties on the
    // VideoEditorController; ensure mocks return non-null values for them.
    when(() => mockController.maxDuration)
        .thenAnswer((_) => Duration(milliseconds: currentDurationMs));
    when(() => mockController.isRotated).thenReturn(false);
    when(() => mockController.minTrim).thenAnswer((_) => currentMinTrim);
    when(() => mockController.maxTrim).thenAnswer((_) => currentMaxTrim);
    when(() => mockController.minCrop).thenAnswer((_) => currentMinCrop);
    when(() => mockController.maxCrop).thenAnswer((_) => currentMaxCrop);
    when(() => mockController.initialized).thenReturn(true);
    when(() => mockController.isPlaying).thenReturn(false);
    // Additional properties used by video_editor widgets
    when(() => mockController.startTrim).thenReturn(Duration.zero);
    when(() => mockController.cacheRotation).thenReturn(0);
    when(() => mockController.endTrim)
        .thenReturn(Duration(milliseconds: currentDurationMs));
    when(() => mockController.cacheMinCrop).thenAnswer((_) => currentMinCrop);
    when(() => mockController.cacheMaxCrop).thenAnswer((_) => currentMaxCrop);
    when(() => mockController.video).thenReturn(mockVideo);
    when(() => mockController.selectedCoverNotifier).thenReturn(coverNotifier);
    when(() => mockController.selectedCoverVal)
        .thenAnswer((_) => coverNotifier.value);
    when(() => mockController.addListener(any())).thenAnswer((invocation) {
      final listener = invocation.positionalArguments.first as VoidCallback;
      listeners.add(listener);
    });
    when(() => mockController.removeListener(any())).thenAnswer((invocation) {
      final listener = invocation.positionalArguments.first as VoidCallback;
      listeners.remove(listener);
    });

    when(() => mockVideo.value).thenReturn(VideoPlayerValue(
      duration: Duration(milliseconds: currentDurationMs),
      size: const Size(1080, 1920),
      position: Duration.zero,
      isPlaying: false,
    ));
    when(() => mockVideo.setLooping(true)).thenAnswer((_) async {});
    when(() => mockVideo.play()).thenAnswer((_) async {});
    when(() => mockVideo.pause()).thenAnswer((_) async {});
    when(() => mockVideo.setPlaybackSpeed(any<double>()))
        .thenAnswer((_) async {});

    final native = _StubVideoNative();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [videoNativeProvider.overrideWithValue(native)],
        child: MaterialApp(
          home: VideoEditorPage(
            filePath: 'ignored.mp4',
            controllerFactory: () => mockController,
            skipHeavyWidgets: true,
          ),
        ),
      ),
    );

    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(VideoEditorPage)),
      listen: false,
    );

    expect(container.read(videoTimelineProvider).trimEndMs, currentDurationMs);

    currentMinTrim = 0.25;
    currentMaxTrim = 0.75;
    for (final listener in List<VoidCallback>.from(listeners)) {
      listener();
    }
    await tester.pump();

    final timelineAfterTrim = container.read(videoTimelineProvider);
    expect(timelineAfterTrim.trimStartMs, 4000);
    expect(timelineAfterTrim.trimEndMs, 12_000);

    currentMinCrop = const Offset(0.1, 0.2);
    currentMaxCrop = const Offset(0.9, 0.8);
    for (final listener in List<VoidCallback>.from(listeners)) {
      listener();
    }
    await tester.pump();

    final timelineAfterCrop = container.read(videoTimelineProvider);
    expect(timelineAfterCrop.cropRect, const Rect.fromLTRB(0.1, 0.2, 0.9, 0.8));

    coverNotifier.value = const CoverData(timeMs: 5000);
    coverNotifier.notifyListeners();
    await tester.pump();

    final timelineAfterCover = container.read(videoTimelineProvider);
    expect(timelineAfterCover.coverTimeMs, 5000);
    expect(native.coverCalls, greaterThan(0));
  });
}
