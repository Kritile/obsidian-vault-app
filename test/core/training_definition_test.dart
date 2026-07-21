import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/vault/training_definition.dart';

void main() {
  test('each sport exposes its Obsidian-specific metrics', () {
    final rowing = trainingDefinition('rowing').metrics.map((item) => item.key);
    final bike = trainingDefinition('bike').metrics.map((item) => item.key);
    final rope = trainingDefinition('rope').metrics.map((item) => item.key);
    final tennis = trainingDefinition('tennis').metrics.map((item) => item.key);

    expect(rowing, containsAll(['strokes', 'stroke_rate', 'stroke_avg_time']));
    expect(bike, containsAll(['distance', 'avg_speed']));
    expect(rope, containsAll(['jumps', 'best_series']));
    expect(tennis, contains('games'));
    expect(
      trainingDefinitions.every(
        (sport) => sport.metrics.first.key == 'duration',
      ),
      isTrue,
    );
  });
}
