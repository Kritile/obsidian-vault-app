import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/markdown/work_entry_codec.dart';

void main() {
  final codec = WorkEntryCodec();

  test('reads existing Russian time-entry variants', () {
    final entry = codec.parse(
      '- Правки валидации - 4,5ч - #le-tech #Punchcloud',
      path: 'Archive/2025-12/Daily/16 October 2025.md',
      date: DateTime(2025, 10, 16),
    );
    expect(entry, isNotNull);
    expect(entry!.hours, 4.5);
    expect(entry.projects, ['le-tech', 'Punchcloud']);
    expect(entry.description, 'Правки валидации');
  });

  test('writes format consumed by current Dataview reports', () {
    expect(codec.encode('Новая задача', 1.5, ['Letech']), '- Новая задача - 1.5ч - #Letech');
  });
}
