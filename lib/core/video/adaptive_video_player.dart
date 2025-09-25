import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:video_player/video_player.dart';

import 'video_track.dart';

/// High level video widget that provides:
///
/// * automatic fallback between multiple renditions
/// * optional local caching for progressive streams
/// * a minimal quality picker exposed through a popup menu
/// * graceful buffering/error overlays so users never stare at a black frame
class AdaptiveVideoPlayer extends StatefulWidget {
  const AdaptiveVideoPlayer({
    super.key,
    required this.tracks,
    this.posterImageUrl,
    this.isActive = true,
    this.autoPlay = false,
    this.loop = false,
    this.muted = false,
    this.aspectRatio,
    this.showControls = false,
    this.cacheEnabled = true,
    this.onError,
    this.semanticLabel,
  }) : assert(tracks.length > 0, 'At least one video track is required.');

  final List<VideoTrack> tracks;
  final String? posterImageUrl;
  final bool isActive;
  final bool autoPlay;
  final bool loop;
  final bool muted;
  final double? aspectRatio;
  final bool showControls;
  final bool cacheEnabled;
  final ValueChanged<String>? onError;
  final String? semanticLabel;

  @override
  State<AdaptiveVideoPlayer> createState() => _AdaptiveVideoPlayerState();
}

class _AdaptiveVideoPlayerState extends State<AdaptiveVideoPlayer> {
  final BaseCacheManager _cacheManager = DefaultCacheManager();

  VideoPlayerController? _controller;
  List<VideoTrack> _tracks = const <VideoTrack>[];
  int _currentTrackIndex = 0;
  bool _isBuffering = false;
  bool _hasFatalError = false;
  bool _manuallySelected = false;
  String? _errorMessage;
  String? _infoMessage;
  Timer? _infoTimer;
  int _trackRequestId = 0;
  DateTime? _lastDiagnosticsPrint;

  VideoPlayerValue? get _controllerValue => _controller?.value;

  @override
  void initState() {
    super.initState();
    _tracks = _normalizeTracks(widget.tracks);
    if (_tracks.isNotEmpty) {
      unawaited(_setTrack(_initialTrackIndex(), manualSelection: false));
    }
  }

  @override
  void didUpdateWidget(covariant AdaptiveVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final normalized = _normalizeTracks(widget.tracks);
    if (_haveTracksChanged(normalized)) {
      _tracks = normalized;
      unawaited(_setTrack(_initialTrackIndex(), manualSelection: _manuallySelected));
    }

    final controller = _controller;
    if (widget.isActive != oldWidget.isActive && controller != null) {
      if (widget.isActive && widget.autoPlay) {
        controller.play();
      } else if (!widget.isActive) {
        controller.pause();
      }
    }

    if (widget.muted != oldWidget.muted && controller != null) {
      controller.setVolume(widget.muted ? 0 : 1);
    }

    if (widget.loop != oldWidget.loop && controller != null) {
      controller.setLooping(widget.loop);
    }
  }

  @override
  void dispose() {
    _infoTimer?.cancel();
    final controller = _controller;
    controller?.removeListener(_handleControllerUpdate);
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = _controllerValue;
    final isReady = value?.isInitialized == true;
    final showPlaceholder = !isReady;

    return Semantics(
      label: widget.semanticLabel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (isReady && controller != null)
            _VideoTexture(
              controller: controller,
              aspectRatio: widget.aspectRatio,
              showControls: widget.showControls,
              onTogglePlay: _togglePlayback,
            )
          else
            _buildPosterFallback(),
          if (showPlaceholder && widget.posterImageUrl == null)
            const Center(
              child: SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
          if (_isBuffering && !_hasFatalError)
            const Center(
              child: SizedBox(
                height: 44,
                width: 44,
                child: CircularProgressIndicator.adaptive(),
              ),
            ),
          if (_tracks.length > 1)
            Positioned(
              right: 12,
              bottom: 12,
              child: _QualityButton(
                tracks: _tracks,
                currentIndex: _currentTrackIndex,
                onSelected: (index) {
                  _showInfo('Switching to ${_tracks[index].label}');
                  unawaited(_setTrack(index, manualSelection: true));
                },
              ),
            ),
          if (_infoMessage != null)
            Positioned(
              top: 12,
              left: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    _infoMessage!,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          if (_hasFatalError)
            Positioned.fill(child: _buildErrorOverlay(context)),
        ],
      ),
    );
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Duration _bufferedAhead(VideoPlayerValue value) {
    for (final range in value.buffered) {
      if (value.position >= range.start && value.position <= range.end) {
        return range.end - value.position;
      }
      if (range.start > value.position) {
        return range.end - value.position;
      }
    }
    return Duration.zero;
  }

  List<VideoTrack> _normalizeTracks(List<VideoTrack> tracks) {
    final deduped = <String, VideoTrack>{};
    for (final track in tracks) {
      deduped.putIfAbsent(track.uri.toString(), () => track);
    }
    final normalized = deduped.values.toList();
    normalized.sort((a, b) {
      if (a.isAdaptive != b.isAdaptive) {
        return a.isAdaptive ? -1 : 1;
      }
      final heightA = a.resolution?.height ?? 0;
      final heightB = b.resolution?.height ?? 0;
      return heightB.compareTo(heightA);
    });
    return normalized;
  }

  bool _haveTracksChanged(List<VideoTrack> nextTracks) {
    if (_tracks.length != nextTracks.length) {
      return true;
    }
    for (var i = 0; i < nextTracks.length; i++) {
      if (_tracks[i].uri.toString() != nextTracks[i].uri.toString()) {
        return true;
      }
    }
    return false;
  }

  int _initialTrackIndex() {
    if (_tracks.isEmpty) {
      return 0;
    }
    if (_tracks.first.isAdaptive) {
      return 0;
    }
    if (widget.autoPlay && widget.isActive) {
      return 0;
    }
    return _tracks.indexWhere((track) => track.isAdaptive) >= 0
        ? _tracks.indexWhere((track) => track.isAdaptive)
        : 0;
  }

  Future<void> _setTrack(int index, {required bool manualSelection}) async {
    if (index < 0 || index >= _tracks.length) {
      return;
    }

    final track = _tracks[index];
    if (kDebugMode) {
      debugPrint(
        'AdaptiveVideoPlayer: loading track ${track.label} (adaptive=${track.isAdaptive}) ${track.uri}',
      );
    }
    final oldController = _controller;
    oldController?.removeListener(_handleControllerUpdate);
    oldController?.pause();

    final requestId = ++_trackRequestId;

    setState(() {
      _controller = null;
      _currentTrackIndex = index;
      _hasFatalError = false;
      _errorMessage = null;
      _manuallySelected = manualSelection;
      _isBuffering = true;
    });

    try {
      final controller = await _buildController(track);
      controller.addListener(_handleControllerUpdate);
      await controller.setLooping(widget.loop);
      if (widget.muted) {
        await controller.setVolume(0);
      }

      try {
        await controller.initialize();
      } catch (error, stackTrace) {
        controller.removeListener(_handleControllerUpdate);
        await controller.dispose();
        if (kDebugMode) {
          debugPrint('Failed to initialize video track ${track.uri}: $error');
          debugPrintStack(stackTrace: stackTrace);
        }
        if (requestId == _trackRequestId) {
          _handlePlaybackError('We couldn\'t load ${track.label}.');
        }
        return;
      }

      if (!mounted || requestId != _trackRequestId) {
        controller.removeListener(_handleControllerUpdate);
        await controller.dispose();
        return;
      }

      if (!widget.muted) {
        await controller.setVolume(1);
      }

      setState(() {
        _controller = controller;
        _isBuffering = controller.value.isBuffering;
      });

      if (widget.isActive && widget.autoPlay) {
        unawaited(controller.play());
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to prepare video track ${track.uri}: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (requestId == _trackRequestId) {
        _handlePlaybackError('We couldn\'t load ${track.label}.');
      }
    } finally {
      await oldController?.dispose();
    }
  }

  Future<VideoPlayerController> _buildController(VideoTrack track) async {
    if (track.isFile) {
      return VideoPlayerController.file(File(track.uri.toFilePath()));
    }

    if (widget.cacheEnabled && !track.isAdaptive) {
      final cacheKey = track.cacheKey ?? track.uri.toString();
      try {
        final cached = await _cacheManager.getFileFromCache(cacheKey);
        if (cached != null && await cached.file.exists()) {
          return VideoPlayerController.file(cached.file);
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Cache lookup failed for ${track.uri}: $error');
        }
      }

      try {
        final fileInfo = await _cacheManager.downloadFile(
          track.uri.toString(),
          key: cacheKey,
          force: false,
        );
        if (await fileInfo.file.exists()) {
          return VideoPlayerController.file(fileInfo.file);
        }
      } catch (error) {
        if (kDebugMode) {
          debugPrint('Cache download failed for ${track.uri}: $error');
        }
      }
    }

    return VideoPlayerController.networkUrl(track.uri);
  }

  void _handleControllerUpdate() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    final value = controller.value;

    if (_isBuffering != value.isBuffering) {
      setState(() => _isBuffering = value.isBuffering);
    }

    if (kDebugMode) {
      final now = DateTime.now();
      if (_lastDiagnosticsPrint == null ||
          now.difference(_lastDiagnosticsPrint!) > const Duration(seconds: 2)) {
        final bufferedAhead = _bufferedAhead(value);
        final trackLabel = (_tracks.isNotEmpty &&
                _currentTrackIndex >= 0 &&
                _currentTrackIndex < _tracks.length)
            ? _tracks[_currentTrackIndex].label
            : 'n/a';
        debugPrint(
          'AdaptiveVideoPlayer diagnostics: track=$trackLabel '
          'pos=${value.position.inMilliseconds}ms '
          'buffered=${bufferedAhead.inMilliseconds}ms '
          'playing=${value.isPlaying} buffering=${value.isBuffering}',
        );
        _lastDiagnosticsPrint = now;
      }
    }

    if (value.hasError && !_hasFatalError) {
      final description = value.errorDescription ?? 'Playback failed.';
      _handlePlaybackError(description);
    }
  }

  void _handlePlaybackError(String message) {
    if (kDebugMode) {
      debugPrint('AdaptiveVideoPlayer error: $message');
    }
    widget.onError?.call(message);
    if (_currentTrackIndex < _tracks.length - 1) {
      final nextIndex = _currentTrackIndex + 1;
      _showInfo('Falling back to ${_tracks[nextIndex].label}');
      unawaited(_setTrack(nextIndex, manualSelection: _manuallySelected));
      return;
    }
    setState(() {
      _hasFatalError = true;
      _errorMessage = message;
      _isBuffering = false;
    });
  }

  void _showInfo(String message) {
    _infoTimer?.cancel();
    setState(() => _infoMessage = message);
    _infoTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _infoMessage = null);
      }
    });
  }

  Widget _buildErrorOverlay(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 38, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'We couldn\'t play this video.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white,
                  height: 1.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              if (_tracks.length > 1)
                FilledButton(
                  onPressed: () {
                    final nextIndex = (_currentTrackIndex + 1) % _tracks.length;
                    _showInfo('Trying ${_tracks[nextIndex].label}');
                    unawaited(
                        _setTrack(nextIndex, manualSelection: true));
                  },
                  child: const Text('Try a different quality'),
                ),
              TextButton(
                onPressed: () {
                  setState(() => _hasFatalError = false);
                  unawaited(
                      _setTrack(_currentTrackIndex, manualSelection: _manuallySelected));
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPosterFallback() {
    final provider = _imageProvider(widget.posterImageUrl);
    if (provider != null) {
      return Image(image: provider, fit: BoxFit.cover);
    }
    return const DecoratedBox(
      decoration: BoxDecoration(color: Colors.black12),
      child: SizedBox.expand(),
    );
  }

  ImageProvider<Object>? _imageProvider(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(source);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return NetworkImage(source);
    }
    if (uri != null && uri.scheme == 'file') {
      return FileImage(File(uri.toFilePath()));
    }
    final file = File(source);
    if (file.existsSync()) {
      return FileImage(file);
    }
    return null;
  }
}

class _VideoTexture extends StatelessWidget {
  const _VideoTexture({
    required this.controller,
    required this.aspectRatio,
    required this.showControls,
    required this.onTogglePlay,
  });

  final VideoPlayerController controller;
  final double? aspectRatio;
  final bool showControls;
  final Future<void> Function() onTogglePlay;

  @override
  Widget build(BuildContext context) {
    final videoAspectRatio = controller.value.aspectRatio == 0
        ? (aspectRatio ?? 16 / 9)
        : (aspectRatio ?? controller.value.aspectRatio);

    final size = controller.value.size;
    final width = size.width == 0 ? 1.0 : size.width;
    final height = size.height == 0 ? 1.0 : size.height;

    Widget child = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: width,
        height: height,
        child: VideoPlayer(controller),
      ),
    );

    if (videoAspectRatio.isFinite && videoAspectRatio > 0) {
      child = AspectRatio(aspectRatio: videoAspectRatio, child: child);
    }

    if (!showControls) {
      return child;
    }

    return GestureDetector(
      onTap: onTogglePlay,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.55),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(width: 8),
                  Icon(
                    controller.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  const _QualityButton({
    required this.tracks,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<VideoTrack> tracks;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Theme(
        data: theme.copyWith(
          popupMenuTheme: theme.popupMenuTheme.copyWith(
            color: Colors.black.withValues(alpha: 0.88),
            textStyle: const TextStyle(color: Colors.white),
          ),
        ),
        child: PopupMenuButton<int>(
          tooltip: 'Video quality',
          icon: const Icon(Icons.high_quality, color: Colors.white),
          onSelected: onSelected,
          itemBuilder: (context) {
            return [
              for (var i = 0; i < tracks.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  child: Row(
                    children: [
                      if (i == currentIndex)
                        const Icon(Icons.check, color: Colors.white, size: 16)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tracks[i].qualityLabel,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                      if (tracks[i].isAdaptive)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text(
                            'Auto',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ];
          },
        ),
      ),
    );
  }
}
