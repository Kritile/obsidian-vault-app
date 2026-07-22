import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/settings/connect_screen.dart';
import '../shared/app_lock_screen.dart';
import '../shared/sync_progress_overlay.dart';
import 'app_shell.dart';
import 'providers.dart';
import '../core/cache/storage_models.dart';

class PavelVaultApp extends ConsumerWidget {
  const PavelVaultApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final sync = ref.watch(syncControllerProvider);
    return MaterialApp(
      title: 'Vellum',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light, settings.motionPreference),
      darkTheme: _theme(Brightness.dark, settings.motionPreference),
      builder: (context, child) {
        final content = ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: HeroMode(
            // HeroController keeps GlobalKey-backed repaint boundaries for the
            // outgoing route. They are unnecessary here and can race with the
            // frequent controller rebuilds produced by WebDAV progress.
            enabled: false,
            child: child ?? const SizedBox.expand(),
          ),
        );
        final progress = sync.progress;
        final notice = sync.operationNotice;

        // Keep this hierarchy stable even when progress/notice values change.
        // Reparenting the Navigator while a route is being popped temporarily
        // makes HeroController's render object inactive and causes a crash.
        return Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (progress != null) SyncProgressOverlay(progress: progress),
            if (notice != null)
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: SafeArea(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(notice),
                    tween: Tween(begin: 1, end: 0),
                    duration:
                        settings.motionPreference == MotionPreference.minimal
                        ? const Duration(milliseconds: 1)
                        : const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Transform.translate(
                      offset: Offset(0, -18 * value),
                      child: child,
                    ),
                    child: Center(
                      child: _OperationNotice(
                        message: notice,
                        isError: sync.operationNoticeIsError,
                        inProgress: sync.operationNoticeInProgress,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      home: !session.initialized
          ? const _LoadingScreen()
          : session.webDav == null
          ? const ConnectScreen()
          : session.locked
          ? const AppLockScreen()
          : const AppShell(),
    );
  }

  ThemeData _theme(Brightness brightness, MotionPreference motion) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff6d5dfc),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Route zoom/fade transitions keep the previous route in a translucent
      // layer. Component-level animations remain enabled, while pages are
      // always replaced as a single opaque frame.
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const _NoPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: scheme.surface,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _NoPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}

class _OperationNotice extends StatelessWidget {
  const _OperationNotice({
    required this.message,
    required this.isError,
    required this.inProgress,
  });
  final String message;
  final bool isError;
  final bool inProgress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 6,
          color: isError ? colors.errorContainer : colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (inProgress)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Icon(
                    isError
                        ? Icons.cloud_off_outlined
                        : Icons.cloud_done_outlined,
                  ),
                const SizedBox(width: 10),
                Flexible(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
