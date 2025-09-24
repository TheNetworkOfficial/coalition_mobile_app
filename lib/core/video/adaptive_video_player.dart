import 'dart:async';
import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'video_track.dart';

/// High level video widget that wraps BetterPlayer and adds:
///
/// * automatic fallback between multiple renditions
/// * optional local caching
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
  BetterPlayerController? _controller;
  List<VideoTrack> _tracks = const <VideoTrack>[];
  int _currentTrackIndex = 0;
  bool _isBuffering = false;
  bool _hasFatalError = false;
  bool _manuallySelected = false;
  String? _errorMessage;
  String? _infoMessage;
  Timer? _infoTimer;

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

    if (widget.isActive != oldWidget.isActive && _controller != null) {
      if (widget.isActive && widget.autoPlay) {
        _controller!.play();
      } else if (!widget.isActive) {
        _controller!.pause();
      }
    }

    if (widget.muted != oldWidget.muted && _controller != null) {
      _controller!.setVolume(widget.muted ? 0 : 1);
    }
  }

  @override
  void dispose() {
    _infoTimer?.cancel();
    _controller?.removeEventsListener(_handleEvent);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showPlaceholder = controller == null;

    return Semantics(
      label: widget.semanticLabel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null)
            BetterPlayer(controller)
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
                  color: Colors.black.withOpacity(0.65),
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
    final oldController = _controller;
    oldController?.removeEventsListener(_handleEvent);

    final configuration = _buildConfiguration(track);
    final dataSource = _buildDataSource(track);
    final controller = BetterPlayerController(
      configuration,
      betterPlayerDataSource: dataSource,
    );
    controller.addEventsListener(_handleEvent);

    setState(() {
      _controller = controller;
      _currentTrackIndex = index;
      _hasFatalError = false;
      _errorMessage = null;
      _manuallySelected = manualSelection;
    });

    if (widget.muted) {
      controller.setVolume(0);
    }

    if (widget.isActive && widget.autoPlay) {
      controller.play();
    }

    await oldController?.dispose();
  }

  BetterPlayerConfiguration _buildConfiguration(VideoTrack track) {
    return BetterPlayerConfiguration(
      autoPlay: widget.autoPlay && widget.isActive,
      looping: widget.loop,
      aspectRatio: widget.aspectRatio,
      fit: BoxFit.cover,
      autoDispose: true,
      handleLifecycle: true,
      controlsConfiguration: BetterPlayerControlsConfiguration(
        showControls: widget.showControls,
        showControlsOnInitialize: widget.showControls,
        enableFullscreen: widget.showControls,
        enableMute: widget.showControls,
        enablePlaybackSpeed: false,
        enableQualities: false,
        enableAudioTracks: false,
        enablePip: false,
        enableSkips: false,
        controlBarColor: Colors.black54,
        iconsColor: Colors.white,
        loadingColor: Colors.white,
      ),
      placeholderOnTop: true,
      placeholder: widget.posterImageUrl != null
          ? _PosterImage(imageProvider: _imageProvider(widget.posterImageUrl))
          : null,
    );
  }

  BetterPlayerDataSource _buildDataSource(VideoTrack track) {
    final type = track.isNetwork
        ? BetterPlayerDataSourceType.network
        : BetterPlayerDataSourceType.file;
    final source = track.isFile ? track.uri.toFilePath() : track.uri.toString();

    return BetterPlayerDataSource(
      type,
      source,
      cacheConfiguration: widget.cacheEnabled && track.isNetwork
          ? BetterPlayerCacheConfiguration(
              useCache: true,
              maxCacheSize: 512 * 1024 * 1024,
              maxCacheFileSize: 200 * 1024 * 1024,
              preCacheSize: 6 * 1024 * 1024,
              key: track.cacheKey ?? track.uri.toString(),
            )
          : null,
      videoFormat: track.isAdaptive || track.uri.path.endsWith('.m3u8')
          ? BetterPlayerVideoFormat.hls
          : BetterPlayerVideoFormat.other,
      useAsmsSubtitles: false,
      useAsmsTracks: track.isAdaptive,
      notificationConfiguration: const BetterPlayerNotificationConfiguration(
        showNotification: false,
      ),
    );
  }

  void _handleEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        if (widget.muted) {
          _controller?.setVolume(0);
        }
        setState(() => _isBuffering = false);
        break;
      case BetterPlayerEventType.bufferingStart:
        setState(() => _isBuffering = true);
        break;
      case BetterPlayerEventType.bufferingEnd:
      case BetterPlayerEventType.play:
      case BetterPlayerEventType.pause:
        if (_isBuffering) {
          setState(() => _isBuffering = false);
        }
        break;
      case BetterPlayerEventType.exception:
        _handlePlaybackError(
          (event.parameters ?? const <String, Object?>{})['exception']
                  ?.toString() ??
              'Playback failed.',
        );
        break;
      default:
        break;
    }
  }

  void _handlePlaybackError(String message) {
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
      color: Colors.black.withOpacity(0.75),
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

class _PosterImage extends StatelessWidget {
  const _PosterImage({required this.imageProvider});

  final ImageProvider<Object>? imageProvider;

  @override
  Widget build(BuildContext context) {
    if (imageProvider == null) {
      return const SizedBox.shrink();
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: imageProvider!,
          fit: BoxFit.cover,
        ),
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
        color: Colors.black.withOpacity(0.55),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Theme(
        data: theme.copyWith(
          popupMenuTheme: theme.popupMenuTheme.copyWith(
            color: Colors.black.withOpacity(0.88),
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
