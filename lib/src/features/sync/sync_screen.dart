import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/sync/sync_models.dart';
import '../../shared/page_scaffold.dart';

class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(syncControllerProvider);
    return PageScaffold(
      title: 'Синхронизация',
      subtitle: controller.activeProfile?.baseUrl.host,
      actions: [
        FilledButton.icon(
          onPressed: controller.busy ? null : controller.synchronize,
          icon: const Icon(Icons.sync),
          label: const Text('Синхронизировать'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                controller.conflicts.isEmpty
                    ? Icons.cloud_done_outlined
                    : Icons.sync_problem,
              ),
              title: Text(controller.syncMessage ?? 'Готово к синхронизации'),
              subtitle: Text(
                controller.error ??
                    'WebDAV-секреты защищены системным хранилищем',
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text('Конфликты', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (controller.conflicts.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle_outline),
                title: Text('Неразрешённых конфликтов нет'),
              ),
            ),
          for (final conflict in controller.conflicts)
            Card(
              child: ListTile(
                leading: const Icon(Icons.compare_arrows),
                title: Text(conflict.path),
                subtitle: const Text('Файл изменён в приложении и на сервере'),
                trailing: FilledButton.tonal(
                  onPressed: () => _resolve(context, ref, conflict),
                  child: const Text('Сравнить'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    SyncConflict conflict,
  ) async {
    final local = utf8.decode(conflict.local, allowMalformed: true);
    final remote = utf8.decode(conflict.remote, allowMalformed: true);
    final merged = TextEditingController(text: local);
    final choice = await showDialog<ConflictResolution>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(conflict.path),
        content: SizedBox(
          width: 900,
          height: 520,
          child: Column(
            children: [
              const Text(
                'Отредактируйте итоговый текст или выберите готовую версию.',
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: _Version(title: 'Локальная', source: local),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Version(title: 'Серверная', source: remote),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: merged,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  style: const TextStyle(fontFamily: 'monospace'),
                  decoration: const InputDecoration(
                    labelText: 'Итоговая версия',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, ConflictResolution.deferred),
            child: const Text('Отложить'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ConflictResolution.remote),
            child: const Text('Серверная'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ConflictResolution.local),
            child: const Text('Локальная'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ConflictResolution.merged),
            child: const Text('Сохранить итог'),
          ),
        ],
      ),
    );
    if (choice != null && choice != ConflictResolution.deferred) {
      await ref
          .read(syncControllerProvider)
          .resolveConflict(conflict, choice, merged: merged.text);
    }
  }
}

class _Version extends StatelessWidget {
  const _Version({required this.title, required this.source});
  final String title;
  final String source;
  @override
  Widget build(BuildContext context) => TextField(
    controller: TextEditingController(text: source),
    readOnly: true,
    expands: true,
    maxLines: null,
    minLines: null,
    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    decoration: InputDecoration(labelText: title),
  );
}
