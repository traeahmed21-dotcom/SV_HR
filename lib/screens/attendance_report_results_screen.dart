import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/language_service.dart';
import '../services/report_export_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import '../widgets/scale_down_text.dart';
import '../widgets/sticky_data_table.dart';

class AttendanceReportResultsScreen extends StatelessWidget {
  final DateTime fromDate;
  final DateTime toDate;
  final List<Map<String, dynamic>> rows;
  final double sumWorkHours;
  final int sumAbsent;
  final int sumLate;
  final int sumPresent;
  final int sumRestDays;

  const AttendanceReportResultsScreen({
    super.key,
    required this.fromDate,
    required this.toDate,
    required this.rows,
    required this.sumWorkHours,
    required this.sumAbsent,
    required this.sumLate,
    required this.sumPresent,
    required this.sumRestDays,
  });

  String _t(BuildContext context, String key) {
    final lang = context.read<LanguageService>().currentLocale.languageCode;
    return Translations.getText(key, lang);
  }

  String _formatDate(DateTime d) => DateFormat('yyyy/MM/dd').format(d);

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

  String _statusText(BuildContext context, String status) {
    final s = status.toLowerCase();
    if (s == 'present') return _t(context, 'attendance_status_present');
    if (s == 'late') return _t(context, 'attendance_status_late');
    if (s == 'absent') return _t(context, 'attendance_status_absent');
    if (s == 'entryonly') return _t(context, 'attendance_status_entry_only');
    if (s == 'earlyleave') return _t(context, 'attendance_status_early_leave');
    if (s == 'incomplete') return _t(context, 'attendance_status_incomplete');
    if (s == 'overtime') return _t(context, 'attendance_status_overtime');
    if (s == 'exception') return _t(context, 'attendance_status_exception');
    if (s == 'restday') return _t(context, 'attendance_status_rest_day');
    if (s == 'officialholiday') return _t(context, 'attendance_status_official_holiday');
    return status;
  }

  Color _tint(ColorScheme scheme, Color main, Brightness brightness) {
    final alpha = brightness == Brightness.dark ? 0.28 : 0.18;
    return Color.alphaBlend(main.withValues(alpha: alpha), scheme.surface);
  }

  Color _statusMainColor(String status) {
    final s = status.toLowerCase();
    if (s == 'present') return const Color(0xFF2E7D32);
    if (s == 'late') return const Color(0xFFF57C00);
    if (s == 'absent') return const Color(0xFFD32F2F);
    if (s == 'earlyleave') return const Color(0xFFEF6C00);
    if (s == 'entryonly') return const Color(0xFF6D4C41);
    if (s == 'incomplete') return const Color(0xFF546E7A);
    if (s == 'overtime') return const Color(0xFF6A1B9A);
    if (s == 'exception') return const Color(0xFF455A64);
    if (s == 'restday') return const Color(0xFFF9A825);
    if (s == 'officialholiday') return const Color(0xFF1565C0);
    return const Color(0xFF5C6BC0);
  }

  Color _statusBg(BuildContext context, ColorScheme scheme, String status) {
    final b = Theme.of(context).brightness;
    final main = _statusMainColor(status);
    return _tint(scheme, main, b);
  }

  Color _statusFg(BuildContext context, Color main) {
    return main.withValues(alpha: 0.95);
  }

  IconData? _statusIcon(String status) {
    final s = status.toLowerCase();
    if (s == 'present') return Icons.check_circle_rounded;
    if (s == 'late') return Icons.schedule_rounded;
    if (s == 'absent') return Icons.cancel_rounded;
    if (s == 'restday') return Icons.weekend_rounded;
    if (s == 'officialholiday') return Icons.event_available_rounded;
    if (s == 'entryonly') return Icons.login_rounded;
    if (s == 'earlyleave') return Icons.logout_rounded;
    if (s == 'overtime') return Icons.timelapse_rounded;
    if (s == 'incomplete') return Icons.warning_rounded;
    if (s == 'exception') return Icons.error_rounded;
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

  DataColumn _col(BuildContext context, String key) {
    return DataColumn(
      label: ScaleDownText(
        _t(context, key),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }

  DataCell _cell(BuildContext context, String value, {TextAlign? align}) {
    return DataCell(
      ScaleDownText(
        value,
        textAlign: align ?? TextAlign.start,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  DataCell _statusCell(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    final main = _statusMainColor(status);
    return DataCell(
      _pill(
        context: context,
        text: _statusText(context, status),
        bg: _statusBg(context, scheme, status),
        fg: _statusFg(context, main),
        icon: _statusIcon(status),
      ),
    );
  }

  DataCell _dayNameCell(BuildContext context, String dayName) {
    final scheme = Theme.of(context).colorScheme;
    return DataCell(
      _pill(
        context: context,
        text: dayName,
        bg: scheme.primaryContainer,
        fg: scheme.onPrimaryContainer,
        icon: Icons.calendar_today_rounded,
      ),
    );
  }

  DataCell _dayTypeCell(
    BuildContext context, {
    required String dayWorkStatus,
    required String attendanceStatus,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    final s = attendanceStatus.toLowerCase();
    if (s == 'officialholiday') {
      final main = _statusMainColor(attendanceStatus);
      return DataCell(
        _pill(
          context: context,
          text: _t(context, 'attendance_status_official_holiday'),
          bg: _tint(scheme, main, b),
          fg: main,
          icon: Icons.event_available_rounded,
        ),
      );
    }

    final isWork = dayWorkStatus.toLowerCase() == 'workday';
    final main = isWork ? const Color(0xFF2E7D32) : const Color(0xFFF9A825);
    return DataCell(
      _pill(
        context: context,
        text: isWork ? _t(context, 'work_day') : _t(context, 'rest_day'),
        bg: _tint(scheme, main, b),
        fg: main,
        icon: isWork ? Icons.work_rounded : Icons.weekend_rounded,
      ),
    );
  }

  Color? _rowTint(BuildContext context, String status) {
    final scheme = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    final s = status.toLowerCase();
    if (s == 'absent' || s == 'late' || s == 'earlyleave' || s == 'incomplete' || s == 'exception') {
      final main = _statusMainColor(status);
      final alpha = b == Brightness.dark ? 0.12 : 0.08;
      return Color.alphaBlend(main.withValues(alpha: alpha), scheme.surface);
    }
    return null;
  }

  void _showGpsDetails(BuildContext context, Map<String, dynamic> row) {
    final punches = (row['DayPunches'] as List?) ?? [];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ScaleDownText(
                      _t(ctx, 'punch_locations'),
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (punches.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ScaleDownText(_t(ctx, 'no_results')),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: punches.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (c, i) {
                      final p = punches[i] as Map? ?? {};
                      final t = (p['t'] ?? '').toString();
                      final gps = (p['gps'] ?? '').toString();
                      final term = (p['term'] ?? '').toString();
                      return CustomCard(
                        padding: const EdgeInsets.all(12),
                        borderRadius: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ScaleDownText(
                              t,
                              style: Theme.of(c).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            if (gps.trim().isNotEmpty) ScaleDownText(gps),
                            if (term.trim().isNotEmpty) ScaleDownText(term),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  DataCell _gpsCell(BuildContext context, Map<String, dynamic> row) {
    final hasGps = row['HasGps'] == true;
    if (!hasGps) {
      return _cell(context, '-', align: TextAlign.center);
    }
    return DataCell(
      TextButton(
        onPressed: () => _showGpsDetails(context, row),
        child: Text(_t(context, 'view')),
      ),
    );
  }

  Future<void> _exportExcel(BuildContext context) async {
    await _runExport(
      context,
      action: () async {
        final headers = [
          _t(context, 'col_date'),
          _t(context, 'col_day'),
          _t(context, 'col_day_type'),
          _t(context, 'col_employee_name'),
          _t(context, 'col_shift'),
          _t(context, 'col_in_1'),
          _t(context, 'col_out_1'),
          _t(context, 'col_in_2'),
          _t(context, 'col_out_2'),
          _t(context, 'col_work_hours'),
          _t(context, 'col_overtime'),
          _t(context, 'col_status'),
          _t(context, 'col_late_minutes'),
          _t(context, 'col_early_leave_minutes'),
          _t(context, 'col_notes'),
        ];

        final outRows = rows.map((row) {
          final dayType = (row['DayWorkStatus'] ?? '').toString().toLowerCase() == 'workday'
              ? _t(context, 'work_day')
              : _t(context, 'rest_day');
          return <String>[
            (row['AttendanceDate'] ?? '').toString(),
            (row['DayName'] ?? '').toString(),
            dayType,
            (row['EmployeeName'] ?? '').toString(),
            (row['ShiftName'] ?? '').toString(),
            (row['Shift1FirstPunchIn'] ?? '').toString(),
            (row['Shift1LastPunchOut'] ?? '').toString(),
            (row['Shift2FirstPunchIn'] ?? '').toString(),
            (row['Shift2LastPunchOut'] ?? '').toString(),
            (row['TotalWorkHours'] ?? '').toString(),
            (row['OvertimeHours'] ?? '').toString(),
            _statusText(context, (row['AttendanceStatus'] ?? '').toString()),
            (row['LateMinutes'] ?? '').toString(),
            (row['EarlyLeaveMinutes'] ?? '').toString(),
            (row['ExceptionNotes'] ?? '').toString(),
          ];
        }).toList();

        await ReportExportService.exportExcelCsv(
          fileBaseName: 'AttendanceReport_${DateTime.now().millisecondsSinceEpoch}',
          headers: headers,
          rows: outRows,
        );
      },
    );
  }

  Future<void> _exportPdf(BuildContext context) async {
    await _runExport(
      context,
      action: () async {
        final headers = [
          _t(context, 'col_date'),
          _t(context, 'col_day'),
          _t(context, 'col_day_type'),
          _t(context, 'col_employee_name'),
          _t(context, 'col_shift'),
          _t(context, 'col_in_1'),
          _t(context, 'col_out_1'),
          _t(context, 'col_in_2'),
          _t(context, 'col_out_2'),
          _t(context, 'col_work_hours'),
          _t(context, 'col_overtime'),
          _t(context, 'col_status'),
          _t(context, 'col_late_minutes'),
          _t(context, 'col_early_leave_minutes'),
          _t(context, 'col_notes'),
        ];

        final outRows = rows.map((row) {
          final dayType = (row['DayWorkStatus'] ?? '').toString().toLowerCase() == 'workday'
              ? _t(context, 'work_day')
              : _t(context, 'rest_day');
          return <String>[
            (row['AttendanceDate'] ?? '').toString(),
            (row['DayName'] ?? '').toString(),
            dayType,
            (row['EmployeeName'] ?? '').toString(),
            (row['ShiftName'] ?? '').toString(),
            (row['Shift1FirstPunchIn'] ?? '').toString(),
            (row['Shift1LastPunchOut'] ?? '').toString(),
            (row['Shift2FirstPunchIn'] ?? '').toString(),
            (row['Shift2LastPunchOut'] ?? '').toString(),
            (row['TotalWorkHours'] ?? '').toString(),
            (row['OvertimeHours'] ?? '').toString(),
            _statusText(context, (row['AttendanceStatus'] ?? '').toString()),
            (row['LateMinutes'] ?? '').toString(),
            (row['EarlyLeaveMinutes'] ?? '').toString(),
            (row['ExceptionNotes'] ?? '').toString(),
          ];
        }).toList();

        await ReportExportService.exportPdfTable(
          context: context,
          fileBaseName: 'AttendanceReport_${DateTime.now().millisecondsSinceEpoch}',
          title: _t(context, 'attendance_reports_title'),
          subtitle: '${_formatDate(fromDate)} → ${_formatDate(toDate)}',
          headers: headers,
          rows: outRows,
        );
      },
    );
  }

  Widget _summaryTile(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return CustomCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 18,
      border: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 1),
      child: SizedBox(
        width: 140,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ScaleDownText(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
            ),
            const SizedBox(height: 6),
            ScaleDownText(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'attendance_reports_title')),
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
                  Row(
                    children: [
                      Expanded(
                        child: CustomCard(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          borderRadius: 16,
                          color: scheme.surfaceContainerHighest,
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_month_rounded,
                                size: 18,
                                color: scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ScaleDownText(
                                  '${_formatDate(fromDate)} → ${_formatDate(toDate)}',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
          if (rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _summaryTile(
                      context,
                      label: _t(context, 'summary_total_work_hours'),
                      value: sumWorkHours.toStringAsFixed(2),
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      context,
                      label: _t(context, 'summary_rest_days'),
                      value: sumRestDays.toString(),
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      context,
                      label: _t(context, 'summary_absent_days'),
                      value: sumAbsent.toString(),
                      color: scheme.error,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      context,
                      label: _t(context, 'summary_late_days'),
                      value: sumLate.toString(),
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      context,
                      label: _t(context, 'summary_present_days'),
                      value: sumPresent.toString(),
                      color: scheme.secondary,
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
                      const SizedBox(height: 64),
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.bar_chart_rounded,
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
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Builder(
                      builder: (context) {
                        final columns = <DataColumn>[
                          _col(context, 'col_date'),
                          _col(context, 'col_day'),
                          _col(context, 'col_day_type'),
                          _col(context, 'col_employee_name'),
                          _col(context, 'col_shift'),
                          _col(context, 'col_in_1'),
                          _col(context, 'col_out_1'),
                          _col(context, 'col_in_2'),
                          _col(context, 'col_out_2'),
                          _col(context, 'col_work_hours'),
                          _col(context, 'col_overtime'),
                          _col(context, 'col_status'),
                          _col(context, 'col_late_minutes'),
                          _col(context, 'col_early_leave_minutes'),
                          _col(context, 'col_notes'),
                          _col(context, 'col_gps'),
                        ];
                        const widths = <double>[
                          110,
                          120,
                          140,
                          190,
                          160,
                          110,
                          110,
                          110,
                          110,
                          120,
                          120,
                          170,
                          130,
                          150,
                          240,
                          90,
                        ];
                        final tableRows = rows.map((row) {
                          final status =
                              (row['AttendanceStatus'] ?? '').toString();
                          final dayWorkStatus =
                              (row['DayWorkStatus'] ?? '').toString();
                          return DataRow(
                            color: WidgetStatePropertyAll(
                              _rowTint(context, status),
                            ),
                            cells: [
                              _cell(context,
                                  (row['AttendanceDate'] ?? '').toString()),
                              _dayNameCell(
                                  context, (row['DayName'] ?? '').toString()),
                              _dayTypeCell(
                                context,
                                dayWorkStatus: dayWorkStatus,
                                attendanceStatus: status,
                              ),
                              _cell(context,
                                  (row['EmployeeName'] ?? '').toString()),
                              _cell(
                                  context, (row['ShiftName'] ?? '').toString()),
                              _cell(
                                context,
                                (row['Shift1FirstPunchIn'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _cell(
                                context,
                                (row['Shift1LastPunchOut'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _cell(
                                context,
                                (row['Shift2FirstPunchIn'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _cell(
                                context,
                                (row['Shift2LastPunchOut'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _cell(
                                context,
                                (row['TotalWorkHours'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _cell(
                                context,
                                (row['OvertimeHours'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _statusCell(context, status),
                              _cell(
                                context,
                                (row['LateMinutes'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _cell(
                                context,
                                (row['EarlyLeaveMinutes'] ?? '').toString(),
                                align: TextAlign.center,
                              ),
                              _cell(context,
                                  (row['ExceptionNotes'] ?? '').toString()),
                              _gpsCell(context, row),
                            ],
                          );
                        }).toList();

                        return StickyDataTable(
                          headingRowColor: WidgetStatePropertyAll(
                            scheme.surfaceContainerHighest,
                          ),
                          dataRowMinHeight: 48,
                          dataRowMaxHeight: 56,
                          columnSpacing: 18,
                          columnWidths: widths,
                          columns: columns,
                          rows: tableRows,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
