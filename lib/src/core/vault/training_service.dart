import 'package:intl/intl.dart';

import 'training_definition.dart';
import 'vault_creation_support.dart';

final class TrainingService extends VaultCreationService {
  TrainingService(super.vault, super.writeNote);

  Future<void> create({
    required DateTime date,
    required String sportKey,
    required Map<String, double?> metrics,
    String mood = 'good',
    String analysis = '',
  }) async {
    final sport = trainingDefinition(sportKey);
    final dateValue = DateFormat('yyyy-MM-dd').format(date);
    final folder = 'Areas/Health/Traning/$dateValue';
    var suffix = '';
    var index = 2;
    while (await vault.read('$folder/$sportKey$suffix.md') != null) {
      suffix = '-${index++}';
    }
    final duration = metrics['duration'] ?? 0;
    final heartRate = metrics['avg_hr'] ?? 0;
    final percent = heartRate / 190 * 100;
    final intensity = percent < 50
        ? 0.3
        : percent < 60
        ? 0.5
        : percent < 70
        ? 0.7
        : percent < 80
        ? 1.0
        : percent < 90
        ? 1.5
        : 2.0;
    final trimp = duration * intensity;
    final load = ((trimp / 150) * 100).clamp(0, 100).round();
    final recovery = (((load / 25) * 24).round()).clamp(12, 1 << 31);
    final metricYaml = sport.metrics
        .map((field) => '  ${field.key}: ${metrics[field.key] ?? ''}')
        .join('\n');
    final source =
        '''---
created: $dateValue
date: $dateValue
time: "${DateFormat('HH:mm').format(date)}"
type: training-log
tags: [${sport.tags.join(', ')}]
sport:
  - ${sport.name}
sport_key: $sportKey
mood: $mood
metrics:
$metricYaml
assessment:
  trimp: ${trimp.toStringAsFixed(1)}
  load: $load
  recovery_hours: $recovery
  joint_risk: ${sport.jointRisk}
  cardio: improving
---

# ${sport.icon} Тренировка — ${DateFormat('d MMMM yyyy', 'ru').format(date)} в ${DateFormat('HH:mm').format(date)}

```dataviewjs
await dv.view("Resources/Scripts/training-card");
```

## 📝 Анализ

${analysis.trim().isEmpty ? '> Заполнить после тренировки.' : analysis.trim()}

## 📌 Вывод

-
''';
    await writeNote('$folder/$sportKey$suffix.md', source);
  }
}
