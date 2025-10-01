import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/video_draft_provider.dart';
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

              debugPrint(
                  'VideoPickerPage: picked file: path=${pickedFile.path} name=${pickedFile.name}');

              final draft = await ref
                  .read(videoDraftsProvider.notifier)
                  .createDraftFromXFile(pickedFile);

              if (!context.mounted) {
                return;
              }

              context.goNamed(
                VideoEditorPage.routeName,
                extra: draft.id,
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
