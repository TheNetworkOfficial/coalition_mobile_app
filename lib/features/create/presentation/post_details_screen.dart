import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/domain/feed_content.dart';
import '../data/create_content_service.dart';
import '../domain/create_post_request.dart';

class PostDetailsScreen extends ConsumerStatefulWidget {
  const PostDetailsScreen({
    required this.mediaPath,
    required this.mediaType,
    required this.aspectRatio,
    this.initialCoverPath,
    this.videoDuration,
    this.composition,
    super.key,
  });

  final String mediaPath;
  final FeedMediaType mediaType;
  final double aspectRatio;
  final String? initialCoverPath;
  final Duration? videoDuration;
  final List<double>? composition;

  @override
  ConsumerState<PostDetailsScreen> createState() => _PostDetailsScreenState();
}

class _PostDetailsScreenState extends ConsumerState<PostDetailsScreen> {
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _linkController = TextEditingController();
  final Set<String> _hashtags = <String>{};
  final Set<String> _mentions = <String>{};
  String? _selectedLocation;
  bool _allowComments = true;
  bool _allowSharing = true;
  String _visibility = 'public';
  bool _acceptMusicPolicy = false;
  String? _coverImagePath;
  Duration _coverPosition = const Duration(seconds: 1);
  bool _isGeneratingCover = false;

  @override
  void initState() {
    super.initState();
    _coverImagePath = widget.initialCoverPath;
    if (widget.mediaType == FeedMediaType.video && _coverImagePath == null) {
      _generateCover(fromPosition: const Duration(seconds: 1));
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _coverImagePath ?? widget.mediaPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post details'),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _descriptionController,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: 'Add description...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  _PreviewCard(
                    previewPath: preview,
                    onEditCover: widget.mediaType == FeedMediaType.video &&
                            !_isGeneratingCover
                        ? _showCoverEditor
                        : null,
                    isLoading: _isGeneratingCover,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _showHashtagDialog,
                      child: const Text('# Hashtags'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _showMentionDialog,
                      child: const Text('@ Mention'),
                    ),
                  ),
                ],
              ),
              if (_hashtags.isNotEmpty || _mentions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _hashtags)
                      Chip(
                        label: Text('#$tag'),
                        onDeleted: () => setState(() => _hashtags.remove(tag)),
                      ),
                    for (final mention in _mentions)
                      Chip(
                        avatar: const Icon(Icons.alternate_email, size: 16),
                        label: Text(mention),
                        onDeleted: () =>
                            setState(() => _mentions.remove(mention)),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              const _SectionHeader(title: 'Location'),
              _LocationPicker(
                selectedLocation: _selectedLocation,
                onLocationSelected: (value) => setState(() {
                  _selectedLocation = value;
                }),
              ),
              const Divider(height: 32),
              const _SectionHeader(title: 'Add link'),
              TextField(
                controller: _linkController,
                decoration: const InputDecoration(
                  hintText: 'Paste an external link',
                  border: OutlineInputBorder(),
                ),
              ),
              const Divider(height: 32),
              _VisibilitySelector(
                visibility: _visibility,
                onChanged: (value) => setState(() => _visibility = value),
              ),
              SwitchListTile(
                value: _allowComments,
                onChanged: (value) => setState(() => _allowComments = value),
                title: const Text('Allow comments'),
              ),
              SwitchListTile(
                value: _allowSharing,
                onChanged: (value) => setState(() => _allowSharing = value),
                title: const Text('Allow sharing'),
              ),
              const SizedBox(height: 16),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ShareTargetButton(icon: Icons.chat_bubble_outline),
                  _ShareTargetButton(icon: Icons.facebook),
                  _ShareTargetButton(icon: Icons.sms),
                ],
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _acceptMusicPolicy,
                onChanged: (value) =>
                    setState(() => _acceptMusicPolicy = value ?? false),
                title: const Text('I accept the Music Usage Confirmation'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Drafts'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _acceptMusicPolicy ? _submit : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xfffe2c55),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Post'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showHashtagDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add hashtag'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter hashtag'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (value != null && value.isNotEmpty) {
      setState(() => _hashtags.add(value.replaceAll('#', '')));
    }
  }

  Future<void> _showMentionDialog() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Mention user'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '@username'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (value != null && value.isNotEmpty) {
      setState(() => _mentions.add(value.startsWith('@') ? value : '@$value'));
    }
  }

  Future<void> _showCoverEditor() async {
    if (widget.videoDuration == null) {
      return;
    }
    final maxSeconds = widget.videoDuration!.inMilliseconds / 1000.0;
    double tempValue = _coverPosition.inMilliseconds / 1000.0;

    final result = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Select cover frame'),
                  Slider(
                    min: 0,
                    max: maxSeconds,
                    value: tempValue.clamp(0, maxSeconds),
                    onChanged: (value) {
                      setModalState(() => tempValue = value);
                    },
                  ),
                  Text('${tempValue.toStringAsFixed(1)}s'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(tempValue),
                    child: const Text('Use frame'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      final position = Duration(milliseconds: (result * 1000).round());
      await _generateCover(fromPosition: position);
      setState(() {
        _coverPosition = position;
      });
    }
  }

  Future<void> _generateCover({required Duration fromPosition}) async {
    if (_isGeneratingCover) return;
    setState(() => _isGeneratingCover = true);
    try {
      final path =
          await ref.read(createContentServiceProvider).generateCoverFromVideo(
                videoPath: widget.mediaPath,
                position: fromPosition,
              );
      if (!mounted) return;
      setState(() {
        _coverImagePath = path;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture cover frame: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isGeneratingCover = false);
      }
    }
  }

  void _submit() {
    final request = CreatePostRequest(
      mediaPath: widget.mediaPath,
      mediaType: widget.mediaType,
      description: _descriptionController.text.trim(),
      tags: _hashtags.toList(),
      aspectRatio: widget.aspectRatio,
      coverImagePath: _coverImagePath,
      coverFramePosition:
          widget.mediaType == FeedMediaType.video ? _coverPosition : null,
      overlays: const <FeedTextOverlay>[],
      compositionTransform: widget.composition,
      location: _selectedLocation,
      mentions: _mentions.toList(),
      visibility: _visibility,
      allowComments: _allowComments,
      allowSharing: _allowSharing,
      externalLink: _linkController.text.trim().isEmpty
          ? null
          : _linkController.text.trim(),
    );

    Navigator.of(context).pop(request);
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.previewPath,
    this.onEditCover,
    this.isLoading = false,
  });

  final String previewPath;
  final VoidCallback? onEditCover;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Preview',
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PreviewImage(path: previewPath),
                  if (isLoading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  if (onEditCover != null)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: FilledButton(
                        onPressed: onEditCover,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.7),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                        child: const Text('Edit cover'),
                      ),
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

class _PreviewImage extends StatelessWidget {
  const _PreviewImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(path);
    ImageProvider provider;
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      provider = NetworkImage(path);
    } else if (uri != null && uri.scheme == 'file') {
      provider = FileImage(File(uri.toFilePath()));
    } else {
      provider = FileImage(File(path));
    }
    return Image(image: provider, fit: BoxFit.cover);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style:
            theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _LocationPicker extends StatelessWidget {
  const _LocationPicker({
    required this.selectedLocation,
    required this.onLocationSelected,
  });

  final String? selectedLocation;
  final ValueChanged<String?> onLocationSelected;

  static const _locations = <String>[
    'Helena',
    'Home Sweet Home',
    'Deadman Pass',
    'Deer Lodge',
    'Billings',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final location in _locations)
          ChoiceChip(
            label: Text(location),
            selected: selectedLocation == location,
            onSelected: (value) => onLocationSelected(value ? location : null),
          ),
        ChoiceChip(
          label: const Text('None'),
          selected: selectedLocation == null,
          onSelected: (value) => onLocationSelected(null),
        ),
      ],
    );
  }
}

class _VisibilitySelector extends StatelessWidget {
  const _VisibilitySelector({
    required this.visibility,
    required this.onChanged,
  });

  final String visibility;
  final ValueChanged<String> onChanged;

  static const options = <String, String>{
    'public': 'Everyone can view this post',
    'friends': 'Friends only',
    'private': 'Only me',
  };

  @override
  Widget build(BuildContext context) {
    final currentLabel = options[visibility] ?? options.values.first;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Visibility'),
      subtitle: Text(currentLabel),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.keyboard_arrow_down),
        onSelected: onChanged,
        itemBuilder: (context) {
          return [
            for (final entry in options.entries)
              PopupMenuItem<String>(
                value: entry.key,
                child: Text(entry.value),
              ),
          ];
        },
      ),
    );
  }
}

class _ShareTargetButton extends StatelessWidget {
  const _ShareTargetButton({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, color: Colors.white70),
      ),
    );
  }
}
