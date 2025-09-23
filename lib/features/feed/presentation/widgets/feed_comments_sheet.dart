import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/data/auth_controller.dart';
import '../../../feed/domain/feed_comment.dart';
import '../../../feed/domain/feed_content.dart';

class FeedCommentsSheet extends ConsumerStatefulWidget {
  const FeedCommentsSheet({
    required this.content,
    required this.initialComments,
    super.key,
  });

  final FeedContent content;
  final List<FeedComment> initialComments;

  @override
  ConsumerState<FeedCommentsSheet> createState() => _FeedCommentsSheetState();
}

class _FeedCommentsSheetState extends ConsumerState<FeedCommentsSheet> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  final List<_CommentThread> _threads = <_CommentThread>[];
  _CommentEntry? _replyTarget;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _focusNode = FocusNode();
    _bootstrapThreads();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _bootstrapThreads() {
    final grouped = <String?, List<FeedComment>>{};
    for (final comment in widget.initialComments) {
      final key = comment.parentId;
      grouped.putIfAbsent(key, () => <FeedComment>[]).add(comment);
    }

    final roots = grouped[null] ?? const <FeedComment>[];
    for (final root in roots) {
      final entry = _CommentEntry.fromComment(root);
      final replies =
          grouped[root.id]?.map(_CommentEntry.fromComment).toList() ??
              <_CommentEntry>[];
      replies.sort(_compareReplies);
      _threads.add(_CommentThread(parent: entry, replies: replies));
    }

    _sortThreads();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.colorScheme.surface;
    final currentUser = ref.read(authControllerProvider).user;
    final currentName = currentUser?.displayName.isNotEmpty == true
        ? currentUser!.displayName
        : 'You';

    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 60,
              height: 5,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Comments',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.content.posterName,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _threads.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Be the first to share your thoughts on this post.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      itemCount: _threads.length,
                      itemBuilder: (context, index) {
                        final thread = _threads[index];
                        return _CommentThreadWidget(
                          thread: thread,
                          onLike: _toggleLike,
                          onReply: _setReplyTarget,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            _buildComposer(theme, currentName),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme, String currentName) {
    final replyingLabel =
        _replyTarget == null ? null : 'Replying to ${_replyTarget!.authorName}';

    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyingLabel != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      replyingLabel,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _replyTarget = null),
                    icon: const Icon(Icons.close),
                    tooltip: 'Cancel reply',
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'Leave a comment as $currentName',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FloatingActionButton.small(
                heroTag: 'comment-send',
                onPressed: _submitComment,
                child: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submitComment() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final currentUser = ref.read(authControllerProvider).user;
    final name = currentUser?.displayName.isNotEmpty == true
        ? currentUser!.displayName
        : 'You';
    final avatar = currentUser?.profileImagePath;

    final parentId = _replyTarget?.id;
    final entry = _CommentEntry(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      authorName: name,
      avatarUrl: avatar,
      message: text,
      likeCount: 0,
      createdAt: DateTime.now(),
      parentId: parentId,
    );

    setState(() {
      if (parentId == null) {
        _threads.add(_CommentThread(parent: entry, replies: <_CommentEntry>[]));
      } else {
        final thread = _threads.firstWhere(
          (t) => t.parent.id == parentId,
          orElse: () {
            final newThread =
                _CommentThread(parent: entry, replies: <_CommentEntry>[]);
            _threads.add(newThread);
            return newThread;
          },
        );
        if (!thread.replies.contains(entry)) {
          thread.replies.add(entry);
        }
      }
      _sortThreads();
      _replyTarget = null;
    });

    _textController.clear();
    _focusNode.unfocus();
  }

  void _toggleLike(_CommentEntry entry) {
    setState(() {
      if (entry.isLiked) {
        entry
          ..isLiked = false
          ..likeCount = math.max(0, entry.likeCount - 1);
      } else {
        entry
          ..isLiked = true
          ..likeCount += 1;
      }
      _sortThreads();
    });
  }

  void _setReplyTarget(_CommentEntry entry) {
    final targetThread = entry.parentId == null
        ? _threads.firstWhere(
            (thread) => thread.parent.id == entry.id,
            orElse: () =>
                _CommentThread(parent: entry, replies: <_CommentEntry>[]),
          )
        : _threads.firstWhere(
            (thread) => thread.parent.id == entry.parentId,
            orElse: () =>
                _CommentThread(parent: entry, replies: <_CommentEntry>[]),
          );
    setState(() {
      _replyTarget = targetThread.parent;
    });
    _focusNode.requestFocus();
  }

  void _sortThreads() {
    _threads.sort((a, b) => b.parent.likeCount.compareTo(a.parent.likeCount));
    for (final thread in _threads) {
      thread.replies.sort(_compareReplies);
    }
  }
}

int _compareReplies(_CommentEntry a, _CommentEntry b) {
  final likeComparison = b.likeCount.compareTo(a.likeCount);
  if (likeComparison != 0) return likeComparison;
  return a.createdAt.compareTo(b.createdAt);
}

class _CommentThread {
  _CommentThread({required this.parent, required this.replies});

  final _CommentEntry parent;
  final List<_CommentEntry> replies;
}

class _CommentEntry {
  _CommentEntry({
    required this.id,
    required this.authorName,
    required this.message,
    required this.likeCount,
    required this.createdAt,
    this.avatarUrl,
    this.parentId,
    this.isLiked = false,
  });

  factory _CommentEntry.fromComment(FeedComment comment) {
    return _CommentEntry(
      id: comment.id,
      authorName: comment.authorName,
      avatarUrl: comment.avatarUrl,
      message: comment.message,
      likeCount: comment.likeCount,
      createdAt: comment.createdAt,
      parentId: comment.parentId,
    );
  }

  final String id;
  final String authorName;
  final String? avatarUrl;
  final String message;
  int likeCount;
  final DateTime createdAt;
  final String? parentId;
  bool isLiked;

  _CommentEntry copyWith({
    String? id,
    String? authorName,
    String? avatarUrl,
    String? message,
    int? likeCount,
    DateTime? createdAt,
    String? parentId,
    bool? isLiked,
  }) {
    return _CommentEntry(
      id: id ?? this.id,
      authorName: authorName ?? this.authorName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      message: message ?? this.message,
      likeCount: likeCount ?? this.likeCount,
      createdAt: createdAt ?? this.createdAt,
      parentId: parentId ?? this.parentId,
      isLiked: isLiked ?? this.isLiked,
    );
  }
}

class _CommentThreadWidget extends StatelessWidget {
  const _CommentThreadWidget({
    required this.thread,
    required this.onLike,
    required this.onReply,
  });

  final _CommentThread thread;
  final void Function(_CommentEntry entry) onLike;
  final void Function(_CommentEntry entry) onReply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentTile(
            entry: thread.parent,
            onLike: onLike,
            onReply: onReply,
          ),
          if (thread.replies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 12),
              child: Column(
                children: [
                  for (final reply in thread.replies)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _CommentTile(
                        entry: reply,
                        onLike: onLike,
                        onReply: onReply,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.entry,
    required this.onLike,
    required this.onReply,
  });

  final _CommentEntry entry;
  final void Function(_CommentEntry entry) onLike;
  final void Function(_CommentEntry entry) onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: theme.colorScheme.primaryContainer,
          backgroundImage:
              entry.avatarUrl != null ? NetworkImage(entry.avatarUrl!) : null,
          child: entry.avatarUrl == null
              ? Text(
                  _initial(entry.authorName),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                )
              : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor.withValues(alpha: 0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.authorName,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.message,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${entry.likeCount} likes',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => onReply(entry),
                      child: const Text('Reply'),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: () => onLike(entry),
                      icon: Icon(
                        entry.isLiked ? Icons.favorite : Icons.favorite_border,
                        size: 20,
                        color: entry.isLiked
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      tooltip: 'Like comment',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _initial(String name) {
    if (name.isEmpty) return '?';
    return name.trim().substring(0, 1).toUpperCase();
  }
}
