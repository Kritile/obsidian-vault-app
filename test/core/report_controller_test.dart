import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pavel_vault/src/app/report_controller.dart';
import 'package:pavel_vault/src/app/vault_controller.dart';
import 'package:pavel_vault/src/core/crypto/encrypted_object_store.dart';
import 'package:pavel_vault/src/core/vault/report_layout.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('comparison periods preserve duration and support previous year', () {
    final controller = ReportController(VaultController());
    final july = ReportPeriod(
      start: DateTime(2026, 7, 1),
      end: DateTime(2026, 7, 31, 23, 59, 59),
      type: 'monthly',
    );

    final previous = controller.comparisonPeriod(
      july,
      ReportComparison.previousPeriod,
    );
    final year = controller.comparisonPeriod(
      july,
      ReportComparison.previousYear,
    );

    expect(previous.end, july.start.subtract(const Duration(milliseconds: 1)));
    expect(previous.start, DateTime(2026, 6, 1));
    expect(year.start, DateTime(2025, 7, 1));
    expect(year.end.year, 2025);
  });

  test('periodic report creation is idempotent', () async {
    final root = await Directory.systemTemp.createTemp('vellum-auto-reports-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final vault = VaultController();
    await vault.initializeStoreForTesting(
      EncryptedObjectStore(rootDirectory: root),
    );
    final controller = ReportController(vault)
      ..noteWriter = (path, source) => vault.saveLocal(path, source);

    await controller.ensurePeriodicReports(now: DateTime(2026, 7, 22));
    final first = vault.index.notes
        .where((note) => note.type == VaultEntityType.periodReport)
        .length;
    await controller.ensurePeriodicReports(now: DateTime(2026, 7, 22));
    final second = vault.index.notes
        .where((note) => note.type == VaultEntityType.periodReport)
        .length;

    expect(first, 2);
    expect(second, first);
  });

  test('report layout exports as an open Markdown template', () async {
    final controller = ReportController(VaultController());
    String? path;
    String? source;
    controller.noteWriter = (valuePath, valueSource) async {
      path = valuePath;
      source = valueSource;
    };

    await controller.exportTemplate('Рабочий отчёт');

    expect(path, 'Templates/Reports/Рабочий отчёт.md');
    expect(source, contains('type: report-template'));
    expect(source, contains('```vellum-report'));
    expect(source, contains('"version": 2'));
  });
}
