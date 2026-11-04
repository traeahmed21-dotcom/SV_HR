import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import '../widgets/scale_down_text.dart';
import 'attendance_report_results_screen.dart';

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
        _recalcSummary();
        _errorMessage = ok
            ? null
            : (resp['Message']?.toString().trim().isNotEmpty == true
                ? resp['Message'].toString()
                : _t(context, 'unexpected_error'));
        _loading = false;
      });
      if (ok) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AttendanceReportResultsScreen(
                fromDate: _fromDate,
                toDate: _toDate,
                rows: _rows,
                sumWorkHours: _sumWorkHours,
                sumAbsent: _sumAbsent,
                sumLate: _sumLate,
                sumPresent: _sumPresent,
                sumRestDays: _sumRestDays,
              ),
            ),
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = _t(context, 'unexpected_error');
      });
    }
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
                  SizedBox(
                    width: double.infinity,
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
            ),
          ),
          Expanded(
            child: ListView(
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
                            : 'قم بتحديد الفلاتر ثم اضغط "${_t(context, 'generate_report')}" وسيتم عرض النتائج في صفحة مستقلة.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
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
