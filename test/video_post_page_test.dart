import 'dart:convert';
import 'dart:io';

import 'package:coalition_mobile_app/core/config/backend_config_loader.dart';
import 'package:coalition_mobile_app/core/config/backend_config_provider.dart';
import 'package:coalition_mobile_app/features/video/models/video_draft.dart';
import 'package:coalition_mobile_app/features/video/models/video_timeline.dart';
import 'package:coalition_mobile_app/features/video/platform/video_native.dart';
import 'package:coalition_mobile_app/features/video/providers/video_draft_provider.dart';
import 'package:coalition_mobile_app/features/video/services/mux_upload_service.dart';
import 'package:coalition_mobile_app/features/video/views/video_post_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _TestHttpClient extends http.BaseClient {
  final List<http.BaseRequest> requests = <http.BaseRequest>[];
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw StateError('Client already closed');
    }
    requests.add(request);
    final path = request.url.path;
    if (request.method == 'POST' && path.endsWith('assets/covers/presign')) {
      final payload = jsonEncode({
        'upload_url': 'https://cdn.example.com/upload.png',
        'cover_url': 'https://cdn.example.com/cover.png',
      });
      return http.StreamedResponse(
        Stream.value(utf8.encode(payload)),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.method == 'PUT') {
      return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
    }
    if (request.method == 'POST' && path.endsWith('posts')) {
      return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
    }
    return http.StreamedResponse(Stream.value(utf8.encode('{}')), 200);
  }

  @override
  void close() {
    _closed = true;
    super.close();
  }
}

class _TestMuxUploadService implements MuxUploadService {
  bool createCalled = false;
  bool uploadCalled = false;

  @override
  Future<MuxUploadTicket> createDirectUpload({
    required String filename,
    required int filesizeBytes,
    String contentType = 'video/mp4',
    bool preferTus = true,
  }) async {
    createCalled = true;
    return MuxUploadTicket(
      uploadId: 'mux-upload-1',
      method: 'POST',
      url: Uri.parse('https://uploads.example/mock'),
    );
  }

  @override
  Future<MuxUploadResult> uploadVideo({
    required MuxUploadTicket ticket,
    required File mp4,
    ProgressCallback? onProgress,
  }) async {
    uploadCalled = true;
    onProgress?.call(mp4.lengthSync(), mp4.lengthSync());
    return MuxUploadResult(
      uploadId: ticket.uploadId,
      bytesSent: mp4.lengthSync(),
    );
  }
}

class _StubVideoNative extends VideoNativeBridge {
  _StubVideoNative({required this.exportPath, required this.coverPath});

  final String exportPath;
  final String coverPath;
  int exportCalls = 0;
  int coverCalls = 0;

  @override
  Future<String> exportEdits({
    required String filePath,
    required Map<String, dynamic> timelineJson,
    required int targetBitrateBps,
  }) async {
    exportCalls += 1;
    return exportPath;
  }

  @override
  Future<String> generateCoverImage(
    String filePath, {
    required double seconds,
  }) async {
    coverCalls += 1;
    return coverPath;
  }

  @override
  Future<void> cancelExport() async {}
}

class _SeededVideoDraftsNotifier extends VideoDraftsNotifier {
  _SeededVideoDraftsNotifier(this.initialState);

  final VideoDraftState initialState;

  @override
  VideoDraftState build() => initialState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('VideoPostPage exports edits, uploads, and cleans up files',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('video_post_page_test');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    final sourcePath = '${tempDir.path}/source.mp4';
    final sourceFile = File(sourcePath)
      ..writeAsBytesSync(List<int>.filled(8, 0));
    final exportedFile = File('${tempDir.path}/export.mp4')
      ..writeAsBytesSync(List<int>.generate(16, (index) => index));
    final coverFile = File('${tempDir.path}/cover.png')
      ..writeAsBytesSync(List<int>.generate(16, (index) => 255 - index));

    final timeline = VideoTimeline(
      sourcePath: sourceFile.path,
      trimStartMs: 1000,
      trimEndMs: 5000,
      coverTimeMs: 1500,
    );

    final draft = VideoDraft(id: 'draft-1', timeline: timeline);
    final draftState = VideoDraftState(
      activeDraftId: draft.id,
      drafts: {draft.id: draft},
    );

    final native = _StubVideoNative(
      exportPath: exportedFile.path,
      coverPath: coverFile.path,
    );

    final muxService = _TestMuxUploadService();
    final httpClient = _TestHttpClient();
    addTearDown(httpClient.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          videoDraftsProvider.overrideWith(
            () => _SeededVideoDraftsNotifier(draftState),
          ),
          muxUploadServiceProvider.overrideWithValue(muxService),
          backendConfigProvider.overrideWithValue(
            BackendConfig(baseUri: Uri.parse('https://api.example.com/')),
          ),
          videoNativeProvider.overrideWithValue(native),
        ],
        child: MaterialApp(
          home: VideoPostPage(httpClientOverride: httpClient),
        ),
      ),
    );

    await tester.pump();

    final state = tester.state(find.byType(VideoPostPage)) as dynamic;

    await tester.runAsync(() async {
      await state.startMuxPostFlowForTesting(timeline);
    });

    await tester.pump();

    expect(native.exportCalls, 1);
    expect(native.coverCalls, greaterThanOrEqualTo(1));
    expect(muxService.createCalled, isTrue);
    expect(muxService.uploadCalled, isTrue);

    final presignRequests = httpClient.requests.where(
      (request) =>
          request.method == 'POST' &&
          request.url.path.endsWith('assets/covers/presign'),
    );
    expect(presignRequests.length, 1);

    final putRequests =
        httpClient.requests.where((request) => request.method == 'PUT');
    expect(putRequests.length, 1);

    expect(sourceFile.existsSync(), isFalse);
    expect(exportedFile.existsSync(), isFalse);
    expect(coverFile.existsSync(), isFalse);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(VideoPostPage)),
      listen: false,
    );
    expect(container.read(activeVideoTimelineProvider), isNull);
  });
}
