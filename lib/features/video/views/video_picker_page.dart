import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/video_timeline_provider.dart';
import '../services/video_permission_service.dart';
import 'video_editor_page.dart';

class VideoPickerPage extends ConsumerWidget {
  const VideoPickerPage({super.key});

  static const routeName = 'video-picker';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select video')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final permissionService = ref.read(videoPermissionServiceProvider);
            VideoPermissionResult permissionResult;
            try {
              permissionResult = await permissionService.ensureGranted();
            } on VideoPermissionException catch (error) {
              if (!context.mounted) {
                return;
              }
              final message = error.message.isNotEmpty
                  ? error.message
                  : 'Unable to verify video permissions. Please try again later.';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
              return;
            }
            if (!permissionResult.granted) {
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    permissionResult.permanentlyDenied
                        ? 'Enable video permissions in Settings to pick a video.'
                        : 'Allow video access to pick a clip.',
                  ),
                  action: permissionResult.permanentlyDenied
                      ? SnackBarAction(
                          label: 'Settings',
                          onPressed: () {
                            permissionService.openAppSettingsPage();
                          },
                        )
                      : null,
                ),
              );
              return;
            }
            final picker = ImagePicker();

            try {
              final pickedFile = await picker.pickVideo(
                source: ImageSource.gallery,
              );

              if (pickedFile == null) {
                return;
              }

              final persistedPath = await _persistVideoSelection(pickedFile);

              ref
                  .read(videoTimelineProvider.notifier)
                  .loadSource(persistedPath);

              if (!context.mounted) {
                return;
              }

              context.goNamed(
                VideoEditorPage.routeName,
                extra: persistedPath,
              );
            } on PlatformException catch (error) {
              if (!context.mounted) {
                return;
              }

              final message = error.message ?? 'Unable to pick video.';
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(message)),
              );
            } catch (error, stackTrace) {
              debugPrint('Failed to prepare picked video: $error\n$stackTrace');
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Unable to access the selected video.')),
              );
            }
          },
          child: const Text('Pick from gallery'),
        ),
      ),
    );
  }
}

Future<String> _persistVideoSelection(XFile pickedFile) async {
  final tempDir = await getTemporaryDirectory();
  final extension = _extensionFor(pickedFile);
  final destination = p.join(
    tempDir.path,
    'video_${DateTime.now().millisecondsSinceEpoch}$extension',
  );

  try {
    await pickedFile.saveTo(destination);
  } on UnsupportedError {
    final bytes = await pickedFile.readAsBytes();
    await File(destination).writeAsBytes(bytes);
  } on PlatformException {
    final bytes = await pickedFile.readAsBytes();
    await File(destination).writeAsBytes(bytes);
  }

  final persistedFile = File(destination);
  if (!await persistedFile.exists()) {
    throw FileSystemException('Persisted video missing', destination);
  }

  return destination;
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
    return '.${candidate}';
  }
  return candidate;
}
