import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/report_export_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import '../widgets/scale_down_text.dart';

class AttendanceReportsScreen extends StatefulWidget {
  final int clientId;

  const AttendanceReportsScreen({
    super.key,
    required this.clientId,
  });

  @override
  State<AttendanceReportsScreen> createState() => _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState extends State<AttendanceReportsScreen> {
  DateTime _fromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _toDate = DateTime(DateTime.now().year, DateTime.now().month + 1, 0);

  bool _loading = false;
  String? _errorMessage;

  List<Map<String, dynamic>> _shifts = [];
  Map<String, dynamic>? _selectedShift;

  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _selectedBranch;

  final _employeeSearchController = TextEditingController();
  Map<String, dynamic>? _selectedEmployee;

  String _status = 'All';
  String _calculationMethod = 'ByPeriod';

  List<Map<String, dynamic>> _rows = [];
  int _total = 0;
  double _sumWorkHours = 0;
  int _sumAbsent = 0;
  int _sumLate = 0;
  int _sumPresent = 0;
  int _sumRestDays = 0;

  String _t(BuildContext context, String key) {
    final lang = context.read<LanguageService>().currentLocale.languageCode;
    return Translations.getText(key, lang);
  }

  @override
  void initState() {
    super.initState();
    _loadShifts();
    _loadBranches();
  }

  @override
  void dispose() {
    _employeeSearchController.dispose();
    super.dispose();
  }

  String _formatDate(DateTime d) => DateFormat('yyyy/MM/dd').format(d);

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

  Future<void> _loadShifts() async {
    final resp = await ApiService.getAttendanceReportShifts(widget.clientId);
    if (!mounted) return;
    final ok = resp['Success'] == true;
    final data = ok ? (resp['Data'] as List?) : null;
    setState(() {
      _shifts = data is List
          ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
    });
  }

  Future<void> _loadBranches() async {
    final resp = await ApiService.getAttendanceReportBranches(widget.clientId);
    if (!mounted) return;
    final ok = resp['Success'] == true;
    final data = ok ? (resp['Data'] as List?) : null;
    setState(() {
      _branches = data is List
          ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
    });
  }

  Future<void> _selectEmployee() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _EmployeePickerSheet(
        clientId: widget.clientId,
        branchId: _selectedBranch?['BranchId'] is int ? _selectedBranch!['BranchId'] as int : null,
        title: _t(ctx, 'employee'),
        initialQuery: _employeeSearchController.text,
      ),
    );
    if (picked == null) return;
    setState(() {
      _selectedEmployee = picked;
      _employeeSearchController.text =
          (picked['EmployeeName'] ?? picked['EmployeeNumber'] ?? '').toString();
    });
  }

  Future<void> _generate() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final resp = await ApiService.generateAttendanceReport(
        widget.clientId,
        fromDate: _fromDate,
        toDate: _toDate,
        employeeId: _selectedEmployee?['EmployeeId'] is int ? _selectedEmployee!['EmployeeId'] as int : null,
        branchId: _selectedBranch?['BranchId'] is int ? _selectedBranch!['BranchId'] as int : null,
        shiftId: _selectedShift?['ShiftId'] is int ? _selectedShift!['ShiftId'] as int : null,
        status: _status,
        calculationMethod: _calculationMethod,
      );
      if (!mounted) return;
      final ok = resp['Success'] == true;
      final data = ok ? (resp['Data'] as List?) : null;
      setState(() {
        _rows = data is List
            ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : <Map<String, dynamic>>[];
        _total = _rows.length;
        _recalcSummary();
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

  Color _statusBg(ColorScheme scheme, String status) {
    final b = Theme.of(context).brightness;
    final main = _statusMainColor(status);
    return _tint(scheme, main, b);
  }

  Color _statusFg(ColorScheme scheme, String status) {
    final b = Theme.of(context).brightness;
    final main = _statusMainColor(status);
    return b == Brightness.dark ? main.withValues(alpha: 0.95) : main.withValues(alpha: 0.95);
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

  Widget _pill({
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

  DataColumn _col(String key) {
    return DataColumn(
      label: ScaleDownText(
        _t(context, key),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }

  DataCell _cell(String value, {TextAlign? align}) {
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

  DataCell _statusCell(String status) {
    final scheme = Theme.of(context).colorScheme;
    return DataCell(
      _pill(
        text: _statusText(context, status),
        bg: _statusBg(scheme, status),
        fg: _statusFg(scheme, status),
        icon: _statusIcon(status),
      ),
    );
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

  DataCell _dayNameCell(String dayName) {
    final scheme = Theme.of(context).colorScheme;
    return DataCell(
      _pill(
        text: dayName,
        bg: scheme.primaryContainer,
        fg: scheme.onPrimaryContainer,
        icon: Icons.calendar_today_rounded,
      ),
    );
  }

  DataCell _dayTypeCell({
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
        text: isWork ? _t(context, 'work_day') : _t(context, 'rest_day'),
        bg: _tint(scheme, main, b),
        fg: main,
        icon: isWork ? Icons.work_rounded : Icons.weekend_rounded,
      ),
    );
  }

  Color? _rowTint(String status) {
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

  void _showGpsDetails(Map<String, dynamic> row) {
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

  DataCell _gpsCell(Map<String, dynamic> row) {
    final hasGps = row['HasGps'] == true;
    if (!hasGps) {
      return _cell('-', align: TextAlign.center);
    }
    return DataCell(
      TextButton(
        onPressed: () => _showGpsDetails(row),
        child: Text(_t(context, 'view')),
      ),
    );
  }

  void _recalcSummary() {
    double workHours = 0;
    int absent = 0;
    int late = 0;
    int present = 0;
    int rest = 0;

    for (final r in _rows) {
      final wh = r['TotalWorkHours'];
      if (wh is num) {
        workHours += wh.toDouble();
      } else {
        final parsed = double.tryParse((wh ?? '').toString());
        if (parsed != null) workHours += parsed;
      }

      final s = (r['AttendanceStatus'] ?? '').toString().toLowerCase();
      if (s == 'absent') absent += 1;
      if (s == 'late') late += 1;
      if (s == 'present') present += 1;
      if (s == 'restday' || s == 'officialholiday') rest += 1;
    }

    _sumWorkHours = workHours;
    _sumAbsent = absent;
    _sumLate = late;
    _sumPresent = present;
    _sumRestDays = rest;
  }

  Future<void> _exportExcel() async {
    if (_rows.isEmpty) return;
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

    final rows = _rows.map((row) {
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
      rows: rows,
    );
  }

  Future<void> _exportPdf() async {
    if (_rows.isEmpty) return;
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

    final rows = _rows.map((row) {
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
      subtitle: '${_formatDate(_fromDate)} → ${_formatDate(_toDate)}',
      headers: headers,
      rows: rows,
    );
  }

  Widget _summaryTile({
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
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Map<String, dynamic>>(
                          key: ValueKey(_selectedBranch),
                          isExpanded: true,
                          initialValue: _selectedBranch,
                          items: [
                            DropdownMenuItem<Map<String, dynamic>>(
                              value: null,
                              child: ScaleDownText(_t(context, 'all_branches')),
                            ),
                            ..._branches.map(
                              (b) => DropdownMenuItem<Map<String, dynamic>>(
                                value: b,
                                child: ScaleDownText((b['BranchName'] ?? '').toString()),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selectedBranch = v;
                              _selectedEmployee = null;
                              _employeeSearchController.clear();
                            });
                          },
                          decoration: InputDecoration(
                            labelText: _t(context, 'branch'),
                            prefixIcon: const Icon(Icons.apartment_rounded),
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<Map<String, dynamic>>(
                          key: ValueKey(_selectedShift),
                          isExpanded: true,
                          initialValue: _selectedShift,
                          items: [
                            DropdownMenuItem<Map<String, dynamic>>(
                              value: null,
                              child: ScaleDownText(_t(context, 'all_shifts')),
                            ),
                            ..._shifts.map(
                              (s) => DropdownMenuItem<Map<String, dynamic>>(
                                value: s,
                                child: ScaleDownText((s['ShiftName'] ?? '').toString()),
                              ),
                            ),
                          ],
                          onChanged: (v) => setState(() => _selectedShift = v),
                          decoration: InputDecoration(
                            labelText: _t(context, 'shift'),
                            prefixIcon: const Icon(Icons.schedule_rounded),
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _employeeSearchController,
                    readOnly: true,
                    onTap: _selectEmployee,
                    decoration: InputDecoration(
                      labelText: _t(context, 'employee'),
                      prefixIcon: const Icon(Icons.person_outline_rounded),
                      suffixIcon: _selectedEmployee == null
                          ? null
                          : IconButton(
                              tooltip: '',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                setState(() {
                                  _selectedEmployee = null;
                                  _employeeSearchController.clear();
                                });
                              },
                            ),
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
                    key: ValueKey(_status),
                    isExpanded: true,
                    initialValue: _status,
                    items: [
                      DropdownMenuItem(value: 'All', child: ScaleDownText(_t(context, 'all_statuses'))),
                      DropdownMenuItem(value: 'Present', child: ScaleDownText(_t(context, 'attendance_status_present'))),
                      DropdownMenuItem(value: 'Late', child: ScaleDownText(_t(context, 'attendance_status_late'))),
                      DropdownMenuItem(value: 'Absent', child: ScaleDownText(_t(context, 'attendance_status_absent'))),
                      DropdownMenuItem(value: 'EntryOnly', child: ScaleDownText(_t(context, 'attendance_status_entry_only'))),
                      DropdownMenuItem(value: 'EarlyLeave', child: ScaleDownText(_t(context, 'attendance_status_early_leave'))),
                      DropdownMenuItem(value: 'Incomplete', child: ScaleDownText(_t(context, 'attendance_status_incomplete'))),
                      DropdownMenuItem(value: 'Overtime', child: ScaleDownText(_t(context, 'attendance_status_overtime'))),
                      DropdownMenuItem(value: 'Exception', child: ScaleDownText(_t(context, 'attendance_status_exception'))),
                      DropdownMenuItem(value: 'RestDay', child: ScaleDownText(_t(context, 'attendance_status_rest_day'))),
                      DropdownMenuItem(value: 'OfficialHoliday', child: ScaleDownText(_t(context, 'attendance_status_official_holiday'))),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'All'),
                    decoration: InputDecoration(
                      labelText: _t(context, 'status'),
                      prefixIcon: const Icon(Icons.tune_rounded),
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
                    key: ValueKey(_calculationMethod),
                    isExpanded: true,
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
                    onChanged: (v) => setState(() => _calculationMethod = v ?? 'ByPeriod'),
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
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _generate,
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.playlist_add_check_rounded),
                          label: Text(_t(context, 'generate_report')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _summaryTile(
                      label: _t(context, 'summary_total_work_hours'),
                      value: _sumWorkHours.toStringAsFixed(2),
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      label: _t(context, 'summary_rest_days'),
                      value: _sumRestDays.toString(),
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      label: _t(context, 'summary_absent_days'),
                      value: _sumAbsent.toString(),
                      color: scheme.error,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      label: _t(context, 'summary_late_days'),
                      value: _sumLate.toString(),
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: 10),
                    _summaryTile(
                      label: _t(context, 'summary_present_days'),
                      value: _sumPresent.toString(),
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
                    '${_t(context, 'total')}: $_total',
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
            child: _rows.isEmpty
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
                              _errorMessage?.isNotEmpty == true
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
                        columns: [
                          _col('col_date'),
                          _col('col_day'),
                          _col('col_day_type'),
                          _col('col_employee_name'),
                          _col('col_shift'),
                          _col('col_in_1'),
                          _col('col_out_1'),
                          _col('col_in_2'),
                          _col('col_out_2'),
                          _col('col_work_hours'),
                          _col('col_overtime'),
                          _col('col_status'),
                          _col('col_late_minutes'),
                          _col('col_early_leave_minutes'),
                          _col('col_notes'),
                          _col('col_gps'),
                        ],
                        rows: _rows.map((row) {
                          final status = (row['AttendanceStatus'] ?? '').toString();
                          final dayWorkStatus = (row['DayWorkStatus'] ?? '').toString();
                          return DataRow(
                            color: WidgetStatePropertyAll(_rowTint(status)),
                            cells: [
                              _cell((row['AttendanceDate'] ?? '').toString()),
                              _dayNameCell((row['DayName'] ?? '').toString()),
                              _dayTypeCell(
                                dayWorkStatus: dayWorkStatus,
                                attendanceStatus: status,
                              ),
                              _cell((row['EmployeeName'] ?? '').toString()),
                              _cell((row['ShiftName'] ?? '').toString()),
                              _cell((row['Shift1FirstPunchIn'] ?? '').toString(), align: TextAlign.center),
                              _cell((row['Shift1LastPunchOut'] ?? '').toString(), align: TextAlign.center),
                              _cell((row['Shift2FirstPunchIn'] ?? '').toString(), align: TextAlign.center),
                              _cell((row['Shift2LastPunchOut'] ?? '').toString(), align: TextAlign.center),
                              _cell((row['TotalWorkHours'] ?? '').toString(), align: TextAlign.center),
                              _cell((row['OvertimeHours'] ?? '').toString(), align: TextAlign.center),
                              _statusCell(status),
                              _cell((row['LateMinutes'] ?? '').toString(), align: TextAlign.center),
                              _cell((row['EarlyLeaveMinutes'] ?? '').toString(), align: TextAlign.center),
                              _cell((row['ExceptionNotes'] ?? '').toString()),
                              _gpsCell(row),
                            ],
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

class _EmployeePickerSheet extends StatefulWidget {
  final int clientId;
  final int? branchId;
  final String title;
  final String initialQuery;

  const _EmployeePickerSheet({
    required this.clientId,
    required this.branchId,
    required this.title,
    required this.initialQuery,
  });

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  final _controller = TextEditingController();
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  String? _error;

  String _t(BuildContext context, String key) {
    final lang = context.read<LanguageService>().currentLocale.languageCode;
    return Translations.getText(key, lang);
  }

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final resp = await ApiService.searchAttendanceReportEmployees(
      widget.clientId,
      query: _controller.text.trim(),
      branchId: widget.branchId,
      page: 1,
      pageSize: 50,
    );
    if (!mounted) return;
    final ok = resp['Success'] == true;
    final data = ok ? (resp['Data'] as List?) : null;
    setState(() {
      _items = data is List
          ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];
      _error = ok ? null : (resp['Message']?.toString());
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                    tooltip: '',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: InputDecoration(
                  hintText: _t(context, 'search'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _controller.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: '',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _controller.clear();
                            setState(() {});
                            _load();
                          },
                        ),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _items.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: ScaleDownText(
                              _error?.trim().isNotEmpty == true
                                  ? _error!
                                  : _t(context, 'no_results'),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _items.length,
                          separatorBuilder: (ctx, i) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            final item = _items[i];
                            final name = (item['EmployeeName'] ?? '').toString();
                            final number = (item['EmployeeNumber'] ?? '').toString();
                            return CustomCard(
                              padding: const EdgeInsets.all(14),
                              borderRadius: 18,
                              border: BorderSide(
                                color: scheme.outlineVariant.withValues(alpha: 0.45),
                                width: 1,
                              ),
                              child: InkWell(
                                onTap: () => Navigator.pop(context, item),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: scheme.secondaryContainer,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.person_rounded,
                                        color: scheme.onSecondaryContainer,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ScaleDownText(
                                            name.isEmpty ? number : name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(fontWeight: FontWeight.w900),
                                          ),
                                          const SizedBox(height: 2),
                                          ScaleDownText(
                                            number,
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                  color: scheme.onSurfaceVariant,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
