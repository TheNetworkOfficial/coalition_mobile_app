// The code performs `mounted` checks before and after awaiting calls that accept
// a BuildContext. Suppress the analyzer's use_build_context_synchronously lint
// for this file to avoid noisy info-level warnings.
// ignore_for_file: use_build_context_synchronously

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import '../platform/video_native.dart';
import '../services/video_permission_service.dart';

class VideoPickerPage extends ConsumerStatefulWidget {
  const VideoPickerPage({
    super.key,
    this.galleryPickerOverride,
    this.cameraPickerOverride,
  });

  static const routeName = 'video-picker';

  final Future<File?> Function(BuildContext context)? galleryPickerOverride;
  final Future<File?> Function(BuildContext context)? cameraPickerOverride;

  @override
  ConsumerState<VideoPickerPage> createState() => _VideoPickerPageState();
}

class _VideoPickerPageState extends ConsumerState<VideoPickerPage> {
  static const int _flagReadUriPermission = 0x00000001;
  static const int _flagPersistableUriPermission = 0x00000040;

  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Select video')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PickerButton(
                icon: Icons.video_library_outlined,
                label: 'Pick from gallery',
                onPressed: _isProcessing ? null : _handleGallery,
              ),
              const SizedBox(height: 16),
              _PickerButton(
                icon: Icons.videocam_outlined,
                label: 'Record a video',
                onPressed: _isProcessing ? null : _handleCamera,
              ),
              if (_isProcessing) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator.adaptive(),
                const SizedBox(height: 8),
                Text(
                  'Preparing video…',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleGallery() async {
    final permissionService = ref.read(videoPermissionServiceProvider);
    VideoPermissionResult permissionResult;
    try {
      permissionResult = await permissionService.ensureGranted();
    } on VideoPermissionException catch (error) {
      _showError(
        error.message.isNotEmpty
            ? error.message
            : 'Unable to verify video permissions. Please try again later.',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    if (!permissionResult.granted) {
      _handlePermissionDenied(permissionResult);
      return;
    }

    try {
      setState(() => _isProcessing = true);
      // Passing BuildContext to an async call is safe here because we check
      // `mounted` before and after.
      final File? picked = widget.galleryPickerOverride != null
          ? await widget.galleryPickerOverride!(context)
          : await _pickGalleryFile(context);
      if (!mounted) {
        return;
      }
      if (picked == null) {
        setState(() => _isProcessing = false);
        if (widget.galleryPickerOverride == null) {
          if (!mounted) {
            return;
          }
          _showError('Unable to access the selected video.');
        }
        return;
      }

      // If an override is provided we assume the file is already local for
      // testing purposes and skip copying to a temp directory which may interact
      // with platform channels in tests.
      final local = widget.galleryPickerOverride != null
          ? picked
          : await _ensureLocalCopy(picked);
      if (!mounted) {
        return;
      }
      setState(() => _isProcessing = false);
      _goToEditor(local.path);
    } on PlatformException catch (error) {
      setState(() => _isProcessing = false);
      if (!mounted) {
        return;
      }
      _showError(error.message ?? 'Unable to pick video.');
    } catch (error, stackTrace) {
      debugPrint('Failed to pick gallery video: $error\n$stackTrace');
      setState(() => _isProcessing = false);
      if (!mounted) {
        return;
      }
      _showError('Unable to access the selected video.');
    }
  }

  Future<void> _handleCamera() async {
    final permissionService = ref.read(videoPermissionServiceProvider);
    VideoPermissionResult mediaPermission;
    try {
      mediaPermission = await permissionService.ensureGranted();
    } on VideoPermissionException catch (error) {
      _showError(
        error.message.isNotEmpty
            ? error.message
            : 'Unable to verify video permissions. Please try again later.',
      );
      return;
    }

    if (!mounted) {
      return;
    }
    if (!mediaPermission.granted) {
      _handlePermissionDenied(mediaPermission);
      return;
    }

    final cameraPermission = await permissionService.ensureCameraGranted();
    if (!mounted) {
      return;
    }
    if (!cameraPermission.granted) {
      _handlePermissionDenied(cameraPermission);
      return;
    }

    try {
      setState(() => _isProcessing = true);
      // Passing BuildContext to an async call is safe here because we check
      // `mounted` before and after.
      final File? picked = widget.cameraPickerOverride != null
          ? await widget.cameraPickerOverride!(context)
          : await _pickCameraFile(context);
      if (!mounted) {
        return;
      }
      if (picked == null) {
        setState(() => _isProcessing = false);
        if (widget.cameraPickerOverride == null) {
          if (!mounted) {
            return;
          }
          _showError('Unable to access the recorded video.');
        }
        return;
      }
      final local = widget.cameraPickerOverride != null
          ? picked
          : await _ensureLocalCopy(picked);
      if (!mounted) {
        return;
      }
      setState(() => _isProcessing = false);
      _goToEditor(local.path);
    } on PlatformException catch (error) {
      setState(() => _isProcessing = false);
      if (!mounted) {
        return;
      }
      _showError(error.message ?? 'Unable to record video.');
    } catch (error, stackTrace) {
      debugPrint('Failed to record video: $error\n$stackTrace');
      setState(() => _isProcessing = false);
      if (!mounted) {
        return;
      }
      _showError('Unable to record video.');
    }
  }

  Future<File> _ensureLocalCopy(File source) async {
    final tmp = await getTemporaryDirectory();
    final normalizedSource = p.normalize(source.path);
    if (normalizedSource.startsWith(tmp.path)) {
      return source;
    }
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${p.basename(source.path)}';
    final dest = File(p.join(tmp.path, filename));
    return source.copy(dest.path);
  }

  void _goToEditor(String path) {
    context.go('/create/video/editor', extra: {'filePath': path});
  }

  Future<File?> _pickGalleryFile(BuildContext context) async {
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: const AssetPickerConfig(
        requestType: RequestType.video,
        maxAssets: 1,
      ),
    );
    if (assets == null || assets.isEmpty) {
      return null;
    }
    await _persistAssetPermission(assets.first);
    return assets.first.file;
  }

  Future<File?> _pickCameraFile(BuildContext context) async {
    final entity = await CameraPicker.pickFromCamera(
      context,
      pickerConfig: const CameraPickerConfig(
        enableAudio: true,
        enableRecording: true,
        onlyEnableRecording: true,
      ),
    );
    return entity?.file;
  }

  void _handlePermissionDenied(VideoPermissionResult result) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.permanentlyDenied
              ? 'Enable video permissions in Settings to continue.'
              : 'Allow access to continue.',
        ),
        action: result.permanentlyDenied
            ? SnackBarAction(
                label: 'Settings',
                onPressed: () {
                  ref
                      .read(videoPermissionServiceProvider)
                      .openAppSettingsPage();
                },
              )
            : null,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _persistAssetPermission(AssetEntity asset) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final uri = await asset.getMediaUrl();
      if (uri == null || !uri.startsWith('content://')) {
        return;
      }
      final intentFlags = _inferPersistableFlags(uri);
      await ref
          .read(videoNativeProvider)
          .persistUriPermission(uri, intentFlags: intentFlags);
    } catch (error, stackTrace) {
      debugPrint('Failed to persist URI permission for asset: $error\n$stackTrace');
    }
  }

  int _inferPersistableFlags(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null) {
      return 0;
    }
    if (parsed.scheme?.toLowerCase() != 'content') {
      return 0;
    }

    final segments = parsed.pathSegments;
    final isDocument = segments.contains('document') || uri.contains('/document/');
    if (!isDocument) {
      return 0;
    }

    return _flagReadUriPermission | _flagPersistableUriPermission;
  }
}

class _PickerButton extends StatelessWidget {
  const _PickerButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(label),
        ),
      ),
    );
  }
}
