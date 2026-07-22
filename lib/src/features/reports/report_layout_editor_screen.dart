import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/vault/report_layout.dart';

class ReportLayoutEditorScreen extends ConsumerStatefulWidget {
  const ReportLayoutEditorScreen({super.key});

  @override
  ConsumerState<ReportLayoutEditorScreen> createState() =>
      _ReportLayoutEditorScreenState();
}

class _ReportLayoutEditorScreenState
    extends ConsumerState<ReportLayoutEditorScreen> {
  late List<ReportBlockDefinition> _blocks;
  var _saving = false;

  @override
  void initState() {
    super.initState();
    _blocks = [...ref.read(reportControllerProvider).layout.blocks];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Редактор отчёта'),
      actions: [
        IconButton(
          tooltip: 'Вернуть стандартную раскладку',
          onPressed: () => setState(
            () => _blocks = [...ReportLayoutConfig.defaults().blocks],
          ),
          icon: const Icon(Icons.restart_alt),
        ),
        IconButton(
          tooltip: 'Сохранить раскладку',
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              : const Icon(Icons.save_outlined),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      // There is no matching FAB on ReportsScreen. Disabling the implicit
      // default Hero avoids retaining this route's RepaintBoundary while the
      // save operation rebuilds the app with WebDAV progress updates.
      heroTag: null,
      onPressed: _add,
      icon: const Icon(Icons.add_chart),
      label: const Text('Добавить блок'),
    ),
    body: ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 100),
      itemCount: _blocks.length,
      onReorderItem: (oldIndex, newIndex) {
        setState(() {
          final item = _blocks.removeAt(oldIndex);
          _blocks.insert(newIndex, item.copyWith());
        });
      },
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Transform.scale(
          scale: 1 + animation.value * .03,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(20),
            child: child,
          ),
        ),
        child: child,
      ),
      itemBuilder: (context, index) {
        final block = _blocks[index];
        return AnimatedOpacity(
          key: ValueKey(block.id),
          opacity: block.visible ? 1 : .58,
          duration: const Duration(milliseconds: 260),
          child: Card(
            child: ListTile(
              leading: ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_indicator),
                ),
              ),
              title: Text(block.title),
              subtitle: Text(
                block.isCustom
                    ? '${_sourceLabel(block.source)} · ${_visualLabel(block.visualization)}'
                    : 'Стандартный блок',
              ),
              onTap: block.isCustom ? () => _edit(index) : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (block.isCustom)
                    PopupMenuButton<String>(
                      tooltip: 'Действия с блоком',
                      onSelected: (value) {
                        if (value == 'edit') _edit(index);
                        if (value == 'copy') _duplicate(index);
                        if (value == 'delete') {
                          setState(() => _blocks.removeAt(index));
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Изменить')),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text('Дублировать'),
                        ),
                        PopupMenuItem(value: 'delete', child: Text('Удалить')),
                      ],
                    ),
                  Switch(
                    value: block.visible,
                    onChanged: (value) => setState(
                      () => _blocks[index] = block.copyWith(visible: value),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Future<void> _add() async {
    final value = await Navigator.of(context).push<ReportBlockDefinition>(
      MaterialPageRoute(builder: (_) => const _CustomBlockEditor()),
    );
    if (value != null && mounted) setState(() => _blocks.add(value));
  }

  Future<void> _edit(int index) async {
    final value = await Navigator.of(context).push<ReportBlockDefinition>(
      MaterialPageRoute(
        builder: (_) => _CustomBlockEditor(initial: _blocks[index]),
      ),
    );
    if (value != null && mounted) setState(() => _blocks[index] = value);
  }

  void _duplicate(int index) {
    final item = _blocks[index];
    setState(
      () => _blocks.insert(
        index + 1,
        ReportBlockDefinition(
          id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
          title: '${item.title} — копия',
          kind: 'custom',
          source: item.source,
          visualization: item.visualization,
          groupBy: item.groupBy,
          valueField: item.valueField,
          rowFormula: item.rowFormula,
          aggregation: item.aggregation,
          filters: item.filters,
          tableFields: item.tableFields,
          metricFormula: item.metricFormula,
          comparison: item.comparison,
          targetRange: item.targetRange,
          showOnDashboard: item.showOnDashboard,
          requiredFields: item.requiredFields,
          updatedAt: DateTime.now().toUtc(),
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ref
        .read(reportControllerProvider)
        .saveLayout(ReportLayoutConfig(blocks: _blocks));
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
  }
}

class _CustomBlockEditor extends StatefulWidget {
  const _CustomBlockEditor({this.initial});
  final ReportBlockDefinition? initial;

  @override
  State<_CustomBlockEditor> createState() => _CustomBlockEditorState();
}

class _CustomBlockEditorState extends State<_CustomBlockEditor> {
  late final TextEditingController _title;
  late final TextEditingController _formula;
  late final TextEditingController _metricFormula;
  late final TextEditingController _targetMinimum;
  late final TextEditingController _target;
  late final TextEditingController _targetMaximum;
  late ReportDataSource _source;
  late ReportVisualization _visual;
  late ReportAggregation _aggregation;
  String? _groupBy;
  String? _valueField;
  late Set<String> _tableFields;
  late List<ReportFilter> _filters;
  late ReportComparison _comparison;
  late bool _showOnDashboard;
  late Set<String> _requiredFields;

  List<String> get _fields => reportFields[_source]!;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _title = TextEditingController(text: value?.title ?? 'Новый блок');
    _formula = TextEditingController(text: value?.rowFormula ?? '');
    _metricFormula = TextEditingController(text: value?.metricFormula ?? '');
    _targetMinimum = TextEditingController(
      text: value?.targetRange.minimum?.toString() ?? '',
    );
    _target = TextEditingController(
      text: value?.targetRange.target?.toString() ?? '',
    );
    _targetMaximum = TextEditingController(
      text: value?.targetRange.maximum?.toString() ?? '',
    );
    _source = value?.source ?? ReportDataSource.daily;
    _visual = value?.visualization ?? ReportVisualization.bar;
    _aggregation = value?.aggregation ?? ReportAggregation.count;
    _groupBy = value?.groupBy;
    _valueField = value?.valueField;
    _tableFields = {...?value?.tableFields};
    _filters = [...?value?.filters];
    _comparison = value?.comparison ?? ReportComparison.none;
    _showOnDashboard = value?.showOnDashboard ?? false;
    _requiredFields = {...?value?.requiredFields};
  }

  @override
  void dispose() {
    _title.dispose();
    _formula.dispose();
    _metricFormula.dispose();
    _targetMinimum.dispose();
    _target.dispose();
    _targetMaximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? 'Новый блок' : 'Настройка блока'),
        actions: [
          IconButton(
            tooltip: 'Сохранить блок',
            onPressed: _finish,
            icon: const Icon(Icons.check),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 560;
          return ListView(
            padding: EdgeInsets.all(narrow ? 12 : 20),
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Название блока'),
              ),
              const SizedBox(height: 12),
              _twoColumns(
                narrow,
                DropdownButtonFormField<ReportDataSource>(
                  isExpanded: true,
                  initialValue: _source,
                  decoration: const InputDecoration(
                    labelText: 'Источник данных',
                  ),
                  items: ReportDataSource.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(_sourceLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    _source = value!;
                    _groupBy = null;
                    _valueField = null;
                    _tableFields.clear();
                    _filters.clear();
                  }),
                ),
                DropdownButtonFormField<ReportVisualization>(
                  isExpanded: true,
                  initialValue: _visual,
                  decoration: const InputDecoration(labelText: 'Отображение'),
                  items: ReportVisualization.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(_visualLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _visual = value!),
                ),
              ),
              const SizedBox(height: 12),
              if (_visual != ReportVisualization.table) ...[
                _twoColumns(
                  narrow,
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    initialValue: _groupBy,
                    decoration: const InputDecoration(
                      labelText: 'Группировать по',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Без группировки'),
                      ),
                      ..._fields.map(
                        (field) => DropdownMenuItem<String?>(
                          value: field,
                          child: Text(_fieldLabel(field)),
                        ),
                      ),
                    ],
                    onChanged: (value) => setState(() => _groupBy = value),
                  ),
                  DropdownButtonFormField<ReportAggregation>(
                    isExpanded: true,
                    initialValue: _aggregation,
                    decoration: const InputDecoration(labelText: 'Агрегация'),
                    items: ReportAggregation.values
                        .map(
                          (item) => DropdownMenuItem(
                            value: item,
                            child: Text(_aggregationLabel(item)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _aggregation = value!),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: _valueField,
                  decoration: const InputDecoration(
                    labelText: 'Числовое поле',
                    helperText: 'Не требуется для подсчёта или при формуле',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Не выбрано'),
                    ),
                    ..._fields.map(
                      (field) => DropdownMenuItem<String?>(
                        value: field,
                        child: Text(_fieldLabel(field)),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _valueField = value),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _formula,
                  decoration: InputDecoration(
                    labelText: 'Построчная формула',
                    hintText: _source == ReportDataSource.training
                        ? 'duration * load'
                        : 'steps / 1000',
                    helperText:
                        'Поддерживаются + − × ÷ %, скобки, abs, round, min, max, coalesce',
                  ),
                ),
              ] else ...[
                Text(
                  'Колонки таблицы',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 5,
                  children: _fields
                      .map(
                        (field) => FilterChip(
                          label: Text(_fieldLabel(field)),
                          selected: _tableFields.contains(field),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _tableFields.add(field);
                            } else {
                              _tableFields.remove(field);
                            }
                          }),
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 20),
              Text('Аналитика', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              TextField(
                controller: _metricFormula,
                decoration: const InputDecoration(
                  labelText: 'Формула показателя',
                  helperText: 'Переменные: value, previous, delta',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ReportComparison>(
                isExpanded: true,
                initialValue: _comparison,
                decoration: const InputDecoration(labelText: 'Сравнение'),
                items: const [
                  DropdownMenuItem(value: ReportComparison.none, child: Text('Без сравнения')),
                  DropdownMenuItem(value: ReportComparison.previousPeriod, child: Text('Предыдущий период')),
                  DropdownMenuItem(value: ReportComparison.previousYear, child: Text('Прошлый год')),
                ],
                onChanged: (value) => setState(() => _comparison = value!),
              ),
              const SizedBox(height: 12),
              _twoColumns(
                narrow,
                TextField(
                  controller: _targetMinimum,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Минимум'),
                ),
                TextField(
                  controller: _target,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Цель'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _targetMaximum,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Максимум диапазона'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Показывать на главной'),
                value: _showOnDashboard,
                onChanged: (value) => setState(() => _showOnDashboard = value),
              ),
              const SizedBox(height: 8),
              Text('Обязательные поля', style: Theme.of(context).textTheme.titleMedium),
              Wrap(
                spacing: 7,
                children: _fields.map((field) => FilterChip(
                  label: Text(_fieldLabel(field)),
                  selected: _requiredFields.contains(field),
                  onSelected: (selected) => setState(() {
                    selected ? _requiredFields.add(field) : _requiredFields.remove(field);
                  }),
                )).toList(),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Фильтры',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Добавить фильтр',
                    onPressed: _addFilter,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              for (var index = 0; index < _filters.length; index++)
                _FilterTile(
                  key: ValueKey('$index-${_filters[index].field}'),
                  value: _filters[index],
                  fields: _fields,
                  onChanged: (value) => setState(() => _filters[index] = value),
                  onDelete: () => setState(() => _filters.removeAt(index)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _twoColumns(bool narrow, Widget first, Widget second) => narrow
      ? Column(children: [first, const SizedBox(height: 12), second])
      : Row(
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );

  void _addFilter() => setState(
    () => _filters.add(
      ReportFilter(field: _fields.first, operator: 'equals', value: ''),
    ),
  );

  void _finish() {
    final title = _title.text.trim();
    final formula = _formula.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите название блока')));
      return;
    }
    final formulaError = formula.isEmpty
        ? null
        : ReportFormula(formula).validate();
    if (formulaError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(formulaError)));
      return;
    }
    final metricFormula = _metricFormula.text.trim();
    final metricError = metricFormula.isEmpty
        ? null
        : ReportFormula(metricFormula).validate();
    if (metricError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(metricError)),
      );
      return;
    }
    Navigator.pop(
      context,
      ReportBlockDefinition(
        id:
            widget.initial?.id ??
            'custom-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        kind: 'custom',
        source: _source,
        visualization: _visual,
        groupBy: _groupBy,
        valueField: _valueField,
        rowFormula: formula.isEmpty ? null : formula,
        aggregation: _aggregation,
        filters: _filters,
        tableFields: _tableFields.toList(),
        metricFormula: metricFormula.isEmpty ? null : metricFormula,
        comparison: _comparison,
        targetRange: ReportTargetRange(
          minimum: double.tryParse(_targetMinimum.text.replaceAll(',', '.')),
          target: double.tryParse(_target.text.replaceAll(',', '.')),
          maximum: double.tryParse(_targetMaximum.text.replaceAll(',', '.')),
        ),
        showOnDashboard: _showOnDashboard,
        requiredFields: _requiredFields.toList(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.value,
    required this.fields,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });
  final ReportFilter value;
  final List<String> fields;
  final ValueChanged<ReportFilter> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 170,
            child: DropdownButtonFormField<String>(
              initialValue: value.field,
              decoration: const InputDecoration(labelText: 'Поле'),
              items: fields
                  .map(
                    (field) => DropdownMenuItem(
                      value: field,
                      child: Text(_fieldLabel(field)),
                    ),
                  )
                  .toList(),
              onChanged: (field) => onChanged(
                ReportFilter(
                  field: field!,
                  operator: value.operator,
                  value: value.value,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<String>(
              initialValue: value.operator,
              decoration: const InputDecoration(labelText: 'Условие'),
              items: const [
                DropdownMenuItem(value: 'equals', child: Text('Равно')),
                DropdownMenuItem(value: 'notEquals', child: Text('Не равно')),
                DropdownMenuItem(value: 'contains', child: Text('Содержит')),
                DropdownMenuItem(value: 'greater', child: Text('Больше')),
                DropdownMenuItem(value: 'less', child: Text('Меньше')),
                DropdownMenuItem(value: 'notEmpty', child: Text('Заполнено')),
              ],
              onChanged: (operator) => onChanged(
                ReportFilter(
                  field: value.field,
                  operator: operator!,
                  value: value.value,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: TextFormField(
              initialValue: value.value?.toString() ?? '',
              decoration: const InputDecoration(labelText: 'Значение'),
              onChanged: (text) => onChanged(
                ReportFilter(
                  field: value.field,
                  operator: value.operator,
                  value: text,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Удалить фильтр',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
}

const reportFields = <ReportDataSource, List<String>>{
  ReportDataSource.daily: [
    'date',
    'title',
    'steps',
    'sleep',
    'calories',
    'done',
  ],
  ReportDataSource.training: [
    'date',
    'title',
    'sport',
    'duration',
    'distance',
    'avg_speed',
    'avg_hr',
    'max_hr',
    'calories',
    'aerobic_te',
    'anaerobic_te',
    'trimp',
    'load',
    'recovery_hours',
    'strokes',
    'stroke_rate',
    'jumps',
    'games',
  ],
  ReportDataSource.task: [
    'date',
    'title',
    'completed',
    'project',
    'hours',
    'kind',
  ],
  ReportDataSource.note: ['date', 'title', 'area', 'date_source'],
  ReportDataSource.habit: ['date', 'title', 'completed'],
  ReportDataSource.done: ['date', 'title'],
};

String _sourceLabel(ReportDataSource? value) => switch (value) {
  ReportDataSource.daily => 'Ежедневники',
  ReportDataSource.training => 'Тренировки',
  ReportDataSource.task => 'Задачи',
  ReportDataSource.note => 'Заметки',
  ReportDataSource.habit => 'Привычки',
  ReportDataSource.done => 'Выполненное',
  null => 'Данные',
};

String _visualLabel(ReportVisualization value) => switch (value) {
  ReportVisualization.kpi => 'Показатель KPI',
  ReportVisualization.table => 'Таблица',
  ReportVisualization.line => 'Линейный график',
  ReportVisualization.bar => 'Столбчатый график',
  ReportVisualization.pie => 'Круговая диаграмма',
};

String _aggregationLabel(ReportAggregation value) => switch (value) {
  ReportAggregation.count => 'Количество',
  ReportAggregation.sum => 'Сумма',
  ReportAggregation.average => 'Среднее',
  ReportAggregation.minimum => 'Минимум',
  ReportAggregation.maximum => 'Максимум',
};

String _fieldLabel(String field) =>
    const {
      'date': 'Дата',
      'title': 'Название',
      'steps': 'Шаги',
      'sleep': 'Сон',
      'calories': 'Калории',
      'done': 'Сделано',
      'sport': 'Вид спорта',
      'duration': 'Длительность',
      'distance': 'Дистанция',
      'avg_speed': 'Средняя скорость',
      'avg_hr': 'Средний пульс',
      'max_hr': 'Макс. пульс',
      'aerobic_te': 'Aerobic TE',
      'anaerobic_te': 'Anaerobic TE',
      'trimp': 'TRIMP',
      'load': 'Нагрузка',
      'recovery_hours': 'Восстановление',
      'completed': 'Выполнено',
      'project': 'Проект',
      'hours': 'Часы',
      'kind': 'Тип',
      'area': 'Раздел',
      'date_source': 'Источник даты',
      'strokes': 'Гребки',
      'stroke_rate': 'Темп гребли',
      'jumps': 'Прыжки',
      'games': 'Партии',
    }[field] ??
    field;
