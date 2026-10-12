import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import 'package:intl/intl.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String employeeNumber;
  final int clientId;
  final String? employeeName;

  const AttendanceHistoryScreen({
    super.key,
    required this.employeeNumber,
    required this.clientId,
    this.employeeName,
  });

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  // متغيرات الحالة
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _attendanceRecords = [];

  // متغيرات التصفية
  DateTime _selectedDate = DateTime.now();
  String _selectedFilter = 'all'; // all, checkin, checkout

  // دالة تسجيل الأحداث للتطوير
  void _log(String message) {
    if (kDebugMode) {
      print('🔄 [AttendanceHistoryScreen] $message');
    }
  }

  @override
  void initState() {
    super.initState();
    _log('🚀 تهيئة صفحة سجل الحضور...');
    _log('👤 EmployeeNumber: ${widget.employeeNumber}');
    _log('🏢 ClientID: ${widget.clientId}');
    _log('👤 EmployeeName: ${widget.employeeName}');
    _log('📅 التاريخ المحدد: $_selectedDate');
    _loadAttendanceHistory();
  }

  Future<void> _loadAttendanceHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _log('🔄 جاري تحميل سجل الحضور...');
      _log('👤 EmployeeNumber: ${widget.employeeNumber}');
      _log('🏢 ClientID: ${widget.clientId}');
      _log('📅 التاريخ: ${_selectedDate.toIso8601String().split('T')[0]}');
      _log('📅 التاريخ الكامل: $_selectedDate');

      final response = await ApiService.getEmployeeAttendance(
        widget.clientId,
        widget.employeeNumber,
        _selectedDate,
      );

      _log('📡 استجابة API: $response');
      _log('📡 نوع الاستجابة: ${response.runtimeType}');
      _log('📡 هل تحتوي على Success: ${response.containsKey('Success')}');
      _log('📡 قيمة Success: ${response['Success']}');
      _log(
          '📡 هل تحتوي على Attendances: ${response.containsKey('Attendances')}');
      _log('📡 نوع Attendances: ${response['Attendances']?.runtimeType}');
      _log('📡 محتوى Attendances: ${response['Attendances']}');

      if (response['Success'] == true) {
        final List<dynamic> data = response['Attendances'] ?? [];
        _log('📊 عدد السجلات في Attendances: ${data.length}');
        _log('📊 نوع Attendances بعد التحويل: ${data.runtimeType}');

        final records = data.cast<Map<String, dynamic>>();
        _log('📊 عدد السجلات بعد التحويل: ${records.length}');

        if (records.isNotEmpty) {
          _log('📊 أول سجل: ${records.first}');
        }

        setState(() {
          _attendanceRecords = records;
          _isLoading = false;
        });

        _log('✅ تم تحميل سجل الحضور بنجاح: ${records.length} سجل');
        _log('✅ _attendanceRecords.length: ${_attendanceRecords.length}');
        _log('✅ _filteredRecords.length: ${_filteredRecords.length}');
      } else {
        _log('❌ فشل في جلب سجل الحضور');
        _log('❌ رسالة الخطأ: ${response['Message']}');
        final languageService = Provider.of<LanguageService>(context, listen: false);
        final lang = languageService.currentLocale.languageCode;
        throw Exception(response['Message'] ?? Translations.getText('error_fetching_attendance', lang));
      }
    } catch (e) {
      _log('❌ خطأ في تحميل سجل الحضور: $e');
      _log('❌ نوع الخطأ: ${e.runtimeType}');
      _log('❌ تفاصيل الخطأ: ${e.toString()}');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDate() async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      locale: languageService.currentLocale,
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _loadAttendanceHistory();
    }
  }

  List<Map<String, dynamic>> get _filteredRecords {
    if (_selectedFilter == 'all') {
      return _attendanceRecords;
    } else if (_selectedFilter == 'checkin') {
      return _attendanceRecords
          .where((record) => record['PunchState'] == '0')
          .toList();
    } else if (_selectedFilter == 'checkout') {
      return _attendanceRecords
          .where((record) => record['PunchState'] == '1')
          .toList();
    }
    return _attendanceRecords;
  }

  String _getPunchStateText(String punchState, String lang) {
    switch (punchState) {
      case '0':
        return Translations.getText('check_in', lang);
      case '1':
        return Translations.getText('check_out', lang);
      default:
        return Translations.getText('unknown', lang);
    }
  }

  Color _getPunchStateColor(String punchState) {
    switch (punchState) {
      case '0':
        return Colors.green;
      case '1':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getPunchStateIcon(String punchState) {
    switch (punchState) {
      case '0':
        return Icons.login;
      case '1':
        return Icons.logout;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('HH:mm:ss').format(dateTime);
    } catch (e) {
      return '--:--:--';
    }
  }

  String _formatDate(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('yyyy/MM/dd').format(dateTime);
    } catch (e) {
      return '----/--/--';
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('attendance_history', lang)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAttendanceHistory,
            tooltip: Translations.getText('refresh', lang),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    Translations.getText('loading', lang),
                    style: const TextStyle(fontFamily: 'Tajawal'),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorWidget(lang)
              : _buildContent(lang),
    );
  }

  Widget _buildErrorWidget(String lang) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              Translations.getText('error_loading_data', lang),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: scheme.error,
                fontFamily: 'Tajawal',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
                fontFamily: 'Tajawal',
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadAttendanceHistory,
              icon: const Icon(Icons.refresh),
              label: Text(Translations.getText('retry', lang)),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(String lang) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // شريط التصفية والتاريخ
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.06),
                spreadRadius: 1,
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              // اختيار التاريخ
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectDate,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: scheme.outlineVariant),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: scheme.onSurfaceVariant,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('yyyy/MM/dd').format(_selectedDate),
                              style: TextStyle(
                                fontSize: 16,
                                color: scheme.onSurface,
                                fontFamily: 'Tajawal',
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_drop_down,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // أزرار التصفية
              Row(
                children: [
                  Expanded(
                    child: _buildFilterButton('all',
                        Translations.getText('all', lang), Icons.list, lang),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterButton(
                        'checkin',
                        Translations.getText('check_in', lang),
                        Icons.login,
                        lang),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildFilterButton(
                        'checkout',
                        Translations.getText('check_out', lang),
                        Icons.logout,
                        lang),
                  ),
                ],
              ),
            ],
          ),
        ),

        // إحصائيات سريعة
        if (_filteredRecords.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.22),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.analytics,
                  color: scheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.getText('today_statistics', lang),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${Translations.getText('total_records', lang)}: ${_filteredRecords.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // قائمة السجلات
        Expanded(
          child: _filteredRecords.isEmpty
              ? _buildEmptyState(lang)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredRecords.length,
                  itemBuilder: (context, index) {
                    final record = _filteredRecords[index];
                    return _buildAttendanceCard(record, index, lang);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterButton(
      String filter, String label, IconData icon, String lang) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _selectedFilter == filter;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = filter;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontFamily: 'Tajawal',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(String lang) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              Translations.getText('no_records', lang),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant,
                fontFamily: 'Tajawal',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Translations.getText('no_attendance_records', lang),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade500,
                fontFamily: 'Tajawal',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(
      Map<String, dynamic> record, int index, String lang) {
    final punchState = record['PunchState'] ?? '';
    final punchTime = record['PunchTime'] ?? '';
    final gpsLocation = record['GpsLocation'] ?? '';
    final mobile = record['Mobile'] ?? '';
    final workCode = record['WorkCode'] ?? '';
    final employeeName = record['EmployeeName'] ?? '';
    final terminalSn = record['TerminalSn'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // رأس البطاقة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _getPunchStateColor(punchState).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getPunchStateColor(punchState),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getPunchStateIcon(punchState),
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getPunchStateText(punchState, lang),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _getPunchStateColor(punchState),
                          fontFamily: 'Tajawal',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatDateTime(punchTime),
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          fontFamily: 'Tajawal',
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getPunchStateColor(punchState),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '#${index + 1}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // تفاصيل البطاقة
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (gpsLocation.isNotEmpty)
                  _buildDetailRow(Translations.getText('location', lang),
                      gpsLocation, Icons.location_on, lang),
                if (mobile.isNotEmpty)
                  _buildDetailRow(Translations.getText('device', lang), mobile,
                      Icons.phone_android, lang),
                if (workCode.isNotEmpty)
                  _buildDetailRow(Translations.getText('work_code', lang),
                      workCode, Icons.work, lang),
                if (terminalSn.isNotEmpty)
                  _buildDetailRow(Translations.getText('terminal', lang),
                      terminalSn, Icons.devices, lang),
                _buildDetailRow(Translations.getText('date', lang),
                    _formatDate(punchTime), Icons.calendar_today, lang),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
      String label, String value, IconData icon, String lang) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          Text(
            '$label:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade700,
              fontFamily: 'Tajawal',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                fontFamily: 'Tajawal',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
