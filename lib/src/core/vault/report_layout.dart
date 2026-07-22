import 'dart:convert';

enum ReportDataSource { daily, training, task, note, habit, done }

enum ReportVisualization { kpi, table, line, bar, pie }

enum ReportAggregation { count, sum, average, minimum, maximum }

enum ReportComparison { none, previousPeriod, previousYear }

class ReportTargetRange {
  const ReportTargetRange({this.minimum, this.target, this.maximum});

  final double? minimum;
  final double? target;
  final double? maximum;

  bool get configured => minimum != null || target != null || maximum != null;

  Map<String, Object?> toJson() => {
    if (minimum != null) 'minimum': minimum,
    if (target != null) 'target': target,
    if (maximum != null) 'maximum': maximum,
  };

  factory ReportTargetRange.fromJson(Map<String, Object?> json) =>
      ReportTargetRange(
        minimum: (json['minimum'] as num?)?.toDouble(),
        target: (json['target'] as num?)?.toDouble(),
        maximum: (json['maximum'] as num?)?.toDouble(),
      );
}

class ReportFilter {
  const ReportFilter({required this.field, required this.operator, this.value});

  final String field;
  final String operator;
  final Object? value;

  Map<String, Object?> toJson() => {
    'field': field,
    'operator': operator,
    'value': value,
  };

  factory ReportFilter.fromJson(Map<String, Object?> json) => ReportFilter(
    field: json['field']?.toString() ?? '',
    operator: json['operator']?.toString() ?? 'equals',
    value: json['value'],
  );
}

class ReportBlockDefinition {
  const ReportBlockDefinition({
    required this.id,
    required this.title,
    required this.kind,
    this.visible = true,
    this.source,
    this.visualization = ReportVisualization.table,
    this.groupBy,
    this.valueField,
    this.rowFormula,
    this.aggregation = ReportAggregation.count,
    this.filters = const [],
    this.tableFields = const [],
    this.metricFormula,
    this.comparison = ReportComparison.none,
    this.targetRange = const ReportTargetRange(),
    this.showOnDashboard = false,
    this.requiredFields = const [],
    this.updatedAt,
  });

  final String id;
  final String title;
  final String kind;
  final bool visible;
  final ReportDataSource? source;
  final ReportVisualization visualization;
  final String? groupBy;
  final String? valueField;
  final String? rowFormula;
  final ReportAggregation aggregation;
  final List<ReportFilter> filters;
  final List<String> tableFields;
  final String? metricFormula;
  final ReportComparison comparison;
  final ReportTargetRange targetRange;
  final bool showOnDashboard;
  final List<String> requiredFields;
  final DateTime? updatedAt;

  bool get isCustom => kind == 'custom';

  ReportBlockDefinition copyWith({
    String? title,
    bool? visible,
    ReportDataSource? source,
    ReportVisualization? visualization,
    String? groupBy,
    String? valueField,
    String? rowFormula,
    ReportAggregation? aggregation,
    List<ReportFilter>? filters,
    List<String>? tableFields,
    String? metricFormula,
    ReportComparison? comparison,
    ReportTargetRange? targetRange,
    bool? showOnDashboard,
    List<String>? requiredFields,
    DateTime? updatedAt,
  }) => ReportBlockDefinition(
    id: id,
    title: title ?? this.title,
    kind: kind,
    visible: visible ?? this.visible,
    source: source ?? this.source,
    visualization: visualization ?? this.visualization,
    groupBy: groupBy ?? this.groupBy,
    valueField: valueField ?? this.valueField,
    rowFormula: rowFormula ?? this.rowFormula,
    aggregation: aggregation ?? this.aggregation,
    filters: filters ?? this.filters,
    tableFields: tableFields ?? this.tableFields,
    metricFormula: metricFormula ?? this.metricFormula,
    comparison: comparison ?? this.comparison,
    targetRange: targetRange ?? this.targetRange,
    showOnDashboard: showOnDashboard ?? this.showOnDashboard,
    requiredFields: requiredFields ?? this.requiredFields,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'kind': kind,
    'visible': visible,
    if (source != null) 'source': source!.name,
    'visualization': visualization.name,
    if (groupBy != null && groupBy!.isNotEmpty) 'groupBy': groupBy,
    if (valueField != null && valueField!.isNotEmpty) 'valueField': valueField,
    if (rowFormula != null && rowFormula!.isNotEmpty) 'rowFormula': rowFormula,
    'aggregation': aggregation.name,
    'filters': filters.map((item) => item.toJson()).toList(),
    'tableFields': tableFields,
    if (metricFormula != null && metricFormula!.isNotEmpty)
      'metricFormula': metricFormula,
    'comparison': comparison.name,
    if (targetRange.configured) 'targetRange': targetRange.toJson(),
    'showOnDashboard': showOnDashboard,
    'requiredFields': requiredFields,
    'updatedAt': (updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
  };

  factory ReportBlockDefinition.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
        values.where((item) => item.name == raw?.toString()).firstOrNull ??
        fallback;
    final source = json['source'];
    return ReportBlockDefinition(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Блок',
      kind: json['kind']?.toString() ?? 'custom',
      visible: json['visible'] != false,
      source: source == null
          ? null
          : enumValue(ReportDataSource.values, source, ReportDataSource.daily),
      visualization: enumValue(
        ReportVisualization.values,
        json['visualization'],
        ReportVisualization.table,
      ),
      groupBy: json['groupBy']?.toString(),
      valueField: json['valueField']?.toString(),
      rowFormula: json['rowFormula']?.toString(),
      aggregation: enumValue(
        ReportAggregation.values,
        json['aggregation'],
        ReportAggregation.count,
      ),
      filters: (json['filters'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ReportFilter.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false),
      tableFields: (json['tableFields'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      metricFormula: json['metricFormula']?.toString(),
      comparison: enumValue(
        ReportComparison.values,
        json['comparison'],
        ReportComparison.none,
      ),
      targetRange: json['targetRange'] is Map
          ? ReportTargetRange.fromJson(
              Map<String, Object?>.from(json['targetRange']! as Map),
            )
          : const ReportTargetRange(),
      showOnDashboard: json['showOnDashboard'] == true,
      requiredFields: (json['requiredFields'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}

class ReportLayoutConfig {
  const ReportLayoutConfig({required this.blocks, this.version = 2});

  static const path = '.pavel-vault/reports-layout.v1.json';
  final int version;
  final List<ReportBlockDefinition> blocks;

  static ReportLayoutConfig defaults() => ReportLayoutConfig(
    blocks: const [
      ReportBlockDefinition(id: 'overview', title: 'Обзор', kind: 'overview'),
      ReportBlockDefinition(id: 'daily', title: 'Ежедневники', kind: 'daily'),
      ReportBlockDefinition(id: 'sports', title: 'Спорт', kind: 'sports'),
      ReportBlockDefinition(id: 'tasks', title: 'Задачи', kind: 'tasks'),
      ReportBlockDefinition(id: 'notes', title: 'Новые заметки', kind: 'notes'),
      ReportBlockDefinition(
        id: 'quality',
        title: 'Качество данных',
        kind: 'quality',
      ),
    ],
  );

  String encode() => const JsonEncoder.withIndent('  ').convert({
    'version': version,
    'blocks': blocks.map((item) => item.toJson()).toList(),
  });

  factory ReportLayoutConfig.decode(String source) {
    final json = jsonDecode(source) as Map<String, Object?>;
    final blocks = (json['blocks'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              ReportBlockDefinition.fromJson(Map<String, Object?>.from(item)),
        )
        .where((item) => item.id.isNotEmpty)
        .toList(growable: false);
    if (blocks.isEmpty) throw const FormatException('Empty report layout');
    return ReportLayoutConfig(
      version: 2,
      blocks: blocks,
    );
  }

  static ReportLayoutConfig merge(
    ReportLayoutConfig local,
    ReportLayoutConfig remote,
  ) {
    final selected = <String, ReportBlockDefinition>{};
    for (final block in [...local.blocks, ...remote.blocks]) {
      final current = selected[block.id];
      final currentDate =
          current?.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final candidateDate =
          block.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      if (current == null || candidateDate.isAfter(currentDate)) {
        selected[block.id] = block;
      }
    }
    final localNewest = local.blocks
        .map((item) => item.updatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final remoteNewest = remote.blocks
        .map((item) => item.updatedAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
    final preferred =
        remoteNewest != null &&
            (localNewest == null || remoteNewest.isAfter(localNewest))
        ? remote.blocks
        : local.blocks;
    final order = [
      ...preferred.map((item) => item.id),
      ...selected.keys.where((id) => !preferred.any((item) => item.id == id)),
    ];
    return ReportLayoutConfig(
      version: local.version > remote.version ? local.version : remote.version,
      blocks: order.map((id) => selected[id]!).toList(growable: false),
    );
  }

  ReportLayoutConfig copyWith({List<ReportBlockDefinition>? blocks}) =>
      ReportLayoutConfig(version: version, blocks: blocks ?? this.blocks);
}

class ReportFormula {
  ReportFormula(this.source);
  final String source;

  double evaluate(Map<String, Object?> row) {
    final parser = _FormulaParser(source, row);
    final value = parser.parse();
    if (!value.isFinite) {
      throw const FormatException('Результат не является числом');
    }
    return value;
  }

  String? validate() {
    try {
      _FormulaParser(source, const {}).parse(allowUnknown: true);
      return null;
    } on FormatException catch (error) {
      return error.message;
    }
  }
}

class _FormulaParser {
  _FormulaParser(this.source, this.values);
  final String source;
  final Map<String, Object?> values;
  var index = 0;
  var allowUnknown = false;

  double parse({bool allowUnknown = false}) {
    this.allowUnknown = allowUnknown;
    final result = _expression();
    _spaces();
    if (index != source.length) throw _error('Неожиданный символ');
    return result;
  }

  double _expression() {
    var value = _term();
    while (true) {
      if (_take('+')) {
        value += _term();
      } else if (_take('-')) {
        value -= _term();
      } else {
        return value;
      }
    }
  }

  double _term() {
    var value = _factor();
    while (true) {
      if (_take('*')) {
        value *= _factor();
      } else if (_take('/')) {
        final divisor = _factor();
        value = divisor == 0 ? 0 : value / divisor;
      } else if (_take('%')) {
        final divisor = _factor();
        value = divisor == 0 ? 0 : value % divisor;
      } else {
        return value;
      }
    }
  }

  double _factor() {
    _spaces();
    if (_take('-')) return -_factor();
    if (_take('(')) {
      final value = _expression();
      if (!_take(')')) throw _error('Ожидалась закрывающая скобка');
      return value;
    }
    final number = RegExp(
      r'^\d+(?:[.,]\d+)?',
    ).firstMatch(source.substring(index));
    if (number != null) {
      index += number.group(0)!.length;
      return double.parse(number.group(0)!.replaceAll(',', '.'));
    }
    final name = _identifier();
    if (name.isEmpty) throw _error('Ожидалось число, поле или функция');
    if (_take('(')) {
      final args = <double>[];
      if (!_peek(')')) {
        do {
          args.add(_expression());
        } while (_take(','));
      }
      if (!_take(')')) throw _error('Ожидалась закрывающая скобка');
      return _function(name, args);
    }
    final raw = _nested(values, name);
    if (raw == null && allowUnknown) return 0;
    return _number(raw) ?? 0;
  }

  double _function(String name, List<double> args) => switch (name) {
    'abs' when args.length == 1 => args.first.abs(),
    'round' when args.length == 1 => args.first.roundToDouble(),
    'min' when args.isNotEmpty => args.reduce((a, b) => a < b ? a : b),
    'max' when args.isNotEmpty => args.reduce((a, b) => a > b ? a : b),
    'coalesce' when args.isNotEmpty => args.firstWhere(
      (item) => item != 0,
      orElse: () => 0,
    ),
    _ => throw _error(
      'Неизвестная функция или неверное число аргументов: $name',
    ),
  };

  String _identifier() {
    _spaces();
    final match = RegExp(
      r'^[\p{L}_][\p{L}\p{N}_.]*',
      unicode: true,
    ).firstMatch(source.substring(index));
    if (match == null) return '';
    index += match.group(0)!.length;
    return match.group(0)!;
  }

  bool _take(String token) {
    _spaces();
    if (!source.startsWith(token, index)) return false;
    index += token.length;
    return true;
  }

  bool _peek(String token) {
    _spaces();
    return source.startsWith(token, index);
  }

  void _spaces() {
    while (index < source.length && source[index].trim().isEmpty) {
      index++;
    }
  }

  FormatException _error(String message) =>
      FormatException('$message, позиция ${index + 1}');
}

Object? _nested(Map<String, Object?> values, String path) {
  Object? current = values;
  for (final part in path.split('.')) {
    if (current is! Map) return null;
    current = current[part];
  }
  return current;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  final match = RegExp(
    r'-?\d+(?:[.,]\d+)?',
  ).firstMatch(value?.toString() ?? '');
  return match == null
      ? null
      : double.tryParse(match.group(0)!.replaceAll(',', '.'));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
