import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/period_report_data.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final parser = ObsidianParser();

  ParsedNote note(String path, String source, {DateTime? modifiedAt}) =>
      parser.parse(
        VaultDocument(
          path: path,
          bytes: parser.encode(source),
          modifiedAt: modifiedAt ?? DateTime(2026, 7, 21),
        ),
      );

  test('builds the same monthly datasets and KPI values as Obsidian', () {
    final notes = [
      note('Daily/21 July 2026.md', '''---
created: 2026-07-21
step: 8000
sleep: 7.5
calories: 430
---
# 21 июля

## Что было сделано
- Завершил отчёт
- Провёл встречу

## Привычки
- [x] Вода
- [ ] Чтение
'''),
      note('Areas/Health/Traning/2026-07-21/rowing.md', '''---
type: training-log
date: 2026-07-21
sport_key: rowing
sport: [Гребной тренажёр]
metrics:
  duration: 35
  calories: 270
assessment:
  load: 42
---
# Гребля
'''),
      note('Tasks/Подготовить релиз.md', '''---
created: 2026-07-20
tags: [task]
status: done
project: [Pavel Vault]
hours: 2.5
---
# Подготовить релиз
'''),
      note('Projects/Pavel Vault/План.md', '''---
created: 2026-07-19
project: [Pavel Vault]
---
# План
- [x] Собрать экран 1,5 ч #mobile
- [ ] Проверить графики
'''),
      note('Resources/Books/Новая книга.md', '''---
added: 2026-07-18
---
# Новая книга
'''),
      note(
        'Areas/Plants/Фикус.md',
        '# Фикус\n',
        modifiedAt: DateTime(2026, 7, 17, 14),
      ),
      note('Daily/30 June 2026.md', '''---
created: 2026-06-30
step: 100000
---
# Вне периода
'''),
    ];
    final period = ReportPeriod(
      start: DateTime(2026, 7),
      end: DateTime(2026, 8).subtract(const Duration(milliseconds: 1)),
      type: 'monthly',
    );

    final report = const PeriodReportDataBuilder().build(notes, period);

    expect(report.periodDays, 31);
    expect(report.dailies, hasLength(1));
    expect(report.steps, 8000);
    expect(report.averageSteps, 8000);
    expect(report.averageSleep, 7.5);
    expect(report.calories, 430);
    expect(report.doneItems.map((item) => item.text), [
      'Завершил отчёт',
      'Провёл встречу',
    ]);
    expect(report.habits, hasLength(2));
    expect(report.habits.where((item) => item.completed), hasLength(1));

    expect(report.trainings, hasLength(1));
    expect(report.trainingDuration, 35);
    expect(report.tasks, hasLength(3));
    expect(report.completedTasks, 2);
    expect(report.tasks.map((item) => item.hours).reduce((a, b) => a + b), 4);

    expect(report.notes, hasLength(3));
    expect(report.notes.map((item) => item.area).toSet(), {
      'Projects',
      'Resources',
      'Areas',
    });
    expect(report.fallbackNotes, 2);
    expect(report.buckets, hasLength(31));
    expect(report.missingSteps, 0);
    expect(report.missingSleep, 0);
    expect(report.missingCalories, 0);
  });

  test('yearly reports aggregate charts into month buckets', () {
    final report = const PeriodReportDataBuilder().build(
      const [],
      ReportPeriod(
        start: DateTime(2026),
        end: DateTime(2027).subtract(const Duration(milliseconds: 1)),
        type: 'yearly',
      ),
    );

    expect(report.buckets, hasLength(12));
    expect(report.buckets.first.start, DateTime(2026));
    expect(report.buckets.last.start, DateTime(2026, 12));
  });

  test('resolves periods from modern and legacy Obsidian report notes', () {
    final modern = note('Resources/Reports/Weekly/Week-2026-W30.md', '''---
type: period-report
report_type: weekly
period_start: 2026-07-20
period_end: 2026-07-26
---
# Недельный отчёт
```dataviewjs
await dv.view("Resources/Scripts/reports/dashboard");
```
''');
    final legacy = note('Resources/Reports/Year/2025.md', '''---
year: "2025"
tags: [Отчёт]
---
# Годовой отчёт
```dataviewjs
const start = dv.date("2025-01-01");
const end = dv.date("2025-12-31");
```
''');

    final modernPeriod = const ReportPeriodResolver().fromNote(modern)!;
    final legacyPeriod = const ReportPeriodResolver().fromNote(legacy)!;

    expect(modernPeriod.type, 'weekly');
    expect(modernPeriod.start, DateTime(2026, 7, 20));
    expect(modernPeriod.end.day, 26);
    expect(legacyPeriod.type, 'yearly');
    expect(legacyPeriod.start, DateTime(2025));
    expect(legacyPeriod.end.year, 2025);
  });
}
