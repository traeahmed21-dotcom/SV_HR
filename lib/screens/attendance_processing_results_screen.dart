import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/language_service.dart';
import '../services/report_export_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import '../widgets/scale_down_text.dart';

class AttendanceProcessingResultsScreen extends StatelessWidget {
  final String subtitle;
  final List<String> headers;
  final List<TextAlign> aligns;
  final List<List<String>> rows;

  const AttendanceProcessingResultsScreen({
    super.key,
    required this.subtitle,
    required this.headers,
    required this.aligns,
    required this.rows,
  });

  String _t(BuildContext context, String key) {
    final lang = context.read<LanguageService>().currentLocale.languageCode;
    return Translations.getText(key, lang);
  }

  Color _tint(ColorScheme scheme, Color main, Brightness brightness) {
    final alpha = brightness == Brightness.dark ? 0.28 : 0.18;
    return Color.alphaBlend(main.withValues(alpha: alpha), scheme.surface);
  }

  Color _statusMainColor(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'طبيعي' || s == 'normal' || s == 'present') {
      return const Color(0xFF2E7D32);
    }
    if (s == 'تأخير' || s == 'late') return const Color(0xFFF57C00);
    if (s == 'غياب' || s == 'absent') return const Color(0xFFD32F2F);
    return const Color(0xFF5C6BC0);
  }

  IconData? _statusIcon(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'طبيعي' || s == 'normal' || s == 'present') {
      return Icons.check_circle_rounded;
    }
    if (s == 'تأخير' || s == 'late') return Icons.schedule_rounded;
    if (s == 'غياب' || s == 'absent') return Icons.cancel_rounded;
    return null;
  }

  Color? _rowTint(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    final s = status.trim().toLowerCase();
    if (s == 'غياب' || s == 'absent' || s == 'تأخير' || s == 'late') {
      final main = _statusMainColor(status);
      final alpha = b == Brightness.dark ? 0.12 : 0.08;
      return Color.alphaBlend(main.withValues(alpha: alpha), scheme.surface);
    }
    return null;
  }

  Widget _pill({
    required BuildContext context,
    required String text,
    required Color bg,
    required Color fg,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
          ],
          ScaleDownText(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ],
      ),
    );
  }

  Future<void> _runExport(
    BuildContext context, {
    required Future<void> Function() action,
  }) async {
    if (rows.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('جاري إنشاء الملف...'),
              ],
            ),
          ),
        );
      },
    );

    try {
      await action();
      rootNavigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء الملف وفتحه بنجاح')),
      );
    } catch (e) {
      rootNavigator.pop();
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(content: Text(msg.isNotEmpty ? msg : 'تعذر إنشاء الملف')),
      );
    }
  }

  Future<void> _exportExcel(BuildContext context) async {
    await _runExport(
      context,
      action: () => ReportExportService.exportExcelCsv(
        fileBaseName: 'AttendanceProcessing_${DateTime.now().millisecondsSinceEpoch}',
        headers: headers,
        rows: rows,
      ),
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    await _runExport(
      context,
      action: () => ReportExportService.exportPdfTable(
        context: context,
        fileBaseName: 'AttendanceProcessing_${DateTime.now().millisecondsSinceEpoch}',
        title: _t(context, 'attendance_processing_title'),
        subtitle: subtitle,
        headers: headers,
        rows: rows,
      ),
    );
  }

  DataColumn _col(BuildContext context, String title) {
    return DataColumn(
      label: ScaleDownText(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }

  DataCell _cell(BuildContext context, String value, TextAlign align) {
    return DataCell(
      ScaleDownText(
        value,
        textAlign: align,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  DataCell _statusCell(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    final main = _statusMainColor(status);
    return DataCell(
      _pill(
        context: context,
        text: status.trim().isEmpty ? '-' : status,
        bg: _tint(scheme, main, b),
        fg: main.withValues(alpha: 0.95),
        icon: _statusIcon(status),
      ),
    );
  }

  DataCell _metricCell(
    BuildContext context, {
    required String value,
    required TextAlign align,
    required Color main,
    required bool highlight,
    IconData? icon,
  }) {
    if (!highlight) {
      return _cell(context, value, align);
    }
    final scheme = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    return DataCell(
      _pill(
        context: context,
        text: value,
        bg: _tint(scheme, main, b),
        fg: main.withValues(alpha: 0.95),
        icon: icon,
      ),
    );
  }

  bool _isPositiveNumber(String value) {
    final normalized = value
        .replaceAll(',', '')
        .replaceAll('٬', '')
        .replaceAll(' ', '')
        .trim();
    if (normalized.isEmpty) return false;
    final parsed = double.tryParse(normalized);
    return parsed != null && parsed > 0;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overallStatusHeader = _t(context, 'col_overall_status');
    final salaryPenaltyHeader = _t(context, 'col_total_salary_penalty');
    final daysPenaltyHeader = _t(context, 'col_total_days_penalty');
    final warningsHeader = _t(context, 'col_total_warnings');
    final lateDaysHeader = _t(context, 'col_late_days');
    final absentDaysHeader = _t(context, 'col_absent_days');

    int indexOfHeader(String header) =>
        headers.indexWhere((h) => h.trim() == header.trim());

    final overallStatusIndex = indexOfHeader(overallStatusHeader);
    final salaryPenaltyIndex = indexOfHeader(salaryPenaltyHeader);
    final daysPenaltyIndex = indexOfHeader(daysPenaltyHeader);
    final warningsIndex = indexOfHeader(warningsHeader);
    final lateDaysIndex = indexOfHeader(lateDaysHeader);
    final absentDaysIndex = indexOfHeader(absentDaysHeader);

    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'attendance_processing_title')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: CustomCard(
              padding: const EdgeInsets.all(14),
              borderRadius: 22,
              border: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 1),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    borderRadius: 16,
                    color: scheme.surfaceContainerHighest,
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month_rounded, size: 18, color: scheme.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ScaleDownText(
                            subtitle,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: rows.isEmpty ? null : () => _exportPdf(context),
                        child: Text(_t(context, 'pdf')),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: rows.isEmpty ? null : () => _exportExcel(context),
                        child: Text(_t(context, 'excel')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: ScaleDownText(
                    '${_t(context, 'total')}: ${rows.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      const SizedBox(height: 56),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.table_chart_rounded,
                              size: 44,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(height: 12),
                            ScaleDownText(
                              _t(context, 'report_empty'),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStatePropertyAll(
                          scheme.surfaceContainerHighest,
                        ),
                        dataRowMinHeight: 48,
                        dataRowMaxHeight: 56,
                        columnSpacing: 18,
                        columns: headers.map((h) => _col(context, h)).toList(),
                        rows: rows.map((r) {
                          final statusValue = overallStatusIndex >= 0 &&
                                  overallStatusIndex < r.length
                              ? r[overallStatusIndex]
                              : '';
                          final rowTint = statusValue.trim().isEmpty
                              ? null
                              : _rowTint(context, statusValue);
                          return DataRow(
                            color: rowTint == null
                                ? null
                                : WidgetStatePropertyAll(rowTint),
                            cells: List.generate(
                              headers.length,
                              (i) {
                                final value = i < r.length ? r[i] : '';
                                final align =
                                    i < aligns.length ? aligns[i] : TextAlign.start;

                                if (i == overallStatusIndex) {
                                  return _statusCell(context, value);
                                }

                                if (i == absentDaysIndex) {
                                  return _metricCell(
                                    context,
                                    value: value,
                                    align: align,
                                    main: const Color(0xFFD32F2F),
                                    highlight: _isPositiveNumber(value),
                                    icon: Icons.cancel_rounded,
                                  );
                                }

                                if (i == lateDaysIndex) {
                                  return _metricCell(
                                    context,
                                    value: value,
                                    align: align,
                                    main: const Color(0xFFF57C00),
                                    highlight: _isPositiveNumber(value),
                                    icon: Icons.schedule_rounded,
                                  );
                                }

                                if (i == salaryPenaltyIndex) {
                                  return _metricCell(
                                    context,
                                    value: value,
                                    align: align,
                                    main: const Color(0xFFD32F2F),
                                    highlight: _isPositiveNumber(value),
                                    icon: Icons.payments_rounded,
                                  );
                                }

                                if (i == daysPenaltyIndex) {
                                  return _metricCell(
                                    context,
                                    value: value,
                                    align: align,
                                    main: const Color(0xFFD32F2F),
                                    highlight: _isPositiveNumber(value),
                                    icon: Icons.event_busy_rounded,
                                  );
                                }

                                if (i == warningsIndex) {
                                  return _metricCell(
                                    context,
                                    value: value,
                                    align: align,
                                    main: const Color(0xFFF57C00),
                                    highlight: _isPositiveNumber(value),
                                    icon: Icons.warning_rounded,
                                  );
                                }

                                return _cell(context, value, align);
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
