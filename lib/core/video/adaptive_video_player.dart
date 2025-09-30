import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'video_track.dart';

const bool _kStoryboardsEnabled = false;

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
    this.storyboardUrl,
    this.vttUrl,
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
  final String? storyboardUrl;
  final String? vttUrl;

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
  _StoryboardManifest? _storyboard;
  int _storyboardRequestId = 0;

  VideoPlayerValue? get _controllerValue => _controller?.value;

  @override
  void initState() {
    super.initState();
    _tracks = _normalizeTracks(widget.tracks);
    if (_tracks.isNotEmpty) {
      unawaited(_setTrack(_initialTrackIndex(), manualSelection: false));
    }
    _loadStoryboardIfNeeded();
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

    if (widget.storyboardUrl != oldWidget.storyboardUrl ||
        widget.vttUrl != oldWidget.vttUrl ||
        widget.showControls != oldWidget.showControls) {
      _loadStoryboardIfNeeded();
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
              storyboard: widget.showControls ? _storyboard : null,
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

  void _loadStoryboardIfNeeded() {
    if (!_kStoryboardsEnabled) {
      if (_storyboard != null) {
        setState(() => _storyboard = null);
      }
      return;
    }

    if (!widget.showControls) {
      if (_storyboard != null) {
        setState(() => _storyboard = null);
      }
      return;
    }

    final storyboardUrl = widget.storyboardUrl;
    final vttUrl = widget.vttUrl;
    if (storyboardUrl == null || storyboardUrl.isEmpty || vttUrl == null ||
        vttUrl.isEmpty) {
      if (_storyboard != null) {
        setState(() => _storyboard = null);
      }
      return;
    }

    final requestId = ++_storyboardRequestId;
    unawaited(_fetchStoryboard(storyboardUrl, vttUrl).then((manifest) {
      if (!mounted || requestId != _storyboardRequestId) {
        return;
      }
      setState(() => _storyboard = manifest);
    }));
  }

  Future<_StoryboardManifest?> _fetchStoryboard(
      String storyboardUrl, String vttUrl) async {
    final vttUri = Uri.tryParse(vttUrl);
    if (vttUri == null) {
      return null;
    }

    final baseUri = Uri.tryParse(storyboardUrl);

    try {
      final contents = await _loadVttContents(vttUri);
      if (contents == null || contents.isEmpty) {
        return null;
      }
      final manifest = _StoryboardManifest.parse(contents, baseUri);
      if (manifest == null) {
        return null;
      }
      await manifest.warmUp();
      return manifest;
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to load storyboard metadata: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      return null;
    }
  }

  Future<String?> _loadVttContents(Uri uri) async {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.body;
      }
      if (kDebugMode) {
        debugPrint('Storyboard VTT request failed: ${response.statusCode}');
      }
      return null;
    }

    if (uri.scheme == 'file') {
      return File(uri.toFilePath()).readAsString();
    }

    // Fallback to treating as a local file path.
    return File(uri.toString()).readAsString();
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
    this.storyboard,
  });

  final VideoPlayerController controller;
  final double? aspectRatio;
  final bool showControls;
  final Future<void> Function() onTogglePlay;
  final _StoryboardManifest? storyboard;

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
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Align(
            alignment: Alignment.bottomCenter,
            child: _VideoControlsOverlay(
              controller: controller,
              storyboard: storyboard,
              onTogglePlay: onTogglePlay,
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoControlsOverlay extends StatefulWidget {
  const _VideoControlsOverlay({
    required this.controller,
    required this.onTogglePlay,
    this.storyboard,
  });

  final VideoPlayerController controller;
  final Future<void> Function() onTogglePlay;
  final _StoryboardManifest? storyboard;

  @override
  State<_VideoControlsOverlay> createState() => _VideoControlsOverlayState();
}

class _VideoControlsOverlayState extends State<_VideoControlsOverlay> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final value = widget.controller.value;
        final duration = value.duration;
        final position = value.position;

        return Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                Colors.black.withValues(alpha: 0.7),
                Colors.black.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ScrubSlider(
                controller: widget.controller,
                position: position,
                duration: duration,
                storyboard: widget.storyboard,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _PlayPauseButton(
                    isPlaying: value.isPlaying,
                    onPressed: widget.onTogglePlay,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatPosition(position),
                    style: _kControlsLabelStyle,
                  ),
                  const Spacer(),
                  Text(
                    _formatPosition(
                      duration,
                      placeholderForZero: true,
                    ),
                    style: _kControlsLabelStyle,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.isPlaying,
    required this.onPressed,
  });

  final bool isPlaying;
  final Future<void> Function() onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => unawaited(onPressed()),
      icon: Icon(
        isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
        color: Colors.white,
        size: 28,
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      splashRadius: 22,
    );
  }
}

class _ScrubSlider extends StatefulWidget {
  const _ScrubSlider({
    required this.controller,
    required this.position,
    required this.duration,
    this.storyboard,
  });

  final VideoPlayerController controller;
  final Duration position;
  final Duration duration;
  final _StoryboardManifest? storyboard;

  @override
  State<_ScrubSlider> createState() => _ScrubSliderState();
}

class _ScrubSliderState extends State<_ScrubSlider> {
  double? _dragValue;
  Duration? _dragPosition;
  _StoryboardCue? _previewCue;
  bool _wasPlayingBeforeDrag = false;

  bool get _isDragging => _dragValue != null;

  @override
  void didUpdateWidget(covariant _ScrubSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.storyboard != oldWidget.storyboard) {
      if (widget.storyboard == null) {
        _previewCue = null;
      } else if (_dragPosition != null) {
        final cue = widget.storyboard!.cueFor(_dragPosition!);
        _previewCue = cue;
        if (cue != null) {
          widget.storyboard!.ensureSheetLoaded(cue).then((_) {
            if (mounted) {
              setState(() {});
            }
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.duration;
    final totalMillis = duration.inMilliseconds;
    final position = widget.position;

    final progress = totalMillis > 0
        ? (position.inMilliseconds / totalMillis).clamp(0.0, 1.0)
        : 0.0;
    final sliderValue = (_dragValue ?? progress).clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final sliderTheme = SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white38,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        );

        Widget slider = SliderTheme(
          data: sliderTheme,
          child: Slider(
            min: 0,
            max: 1,
            value: sliderValue,
            onChangeStart: totalMillis > 0 ? _handleDragStart : null,
            onChanged: totalMillis > 0 ? _handleDragUpdate : null,
            onChangeEnd: totalMillis > 0 ? _handleDragEnd : null,
          ),
        );

        Widget? previewWidget;
        double previewWidth = 0;
        if (_isDragging && widget.storyboard != null && _previewCue != null) {
          final cue = _previewCue!;
          final tileSize = cue.tileSize;
          if (tileSize.width > 0 && tileSize.height > 0) {
            const maxPreviewWidth = 180.0;
            var scale = 1.0;
            if (tileSize.width > maxPreviewWidth) {
              scale = maxPreviewWidth / tileSize.width;
            }
            previewWidth = tileSize.width * scale;
            previewWidget = _StoryboardPreview(
              cue: cue,
              scale: scale,
            );
          }
        }

        if (previewWidget == null) {
          return slider;
        }

        final thumbSize = sliderTheme.thumbShape
                ?.getPreferredSize(true, true) ??
            const Size(16, 16);
        final sliderWidth = constraints.maxWidth;
        final trackWidth = math.max(0.0, sliderWidth - thumbSize.width);
        final thumbCenter = trackWidth * sliderValue + thumbSize.width / 2;
        var left = thumbCenter - previewWidth / 2;
        left = left.clamp(0.0, math.max(0.0, sliderWidth - previewWidth));

        final previewPosition = _dragPosition ?? Duration.zero;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            slider,
            Positioned(
              left: left,
              bottom: 34,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  previewWidget,
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatPosition(previewPosition),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleDragStart(double value) {
    _wasPlayingBeforeDrag = widget.controller.value.isPlaying;
    if (_wasPlayingBeforeDrag) {
      unawaited(widget.controller.pause());
    }
    final position = _positionForValue(value);
    final cue = widget.storyboard?.cueFor(position);
    setState(() {
      _dragValue = value;
      _dragPosition = position;
      _previewCue = cue;
    });
    if (cue != null) {
      widget.storyboard!.ensureSheetLoaded(cue).then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  void _handleDragUpdate(double value) {
    final position = _positionForValue(value);
    final cue = widget.storyboard?.cueFor(position);
    setState(() {
      _dragValue = value;
      _dragPosition = position;
      _previewCue = cue;
    });
    if (cue != null) {
      widget.storyboard!.ensureSheetLoaded(cue).then((_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  void _handleDragEnd(double value) {
    final position = _positionForValue(value);
    if (widget.duration.inMilliseconds > 0) {
      unawaited(widget.controller.seekTo(position));
    }
    if (_wasPlayingBeforeDrag) {
      unawaited(widget.controller.play());
    }
    setState(() {
      _dragValue = null;
      _dragPosition = null;
      _previewCue = null;
    });
  }

  Duration _positionForValue(double value) {
    final totalMillis = widget.duration.inMilliseconds;
    if (totalMillis <= 0) {
      return Duration.zero;
    }
    final targetMillis = (totalMillis * value).round();
    return Duration(milliseconds: targetMillis);
  }
}

class _StoryboardPreview extends StatelessWidget {
  const _StoryboardPreview({
    required this.cue,
    required this.scale,
  });

  final _StoryboardCue cue;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final sheet = cue.sheet;
    final image = sheet.image;
    final width = cue.region.width * scale;
    final height = cue.region.height * scale;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: width,
          height: height,
          child: image != null
              ? CustomPaint(
                  painter: _StoryboardPainter(
                    image,
                    cue.region,
                    scale,
                  ),
                )
              : const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
        ),
      ),
    );
  }
}

class _StoryboardPainter extends CustomPainter {
  const _StoryboardPainter(this.image, this.region, this.scale);

  final ui.Image image;
  final Rect region;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final destination = Offset.zero & size;
    canvas.drawImageRect(image, region, destination, Paint());
  }

  @override
  bool shouldRepaint(covariant _StoryboardPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.region != region ||
        oldDelegate.scale != scale;
  }
}

const TextStyle _kControlsLabelStyle = TextStyle(
  color: Colors.white70,
  fontSize: 12,
);

String _formatPosition(Duration duration, {bool placeholderForZero = false}) {
  if (duration.inMilliseconds <= 0) {
    return placeholderForZero ? '--:--' : '0:00';
  }
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds ~/ 60) % 60;
  final seconds = totalSeconds % 60;

  final minuteComponent = hours > 0
      ? minutes.toString().padLeft(2, '0')
      : (totalSeconds ~/ 60).toString();
  final secondComponent = seconds.toString().padLeft(2, '0');

  if (hours > 0) {
    return '$hours:$minuteComponent:$secondComponent';
  }
  return '$minuteComponent:$secondComponent';
}

class _StoryboardManifest {
  _StoryboardManifest(this.cues);

  final List<_StoryboardCue> cues;

  static _StoryboardManifest? parse(String contents, Uri? baseUri) {
    final lines = contents.split(RegExp(r'\r?\n'));
    final cues = <_StoryboardCue>[];
    final sheets = <Uri, _StoryboardSheet>{};
    final buffer = <String>[];

    void flush() {
      if (buffer.isEmpty) {
        return;
      }
      final cue = _parseCue(buffer, baseUri, sheets);
      buffer.clear();
      if (cue != null) {
        cues.add(cue);
      }
    }

    for (final line in lines) {
      if (line.trim().isEmpty) {
        flush();
      } else {
        buffer.add(line);
      }
    }
    flush();

    if (cues.isEmpty) {
      return null;
    }

    cues.sort((a, b) => a.start.compareTo(b.start));
    return _StoryboardManifest(cues);
  }

  Future<void> warmUp() async {
    if (cues.isEmpty) {
      return;
    }
    await ensureSheetLoaded(cues.first);
  }

  Future<void> ensureSheetLoaded(_StoryboardCue cue) {
    return cue.sheet.ensureImage();
  }

  _StoryboardCue? cueFor(Duration position) {
    if (cues.isEmpty) {
      return null;
    }
    _StoryboardCue? candidate;
    for (final cue in cues) {
      if (position < cue.start) {
        break;
      }
      candidate = cue;
      if (position < cue.end) {
        break;
      }
    }
    return candidate ?? cues.first;
  }

  static _StoryboardCue? _parseCue(
    List<String> rawBlock,
    Uri? baseUri,
    Map<Uri, _StoryboardSheet> sheets,
  ) {
    final block = rawBlock
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    if (block.isEmpty) {
      return null;
    }
    if (block.length == 1 && block.first.toUpperCase() == 'WEBVTT') {
      return null;
    }
    if (block.first.startsWith('NOTE')) {
      return null;
    }

    var index = 0;
    if (!block[index].contains('-->')) {
      index++;
      if (index >= block.length) {
        return null;
      }
    }

    final timingLine = block[index];
    final timingParts = timingLine.split(RegExp(r'\s+-->\s+'));
    if (timingParts.length < 2) {
      return null;
    }

    final start = _parseTimestamp(_sanitizeTimestamp(timingParts[0]));
    final end = _parseTimestamp(_sanitizeTimestamp(timingParts[1]));
    if (start == null || end == null || end <= start) {
      return null;
    }

    index++;
    if (index >= block.length) {
      return null;
    }

    final payload = StringBuffer();
    for (var i = index; i < block.length; i++) {
      final line = block[i];
      if (line.startsWith('NOTE')) {
        continue;
      }
      payload.write(line);
    }

    final cueText = payload.toString().trim();
    if (cueText.isEmpty) {
      return null;
    }

    final separatorIndex = cueText.indexOf('#');
    final resourcePart = separatorIndex == -1
        ? cueText
        : cueText.substring(0, separatorIndex);
    final fragment = separatorIndex == -1
        ? ''
        : cueText.substring(separatorIndex + 1);

    final imageUri = _resolveImageUri(resourcePart, baseUri);
    if (imageUri == null) {
      return null;
    }

    final region = _parseRegion(fragment);
    if (region == null) {
      return null;
    }

    final sheet = sheets.putIfAbsent(imageUri, () => _StoryboardSheet(imageUri));
    return _StoryboardCue(
      start: start,
      end: end,
      sheet: sheet,
      region: region,
    );
  }

  static Duration? _parseTimestamp(String raw) {
    if (raw.isEmpty) {
      return null;
    }
    final parts = raw.split('.');
    final primary = parts.first.split(':');
    if (primary.length < 2 || primary.length > 3) {
      return null;
    }

    final hours = primary.length == 3 ? int.tryParse(primary[0]) ?? 0 : 0;
    final minutes = int.tryParse(primary[primary.length - 2]) ?? 0;
    final seconds = int.tryParse(primary.last) ?? 0;
    final milliseconds = parts.length > 1
        ? int.tryParse(parts[1].padRight(3, '0').substring(0, 3)) ?? 0
        : 0;

    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }

  static String _sanitizeTimestamp(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return trimmed;
    }
    return trimmed.split(RegExp(r'\s+')).first;
  }

  static Uri? _resolveImageUri(String resource, Uri? baseUri) {
    final trimmed = resource.trim();
    if (trimmed.isEmpty) {
      return baseUri;
    }
    final candidate = Uri.tryParse(trimmed);
    if (candidate == null) {
      return null;
    }
    if (candidate.hasScheme) {
      return candidate;
    }
    if (baseUri != null) {
      return baseUri.resolveUri(candidate);
    }
    return candidate;
  }

  static Rect? _parseRegion(String fragment) {
    if (fragment.isEmpty) {
      return null;
    }
    final match = RegExp(r'xywh=(\d+),(\d+),(\d+),(\d+)').firstMatch(fragment);
    if (match == null) {
      return null;
    }
    final left = double.tryParse(match.group(1)!);
    final top = double.tryParse(match.group(2)!);
    final width = double.tryParse(match.group(3)!);
    final height = double.tryParse(match.group(4)!);
    if (left == null || top == null || width == null || height == null) {
      return null;
    }
    return Rect.fromLTWH(left, top, width, height);
  }
}

class _StoryboardCue {
  _StoryboardCue({
    required this.start,
    required this.end,
    required this.sheet,
    required this.region,
  });

  final Duration start;
  final Duration end;
  final _StoryboardSheet sheet;
  final Rect region;

  Size get tileSize => Size(region.width, region.height);
}

class _StoryboardSheet {
  _StoryboardSheet(this.uri)
      : provider = _buildProvider(uri);

  final Uri uri;
  final ImageProvider<Object> provider;

  ui.Image? _image;
  Future<ui.Image?>? _pending;

  ui.Image? get image => _image;

  Future<ui.Image?> ensureImage() {
    final cached = _image;
    if (cached != null) {
      return Future.value(cached);
    }
    final pending = _pending;
    if (pending != null) {
      return pending;
    }

    final completer = Completer<ui.Image?>();
    _pending = completer.future;

    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, _) {
        _image = imageInfo.image;
        completer.complete(_image);
        stream.removeListener(listener);
        _pending = null;
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('Failed to load storyboard sheet $uri: $error');
        }
        completer.complete(null);
        stream.removeListener(listener);
        _pending = null;
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static ImageProvider<Object> _buildProvider(Uri uri) {
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return NetworkImage(uri.toString());
    }
    if (uri.scheme == 'file') {
      return FileImage(File(uri.toFilePath()));
    }
    if (uri.scheme.isEmpty) {
      final file = File(uri.toString());
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return NetworkImage(uri.toString());
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
