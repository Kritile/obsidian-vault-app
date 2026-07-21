import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../core/cache/storage_models.dart';
import '../../core/sync/webdav_client.dart';
import '../../core/sync/webdav_profile.dart';
import '../../shared/page_scaffold.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  var _usageRevision = 0;
  late Future<StorageUsage> _usageFuture;

  @override
  void initState() {
    super.initState();
    _usageFuture = Future.microtask(
      () => ref.read(appControllerProvider).storageUsage(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appControllerProvider);
    final narrow = MediaQuery.sizeOf(context).width < 480;
    return PageScaffold(
      title: 'Настройки',
      subtitle: 'Хранилища, память и интерфейс',
      actions: [
        FilledButton.icon(
          onPressed: () => _editProfile(),
          icon: const Icon(Icons.add),
          label: const Text('Хранилище'),
        ),
      ],
      child: ListView(
        padding: EdgeInsets.fromLTRB(narrow ? 10 : 20, 0, narrow ? 10 : 20, 30),
        children: [
          _Header(icon: Icons.cloud_outlined, title: 'WebDAV-хранилища'),
          const SizedBox(height: 8),
          ...controller.webDavProfiles.map(
            (profile) => _ProfileCard(
              profile: profile,
              active: profile.id == controller.activeProfileId,
              busy: controller.busy,
              onSelect: () => _switch(profile),
              onEdit: () => _editProfile(profile),
              onDelete: () => _deleteProfile(profile),
            ),
          ),
          const SizedBox(height: 22),
          _Header(icon: Icons.storage_outlined, title: 'Управление памятью'),
          const SizedBox(height: 8),
          FutureBuilder<StorageUsage>(
            key: ValueKey(_usageRevision),
            future: _usageFuture,
            builder: (context, snapshot) => _StorageCard(
              usage: snapshot.data,
              loading: snapshot.connectionState != ConnectionState.done,
              onClearImages: () => _clear(
                'Очистить кеш изображений?',
                'Сетевые изображения при необходимости загрузятся повторно.',
                controller.clearImageCache,
              ),
              onClearInactive: () => _clear(
                'Очистить кеш неактивных хранилищ?',
                'Несинхронизированные данные неактивных профилей будут удалены.',
                controller.clearInactiveVaultCaches,
              ),
              onClearCurrent: () => _clearCurrent(controller),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DropdownButtonFormField<int>(
                isExpanded: true,
                initialValue: controller.imageCacheLimitBytes,
                decoration: const InputDecoration(
                  labelText: 'Лимит кеша изображений',
                  prefixIcon: Icon(Icons.photo_library_outlined),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 100 * 1024 * 1024,
                    child: Text('100 МБ'),
                  ),
                  DropdownMenuItem(
                    value: 250 * 1024 * 1024,
                    child: Text('250 МБ'),
                  ),
                  DropdownMenuItem(
                    value: 500 * 1024 * 1024,
                    child: Text('500 МБ'),
                  ),
                  DropdownMenuItem(
                    value: 1000 * 1024 * 1024,
                    child: Text('1 ГБ'),
                  ),
                  DropdownMenuItem(value: 0, child: Text('Без ограничения')),
                ],
                onChanged: (value) async {
                  if (value == null) return;
                  await controller.setImageCacheLimit(value);
                  _refreshUsage();
                },
              ),
            ),
          ),
          const SizedBox(height: 22),
          _Header(icon: Icons.animation, title: 'Анимации'),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MotionPreference.values
                    .map(
                      (value) => ChoiceChip(
                        avatar: Icon(
                          value == MotionPreference.expressive
                              ? Icons.auto_awesome
                              : value == MotionPreference.balanced
                              ? Icons.motion_photos_auto_outlined
                              : Icons.motion_photos_off_outlined,
                          size: 18,
                        ),
                        label: Text(_motionLabel(value)),
                        selected: controller.motionPreference == value,
                        onSelected: (_) =>
                            controller.setMotionPreference(value),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _switch(WebDavProfile profile) async {
    final controller = ref.read(appControllerProvider);
    try {
      await controller.switchWebDavProfile(profile.id);
    } catch (error) {
      if (!mounted) return;
      final force = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Не удалось синхронизировать'),
          content: Text(
            '$error\n\nЛокальные изменения останутся в кеше текущего профиля.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Остаться'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Переключить без синхронизации'),
            ),
          ],
        ),
      );
      if (force == true) {
        await controller.switchWebDavProfile(profile.id, syncCurrent: false);
      }
    }
    _refreshUsage();
  }

  Future<void> _editProfile([WebDavProfile? profile]) async {
    final result = await showDialog<_ProfileInput>(
      context: context,
      builder: (_) => _ProfileDialog(profile: profile),
    );
    if (result == null) return;
    try {
      await ref
          .read(appControllerProvider)
          .saveWebDavProfile(
            id: profile?.id,
            name: result.name,
            url: result.url,
            username: result.username,
            password: result.password,
            activate: profile == null,
          );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сохранить профиль: $error')),
        );
      }
    }
    _refreshUsage();
  }

  Future<void> _deleteProfile(WebDavProfile profile) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить ${profile.name}?'),
        content: const Text(
          'Можно сохранить зашифрованный кеш для последующего повторного подключения.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'keep'),
            child: const Text('Оставить кеш'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            child: const Text('Удалить с кешем'),
          ),
        ],
      ),
    );
    if (action == null) return;
    try {
      await ref
          .read(appControllerProvider)
          .deleteWebDavProfile(profile.id, deleteCache: action == 'delete');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    _refreshUsage();
  }

  Future<void> _clearCurrent(dynamic controller) async {
    final synced = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Очистить текущую офлайн-копию?'),
        content: const Text(
          'Сначала будет выполнена синхронизация. После очистки заметки вернутся при следующей ручной синхронизации.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Синхронизировать и очистить'),
          ),
        ],
      ),
    );
    if (synced != true) return;
    await controller.synchronize();
    if (controller.error == null && controller.conflicts.isEmpty) {
      await controller.clearCurrentVaultCache();
      _refreshUsage();
    }
  }

  Future<void> _clear(
    String title,
    String message,
    Future<void> Function() action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    _refreshUsage();
  }

  void _refreshUsage() {
    if (mounted) {
      setState(() {
        _usageRevision++;
        _usageFuture = ref.read(appControllerProvider).storageUsage();
      });
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.icon, required this.title});
  final IconData icon;
  final String title;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    ],
  );
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.active,
    required this.busy,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });
  final WebDavProfile profile;
  final bool active;
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: active
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          shape: BoxShape.circle,
        ),
        child: Icon(active ? Icons.cloud_done : Icons.cloud_outlined),
      ),
      title: Row(
        children: [
          Flexible(child: Text(profile.name)),
          if (active) ...[
            const SizedBox(width: 7),
            const Chip(label: Text('Активно')),
          ],
        ],
      ),
      subtitle: Text(
        '${profile.baseUrl.host}${profile.baseUrl.path}\n${profile.lastSyncAt == null ? 'Ещё не синхронизировано' : 'Синхронизация ${DateFormat('dd.MM.yyyy HH:mm').format(profile.lastSyncAt!.toLocal())}'}',
      ),
      isThreeLine: true,
      onTap: active || busy ? null : onSelect,
      trailing: PopupMenuButton<String>(
        onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'edit', child: Text('Изменить')),
          PopupMenuItem(value: 'delete', child: Text('Удалить')),
        ],
      ),
    ),
  );
}

class _StorageCard extends StatelessWidget {
  const _StorageCard({
    required this.usage,
    required this.loading,
    required this.onClearImages,
    required this.onClearInactive,
    required this.onClearCurrent,
  });
  final StorageUsage? usage;
  final bool loading;
  final VoidCallback onClearImages;
  final VoidCallback onClearInactive;
  final VoidCallback onClearCurrent;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        child: loading || usage == null
            ? const SizedBox(
                height: 110,
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                key: ValueKey(usage!.totalBytes),
                children: [
                  _UsageRow(
                    label: 'Текущий vault',
                    bytes: usage!.currentVaultBytes,
                    onClear: onClearCurrent,
                  ),
                  _UsageRow(
                    label: 'Изображения',
                    bytes: usage!.imageBytes,
                    onClear: onClearImages,
                  ),
                  _UsageRow(
                    label: 'Неактивные vault',
                    bytes: usage!.inactiveVaultBytes,
                    onClear: onClearInactive,
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Всего',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        _size(usage!.totalBytes),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    ),
  );
}

class _UsageRow extends StatelessWidget {
  const _UsageRow({
    required this.label,
    required this.bytes,
    required this.onClear,
  });
  final String label;
  final int bytes;
  final VoidCallback onClear;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    subtitle: Text(_size(bytes)),
    trailing: IconButton(
      tooltip: 'Очистить',
      onPressed: bytes == 0 ? null : onClear,
      icon: const Icon(Icons.cleaning_services_outlined),
    ),
  );
}

class _ProfileInput {
  const _ProfileInput(this.name, this.url, this.username, this.password);
  final String name;
  final Uri url;
  final String username;
  final String password;
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({this.profile});
  final WebDavProfile? profile;
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController name;
  late final TextEditingController url;
  late final TextEditingController username;
  late final TextEditingController password;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.profile?.name ?? '');
    url = TextEditingController(text: widget.profile?.baseUrl.toString() ?? '');
    username = TextEditingController(text: widget.profile?.username ?? '');
    password = TextEditingController(text: widget.profile?.password ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.profile == null ? 'Новое хранилище' : 'Изменить хранилище',
    ),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: url,
              decoration: const InputDecoration(labelText: 'WebDAV URL'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: username,
              decoration: const InputDecoration(labelText: 'Логин'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль'),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: _finish,
        child: const Text('Проверить и сохранить'),
      ),
    ],
  );
  void _finish() {
    final uri = WebDavPathCodec.parseBaseUrl(url.text);
    if (uri == null || username.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Проверьте URL, логин и пароль');
      return;
    }
    Navigator.pop(
      context,
      _ProfileInput(name.text, uri, username.text.trim(), password.text),
    );
  }
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes Б';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
  }
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

String _motionLabel(MotionPreference value) => switch (value) {
  MotionPreference.expressive => 'Выразительные',
  MotionPreference.balanced => 'Умеренные',
  MotionPreference.minimal => 'Минимальные',
};
