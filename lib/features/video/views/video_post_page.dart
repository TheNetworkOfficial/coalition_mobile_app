import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/backend_config_provider.dart';
import '../models/video_timeline.dart';
import '../platform/video_native.dart';
import '../providers/video_draft_provider.dart';
import '../services/mux_upload_service.dart';

class VideoPostPage extends ConsumerStatefulWidget {
  const VideoPostPage({super.key, this.draftId, this.httpClientOverride});

  static const routeName = 'video-post';

  final String? draftId;
  final http.Client? httpClientOverride;

  @override
  ConsumerState<VideoPostPage> createState() => _VideoPostPageState();
}

enum _PostStage { idle, exporting, uploading, processing }

class _VideoPostPageState extends ConsumerState<VideoPostPage> {
  _PostStage _stage = _PostStage.idle;
  final _captionController = TextEditingController();
  late final http.Client _httpClient;
  bool _isPrivate = false;
  bool _uploadFailed = false;
  double _uploadProgress = 0;
  File? _exportedVideoFile;
  String? _localCoverPath;
  String? _uploadedCoverUrl;
  MuxUploadTicket? _currentTicket;
  bool _uploadCompleted = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _httpClient = widget.httpClientOverride ?? http.Client();
    if (widget.draftId != null) {
      ref.read(videoDraftsProvider.notifier).setActiveDraft(widget.draftId);
    }
  }

  @override
  void dispose() {
    _httpClient.close();
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _onPostPressed(VideoTimeline timeline) async {
    if (!kUseMux) {
      setState(() {
        _errorMessage = 'Video uploads are currently unavailable.';
      });
      return;
    }

    await _startMuxPostFlow(timeline);
  }

  Map<String, dynamic> _buildTimelineJson(VideoTimeline timeline) {
    final map = <String, dynamic>{};

    final trimStart = timeline.trimStartMs;
    final trimEnd = timeline.trimEndMs;
    if (trimStart != null || trimEnd != null) {
      map['trim'] = <String, dynamic>{
        if (trimStart != null) 'startSeconds': trimStart / 1000,
        if (trimEnd != null) 'endSeconds': trimEnd / 1000,
      };
    }

    final crop = timeline.cropRect;
    if (crop != null) {
      map['crop'] = <String, dynamic>{
        'left': crop.left,
        'top': crop.top,
        'right': crop.right,
        'bottom': crop.bottom,
      };
    }

    // Additional effects, filters, and overlays can be serialized here as they
    // are implemented in the editing flow.

    return map;
  }

  Future<void> _startMuxPostFlow(VideoTimeline timeline) async {
    final existing = _exportedVideoFile;
    var hasExported = false;
    if (existing != null && existing.existsSync()) {
      hasExported = true;
    } else {
      _exportedVideoFile = null;
    }

    final needsExport = !hasExported;
    final needsUpload = !_uploadCompleted;

    setState(() {
      _errorMessage = null;
      _uploadFailed = false;
      if (needsExport) {
        _stage = _PostStage.exporting;
      } else if (needsUpload) {
        _stage = _PostStage.uploading;
        _uploadProgress = 0;
      } else {
        _stage = _PostStage.processing;
      }
    });

    var uploadAttempted = false;
    var postAttempted = false;

    try {
      final videoFile = await _ensureExportedVideo(timeline);
      final coverPath = await _ensureCoverImage(timeline);
      final coverUrl = await _ensureCoverUpload(coverPath);
      final ticket = await _ensureMuxTicket(videoFile);

      if (!_uploadCompleted) {
        uploadAttempted = true;
        await _performMuxUpload(ticket, videoFile);
        if (!mounted) {
          return;
        }
        setState(() {
          _uploadCompleted = true;
          _uploadProgress = 1.0;
        });
      }

      postAttempted = true;
      await _postToBackend(
        uploadId: ticket.uploadId,
        coverUrl: coverUrl,
        timeline: timeline,
      );

      await ref
          .read(videoDraftsProvider.notifier)
          .clearActiveDraft(deleteAssets: true);
      await _purgeLocalScratchFiles();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Processing video…')),
      );
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      // In a production environment this would be reported to crash logging.
      debugPrint('Failed to post video: $error\n$stackTrace');
      final isTusTicket = _currentTicket?.isTus == true;
      if (!mounted) {
        return;
      }
      setState(() {
        _stage = _PostStage.idle;
        _uploadProgress = 0;
        _uploadFailed = uploadAttempted || postAttempted;
        if (_uploadFailed &&
            _currentTicket != null &&
            !_currentTicket!.isTus &&
            !_uploadCompleted) {
          _currentTicket = null;
        }
        _errorMessage = _messageForError(
            uploadAttempted: uploadAttempted,
            postAttempted: postAttempted,
            isTusTicket: isTusTicket);
      });
    }
  }

  @visibleForTesting
  Future<void> startMuxPostFlowForTesting(VideoTimeline timeline) =>
      _startMuxPostFlow(timeline);

  String _messageForError({
    required bool uploadAttempted,
    required bool postAttempted,
    required bool isTusTicket,
  }) {
    if (postAttempted) {
      return 'Failed to create post. Please try again.';
    }
    if (uploadAttempted) {
      return isTusTicket
          ? 'Upload interrupted. Tap “Resume upload” to continue.'
          : 'Upload failed. Tap “Retry upload” to try again.';
    }
    return 'Failed to prepare video. Please try again.';
  }

  Future<File> _ensureExportedVideo(VideoTimeline timeline) async {
    final existing = _exportedVideoFile;
    if (existing != null && await existing.exists()) {
      return existing;
    }

    final timelineJson = _buildTimelineJson(timeline);
    final native = ref.read(videoNativeProvider);
    final exportedPath = await native.exportEdits(
      filePath: timeline.sourcePath,
      timelineJson: timelineJson,
      targetBitrateBps: 6_000_000,
    );

    final file = File(exportedPath);
    _exportedVideoFile = file;
    _uploadCompleted = false;
    return file;
  }

  Future<String> _ensureCoverImage(VideoTimeline timeline) async {
    final cached = _localCoverPath ?? timeline.coverImagePath;
    if (cached != null && cached.isNotEmpty) {
      if (_isRemoteAsset(cached)) {
        return cached;
      }
      final file = File(cached);
      if (await file.exists()) {
        _localCoverPath = cached;
        return cached;
      }
    }

    final seconds = (timeline.coverTimeMs ?? 0) / 1000;
    final native = ref.read(videoNativeProvider);
    final coverPath = await native.generateCoverImage(
      timeline.sourcePath,
      seconds: seconds,
    );
    _localCoverPath = coverPath;
    return coverPath;
  }

  Future<String> _ensureCoverUpload(String coverPath) async {
    final cached = _uploadedCoverUrl;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    if (_isRemoteAsset(coverPath)) {
      _uploadedCoverUrl = coverPath;
      return coverPath;
    }
    final uploaded = await _uploadCoverImage(coverPath);
    _uploadedCoverUrl = uploaded;
    return uploaded;
  }

  Future<String> _uploadCoverImage(String coverPath) async {
    final file = File(coverPath);
    if (!await file.exists()) {
      throw FileSystemException('Cover image missing', coverPath);
    }

    final uri = _resolveBackendUri('assets/covers/presign');
    final response = await _httpClient.post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'filename': _basename(coverPath),
        'content_type': 'image/png',
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Failed to presign cover upload: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
        uri: uri,
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final uploadUrl =
        payload['put_url'] ?? payload['upload_url'] ?? payload['url'];
    final assetUrl =
        payload['asset_url'] ?? payload['cover_url'] ?? payload['public_url'];
    final headers = payload['headers'];

    if (uploadUrl is! String || assetUrl is! String) {
      throw const FormatException('Presign response missing upload target.');
    }

    final request = http.Request('PUT', Uri.parse(uploadUrl));
    request.headers['content-type'] = 'image/png';
    if (headers is Map) {
      request.headers.addAll(headers.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ));
    }
    request.bodyBytes = await file.readAsBytes();

    final uploadResponse = await _httpClient.send(request);
    await uploadResponse.stream.drain();
    if (uploadResponse.statusCode < 200 || uploadResponse.statusCode >= 300) {
      throw HttpException(
        'Failed to upload cover: ${uploadResponse.statusCode} ${uploadResponse.reasonPhrase}',
        uri: request.url,
      );
    }

    return assetUrl;
  }

  Future<MuxUploadTicket> _ensureMuxTicket(File video) async {
    final existing = _currentTicket;
    if (existing != null) {
      if (existing.isTus || _uploadCompleted) {
        return existing;
      }
    }

    final filesize = await video.length();
    final ticket = await ref.read(muxUploadServiceProvider).createDirectUpload(
          filename: _basename(video.path),
          filesizeBytes: filesize,
          preferTus: true,
        );
    _currentTicket = ticket;
    return ticket;
  }

  Future<void> _performMuxUpload(MuxUploadTicket ticket, File video) async {
    final service = ref.read(muxUploadServiceProvider);
    await service.uploadVideo(
      ticket: ticket,
      mp4: video,
      onProgress: (sent, total) {
        if (!mounted) {
          return;
        }
        setState(() {
          _uploadProgress = total == 0 ? 0 : sent / total;
        });
      },
    );
  }

  Future<void> _postToBackend({
    required String uploadId,
    required String coverUrl,
    required VideoTimeline timeline,
  }) async {
    final uri = _resolveBackendUri('posts/video');
    final payload = {
      'caption': _captionController.text,
      'is_private': _isPrivate,
      'mux_upload_id': uploadId,
      'cover_url': coverUrl,
      'timeline': _buildTimelineJson(timeline),
    };

    final response = await _httpClient.post(
      uri,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Failed to create post: ${response.statusCode} ${response.reasonPhrase}\n${response.body}',
        uri: uri,
      );
    }
  }

  Uri _resolveBackendUri(String path) {
    final backendConfig = ref.read(backendConfigProvider);
    final base = backendConfig.baseUri;
    return _ensureTrailingSlash(base).resolve(path);
  }

  Uri _ensureTrailingSlash(Uri uri) {
    final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    return uri.replace(path: path);
  }

  String _basename(String path) {
    final index = path.lastIndexOf('/');
    if (index == -1) {
      return path;
    }
    return path.substring(index + 1);
  }

  bool _isRemoteAsset(String path) {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  Future<void> _purgeLocalScratchFiles() async {
    final exported = _exportedVideoFile;
    if (exported != null && await exported.exists()) {
      try {
        await exported.delete();
      } catch (_) {}
    }
    _exportedVideoFile = null;

    final cover = _localCoverPath;
    if (cover != null && cover.isNotEmpty) {
      await _deleteIfExists(cover);
    }
    _localCoverPath = null;
    _uploadedCoverUrl = null;
    _currentTicket = null;
    _uploadCompleted = false;
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  String _statusLabel() {
    switch (_stage) {
      case _PostStage.exporting:
        return 'Exporting video…';
      case _PostStage.uploading:
        return 'Uploading to Mux…';
      case _PostStage.processing:
        return 'Finalizing post…';
      case _PostStage.idle:
        if (_uploadFailed) {
          return 'Upload failed. Please try again.';
        }
        return 'Ready to post';
    }
  }

  String _primaryButtonLabel() {
    switch (_stage) {
      case _PostStage.exporting:
        return 'Exporting…';
      case _PostStage.uploading:
        return 'Uploading…';
      case _PostStage.processing:
        return 'Processing…';
      case _PostStage.idle:
        if (_uploadFailed) {
          if (_uploadCompleted) {
            return 'Retry';
          }
          return _currentTicket?.isTus == true
              ? 'Resume upload'
              : 'Retry upload';
        }
        return 'Post';
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = ref.watch(activeVideoTimelineProvider);
    final isBusy = _stage == _PostStage.exporting ||
        _stage == _PostStage.uploading ||
        _stage == _PostStage.processing;
    final double? progressValue =
        _stage == _PostStage.uploading ? _uploadProgress.clamp(0.0, 1.0) : null;
    final buttonLabel = _primaryButtonLabel();
    final VoidCallback? buttonOnPressed =
        timeline == null || isBusy ? null : () => _onPostPressed(timeline);

    return Scaffold(
      appBar: AppBar(title: const Text('Post video')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _captionController,
              decoration: const InputDecoration(labelText: 'Caption'),
              enabled: !isBusy,
            ),
            SwitchListTile(
              value: _isPrivate,
              title: const Text('Private'),
              onChanged: isBusy
                  ? null
                  : (value) {
                      setState(() {
                        _isPrivate = value;
                      });
                    },
            ),
            if (isBusy) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: progressValue),
              const SizedBox(height: 8),
              Text(
                _statusLabel(),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: buttonOnPressed,
                child: Text(buttonLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
