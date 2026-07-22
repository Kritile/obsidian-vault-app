import 'package:flutter/foundation.dart';

import '../core/vault/period_report_data.dart';
import '../core/vault/report_layout.dart';
import '../core/vault/vault_models.dart';
import '../shared/app_log.dart';
import 'vault_controller.dart';

typedef NoteWriter = Future<void> Function(String path, String source);

class ReportController extends ChangeNotifier {
  ReportController(this._vault);

  final VaultController _vault;
  NoteWriter? noteWriter;
  ReportLayoutConfig layout = ReportLayoutConfig.defaults();
  final _builder = const PeriodReportDataBuilder();

  PeriodReportData build(ReportPeriod period) =>
      _builder.build(_vault.index.notes, period);

  List<WorkEntry> workEntries(ReportPeriod period) =>
      _vault.index.workEntries(period);

  Future<void> refresh() async {
    final document = _vault.documents
        .where((item) => item.path == ReportLayoutConfig.path)
        .firstOrNull;
    if (document == null) {
      layout = ReportLayoutConfig.defaults();
      notifyListeners();
      return;
    }
    try {
      layout = ReportLayoutConfig.decode(document.text);
    } catch (error, stackTrace) {
      layout = ReportLayoutConfig.defaults();
      AppLog.error(
        'Reports',
        'Конфигурация блоков повреждена; используется стандартная',
        error,
        stackTrace,
      );
    }
    notifyListeners();
  }

  Future<void> saveLayout(ReportLayoutConfig value) async {
    final writer = noteWriter;
    if (writer == null) throw StateError('Note writer is not configured');
    layout = value;
    notifyListeners();
    await writer(ReportLayoutConfig.path, value.encode());
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
