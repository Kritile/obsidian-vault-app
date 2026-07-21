import 'package:flutter/material.dart';

import '../core/sync/sync_models.dart';

class SyncProgressOverlay extends StatelessWidget {
  const SyncProgressOverlay({required this.progress, super.key});
  final SyncProgress progress;

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      const ModalBarrier(dismissible: false, color: Colors.black54),
      Center(
        child: Card(
          margin: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cloud_sync_outlined),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Обмен с WebDAV',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  LinearProgressIndicator(value: progress.fraction),
                  const SizedBox(height: 12),
                  Text(
                    progress.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (progress.counter != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${progress.counter} · ${(progress.fraction! * 100).round()}%',
                      style: Theme.of(context).textTheme.labelLarge,
                      textAlign: TextAlign.end,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
