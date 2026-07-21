import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/markdown/obsidian_parser.dart';
import 'package:pavel_vault/src/core/vault/training_yaml.dart';
import 'package:pavel_vault/src/core/vault/vault_models.dart';

void main() {
  test('copies the complete original training YAML frontmatter', () {
    const source = '''---
type: training-log
sport: [Велосипед]
metrics:
  duration: 45
  aerobic_te: 3,4
  anaerobic_te: 0,5
assessment:
  load: 48
---
# Тренировка
''';
    final parser = ObsidianParser();
    final note = parser.parse(
      VaultDocument(
        path: 'Areas/Health/Traning/2026-07-21/bike.md',
        bytes: parser.encode(source),
        modifiedAt: DateTime(2026, 7, 21),
      ),
    );

    final yaml = trainingYaml(note);

    expect(yaml, contains('type: training-log'));
    expect(yaml, contains('aerobic_te: 3,4'));
    expect(yaml, contains('anaerobic_te: 0,5'));
    expect(yaml, contains('load: 48'));
    expect(yaml, isNot(contains('# Тренировка')));
  });
}
