import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import 'app_motion.dart';

class CachedVaultImage extends ConsumerWidget {
  const CachedVaultImage({
    required this.source,
    this.notePath,
    this.fit = BoxFit.cover,
    this.placeholder,
    super.key,
  });

  final String source;
  final String? notePath;
  final BoxFit fit;
  final Widget? placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) => FutureBuilder(
    future: ref
        .read(appControllerProvider)
        .imageCache
        .load(source, notePath: notePath),
    builder: (context, snapshot) => AnimatedSwitcher(
      duration: motionDuration(
        context,
        ref.watch(appControllerProvider).motionPreference,
      ),
      switchInCurve: motionCurve(
        ref.read(appControllerProvider).motionPreference,
      ),
      child: snapshot.data == null
          ? Container(
              key: const ValueKey('placeholder'),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child:
                  placeholder ??
                  const Center(child: Icon(Icons.image_outlined)),
            )
          : Image.memory(
              snapshot.data!,
              key: ValueKey(source),
              fit: fit,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) =>
                  placeholder ?? const Icon(Icons.broken_image_outlined),
            ),
    ),
  );
}
