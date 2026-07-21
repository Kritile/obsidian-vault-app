import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pavel_vault/src/app/app_controller.dart';
import 'package:pavel_vault/src/app/app_shell.dart';
import 'package:pavel_vault/src/app/providers.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';
import 'package:pavel_vault/src/features/dashboard/dashboard_screen.dart';
import 'package:pavel_vault/src/features/projects/projects_screen.dart';
import 'package:pavel_vault/src/features/reports/report_layout_editor_screen.dart';
import 'package:pavel_vault/src/features/reports/reports_screen.dart';
import 'package:pavel_vault/src/features/settings/settings_screen.dart';
import 'package:pavel_vault/src/features/vault/note_screen.dart';
import 'package:pavel_vault/src/features/vault/vault_browser_screen.dart';
import 'package:pavel_vault/src/shared/page_scaffold.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('tab switch unmounts the previous visual surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => AppController()),
        ],
        child: const MaterialApp(home: AppShell()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('app-tab-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-tab-2')), findsNothing);

    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(1);
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byKey(const ValueKey('app-tab-0')), findsNothing);
    expect(find.byKey(const ValueKey('app-tab-2')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('page header does not overflow on Fold cover width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(240, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageScaffold(
            title: 'Очень длинный заголовок раздела',
            subtitle: 'Подробное описание раздела',
            actions: [
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.fitness_center),
                label: const Text('Тренировка'),
              ),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.add),
                label: const Text('Добавить'),
              ),
            ],
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Очень длинный заголовок раздела'), findsOneWidget);
  });

  testWidgets('Obsidian-style dashboard fits Fold cover width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => AppController()),
        ],
        child: const MaterialApp(home: Scaffold(body: DashboardScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('хранилища'), findsOneWidget);
    expect(find.text('Активные проекты'), findsOneWidget);
  });

  testWidgets('collection filters fit Fold cover width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => AppController()),
        ],
        child: const MaterialApp(home: Scaffold(body: VaultBrowserScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Все'), findsOneWidget);
    expect(find.byTooltip('Сортировка'), findsOneWidget);
  });

  testWidgets('project filters fit Fold cover width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => AppController()),
        ],
        child: const MaterialApp(home: Scaffold(body: ProjectsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Проекты'), findsWidgets);
    expect(find.byTooltip('Сортировка проектов'), findsOneWidget);
  });

  testWidgets('project task row opens the task note', (tester) async {
    final controller = AppController();
    controller.index.rebuild([
      VaultDocument(
        path: 'Projects/Test/Открываемая задача.md',
        bytes: controller.parser.encode('''---
type: task
project: Test
status: todo
complete: false
priority: high
---
# Открываемая задача

Описание задачи.
'''),
        modifiedAt: DateTime(2026, 7, 21),
      ),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: Scaffold(body: ProjectsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is SegmentedButton),
        matching: find.text('Задачи'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsOneWidget);

    await tester.tap(find.text('Открываемая задача'));
    await tester.pumpAndSettle();

    expect(find.byType(NoteScreen), findsOneWidget);
    expect(find.text('Описание задачи.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Obsidian-style reports fit Fold cover width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => AppController()),
        ],
        child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Обзор'), findsOneWidget);
    expect(find.text('Заполнено дней'), findsOneWidget);
  });

  testWidgets('sports report has sortable columns without row checkboxes', (
    tester,
  ) async {
    final controller = AppController();
    final now = DateTime.now();
    final date =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-15';
    controller.index.rebuild([
      VaultDocument(
        path: 'Areas/Health/Traning/$date/run.md',
        bytes: controller.parser.encode('''---
type: training
date: $date
sport: [Бег]
metrics:
  duration: 42
  avg_hr: 145
  calories: 510
  aerobic_te: 3.4
  anaerobic_te: 1.2
assessment:
  load: 88
  trimp: 76
  recovery_hours: 18
---
# Бег
'''),
        modifiedAt: now,
      ),
    ]);
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith((ref) => controller)],
        child: const MaterialApp(home: ReportsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    DataTable sportsTable() => tester
        .widgetList<DataTable>(find.byType(DataTable))
        .singleWhere(
          (table) => table.columns.any(
            (column) =>
                column.label is Text &&
                (column.label as Text).data == 'Aerobic TE',
          ),
        );

    expect(sportsTable().showCheckboxColumn, isFalse);
    expect(sportsTable().sortColumnIndex, 0);
    expect(find.byType(Checkbox), findsNothing);

    await tester.tap(find.text('Мин'));
    await tester.pumpAndSettle();

    expect(sportsTable().sortColumnIndex, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'period report note renders native charts instead of placeholder',
    (tester) async {
      final parser = ObsidianParser();
      final note = parser.parse(
        VaultDocument(
          path: 'Resources/Reports/Month/July 2026.md',
          bytes: parser.encode('''---
type: period-report
report_type: monthly
period_start: 2026-07-01
period_end: 2026-07-31
---
# Отчёт за июль
```dataviewjs
await dv.view("Resources/Scripts/reports/dashboard");
```
'''),
          modifiedAt: DateTime(2026, 7, 21),
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith((ref) => AppController()),
          ],
          child: MaterialApp(home: NoteScreen(note: note)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Обзор'), findsOneWidget);
      expect(find.text('Заполнено дней'), findsOneWidget);
      expect(find.textContaining('Интерактивный блок Obsidian'), findsNothing);
    },
  );

  testWidgets('report layout editor fits Fold cover width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => AppController()),
        ],
        child: const MaterialApp(home: ReportLayoutEditorScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Редактор отчёта'), findsOneWidget);
    expect(find.text('Добавить блок'), findsOneWidget);
    await tester.tap(find.text('Добавить блок'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Новый блок'), findsWidgets);
  });

  testWidgets('settings controls fit Fold cover width', (tester) async {
    await tester.binding.setSurfaceSize(const Size(240, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith((ref) => AppController()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Настройки'), findsOneWidget);
    expect(find.text('WebDAV-хранилища'), findsOneWidget);
  });
}
