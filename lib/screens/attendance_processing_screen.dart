import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/report_export_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import '../widgets/scale_down_text.dart';

class AttendanceProcessingScreen extends StatefulWidget {
  final int clientId;

  const AttendanceProcessingScreen({
    super.key,
    required this.clientId,
  });

  @override
  State<AttendanceProcessingScreen> createState() =>
      _AttendanceProcessingScreenState();
}

class _ColDef {
  final String key;
  final String labelKey;
  final TextAlign align;

  const _ColDef({
    required this.key,
    required this.labelKey,
    this.align = TextAlign.start,
  });
}

class _AttendanceProcessingScreenState extends State<AttendanceProcessingScreen> {
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime.now();
  bool _loading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _departments = <Map<String, dynamic>>[];
  Map<String, dynamic>? _selectedDepartment;

  String _calculationMethod = 'ByPeriod';

  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  late final List<_ColDef> _allCols;
  late Map<String, bool> _visibleCols;

  String _t(BuildContext context, String key) {
    final lang = context.read<LanguageService>().currentLocale.languageCode;
    return Translations.getText(key, lang);
  }

  @override
  void initState() {
    super.initState();
    _allCols = [
      _ColDef(key: 'EmployeeID', labelKey: 'col_employee_id', align: TextAlign.center),
      _ColDef(key: 'EmployeeName', labelKey: 'col_employee_name'),
      _ColDef(key: 'EmployeeNumber', labelKey: 'col_employee_number'),
      _ColDef(key: 'DepartmentName', labelKey: 'col_department'),
      _ColDef(key: 'ShiftName', labelKey: 'col_shift'),
      _ColDef(key: 'TotalDays', labelKey: 'col_total_days', align: TextAlign.center),
      _ColDef(key: 'WorkDays', labelKey: 'col_work_days', align: TextAlign.center),
      _ColDef(key: 'PresentDays', labelKey: 'col_present_days', align: TextAlign.center),
      _ColDef(key: 'LateDays', labelKey: 'col_late_days', align: TextAlign.center),
      _ColDef(key: 'AbsentDays', labelKey: 'col_absent_days', align: TextAlign.center),
      _ColDef(key: 'TotalLateMinutes', labelKey: 'col_total_late_minutes', align: TextAlign.center),
      _ColDef(key: 'TotalEarlyLeaveMinutes', labelKey: 'col_total_early_leave_minutes', align: TextAlign.center),
      _ColDef(key: 'TotalWorkHours', labelKey: 'col_total_work_hours', align: TextAlign.center),
      _ColDef(key: 'TotalOvertimeHours', labelKey: 'col_total_overtime_hours', align: TextAlign.center),
      _ColDef(key: 'AttendanceRate', labelKey: 'col_attendance_rate', align: TextAlign.center),
      _ColDef(key: 'BasicSalary', labelKey: 'col_basic_salary', align: TextAlign.center),
      _ColDef(key: 'TotalSalary', labelKey: 'col_total_salary', align: TextAlign.center),
      _ColDef(key: 'DailyRate', labelKey: 'col_daily_rate', align: TextAlign.center),
      _ColDef(key: 'HourlyRate', labelKey: 'col_hourly_rate', align: TextAlign.center),
      _ColDef(key: 'MinuteRate', labelKey: 'col_minute_rate', align: TextAlign.center),
      _ColDef(key: 'OverallStatus', labelKey: 'col_overall_status'),
      _ColDef(key: 'TotalPenalties', labelKey: 'col_total_penalties', align: TextAlign.center),
      _ColDef(key: 'TotalSalaryPenalty', labelKey: 'col_total_salary_penalty', align: TextAlign.center),
      _ColDef(key: 'TotalDaysPenalty', labelKey: 'col_total_days_penalty', align: TextAlign.center),
      _ColDef(key: 'TotalWarnings', labelKey: 'col_total_warnings', align: TextAlign.center),
      _ColDef(key: 'PenaltyDetails', labelKey: 'col_penalty_details'),
    ];
    _visibleCols = {for (final c in _allCols) c.key: true};
    _loadDepartments();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(DateTime.now().year - 5, 1, 1),
      lastDate: DateTime(DateTime.now().year + 1, 12, 31),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate.isBefore(_fromDate)) {
          _toDate = _fromDate;
        }
      } else {
        _toDate = picked;
        if (_toDate.isBefore(_fromDate)) {
          _fromDate = _toDate;
        }
      }
    });
  }

  String _formatDate(DateTime d) {
    return '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadDepartments() async {
    final resp = await ApiService.getAttendanceProcessingDepartments(
      widget.clientId,
    );
    if (!mounted) return;
    final ok = resp['Success'] == true;
    final data = ok ? (resp['Data'] as List?) : null;
    setState(() {
      _departments = data is List
          ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
    });
  }

  Future<void> _process() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
      _rows = <Map<String, dynamic>>[];
    });
    try {
      final resp = await ApiService.previewAttendanceProcessing(
        widget.clientId,
        fromDate: _fromDate,
        toDate: _toDate,
        departmentId: _selectedDepartment?['DepartmentId'] as int?,
        calculationMethod: _calculationMethod,
      );
      if (!mounted) return;
      final ok = resp['Success'] == true;
      final data = ok ? (resp['Data'] as List?) : null;
      setState(() {
        _rows = data is List
            ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        _errorMessage = ok
            ? null
            : (resp['Message']?.toString().trim().isNotEmpty == true
                ? resp['Message'].toString()
                : _t(context, 'unexpected_error'));
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = _t(context, 'unexpected_error');
      });
    }
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

  String _v(Map<String, dynamic> row, String key) =>
      (row[key] ?? '').toString();

  List<_ColDef> get _visibleColumns =>
      _allCols.where((c) => _visibleCols[c.key] == true).toList();

  Future<void> _openColumnsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ScaleDownText(
                            _t(ctx, 'control_columns'),
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
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _allCols.map((c) {
                            final selected = _visibleCols[c.key] == true;
                            return FilterChip(
                              selected: selected,
                              label: ScaleDownText(_t(ctx, c.labelKey)),
                              showCheckmark: false,
                              selectedColor: scheme.secondaryContainer,
                              onSelected: (v) {
                                setState(() {
                                  _visibleCols[c.key] = v;
                                  if (_visibleCols.values.where((x) => x == true).isEmpty) {
                                    _visibleCols[c.key] = true;
                                  }
                                });
                                setModalState(() {});
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) return;
    final cols = _visibleColumns;
    final headers = cols.map((c) => _t(context, c.labelKey)).toList();
    final rows = _rows
        .map((r) => cols.map((c) => _v(r, c.key)).toList(growable: false))
        .toList(growable: false);

    await ReportExportService.exportExcelCsv(
      fileBaseName: 'AttendanceProcessing_${DateTime.now().millisecondsSinceEpoch}',
      headers: headers,
      rows: rows,
    );
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
    final cols = _visibleColumns;
    final headers = cols.map((c) => _t(context, c.labelKey)).toList();
    final rows = _rows
        .map((r) => cols.map((c) => _v(r, c.key)).toList(growable: false))
        .toList(growable: false);

    await ReportExportService.exportPdfTable(
      context: context,
      fileBaseName: 'AttendanceProcessing_${DateTime.now().millisecondsSinceEpoch}',
      title: _t(context, 'attendance_processing_title'),
      subtitle: '${_formatDate(_fromDate)} → ${_formatDate(_toDate)}',
      headers: headers,
      rows: rows,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final filtersCard = CustomCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 22,
      border: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45), width: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _FilterField(
                  label: _t(context, 'from_date'),
                  value: _formatDate(_fromDate),
                  icon: Icons.calendar_month_rounded,
                  onTap: () => _pickDate(isFrom: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FilterField(
                  label: _t(context, 'to_date'),
                  value: _formatDate(_toDate),
                  icon: Icons.calendar_month_rounded,
                  onTap: () => _pickDate(isFrom: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<Map<String, dynamic>>(
            isExpanded: true,
            key: ValueKey(_selectedDepartment),
            initialValue: _selectedDepartment,
            items: [
              DropdownMenuItem<Map<String, dynamic>>(
                value: null,
                child: ScaleDownText(_t(context, 'all_departments')),
              ),
              ..._departments.map(
                (d) => DropdownMenuItem<Map<String, dynamic>>(
                  value: d,
                  child: ScaleDownText((d['DepartmentName'] ?? '').toString()),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _selectedDepartment = v),
            decoration: InputDecoration(
              labelText: _t(context, 'department'),
              prefixIcon: const Icon(Icons.apartment_rounded),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            key: ValueKey(_calculationMethod),
            initialValue: _calculationMethod,
            items: [
              DropdownMenuItem(
                value: 'ByPeriod',
                child: ScaleDownText(_t(context, 'calc_by_period')),
              ),
              DropdownMenuItem(
                value: 'ByTransaction',
                child: ScaleDownText(_t(context, 'calc_by_transaction')),
              ),
            ],
            onChanged: (v) =>
                setState(() => _calculationMethod = (v ?? 'ByPeriod')),
            decoration: InputDecoration(
              labelText: _t(context, 'calculation_method'),
              prefixIcon: const Icon(Icons.calculate_rounded),
              filled: true,
              fillColor: scheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                onPressed: _rows.isEmpty ? null : _exportPdf,
                child: Text(_t(context, 'pdf')),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                onPressed: _rows.isEmpty ? null : _exportExcel,
                child: Text(_t(context, 'excel')),
              ),
              const SizedBox(width: 10),
              IconButton(
                onPressed: _openColumnsSheet,
                tooltip: '',
                icon: const Icon(Icons.view_column_rounded),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _loading ? null : _process,
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_fix_high_rounded),
                  label: Text(_t(context, 'process_data')),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final header = Padding(
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
              '${_t(context, 'total')}: ${_rows.length}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      ),
    );

    Widget body;
    if (_rows.isEmpty) {
      body = ListView(
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
                  _errorMessage?.trim().isNotEmpty == true
                      ? _errorMessage!
                      : _t(context, 'report_empty'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      final visibleCols = _visibleColumns;
      final columns = visibleCols.map((c) => _col(context, c.labelKey)).toList();

      final rows = _rows.map((r) {
        return DataRow(
          cells: visibleCols
              .map(
                (c) => _cell(
                  context,
                  _v(r, c.key),
                  align: c.align,
                ),
              )
              .toList(),
        );
      }).toList();

      body = SingleChildScrollView(
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
            columns: columns,
            rows: rows,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'attendance_processing_title')),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: filtersCard,
          ),
          header,
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  const _FilterField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  ScaleDownText(
                    value,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
