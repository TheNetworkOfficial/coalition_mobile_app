import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/video_draft.dart';
import '../models/video_timeline.dart';
import '../platform/video_native.dart';

class VideoDraftsNotifier extends Notifier<VideoDraftState> {
  VideoDraftsNotifier();

  static final Uuid _uuid = Uuid();
  Directory? _cachedDraftDirectory;

  @override
  VideoDraftState build() => const VideoDraftState();

  Future<VideoDraft> createDraftFromXFile(XFile pickedFile) async {
    await clearActiveDraft(deleteAssets: true);

    final draftId = _uuid.v4();
    final destination = await _resolveDestinationPath(
      draftId: draftId,
      preferredExtension: _extensionFor(pickedFile),
    );

    await _persistXFile(pickedFile, destination);

    final draft = VideoDraft(
      id: draftId,
      timeline: VideoTimeline.initial(destination),
    );

    _upsertDraft(draft, setActive: true);
    return draft;
  }

  void setActiveDraft(String? draftId) {
    if (draftId == null) {
      return;
    }
    if (!state.drafts.containsKey(draftId)) {
      return;
    }
    if (state.activeDraftId == draftId) {
      return;
    }
    state = state.copyWith(activeDraftId: draftId);
  }

  void updateTimeline(VideoTimeline timeline) {
    final active = state.activeDraft;
    if (active == null) {
      return;
    }
    _upsertDraft(active.copyWith(timeline: timeline));
  }

  void updateTrim({int? startMs, int? endMs}) {
    final active = state.activeDraft;
    if (active == null) {
      return;
    }
    final current = active.timeline;
    final updated = current.copyWith(
      trimStartMs: startMs ?? current.trimStartMs,
      trimEndMs: endMs ?? current.trimEndMs,
    );
    _upsertDraft(active.copyWith(timeline: updated));
  }

  void setCoverTime(int timeMs) {
    final active = state.activeDraft;
    if (active == null) {
      return;
    }
    final updated = active.timeline.copyWith(coverTimeMs: timeMs);
    _upsertDraft(active.copyWith(timeline: updated));
  }

  Future<void> generateCover({required int timeMs}) async {
    final active = state.activeDraft;
    if (active == null) {
      return;
    }

    final native = ref.read(videoNativeProvider);
    final seconds = timeMs / 1000;

    final newPath = await native.generateCoverImage(
      active.sourcePath,
      seconds: seconds,
    );

    final previousCover = active.timeline.coverImagePath;
    if (previousCover != null && previousCover != newPath) {
      await _deleteIfExists(previousCover);
    }

    final updatedTimeline = active.timeline.copyWith(
      coverTimeMs: timeMs,
      coverImagePath: newPath,
    );

    _upsertDraft(active.copyWith(timeline: updatedTimeline));
  }

  void resetTimeline() {
    final active = state.activeDraft;
    if (active == null) {
      return;
    }
    final reset = VideoTimeline.initial(active.sourcePath);
    _upsertDraft(active.copyWith(timeline: reset));
  }

  Future<void> clearActiveDraft({bool deleteAssets = true}) async {
    final activeId = state.activeDraftId;
    if (activeId == null) {
      return;
    }
    await removeDraft(activeId, deleteAssets: deleteAssets);
  }

  Future<void> removeDraft(String draftId, {bool deleteAssets = true}) async {
    final draft = state.drafts[draftId];
    if (draft == null) {
      return;
    }

    final updatedDrafts = Map<String, VideoDraft>.from(state.drafts)
      ..remove(draftId);
    state = state.copyWith(
      drafts: updatedDrafts,
      activeDraftId:
          state.activeDraftId == draftId ? null : state.activeDraftId,
    );

    if (!deleteAssets) {
      return;
    }

    await _deleteIfExists(draft.sourcePath);
    final cover = draft.timeline.coverImagePath;
    if (cover != null && cover.isNotEmpty) {
      await _deleteIfExists(cover);
    }
  }

  void _upsertDraft(VideoDraft draft, {bool setActive = false}) {
    final updatedDrafts = Map<String, VideoDraft>.from(state.drafts)
      ..[draft.id] = draft;

    state = state.copyWith(
      drafts: updatedDrafts,
      activeDraftId: setActive ? draft.id : state.activeDraftId,
    );
  }

  Future<String> _resolveDestinationPath({
    required String draftId,
    required String preferredExtension,
  }) async {
    final directory = await _ensureDraftDirectory();
    return p.join(directory.path, '$draftId$preferredExtension');
  }

  Future<Directory> _ensureDraftDirectory() async {
    final cached = _cachedDraftDirectory;
    if (cached != null) {
      return cached;
    }

    final supportDir = await getApplicationSupportDirectory();
    final draftsDir = Directory(p.join(supportDir.path, 'video_drafts'));
    await draftsDir.create(recursive: true);
    _cachedDraftDirectory = draftsDir;
    return draftsDir;
  }

  Future<void> _persistXFile(XFile source, String destination) async {
    debugPrint(
        'Persisting picked video: name=${source.name} path=${source.path} -> $destination');

    // Inspect the source path so logs show if the XFile is a content:// URI
    // or a normal filesystem path. This helps diagnose emulator/permission
    // issues where the picked file isn't accessible by traditional File APIs.
    try {
      final srcPath = source.path;
      if (srcPath.isEmpty) {
        debugPrint(
            'Picked XFile has empty path (likely platform-stream backed).');
      } else if (srcPath.startsWith('content://')) {
        debugPrint(
            'Picked XFile path appears to be a content:// URI: $srcPath');
      } else {
        final srcFile = File(srcPath);
        final exists = await srcFile.exists();
        debugPrint('Picked XFile local file exists: $exists at $srcPath');
      }
    } catch (e) {
      debugPrint('Error while inspecting picked file path: $e');
    }

    Future<void> _copyByStream(XFile src, String dest) async {
      // Use streaming copy to avoid loading large video into memory and to
      // support content:// URIs backed by platform streams.
      final inStream = src.openRead();
      final outFile = File(dest);
      final sink = outFile.openWrite();
      try {
        await for (final chunk in inStream) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
    }

    try {
      await source.saveTo(destination);
    } on UnsupportedError catch (e) {
      debugPrint('saveTo unsupported, falling back to stream copy: $e');
      await _copyByStream(source, destination);
    } on PlatformException catch (e) {
      debugPrint(
          'saveTo threw PlatformException, falling back to stream copy: ${e.message}');
      await _copyByStream(source, destination);
    } catch (error) {
      // As a last-resort attempt, try streaming. If this also fails, surface
      // the original error to the caller.
      debugPrint(
          'saveTo failed with unexpected error: $error; trying stream fallback');
      try {
        await _copyByStream(source, destination);
      } catch (streamError) {
        debugPrint('stream fallback also failed: $streamError');
        rethrow;
      }
    }

    if (!await File(destination).exists()) {
      final msg =
          'Persisted video missing at expected destination: $destination';
      debugPrint(msg);
      throw FileSystemException(msg, destination);
    }
  }

  Future<void> _deleteIfExists(String path) async {
    if (path.isEmpty) {
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {
        // Best-effort cleanup; ignore errors.
      }
    }
  }

  String _extensionFor(XFile file) {
    String? candidate;
    if (file.name.contains('.')) {
      candidate = file.name.substring(file.name.lastIndexOf('.'));
    } else if (file.path.contains('.')) {
      candidate = file.path.substring(file.path.lastIndexOf('.'));
    }

    if (candidate == null || candidate.isEmpty || candidate.length > 10) {
      return '.mp4';
    }
    if (!candidate.startsWith('.')) {
      return '.$candidate';
    }
    return candidate;
  }
}

final videoDraftsProvider =
    NotifierProvider<VideoDraftsNotifier, VideoDraftState>(
  VideoDraftsNotifier.new,
);

final activeVideoDraftProvider = Provider<VideoDraft?>((ref) {
  return ref.watch(videoDraftsProvider).activeDraft;
});

final activeVideoTimelineProvider = Provider<VideoTimeline?>((ref) {
  final draft = ref.watch(activeVideoDraftProvider);
  return draft?.timeline;
});
