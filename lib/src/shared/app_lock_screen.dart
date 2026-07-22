import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});
  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _pin = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _systemUnlock());
  }

  Future<void> _systemUnlock() async {
    final ok = await ref.read(sessionControllerProvider).unlock();
    if (!ok && mounted) setState(() => _error = 'Используйте PIN приложения');
  }

  Future<void> _pinUnlock() async {
    final ok = await ref.read(sessionControllerProvider).unlock(pin: _pin.text);
    if (!ok && mounted) setState(() => _error = 'Неверный PIN');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 52),
                const SizedBox(height: 16),
                Text(
                  'Pavel Vault заблокирован',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _pinUnlock(),
                  decoration: InputDecoration(
                    labelText: 'PIN',
                    errorText: _error,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _pinUnlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Разблокировать'),
                ),
                TextButton(
                  onPressed: _systemUnlock,
                  child: const Text('Системная авторизация'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
