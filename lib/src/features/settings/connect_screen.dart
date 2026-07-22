import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/sync/webdav_client.dart';

class ConnectScreen extends ConsumerStatefulWidget {
  const ConnectScreen({super.key});
  @override
  ConsumerState<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends ConsumerState<ConnectScreen> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _pin = TextEditingController();

  Future<void> _connect() async {
    final uri = WebDavPathCodec.parseBaseUrl(_url.text);
    if (uri == null || _pin.text.length < 4) return;
    await ref
        .read(sessionControllerProvider)
        .connect(
          url: uri,
          username: _username.text,
          password: _password.text,
          pin: _pin.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(sessionControllerProvider);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.cloud_sync_outlined, size: 58),
                    const SizedBox(height: 16),
                    Text(
                      'Подключить Obsidian vault',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Файлы останутся обычными Markdown/YAML на WebDAV. Локальная копия приложения будет зашифрована.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                        labelText: 'WebDAV URL',
                        hintText: 'https://cloud.example.com/vault/',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _username,
                      decoration: const InputDecoration(labelText: 'Логин'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Пароль WebDAV',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pin,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'PIN приложения',
                        helperText:
                            'Не менее 4 цифр; fallback для разблокировки',
                      ),
                    ),
                    if (controller.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        controller.error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: controller.busy ? null : _connect,
                      icon: controller.busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: const Text('Проверить и подключить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
