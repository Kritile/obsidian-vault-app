import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/daily/daily_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/projects/projects_screen.dart';
import '../features/reports/reports_screen.dart';
import '../features/sync/sync_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/tasks/tasks_screen.dart';
import '../features/projects/project_forms.dart';
import '../features/vault/vault_browser_screen.dart';
import '../shared/app_motion.dart';
import 'providers.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  var _screenIndex = 0;
  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.space_dashboard_outlined),
      selectedIcon: Icon(Icons.space_dashboard),
      label: 'Главная',
    ),
    NavigationDestination(
      icon: Icon(Icons.folder_outlined),
      selectedIcon: Icon(Icons.folder),
      label: 'Vault',
    ),
    NavigationDestination(
      icon: Icon(Icons.today_outlined),
      selectedIcon: Icon(Icons.today),
      label: 'День',
    ),
    NavigationDestination(
      icon: Icon(Icons.task_alt_outlined),
      selectedIcon: Icon(Icons.task_alt),
      label: 'Задачи',
    ),
    NavigationDestination(
      icon: Icon(Icons.work_outline),
      selectedIcon: Icon(Icons.work),
      label: 'Проекты',
    ),
    NavigationDestination(
      icon: Icon(Icons.insights_outlined),
      selectedIcon: Icon(Icons.insights),
      label: 'Отчёты',
    ),
    NavigationDestination(
      icon: Icon(Icons.sync_outlined),
      selectedIcon: Icon(Icons.sync),
      label: 'Sync',
    ),
    NavigationDestination(
      icon: Icon(Icons.settings_outlined),
      selectedIcon: Icon(Icons.settings),
      label: 'Настройки',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openExternalCapture());
  }

  Future<void> _openExternalCapture() async {
    final text = await ref.read(taskControllerProvider).takeExternalSelection();
    if (text == null || !mounted) return;
    final projects = ref
        .read(vaultControllerProvider)
        .index
        .projects
        .map((note) => note.frontmatter['project']?.toString() ?? note.title)
        .toList(growable: false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateTaskScreen(
          projects: projects,
          initialTitle: text,
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      ref.read(sessionControllerProvider).enterBackground();
    } else if (state == AppLifecycleState.resumed) {
      ref.read(sessionControllerProvider).resume();
    }
  }

  void _selectScreen(int index) {
    if (index == _screenIndex) return;

    // Dialogs, popup menus, bottom sheets and pushed note pages all use the
    // root navigator. Close them before changing a tab so an overlay from the
    // previous tab cannot remain above the newly selected screen.
    Navigator.of(context).popUntil((route) => route.isFirst);
    if (mounted) setState(() => _screenIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final visibleIndex = wide && _screenIndex == 8 ? 0 : _screenIndex;
    final screens = <Widget>[
      const DashboardScreen(),
      const VaultBrowserScreen(),
      const DailyScreen(),
      const TasksScreen(),
      const ProjectsScreen(),
      const ReportsScreen(),
      const SyncScreen(),
      const SettingsScreen(),
      _MoreScreen(onSelect: _selectScreen),
    ];
    final motion = ref.watch(settingsControllerProvider).motionPreference;
    final tabDuration = motionDuration(
      context,
      motion,
      expressive: 360,
      balanced: 220,
    );
    // Mount exactly one tab. Keeping inactive render trees around caused stale
    // layers on some Android compositors even when IndexedStack skipped their
    // paint pass. The opaque surface also prevents a previous route/frame from
    // showing through while the selected tab is rebuilt.
    final content = ClipRect(
      child: RepaintBoundary(
        key: ValueKey('app-tab-boundary-$visibleIndex'),
        child: ColoredBox(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: KeyedSubtree(
            key: ValueKey('app-tab-$visibleIndex'),
            child: _TabEntrance(
              duration: tabDuration,
              child: screens[visibleIndex],
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: visibleIndex.clamp(0, 7),
                onDestinationSelected: _selectScreen,
                extended: MediaQuery.sizeOf(context).width >= 1180,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: CircleAvatar(child: Icon(Icons.auto_awesome_mosaic)),
                ),
                destinations: _destinations
                    .map(
                      (item) => NavigationRailDestination(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: Text(item.label),
                      ),
                    )
                    .toList(growable: false),
              ),
            Expanded(child: content),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _narrowIndex,
              onDestinationSelected: (value) =>
                  _selectScreen(const [0, 2, 1, 8][value]),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Главная',
                ),
                NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today),
                  label: 'День',
                ),
                NavigationDestination(
                  icon: Icon(Icons.collections_bookmark_outlined),
                  selectedIcon: Icon(Icons.collections_bookmark),
                  label: 'Коллекции',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'Ещё',
                ),
              ],
            ),
    );
  }

  int get _narrowIndex => switch (_screenIndex) {
    0 => 0,
    2 => 1,
    1 => 2,
    _ => 3,
  };
}

class _TabEntrance extends StatelessWidget {
  const _TabEntrance({required this.duration, required this.child});

  final Duration duration;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 1, end: 0),
    duration: duration,
    curve: Curves.easeOutCubic,
    // Only the new, fully opaque tab exists during this animation. Translation
    // does not require an off-screen opacity layer or retain the previous tab.
    builder: (context, value, child) =>
        Transform.translate(offset: Offset(14 * value, 0), child: child),
    child: child,
  );
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.onSelect});
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
          child: Text('Ещё', style: Theme.of(context).textTheme.headlineMedium),
        ),
        Expanded(
          child: GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width < 330 ? 1 : 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: MediaQuery.sizeOf(context).width < 330
                ? 2.4
                : 1.15,
            children: [
              _MoreCard(
                icon: Icons.task_alt_outlined,
                title: 'Задачи',
                subtitle: 'Inbox, сроки и календарь',
                onTap: () => onSelect(3),
              ),
              _MoreCard(
                icon: Icons.work_outline,
                title: 'Проекты',
                subtitle: 'Проекты и Kanban',
                onTap: () => onSelect(4),
              ),
              _MoreCard(
                icon: Icons.insights_outlined,
                title: 'Отчёты',
                subtitle: 'Периоды и экспорт',
                onTap: () => onSelect(5),
              ),
              _MoreCard(
                icon: Icons.sync,
                title: 'Синхронизация',
                subtitle: 'WebDAV и конфликты',
                onTap: () => onSelect(6),
              ),
              _MoreCard(
                icon: Icons.settings_outlined,
                title: 'Настройки',
                subtitle: 'Хранилища, память и интерфейс',
                onTap: () => onSelect(7),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MoreCard extends StatelessWidget {
  const _MoreCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    ),
  );
}
