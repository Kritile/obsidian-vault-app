import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cached_vault_image.dart';

class ObsidianMarkdownView extends ConsumerWidget {
  const ObsidianMarkdownView({
    required this.source,
    this.notePath,
    this.onWikiLink,
    super.key,
  });
  final String source;
  final String? notePath;
  final ValueChanged<String>? onWikiLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Markdown(
    data: convertObsidianMarkdown(source),
    selectable: true,
    imageBuilder: (uri, title, alt) {
      final value = uri.scheme == 'vault-image'
          ? Uri.decodeComponent(uri.toString().substring('vault-image:'.length))
          : uri.toString();
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedVaultImage(
            source: value,
            notePath: notePath,
            fit: BoxFit.contain,
          ),
        ),
      );
    },
    onTapLink: (text, href, title) {
      if (href?.startsWith('vault:') ?? false) {
        onWikiLink?.call(Uri.decodeComponent(href!.substring(6)));
      }
    },
  );
}

String convertObsidianMarkdown(String value) {
  final withoutDataview = value.replaceAllMapped(
    RegExp(r'```dataview(?:js)?\s*[\s\S]*?```', caseSensitive: false),
    (_) =>
        '> **Интерактивный блок Obsidian**  \n> В приложении его данные показаны в соответствующем нативном разделе.',
  );
  return withoutDataview.replaceAllMapped(
    RegExp(r'(!)?\[\[([^\]|]+)(?:\|([^\]]+))?\]\]'),
    (match) {
      final target = match.group(2)!.trim();
      final label = match.group(3)?.trim() ?? target.split('/').last;
      final embedded = match.group(1) != null;
      final isImage = RegExp(
        r'\.(?:png|jpe?g|gif|webp|bmp|svg)$',
        caseSensitive: false,
      ).hasMatch(target);
      if (embedded && isImage) {
        return '![$label](vault-image:${Uri.encodeComponent(target)})';
      }
      return '[${embedded ? '📎 ' : ''}$label](vault:${Uri.encodeComponent(target)})';
    },
  );
}
