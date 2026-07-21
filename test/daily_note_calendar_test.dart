import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';
import 'package:pavel_vault/src/features/daily/daily_note_calendar.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets(
    'calendar marks and returns an existing daily note on Fold width',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(240, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final now = DateTime.now();
      final date = DateTime(now.year, now.month, 15);
      final source =
          '''---
tags: [Ежедневник]
created: ${date.year}-${date.month.toString().padLeft(2, '0')}-15
---
# День
''';
      final note = ObsidianParser().parse(
        VaultDocument(
          path: 'Daily/15 July ${date.year}.md',
          bytes: Uint8List.fromList(utf8.encode(source)),
          modifiedAt: date,
        ),
      );
      DailyDateSelection? selection;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  selection = await showDailyNoteCalendar(
                    context,
                    notes: [note],
                  );
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Открыть существующую заметку'), findsOneWidget);

      await tester.tap(find.text('15'));
      await tester.pumpAndSettle();
      expect(selection?.date, date);
      expect(selection?.note, same(note));
    },
  );
}
