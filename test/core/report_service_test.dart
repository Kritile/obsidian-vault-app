import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/period_report_data.dart';
import 'package:pavel_vault/src/core/vault/report_service.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));
  final parser = ObsidianParser();

  final training = parser.parse(
    VaultDocument(
      path: 'Areas/Health/Traning/2026-07-19/bike.md',
      bytes: parser.encode('''---
date: 2026-07-19
type: training-log
sport: [Велосипед]
metrics:
  duration: 45
  avg_hr: 132
  max_hr: 176
  calories: 410
  aerobic_te: 3,4
  anaerobic_te: 0,7
assessment:
  trimp: 54,2
  load: 48
  recovery_hours: 18
---
# Тренировка

## Анализ
Интенсивная аэробная тренировка.
'''),
      modifiedAt: DateTime.utc(2026, 7, 19),
    ),
  );
  final daily = parser.parse(
    VaultDocument(
      path: 'Daily/19 July 2026.md',
      bytes: parser.encode('''---
created: 2026-07-19
step: 12345
sleep: 7.5
calories: 620
---
# День
## Что было сделано
- Подготовлен экспорт
'''),
      modifiedAt: DateTime.utc(2026, 7, 19),
    ),
  );
  final period = ReportPeriod(
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 7, 31),
    type: 'monthly',
  );

  PeriodReportData reportData() =>
      const PeriodReportDataBuilder().build([daily, training], period);

  test('Markdown report includes daily and detailed training metrics', () {
    final markdown = ReportService().markdown(
      const [],
      period,
      trainings: [training],
      reportData: reportData(),
    );

    expect(
      markdown,
      contains('| 19.07.2026 | День | 12345.0 | 7.5 | 620.0 | 1 |'),
    );
    expect(markdown, contains('## 🏋️ Тренировки'));
    expect(
      markdown,
      contains(
        '| 19.07.2026 | Велосипед | 45 | 132 | 176 | 410 | 3,4 | 0,7 | 54,2 | 48 | 18 |',
      ),
    );
  });

  test('CSV contains health, aerobic and anaerobic export columns', () {
    final csv = ReportService().detailedCsv(
      const [],
      period,
      trainings: [training],
      reportData: reportData(),
    );

    expect(csv, contains('steps,sleep_hours,daily_calories'));
    expect(csv, contains('aerobic_te,anaerobic_te,trimp,load'));
    expect(csv, contains('"12345.0"'));
    expect(csv, contains('"3,4"'));
    expect(csv, contains('"0,7"'));
  });

  test('PDF with Cyrillic and detailed metrics is generated', () async {
    final bytes = await ReportService().buildPdf(
      const [],
      period,
      trainings: [training],
      reportData: reportData(),
    );

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
