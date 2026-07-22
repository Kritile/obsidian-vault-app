import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/vault/vault_models.dart';
import 'cached_vault_image.dart';

class ObsidianMarkdownView extends ConsumerWidget {
  const ObsidianMarkdownView({
    required this.source,
    this.notePath,
    this.onWikiLink,
    this.onToggleTask,
    super.key,
  });
  final String source;
  final String? notePath;
  final ValueChanged<String>? onWikiLink;
  final void Function(int index, bool checked)? onToggleTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var taskIndex = 0;
    final block = RegExp(
      r'```dataview(js)?\s*([\s\S]*?)```',
      caseSensitive: false,
    );
    final children = <Widget>[];
    var offset = 0;
    for (final match in block.allMatches(source)) {
      if (match.start > offset) {
        children.add(
          _markdown(source.substring(offset, match.start), () => taskIndex++),
        );
      }
      children.add(
        _NativeDataviewBlock(
          source: match.group(2)!.trim(),
          notePath: notePath,
          onWikiLink: onWikiLink,
        ),
      );
      offset = match.end;
    }
    if (offset < source.length) {
      children.add(_markdown(source.substring(offset), () => taskIndex++));
    }
    return ListView(padding: const EdgeInsets.all(16), children: children);
  }

  Widget _markdown(String value, int Function() nextTask) => MarkdownBody(
    data: convertObsidianMarkdown(value),
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
    checkboxBuilder: (checked) {
      final index = nextTask();
      return Checkbox(
        value: checked,
        onChanged: onToggleTask == null
            ? null
            : (value) => onToggleTask!(index, value ?? false),
      );
    },
  );
}

class _NativeDataviewBlock extends ConsumerWidget {
  const _NativeDataviewBlock({
    required this.source,
    required this.notePath,
    required this.onWikiLink,
  });

  final String source;
  final String? notePath;
  final ValueChanged<String>? onWikiLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(vaultControllerProvider).index;
    final current = notePath == null ? null : index.byPath(notePath!);
    final view = RegExp(
      r'''dv\.view\(["']([^"']+)["']''',
    ).firstMatch(source)?.group(1);
    List<ParsedNote> notes = const [];
    String title;
    if (view?.endsWith('training-card') ?? false) {
      notes = current == null ? const [] : [current];
      title = 'Карточка тренировки';
    } else if (view?.endsWith('project-dashboard') ?? false) {
      final project =
          current?.frontmatter['project']?.toString() ?? current?.title;
      notes = index.notes
          .where((note) => note.frontmatter['project']?.toString() == project)
          .toList(growable: false);
      title = 'Проект';
    } else if (view?.endsWith('project-note-card') ?? false) {
      notes = current == null ? const [] : [current];
      title = 'Свойства заметки';
    } else if (view?.contains('reports/dashboard') ?? false) {
      notes = index.dailies;
      title = 'Данные отчёта';
    } else if (source.contains('dv.pages(')) {
      final token =
          RegExp(
            r'''dv\.pages\(["']([^"']*)["']''',
          ).firstMatch(source)?.group(1) ??
          '';
      notes = index.notes
          .where((note) {
            if (token.startsWith('#')) {
              return note.tags.contains(token.substring(1));
            }
            final folder = token.replaceAll('"', '');
            return folder.isEmpty || note.document.path.startsWith(folder);
          })
          .take(30)
          .toList(growable: false);
      title = source.contains('taskList') ? 'Задачи' : 'Результат Dataview';
    } else {
      return Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.code_off),
          title: const Text('DataviewJS-выражение не поддерживается'),
          subtitle: SelectableText(source),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            if (notes.isEmpty) const Text('Нет подходящих записей'),
            for (final note in notes.take(20))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  note.tasks.any((task) => !task.completed)
                      ? Icons.check_box_outline_blank
                      : Icons.description_outlined,
                ),
                title: Text(note.title),
                subtitle: note.frontmatter.isEmpty
                    ? null
                    : Text(
                        note.frontmatter.entries
                            .take(3)
                            .map((entry) => '${entry.key}: ${entry.value}')
                            .join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                onTap: () => onWikiLink?.call(note.document.path),
              ),
          ],
        ),
      ),
    );
  }
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
