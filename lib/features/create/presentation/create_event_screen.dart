import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import '../../auth/data/auth_controller.dart';
import '../../auth/domain/app_user.dart';
import '../../candidates/data/candidate_providers.dart';
import '../../candidates/domain/candidate.dart';
import '../../events/data/event_providers.dart';
import '../../events/domain/event.dart';
import '../../feed/domain/feed_content.dart';
import '../data/create_content_service.dart';
import '../domain/create_event_request.dart';
import 'widgets/media_composer_support.dart';

class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({super.key});

  static const routeName = 'create-event';

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  static const _uuid = Uuid();
  static const double _defaultMediaAspectRatio = 9 / 16;

  static const _eventTypes = <String, String>{
    'organizing': 'Organizing & field',
    'town-hall': 'Town hall / forum',
    'fundraiser': 'Fundraiser',
    'training': 'Training / workshop',
    'general': 'Community gathering',
  };

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final FocusNode _descriptionFocusNode = FocusNode();

  XFile? _mediaFile;
  FeedMediaType? _mediaType;
  double? _mediaAspectRatio;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;

  final List<EditableOverlay> _overlays = <EditableOverlay>[];
  final Set<String> _selectedTags = <String>{};
  final Set<String> _selectedCandidateIds = <String>{};
  final List<_EventSlotDraft> _slots = <_EventSlotDraft>[];

  DateTime? _eventDate;
  TimeOfDay _eventTime = const TimeOfDay(hour: 18, minute: 0);

  String _eventType = 'organizing';

  String? _generatedCoverPath;
  XFile? _customCoverFile;
  Duration? _coverFramePosition;
  bool _isGeneratingCover = false;

  bool _isSubmitting = false;

  @override
  void dispose() {
    _disposeVideoController();
    _titleController.dispose();
    _locationController.dispose();
    _costController.dispose();
    _descriptionController.dispose();
    _descriptionFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final user = authState.user;

    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to publish events.')),
      );
    }

    if (user.accountType != UserAccountType.candidate) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Only candidate accounts can create coalition events. Message the admin team to request a candidate upgrade.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      );
    }

    final eventTagsAsync = ref.watch(eventTagsProvider);
    final eventTags = eventTagsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <String>[],
    );

    final candidatesAsync = ref.watch(candidateListProvider);
    final candidateList = candidatesAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <Candidate>[],
    );

    final canSubmit = !_isSubmitting && _titleController.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create event'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Discard',
        ),
        actions: [
          TextButton(
            onPressed: canSubmit ? () => _handleSubmit(user) : null,
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Text('Publish'),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildMediaSection(context)),
            SliverToBoxAdapter(child: _buildOverlaySection(context)),
            SliverToBoxAdapter(child: _buildDetailsSection(context)),
            SliverToBoxAdapter(
                child: _buildHostsSection(context, candidateList)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Event tags',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (eventTagsAsync.isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (eventTags.isEmpty)
                      Text(
                        'Tags help volunteers discover events by focus area. Admins can configure new tags in the dashboard.',
                        style: Theme.of(context).textTheme.bodySmall,
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final tag in eventTags)
                            FilterChip(
                              label: Text(tag),
                              selected: _selectedTags.contains(tag),
                              onSelected: (value) => setState(() {
                                if (value) {
                                  _selectedTags.add(tag);
                                } else {
                                  _selectedTags.remove(tag);
                                }
                              }),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    if (_mediaFile == null || _mediaType == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border:
                Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.event_available_outlined,
                    size: 64, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Add a cover visual',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose a photo or a short video teaser. You can layer text overlays, customize fonts, and set a cover image to match campaign branding.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose photo'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _pickVideo,
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Choose video'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final aspectRatio = _mediaAspectRatio ??
        (_mediaType == FeedMediaType.video
            ? (_videoController?.value.aspectRatio ?? _defaultMediaAspectRatio)
            : _defaultMediaAspectRatio);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio:
                aspectRatio <= 0 ? _defaultMediaAspectRatio : aspectRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      Positioned.fill(child: _buildMediaPreview()),
                      if (_overlays.isNotEmpty)
                        Positioned.fill(
                          child: OverlayLayer(
                            overlays: _overlays,
                            onOverlayDragged: (id, delta) {
                              _updateOverlayPosition(
                                  id, delta, constraints.biggest);
                            },
                            onOverlayTapped: (overlay) {
                              _openOverlayEditor(existing: overlay);
                            },
                          ),
                        ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.photo_camera_back_outlined,
                                color: Colors.white),
                            tooltip: 'Change media',
                            onPressed: () => _showMediaSwapSheet(context),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_mediaType == FeedMediaType.video)
            OutlinedButton.icon(
              onPressed: _isGeneratingCover ? null : _openCoverEditor,
              icon: _isGeneratingCover
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.photo_album_outlined),
              label: Text(
                _generatedCoverPath != null || _customCoverFile != null
                    ? 'Update cover image'
                    : 'Edit cover image',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview() {
    if (_mediaType == FeedMediaType.video) {
      final controller = _videoController;
      if (controller == null) {
        return const ColoredBox(color: Colors.black12);
      }
      return FutureBuilder<void>(
        future: _videoInitialization,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!controller.value.isInitialized) {
            return const ColoredBox(color: Colors.black12);
          }
          if (!controller.value.isPlaying) {
            controller
              ..setLooping(true)
              ..play();
          }
          return FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          );
        },
      );
    }

    return Image.file(
      File(_mediaFile!.path),
      fit: BoxFit.cover,
    );
  }

  Widget _buildOverlaySection(BuildContext context) {
    if (_mediaFile == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Text overlays', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Highlight speaker names, calls to action, or sponsorship language. Drag overlays to reposition and tap to edit styles.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              FilledButton.icon(
                onPressed: () => _openOverlayEditor(),
                icon: const Icon(Icons.text_fields_outlined),
                label: const Text('Add text'),
              ),
              if (_overlays.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () => setState(() => _overlays.clear()),
                  icon: const Icon(Icons.layers_clear),
                  label: const Text('Clear overlays'),
                ),
            ],
          ),
          if (_overlays.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final overlay in _overlays)
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerLow,
                child: ListTile(
                  title: Text(
                    overlay.text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: overlay.fontFamily,
                      fontWeight: overlay.fontWeight,
                      fontStyle: overlay.fontStyle,
                      fontSize: overlay.fontSize,
                      color: overlay.color,
                    ),
                  ),
                  subtitle: Text(
                    'Font: ${overlay.displayFontLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Edit overlay',
                    onPressed: () => _openOverlayEditor(existing: overlay),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailsSection(BuildContext context) {
    final theme = Theme.of(context);
    final localization = MaterialLocalizations.of(context);

    final dateLabel = _eventDate != null
        ? localization.formatFullDate(_eventDate!)
        : 'Select date';
    final timeLabel = _eventDate != null
        ? localization.formatTimeOfDay(TimeOfDay.fromDateTime(_eventDate!))
        : localization.formatTimeOfDay(_eventTime);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Event details', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Event title'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(dateLabel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _eventDate == null ? null : _pickTime,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text(timeLabel),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            textCapitalization: TextCapitalization.words,
            decoration:
                const InputDecoration(labelText: 'Location or meeting link'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _eventType,
            decoration: const InputDecoration(labelText: 'Event type'),
            items: [
              for (final entry in _eventTypes.entries)
                DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
            onChanged: (value) => setState(() {
              if (value != null) {
                _eventType = value;
              }
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _costController,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Cost or RSVP notes (optional)',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionController,
            focusNode: _descriptionFocusNode,
            maxLines: 6,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Event description',
              hintText:
                  'Share speakers, agenda, accessibility notes, or volunteer expectations.',
            ),
          ),
          const SizedBox(height: 20),
          Text('RSVP slots', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_slots.isEmpty)
            Text(
              'Add optional time slots with capacity limits for trainings or canvasses.',
              style: theme.textTheme.bodySmall,
            ),
          for (final slot in _slots)
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              child: ListTile(
                title: Text(slot.label),
                subtitle: slot.capacity != null
                    ? Text('Capacity: ${slot.capacity}')
                    : const Text('No capacity limit'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove slot',
                  onPressed: () => setState(() => _slots.remove(slot)),
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _openAddSlotDialog,
              icon: const Icon(Icons.add_outlined),
              label: const Text('Add time slot'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHostsSection(BuildContext context, List<Candidate> candidates) {
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Hosted by',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final candidate in candidates)
                FilterChip(
                  label: Text(candidate.name),
                  selected: _selectedCandidateIds.contains(candidate.id),
                  onSelected: (value) => setState(() {
                    if (value) {
                      _selectedCandidateIds.add(candidate.id);
                    } else {
                      _selectedCandidateIds.remove(candidate.id);
                    }
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
        maxHeight: 2160,
        maxWidth: 2160,
      );
      if (file == null) return;
      await _setMedia(file, FeedMediaType.image);
    } on PlatformException catch (error) {
      _showError('We could not access your gallery (${error.message}).');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _picker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 7),
      );
      if (file == null) return;
      await _setMedia(file, FeedMediaType.video);
    } on PlatformException catch (error) {
      _showError('We could not access your gallery (${error.message}).');
    }
  }

  Future<void> _setMedia(XFile file, FeedMediaType type) async {
    _disposeVideoController();
    setState(() {
      _mediaFile = file;
      _mediaType = type;
      _generatedCoverPath = null;
      _customCoverFile = null;
      _coverFramePosition = null;
      _overlays.clear();
      _mediaAspectRatio = null;
    });

    if (type == FeedMediaType.image) {
      final fileBytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(fileBytes);
      setState(() {
        _mediaAspectRatio = decoded.width == 0
            ? _defaultMediaAspectRatio
            : decoded.width / decoded.height;
      });
    } else {
      final controller = VideoPlayerController.file(File(file.path));
      setState(() {
        _videoController = controller;
        _videoInitialization = controller.initialize().then((_) {
          setState(() {
            _mediaAspectRatio = controller.value.aspectRatio;
          });
          controller
            ..setLooping(true)
            ..play();
        });
      });
    }
  }

  void _disposeVideoController() {
    _videoController?.dispose();
    _videoController = null;
    _videoInitialization = null;
  }

  Future<void> _showMediaSwapSheet(BuildContext context) async {
    final action = await showModalBottomSheet<MediaSwapAction>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Replace with photo'),
              onTap: () => Navigator.of(ctx).pop(MediaSwapAction.photo),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Replace with video'),
              onTap: () => Navigator.of(ctx).pop(MediaSwapAction.video),
            ),
            if (_mediaFile != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Remove media'),
                onTap: () => Navigator.of(ctx).pop(MediaSwapAction.remove),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    switch (action) {
      case MediaSwapAction.photo:
        await _pickImage();
        break;
      case MediaSwapAction.video:
        await _pickVideo();
        break;
      case MediaSwapAction.remove:
        setState(() {
          _mediaFile = null;
          _mediaType = null;
          _overlays.clear();
          _generatedCoverPath = null;
          _customCoverFile = null;
          _coverFramePosition = null;
        });
        _disposeVideoController();
        break;
      case null:
        break;
    }
  }

  void _updateOverlayPosition(
    String id,
    Offset delta,
    Size canvasSize,
  ) {
    final overlayIndex = _overlays.indexWhere((element) => element.id == id);
    if (overlayIndex == -1) return;
    if (canvasSize.width == 0 || canvasSize.height == 0) return;

    final overlay = _overlays[overlayIndex];
    final dx = delta.dx / canvasSize.width;
    final dy = delta.dy / canvasSize.height;

    final updated = overlay.copyWith(
      position: Offset(
        (overlay.position.dx + dx).clamp(0.0, 1.0),
        (overlay.position.dy + dy).clamp(0.0, 1.0),
      ),
    );

    setState(() => _overlays[overlayIndex] = updated);
  }

  Future<void> _openOverlayEditor({EditableOverlay? existing}) async {
    final initial = existing ??
        EditableOverlay(
          id: _uuid.v4(),
          text: 'Event headline',
          color: Colors.white,
          fontFamily: overlayFontOptions.first.fontFamily,
          fontLabel: overlayFontOptions.first.label,
          fontWeight: overlayFontOptions.first.fontWeight,
          fontStyle: overlayFontOptions.first.fontStyle,
          fontSize: 24,
          position: const Offset(0.38, 0.3),
        );

    final result = await showModalBottomSheet<OverlayEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => OverlayEditorSheet(
        initial: initial,
        allowDelete: existing != null,
      ),
    );

    if (result == null) return;

    if (result.delete && existing != null) {
      setState(
          () => _overlays.removeWhere((element) => element.id == existing.id));
      return;
    }

    final overlay = result.overlay;
    if (overlay == null) return;

    setState(() {
      final index = _overlays.indexWhere((element) => element.id == overlay.id);
      if (index == -1) {
        _overlays.add(overlay);
      } else {
        _overlays[index] = overlay;
      }
    });
  }

  Future<void> _openCoverEditor() async {
    if (_mediaType != FeedMediaType.video || _videoController == null) {
      return;
    }
    final controller = _videoController!;
    await controller.pause();

    if (!mounted) return;
    final result = await showModalBottomSheet<CoverEditorResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => CoverEditorSheet(
        controller: controller,
        initialFrame: _coverFramePosition,
        initialCustomCoverPath: _customCoverFile?.path,
      ),
    );

    if (result == null) {
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (result.clear) {
      setState(() {
        _generatedCoverPath = null;
        _customCoverFile = null;
        _coverFramePosition = null;
      });
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (result.customCoverPath != null) {
      setState(() {
        _generatedCoverPath = null;
        _customCoverFile = XFile(result.customCoverPath!);
        _coverFramePosition = null;
      });
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (result.framePosition != null) {
      setState(() {
        _coverFramePosition = result.framePosition;
        _isGeneratingCover = true;
      });
      try {
        final generated =
            await ref.read(createContentServiceProvider).generateCoverFromVideo(
                  videoPath: _mediaFile!.path,
                  position: result.framePosition!,
                );
        if (!mounted) return;
        setState(() {
          _generatedCoverPath = generated;
          _customCoverFile = null;
        });
      } catch (error) {
        _showError('We could not save that frame as a cover. $error');
      } finally {
        if (mounted) {
          setState(() => _isGeneratingCover = false);
        }
      }
      if (!mounted) return;
      await controller.play();
      return;
    }

    if (!mounted) return;
    await controller.play();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _eventDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _eventDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _eventTime.hour,
        _eventTime.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          _eventDate != null ? TimeOfDay.fromDateTime(_eventDate!) : _eventTime,
    );
    if (picked == null) return;
    setState(() {
      _eventTime = picked;
      final baseDate = _eventDate ?? DateTime.now();
      _eventDate = DateTime(
        baseDate.year,
        baseDate.month,
        baseDate.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _openAddSlotDialog() async {
    final labelController = TextEditingController();
    final capacityController = TextEditingController();

    final result = await showDialog<_EventSlotDraft>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add RSVP slot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelController,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Slot label'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: capacityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacity (optional)',
                hintText: 'Leave blank for unlimited',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final label = labelController.text.trim();
              if (label.isEmpty) {
                return;
              }
              final capacityText = capacityController.text.trim();
              final capacity = int.tryParse(capacityText);
              Navigator.of(ctx).pop(
                _EventSlotDraft(
                  id: _uuid.v4(),
                  label: label,
                  capacity: capacity,
                ),
              );
            },
            child: const Text('Add slot'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() => _slots.add(result));
    }
  }

  Future<void> _handleSubmit(AppUser user) async {
    final title = _titleController.text.trim();
    final location = _locationController.text.trim();
    final summary = _descriptionController.text.trim();
    final cost = _costController.text.trim();

    if (title.isEmpty) {
      _showError('Add a short event title.');
      return;
    }
    if (_eventDate == null) {
      _showError('Select a date and time.');
      return;
    }
    if (location.isEmpty) {
      _showError('Add a meeting location or virtual link.');
      return;
    }

    final overlays = [
      for (final overlay in _overlays)
        FeedTextOverlay(
          id: overlay.id,
          text: overlay.text,
          color: overlay.color,
          fontFamily: overlay.fontFamily,
          fontWeight: overlay.fontWeight,
          fontStyle: overlay.fontStyle,
          fontSize: overlay.fontSize,
          position: overlay.position,
        ),
    ];

    final slots = [
      for (final slot in _slots)
        EventTimeSlot(
          id: slot.id,
          label: slot.label,
          capacity: slot.capacity,
        ),
    ];

    final request = CreateEventRequest(
      title: title,
      description: summary,
      primaryDate: _eventDate!,
      location: location,
      cost: cost.isEmpty ? null : cost,
      eventType: _eventType,
      tags: _selectedTags.toList(),
      hostCandidateIds: _selectedCandidateIds.toList(),
      timeSlots: slots,
      mediaPath: _mediaFile?.path,
      mediaType: _mediaType,
      coverImagePath: _customCoverFile?.path ?? _generatedCoverPath,
      mediaAspectRatio: _mediaAspectRatio,
      overlays: overlays,
    );

    setState(() => _isSubmitting = true);

    try {
      final eventId = await ref
          .read(createContentServiceProvider)
          .createEvent(request, author: user);

      if (!mounted) return;
      Navigator.of(context).pop(eventId);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Event published to the coalition calendar.')),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to create event: $error\n$stackTrace');
      if (!mounted) return;
      _showError('We could not publish your event. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _EventSlotDraft {
  const _EventSlotDraft({
    required this.id,
    required this.label,
    this.capacity,
  });

  final String id;
  final String label;
  final int? capacity;
}
