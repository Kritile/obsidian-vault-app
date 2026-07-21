class TrainingMetricDefinition {
  const TrainingMetricDefinition({
    required this.key,
    required this.label,
    this.unit = '',
    this.required = false,
  });
  final String key;
  final String label;
  final String unit;
  final bool required;
}

class TrainingDefinition {
  const TrainingDefinition({
    required this.key,
    required this.icon,
    required this.name,
    required this.tags,
    required this.jointRisk,
    required this.metrics,
  });
  final String key;
  final String icon;
  final String name;
  final List<String> tags;
  final String jointRisk;
  final List<TrainingMetricDefinition> metrics;
}

const trainingDefinitions = <TrainingDefinition>[
  TrainingDefinition(
    key: 'rowing',
    icon: '🚣',
    name: 'Гребной тренажёр',
    tags: ['здоровье', 'тренировки', 'гребной-тренажер', 'кардио'],
    jointRisk: 'low',
    metrics: [
      TrainingMetricDefinition(
        key: 'duration',
        label: 'Длительность',
        unit: 'мин',
        required: true,
      ),
      TrainingMetricDefinition(
        key: 'avg_hr',
        label: 'Средний пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(
        key: 'max_hr',
        label: 'Максимальный пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(key: 'calories', label: 'Калории', unit: 'ккал'),
      TrainingMetricDefinition(key: 'strokes', label: 'Количество гребков'),
      TrainingMetricDefinition(
        key: 'stroke_rate',
        label: 'Средний темп',
        unit: 'греб/мин',
      ),
      TrainingMetricDefinition(
        key: 'stroke_avg_time',
        label: 'Среднее время гребка',
        unit: 'сек',
      ),
      TrainingMetricDefinition(key: 'aerobic_te', label: 'Aerobic TE'),
      TrainingMetricDefinition(key: 'anaerobic_te', label: 'Anaerobic TE'),
    ],
  ),
  TrainingDefinition(
    key: 'bike',
    icon: '🚴',
    name: 'Велосипед',
    tags: ['здоровье', 'тренировки', 'велосипед', 'кардио'],
    jointRisk: 'medium',
    metrics: [
      TrainingMetricDefinition(
        key: 'duration',
        label: 'Длительность',
        unit: 'мин',
        required: true,
      ),
      TrainingMetricDefinition(key: 'distance', label: 'Дистанция', unit: 'км'),
      TrainingMetricDefinition(
        key: 'avg_speed',
        label: 'Средняя скорость',
        unit: 'км/ч',
      ),
      TrainingMetricDefinition(
        key: 'avg_hr',
        label: 'Средний пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(
        key: 'max_hr',
        label: 'Максимальный пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(key: 'calories', label: 'Калории', unit: 'ккал'),
      TrainingMetricDefinition(key: 'aerobic_te', label: 'Aerobic TE'),
      TrainingMetricDefinition(key: 'anaerobic_te', label: 'Anaerobic TE'),
    ],
  ),
  TrainingDefinition(
    key: 'rope',
    icon: '🪢',
    name: 'Скакалка',
    tags: ['здоровье', 'тренировки', 'скакалка', 'кардио'],
    jointRisk: 'high',
    metrics: [
      TrainingMetricDefinition(
        key: 'duration',
        label: 'Длительность',
        unit: 'мин',
        required: true,
      ),
      TrainingMetricDefinition(key: 'jumps', label: 'Прыжков'),
      TrainingMetricDefinition(key: 'best_series', label: 'Максимум подряд'),
      TrainingMetricDefinition(
        key: 'avg_hr',
        label: 'Средний пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(
        key: 'max_hr',
        label: 'Максимальный пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(key: 'calories', label: 'Калории', unit: 'ккал'),
      TrainingMetricDefinition(key: 'aerobic_te', label: 'Aerobic TE'),
      TrainingMetricDefinition(key: 'anaerobic_te', label: 'Anaerobic TE'),
    ],
  ),
  TrainingDefinition(
    key: 'tennis',
    icon: '🏓',
    name: 'Настольный теннис',
    tags: ['здоровье', 'тренировки', 'настольный-теннис', 'координация'],
    jointRisk: 'low',
    metrics: [
      TrainingMetricDefinition(
        key: 'duration',
        label: 'Длительность',
        unit: 'мин',
        required: true,
      ),
      TrainingMetricDefinition(key: 'games', label: 'Количество партий'),
      TrainingMetricDefinition(
        key: 'avg_hr',
        label: 'Средний пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(
        key: 'max_hr',
        label: 'Максимальный пульс',
        unit: 'уд/мин',
      ),
      TrainingMetricDefinition(key: 'calories', label: 'Калории', unit: 'ккал'),
      TrainingMetricDefinition(key: 'aerobic_te', label: 'Aerobic TE'),
      TrainingMetricDefinition(key: 'anaerobic_te', label: 'Anaerobic TE'),
    ],
  ),
];

TrainingDefinition trainingDefinition(String key) =>
    trainingDefinitions.firstWhere(
      (item) => item.key == key,
      orElse: () => trainingDefinitions.first,
    );
