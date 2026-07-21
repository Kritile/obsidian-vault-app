import 'package:flutter_test/flutter_test.dart';
import 'package:pavel_vault/src/core/vault/report_layout.dart';

void main() {
  test('report layout round-trips standard and custom blocks', () {
    final source = ReportLayoutConfig(
      blocks: [
        ...ReportLayoutConfig.defaults().blocks,
        ReportBlockDefinition(
          id: 'custom-1',
          title: 'Интенсивность',
          kind: 'custom',
          source: ReportDataSource.training,
          visualization: ReportVisualization.bar,
          groupBy: 'sport',
          rowFormula: 'duration * load',
          aggregation: ReportAggregation.average,
          filters: const [
            ReportFilter(field: 'load', operator: 'greater', value: 10),
          ],
        ),
      ],
    );

    final decoded = ReportLayoutConfig.decode(source.encode());

    expect(decoded.blocks, hasLength(7));
    expect(decoded.blocks.last.source, ReportDataSource.training);
    expect(decoded.blocks.last.rowFormula, 'duration * load');
    expect(decoded.blocks.last.filters.single.operator, 'greater');
  });

  test('safe row formulas support nested fields and functions', () {
    final result =
        ReportFormula(
          'round(metrics.duration * assessment.load / 10)',
        ).evaluate({
          'metrics': {'duration': 42.5},
          'assessment': {'load': 18},
        });

    expect(result, 77);
    expect(ReportFormula('duration * (load +').validate(), isNotNull);
    expect(ReportFormula('system("rm")').validate(), isNotNull);
  });

  test('division by zero is stable for report previews', () {
    expect(ReportFormula('steps / 0').evaluate({'steps': 12000}), 0);
  });

  test('concurrent report layouts merge by block timestamp', () {
    final old = DateTime.utc(2026, 7, 20);
    final newer = DateTime.utc(2026, 7, 21);
    final local = ReportLayoutConfig(
      blocks: [
        ReportBlockDefinition(
          id: 'overview',
          title: 'Обзор',
          kind: 'overview',
          visible: false,
          updatedAt: newer,
        ),
      ],
    );
    final remote = ReportLayoutConfig(
      blocks: [
        ReportBlockDefinition(
          id: 'overview',
          title: 'Обзор',
          kind: 'overview',
          updatedAt: old,
        ),
        ReportBlockDefinition(
          id: 'custom-remote',
          title: 'Удалённый блок',
          kind: 'custom',
          updatedAt: newer,
        ),
      ],
    );

    final merged = ReportLayoutConfig.merge(local, remote);

    expect(merged.blocks, hasLength(2));
    expect(
      merged.blocks.firstWhere((item) => item.id == 'overview').visible,
      isFalse,
    );
    expect(merged.blocks.any((item) => item.id == 'custom-remote'), isTrue);
  });
}
