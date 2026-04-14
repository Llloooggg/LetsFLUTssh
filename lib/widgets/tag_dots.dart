import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tags/tag.dart';
import '../providers/tag_provider.dart';
import '../theme/app_theme.dart';

/// Small colored dots representing tags on a session or folder.
///
/// Watches the provider and rebuilds when tags change. Shows up to
/// [maxDots] dots to avoid overflow in narrow tree rows.
class SessionTagDots extends ConsumerWidget {
  final String sessionId;
  final int maxDots;

  const SessionTagDots({super.key, required this.sessionId, this.maxDots = 3});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(sessionTagsProvider(sessionId));
    return tagsAsync.when(
      data: (tags) => _TagDotRow(tags: tags, maxDots: maxDots),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

/// Small colored dots for folder tags.
class FolderTagDots extends ConsumerWidget {
  final String folderId;
  final int maxDots;

  const FolderTagDots({super.key, required this.folderId, this.maxDots = 3});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(folderTagsProvider(folderId));
    return tagsAsync.when(
      data: (tags) => _TagDotRow(tags: tags, maxDots: maxDots),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _TagDotRow extends StatelessWidget {
  final List<Tag> tags;
  final int maxDots;

  const _TagDotRow({required this.tags, required this.maxDots});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final visible = tags.take(maxDots);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final tag in visible)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: tag.colorValue ?? AppTheme.fgDim,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
