import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/theme_controller.dart';
import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  static const routeName = 'profile';

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Sign in to view your coalition profile.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }

    final themeMode = ref.watch(themeControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _ProfileHeader(
              user: user,
              onChangePhoto: () => _handleAvatarChange(user),
            ),
            const SizedBox(height: 24),
            _ProfileDetails(user: user),
            const SizedBox(height: 24),
            _ThemeSelector(
              currentMode: themeMode,
              onModeSelected: (mode) =>
                  ref.read(themeControllerProvider.notifier).setThemeMode(mode),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () async {
                await ref.read(authControllerProvider.notifier).signOut();
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAvatarChange(AppUser user) async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxHeight: 720,
        maxWidth: 720,
        imageQuality: 85,
      );
      if (image == null) return;
      await ref
          .read(authControllerProvider.notifier)
          .updateProfileImage(image.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('We could not update your photo. Please try again.'),
        ),
      );
    }
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.onChangePhoto,
  });

  final AppUser user;
  final VoidCallback onChangePhoto;

  @override
  Widget build(BuildContext context) {
    final displayName = user.displayName.isEmpty
        ? '@${user.username}'
        : user.displayName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileAvatar(
              imagePath: user.profileImagePath,
              displayName: displayName,
              onTap: onChangePhoto,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '@${user.username}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 12),
                  _AccountTypeChip(accountType: user.accountType),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (user.bio.trim().isNotEmpty)
          Text(
            user.bio.trim(),
            style: Theme.of(context).textTheme.bodyMedium,
          )
        else
          Text(
            'Add a short bio to help others learn about your work.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.imagePath,
    required this.displayName,
    required this.onTap,
  });

  final String? imagePath;
  final String displayName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = 48.0;
    ImageProvider? provider;
    if (imagePath != null && imagePath!.isNotEmpty) {
      if (kIsWeb) {
        provider = NetworkImage(imagePath!);
      } else {
        final file = File(imagePath!);
        if (file.existsSync()) {
          provider = FileImage(file);
        }
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundImage: provider,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: provider == null
                ? Text(
                    displayName.isNotEmpty
                        ? displayName[0].toUpperCase()
                        : '?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                  )
                : null,
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: CircleAvatar(
              radius: 17,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: const Icon(
                Icons.camera_alt,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetails extends StatelessWidget {
  const _ProfileDetails({required this.user});

  final AppUser user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tiles = [
      _DetailTile(
        icon: Icons.mail_outline,
        label: 'Email',
        value: user.email,
      ),
      _DetailTile(
        icon: Icons.home_outlined,
        label: 'ZIP code',
        value: user.zipCode.isEmpty ? 'Not provided' : user.zipCode,
      ),
      _DetailTile(
        icon: Icons.favorite_border,
        label: 'Supporters',
        value: '${user.followersCount}',
      ),
      _DetailTile(
        icon: Icons.event_available_outlined,
        label: 'Events RSVP’d',
        value: '${user.rsvpEventIds.length}',
      ),
    ];

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            tiles[i],
            if (i != tiles.length - 1)
              Divider(
                height: 0,
                indent: 16,
                endIndent: 16,
                color: theme.colorScheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(
        value.isEmpty ? 'Not available' : value,
        style: theme.textTheme.bodyMedium,
      ),
    );
  }
}

class _AccountTypeChip extends StatelessWidget {
  const _AccountTypeChip({required this.accountType});

  final UserAccountType accountType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCandidate = accountType == UserAccountType.candidate;
    final background = isCandidate
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.secondaryContainer;
    final foreground = isCandidate
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isCandidate ? Icons.campaign_outlined : Icons.person_outline,
            size: 16,
            color: foreground,
          ),
          const SizedBox(width: 6),
          Text(
            isCandidate ? 'Candidate' : 'Constituent',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({
    required this.currentMode,
    required this.onModeSelected,
  });

  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onModeSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appearance',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<ThemeMode>(
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ButtonSegment(value: ThemeMode.light, label: Text('Light')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
          ],
          selected: <ThemeMode>{currentMode},
          onSelectionChanged: (value) {
            final mode = value.isEmpty ? ThemeMode.system : value.first;
            onModeSelected(mode);
          },
        ),
      ],
    );
  }
}
