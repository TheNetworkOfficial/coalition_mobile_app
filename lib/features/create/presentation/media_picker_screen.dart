import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../feed/domain/feed_content.dart';
import '../domain/video_proxy_service.dart';
import 'widgets/transcode_status.dart';

class MediaPickerResult {
  const MediaPickerResult({
    required this.filePath,
    required this.mediaType,
    required this.aspectRatio,
  });

  final String filePath;
  final FeedMediaType mediaType;
  final double aspectRatio;
}

class MediaPickerScreen extends StatefulWidget {
  const MediaPickerScreen({super.key});

  @override
  State<MediaPickerScreen> createState() => _MediaPickerScreenState();
}

class _MediaPickerScreenState extends State<MediaPickerScreen> {
  static const _pageSize = 80;
  static const double _defaultVideoAspectRatio = 9 / 16;
  static const double _defaultImageAspectRatio = 4 / 5;
  static const PermissionRequestOption _permissionRequestOption =
      PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      mediaLocation: false,
    ),
  );

  final ScrollController _gridController = ScrollController();

  AssetPathEntity? _recentAlbum;
  List<AssetEntity> _allAssets = <AssetEntity>[];
  List<AssetEntity> _visibleAssets = <AssetEntity>[];
  AssetEntity? _selectedAsset;
  FeedMediaType? _activeFilter;

  bool _initializing = true;
  bool _permissionDenied = false;
  PermissionState? _permissionState;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _currentPage = 0;
  bool _isAdvancing = false;
  bool _selectionLoading = false;
  double? _proxyProgress;
  String? _proxyError;

  File? _selectedFile;
  VideoPlayerController? _previewVideoController;

  @override
  void initState() {
    super.initState();
    _gridController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initGallery();
    });
  }

  @override
  void dispose() {
    _gridController.dispose();
    _previewVideoController?.dispose();
    super.dispose();
  }

  bool _permissionHasAccess(PermissionState state) {
    return state == PermissionState.authorized ||
        state == PermissionState.limited;
  }

  Future<void> _initGallery() async {
    final permission = await PhotoManager.getPermissionState(
      requestOption: _permissionRequestOption,
    );
    if (!mounted) return;

    if (!_permissionHasAccess(permission)) {
      setState(() {
        _permissionDenied = true;
        _permissionState = permission;
        _initializing = false;
      });
      return;
    }

    setState(() {
      _permissionState = permission;
    });

    await _loadGalleryAssets();
  }

  Future<void> _loadGalleryAssets() async {
    if (!mounted) return;
    setState(() {
      _initializing = true;
      _permissionDenied = false;
    });

    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      filterOption: FilterOptionGroup(
        orders: const <OrderOption>[
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
        imageOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true)),
        videoOption: const FilterOption(
            sizeConstraint: SizeConstraint(ignoreSize: true)),
      ),
    );

    if (!mounted) return;

    if (paths.isEmpty) {
      setState(() {
        _recentAlbum = null;
        _allAssets = <AssetEntity>[];
        _visibleAssets = <AssetEntity>[];
        _selectedAsset = null;
        _initializing = false;
      });
      return;
    }

    final recent = paths.first;
    final assets = await recent.getAssetListPaged(page: 0, size: _pageSize);

    if (!mounted) return;

    final filtered = _applyFilter(assets, _activeFilter);
    final first = filtered.isNotEmpty ? filtered.first : null;

    setState(() {
      _recentAlbum = recent;
      _allAssets = assets;
      _visibleAssets = filtered;
      _selectedAsset = first;
      _initializing = false;
      _currentPage = 0;
      _hasMore = assets.length == _pageSize;
    });

    if (first != null) {
      await _prepareSelection(first);
    }
  }

  Future<void> _requestPermission() async {
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: _permissionRequestOption,
    );
    if (!mounted) return;

    if (_permissionHasAccess(permission)) {
      setState(() {
        _permissionState = permission;
      });
      await _loadGalleryAssets();
      return;
    }

    setState(() {
      _permissionDenied = true;
      _permissionState = permission;
    });
  }

  bool get _shouldShowSettingsButton {
    final permission = _permissionState;
    if (permission == null) {
      return false;
    }
    return permission == PermissionState.denied ||
        permission == PermissionState.restricted;
  }

  void _handleScroll() {
    if (_gridController.position.extentAfter < 600) {
      _loadMoreAssets();
    }
  }

  Future<void> _loadMoreAssets() async {
    if (_loadingMore || !_hasMore) return;
    final album = _recentAlbum;
    if (album == null) return;

    setState(() => _loadingMore = true);

    final nextPage = _currentPage + 1;
    final fetched =
        await album.getAssetListPaged(page: nextPage, size: _pageSize);

    if (!mounted) return;

    if (fetched.isEmpty) {
      setState(() {
        _hasMore = false;
        _loadingMore = false;
      });
      return;
    }

    final updatedAll = List<AssetEntity>.from(_allAssets)..addAll(fetched);
    final filtered = _applyFilter(updatedAll, _activeFilter);

    setState(() {
      _allAssets = updatedAll;
      _visibleAssets = filtered;
      _currentPage = nextPage;
      _hasMore = fetched.length == _pageSize;
      _loadingMore = false;
    });
  }

  List<AssetEntity> _applyFilter(
      List<AssetEntity> source, FeedMediaType? filter) {
    if (filter == null) {
      return List<AssetEntity>.from(source);
    }

    return source
        .where((asset) => _assetMatchesFilter(asset, filter))
        .toList(growable: false);
  }

  bool _assetMatchesFilter(AssetEntity asset, FeedMediaType? filter) {
    if (filter == null) return true;
    if (filter == FeedMediaType.image) {
      return asset.type == AssetType.image;
    }
    if (filter == FeedMediaType.video) {
      return asset.type == AssetType.video;
    }
    return true;
  }

  Future<void> _prepareSelection(AssetEntity asset) async {
    setState(() {
      _selectionLoading = true;
      _proxyProgress = null;
      _proxyError = null;
    });

    final existingController = _previewVideoController;
    _previewVideoController = null;
    _selectedFile = null;
    await existingController?.dispose();

    final file = await asset.file;
    if (!mounted) {
      return;
    }

    if (file == null) {
      setState(() => _selectionLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('We could not open that media item.')),
      );
      return;
    }

    VideoPlayerController? controller;
    if (asset.type == AssetType.video) {
      final proxyService = VideoProxyService.instance;
      File previewFile = file;

      final fileLength = await file.length();
      final shouldProxy = await proxyService.shouldTranscode(
        path: file.path,
        width: asset.width,
        height: asset.height,
        fileLengthBytes: fileLength,
      );

      if (shouldProxy) {
        if (!mounted) {
          return;
        }
        setState(() {
          _proxyProgress = 0;
        });
        try {
          final result = await proxyService.ensureProxy(
            file.path,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _proxyProgress = progress;
              });
            },
          );
          previewFile = File(result.proxyPath);
          if (mounted) {
            setState(() {
              _proxyError = null;
            });
          }
        } catch (_) {
          if (!mounted) {
            return;
          }
          setState(() {
            _proxyError =
                'We had trouble preparing a lightweight preview. Playing original.';
          });
          previewFile = file;
        } finally {
          if (mounted) {
            setState(() {
              _proxyProgress = null;
            });
          }
        }
      }

      controller = VideoPlayerController.file(previewFile)
        ..setLooping(true)
        ..setVolume(0);
      try {
        await controller.initialize();
        await controller.play();
      } catch (_) {
        await controller.dispose();
        controller = null;
      }
    }

    if (!mounted) {
      await controller?.dispose();
      return;
    }

    setState(() {
      _selectedFile = file;
      _previewVideoController = controller;
      _selectionLoading = false;
      _proxyProgress = null;
    });
  }

  void _onSelectAsset(AssetEntity asset) {
    if (_selectedAsset == asset) return;
    setState(() {
      _selectedAsset = asset;
    });
    _prepareSelection(asset);
  }

  void _onFilterChanged(FeedMediaType? filter) {
    if (_activeFilter == filter) return;

    final filtered = _applyFilter(_allAssets, filter);
    AssetEntity? nextSelected = _selectedAsset;
    if (nextSelected == null || !filtered.contains(nextSelected)) {
      nextSelected = filtered.isNotEmpty ? filtered.first : null;
    }

    setState(() {
      _activeFilter = filter;
      _visibleAssets = filtered;
      _selectedAsset = nextSelected;
    });

    if (nextSelected != null) {
      _prepareSelection(nextSelected);
    }
  }

  Future<void> _handleAdvance() async {
    if (_isAdvancing) return;

    final asset = _selectedAsset;
    if (asset == null) return;

    setState(() => _isAdvancing = true);

    try {
      File? file = _selectedFile;
      file ??= await asset.file;

      if (file == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('We could not read that media file.')),
        );
        return;
      }

      final mediaType = asset.type == AssetType.video
          ? FeedMediaType.video
          : FeedMediaType.image;

      final aspectRatio = _computeResultAspectRatio(asset);

      if (!mounted) return;

      Navigator.of(context).pop(
        MediaPickerResult(
          filePath: file.path,
          mediaType: mediaType,
          aspectRatio: aspectRatio,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isAdvancing = false);
      }
    }
  }

  Future<void> _openSettings() async {
    await PhotoManager.openSetting();
    if (!mounted) return;
    await _initGallery();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: _initializing
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : _permissionDenied
                ? _PermissionView(
                    onRequestPermission: _requestPermission,
                    onOpenSettings: _openSettings,
                    showSettings: _shouldShowSettingsButton,
                  )
                : _visibleAssets.isEmpty
                    ? _EmptyGalleryView(
                        onClose: () => Navigator.of(context).maybePop())
                    : Column(
                        children: [
                          _buildHeader(context),
                          Expanded(
                            child: Column(
                              children: [
                                _buildPreview(context),
                                _buildFilterBar(context),
                                Expanded(child: _buildGrid()),
                                if (_loadingMore)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                const SizedBox(height: 12),
                              ],
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close, color: Colors.white),
            tooltip: 'Close',
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'New post',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
          ),
          TextButton(
            onPressed:
                _isAdvancing || _selectionLoading || _selectedAsset == null
                    ? null
                    : _handleAdvance,
            child: _isAdvancing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Next',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final asset = _selectedAsset;
    final file = _selectedFile;
    final controller = _previewVideoController;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
      child: AspectRatio(
        aspectRatio: _resolvePreviewAspectRatio(asset),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: DecoratedBox(
            decoration: const BoxDecoration(color: Colors.black),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_selectionLoading)
                  _proxyProgress != null
                      ? TranscodeProgressOverlay(progress: _proxyProgress)
                      : const Center(
                          child:
                              CircularProgressIndicator(color: Colors.white),
                        )
                else if (asset == null || file == null)
                  const Center(
                    child: Icon(Icons.photo_library_outlined,
                        color: Colors.white30, size: 42),
                  )
                else if (asset.type == AssetType.video)
                  _buildVideoPreview(controller)
                else
                  Image.file(file, fit: BoxFit.cover),
                if (asset?.type == AssetType.video)
                  const Positioned(
                    top: 16,
                    right: 16,
                    child: Icon(Icons.videocam, color: Colors.white70),
                  ),
                if (_proxyError != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: TranscodeErrorBanner(message: _proxyError!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double _resolvePreviewAspectRatio(AssetEntity? asset) {
    if (asset == null) {
      return 3 / 4;
    }
    if (asset.type == AssetType.video) {
      final controller = _previewVideoController;
      if (controller != null && controller.value.isInitialized) {
        return _videoAspectRatioFromController(controller);
      }
      return _aspectRatioFromDimensions(
        asset.width.toDouble(),
        asset.height.toDouble(),
        fallback: _defaultVideoAspectRatio,
        invertIfGreaterThanOne: true,
      );
    }
    return _aspectRatioFromDimensions(
      asset.width.toDouble(),
      asset.height.toDouble(),
      fallback: 3 / 4,
    );
  }

  Widget _buildVideoPreview(VideoPlayerController? controller) {
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final videoSize = controller.value.size;
    final isLandscape = videoSize.width > videoSize.height;
    Widget player;
    if (isLandscape) {
      player = Transform.rotate(
        angle: math.pi / 2,
        child: SizedBox(
          width: videoSize.height,
          height: videoSize.width,
          child: VideoPlayer(controller),
        ),
      );
    } else {
      player = SizedBox(
        width: videoSize.width,
        height: videoSize.height,
        child: VideoPlayer(controller),
      );
    }

    return FittedBox(fit: BoxFit.cover, child: player);
  }

  double _computeResultAspectRatio(AssetEntity asset) {
    if (asset.type == AssetType.video) {
      final controller = _previewVideoController;
      if (controller != null && controller.value.isInitialized) {
        return _videoAspectRatioFromController(controller);
      }
      return _aspectRatioFromDimensions(
        asset.width.toDouble(),
        asset.height.toDouble(),
        fallback: _defaultVideoAspectRatio,
        invertIfGreaterThanOne: true,
      );
    }
    return _aspectRatioFromDimensions(
      asset.width.toDouble(),
      asset.height.toDouble(),
      fallback: _defaultImageAspectRatio,
    );
  }

  double _videoAspectRatioFromController(VideoPlayerController controller) {
    final size = controller.value.size;
    return _aspectRatioFromDimensions(
      size.width,
      size.height,
      fallback: _defaultVideoAspectRatio,
      invertIfGreaterThanOne: true,
    );
  }

  double _aspectRatioFromDimensions(
    double width,
    double height, {
    required double fallback,
    bool invertIfGreaterThanOne = false,
  }) {
    if (width <= 0 || height <= 0) {
      return fallback;
    }
    final ratio = width / height;
    if (!ratio.isFinite || ratio <= 0) {
      return fallback;
    }
    if (invertIfGreaterThanOne && ratio > 1) {
      return 1 / ratio;
    }
    return ratio;
  }

  Widget _buildFilterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          _FilterChip(
            label: 'All',
            selected: _activeFilter == null,
            onTap: () => _onFilterChanged(null),
          ),
          _FilterChip(
            label: 'Photos',
            selected: _activeFilter == FeedMediaType.image,
            onTap: () => _onFilterChanged(FeedMediaType.image),
          ),
          _FilterChip(
            label: 'Videos',
            selected: _activeFilter == FeedMediaType.video,
            onTap: () => _onFilterChanged(FeedMediaType.video),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    return GridView.builder(
      controller: _gridController,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: _visibleAssets.length,
      itemBuilder: (context, index) {
        final asset = _visibleAssets[index];
        return _AssetTile(
          asset: asset,
          selected: identical(asset, _selectedAsset),
          onTap: () => _onSelectAsset(asset),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: Colors.white,
        backgroundColor: Colors.white10,
        labelStyle: TextStyle(
          color: selected ? Colors.black : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({
    required this.asset,
    required this.selected,
    required this.onTap,
  });

  final AssetEntity asset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _AssetThumbnail(asset: asset),
            if (asset.type == AssetType.video)
              Positioned(
                left: 6,
                bottom: 6,
                child: Row(
                  children: [
                    const Icon(Icons.videocam, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(asset.duration),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (selected)
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _formatDuration(int totalSeconds) {
    if (totalSeconds <= 0) return '0:00';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _AssetThumbnail extends StatelessWidget {
  const _AssetThumbnail({required this.asset});

  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(
        const ThumbnailSize.square(400),
        quality: 85,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            snapshot.data == null) {
          return const ColoredBox(color: Colors.black26);
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
        );
      },
    );
  }
}

class _PermissionView extends StatelessWidget {
  const _PermissionView({
    required this.onRequestPermission,
    required this.onOpenSettings,
    required this.showSettings,
  });

  final VoidCallback onRequestPermission;
  final VoidCallback onOpenSettings;
  final bool showSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, color: Colors.white60, size: 48),
          const SizedBox(height: 24),
          const Text(
            'Allow gallery access',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Grant permission to browse your photos and videos directly inside the app.',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          if (showSettings)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'If you previously denied access, enable it from system settings.',
                style: TextStyle(color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onRequestPermission,
            child: const Text('Allow access'),
          ),
          if (showSettings) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
          ],
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

class _EmptyGalleryView extends StatelessWidget {
  const _EmptyGalleryView({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.photo_size_select_actual_outlined,
              color: Colors.white70, size: 48),
          const SizedBox(height: 22),
          const Text(
            'No media found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Add photos or videos to your gallery to create your first post.',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: onClose,
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
