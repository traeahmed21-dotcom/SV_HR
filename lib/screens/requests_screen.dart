import 'package:flutter/material.dart';
import '../models/request.dart' as request_models;
import '../models/api_models.dart' as api_models;
import 'package:provider/provider.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../services/api_service.dart';
import 'create_request_screen.dart';

class RequestsScreen extends StatefulWidget {
  final String employeeId;
  final api_models.EmployeeData employeeData;

  const RequestsScreen({
    super.key,
    required this.employeeId,
    required this.employeeData,
  });

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<request_models.EmployeeRequest> _requests = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  static const String _allRequestTypeValue = '__all__';
  List<api_models.RequestType> _availableRequestTypes = [];
  List<String> _requestTypeOptions = [_allRequestTypeValue];
  String _selectedRequestTypeValue = _allRequestTypeValue;
  bool _isLoadingRequestTypes = false;
  _RequestSort _sort = _RequestSort.newestFirst;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRequestTypes();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      // جلب الطلبات من API
      final requests = await _fetchRequestsFromAPI();
      setState(() {
        _requests = requests;
        _syncRequestTypeOptions();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadRequestTypes() async {
    setState(() {
      _isLoadingRequestTypes = true;
    });

    try {
      final types =
          await ApiService.getRequestTypes(widget.employeeData.clientID);

      if (!mounted) {
        return;
      }

      setState(() {
        _availableRequestTypes = types;
        _syncRequestTypeOptions();
        _isLoadingRequestTypes = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _availableRequestTypes = [];
        _syncRequestTypeOptions();
        _isLoadingRequestTypes = false;
      });
    }
  }

  void _syncRequestTypeOptions() {
    final unique = <String>{_allRequestTypeValue};

    for (final t in _availableRequestTypes) {
      final text = t.text.trim();
      if (text.isNotEmpty) {
        unique.add(text);
      }
    }

    for (final r in _requests) {
      final title = r.title.trim();
      if (title.isNotEmpty) {
        unique.add(title);
      }
    }

    final options = unique.toList();
    options.remove(_allRequestTypeValue);
    options.sort((a, b) => a.compareTo(b));
    options.insert(0, _allRequestTypeValue);

    _requestTypeOptions = options;
    if (!_requestTypeOptions.contains(_selectedRequestTypeValue)) {
      _selectedRequestTypeValue = _allRequestTypeValue;
    }
  }

  Future<List<request_models.EmployeeRequest>> _fetchRequestsFromAPI() async {
    try {
      // استخدام API لجلب الطلبات
      final response = await ApiService.getRequests(
        widget.employeeData.clientID,
        employeeId: widget.employeeData.employeeID,
      );

      if (response['Success'] == true) {
        final List<dynamic> data = response['Data'] ?? [];
        return data.map((json) => _parseRequestFromAPI(json)).toList();
      } else {
        throw Exception(response['Message'] ?? 'فشل في جلب الطلبات');
      }
    } catch (e) {
      // في حالة فشل API، نرجع قائمة فارغة
      debugPrint('فشل في جلب الطلبات من API: $e');
      return [];
    }
  }

  request_models.EmployeeRequest _parseRequestFromAPI(
      Map<String, dynamic> json) {
    // تحويل البيانات من API إلى نموذج EmployeeRequest
    return request_models.EmployeeRequest(
      id: json['ID']?.toString() ?? '',
      requestNumber: json['RequestNumber']?.toString() ?? '',
      employeeId: json['EmployeeID']?.toString() ?? '',
      employeeName: json['EmployeeName']?.toString() ?? '',
      type: _parseRequestType(json['RequestTypeName']),
      title: json['RequestTypeName'] ?? '',
      description: '', // سيتم جلبها من تفاصيل الطلب
      startDate: DateTime.tryParse(json['CreatedDate'] ?? '') ?? DateTime.now(),
      endDate: DateTime.tryParse(json['CreatedDate'] ?? '') ?? DateTime.now(),
      status: _parseRequestStatus(json['Status']),
      priority: json['Priority']?.toString() ?? 'Normal',
      createdAt: DateTime.tryParse(json['CreatedDate'] ?? '') ?? DateTime.now(),
      approvedBy: null,
      rejectionReason: null,
    );
  }

  request_models.RequestType _parseRequestType(String? typeName) {
    if (typeName?.contains('سلفة') == true) {
      return request_models.RequestType.loan;
    } else if (typeName?.contains('إجازة') == true) {
      return request_models.RequestType.leave;
    } else if (typeName?.contains('تأشيرة خروج وعودة') == true) {
      return request_models.RequestType.other;
    } else if (typeName?.contains('استئذان') == true) {
      return request_models.RequestType.other;
    }
    return request_models.RequestType.other;
  }

  request_models.RequestStatus _parseRequestStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
      case 'بانتظار الموافقة':
      case 'draft':
        return request_models.RequestStatus.pending;
      case 'approved':
      case 'معتمد':
        return request_models.RequestStatus.approved;
      case 'rejected':
      case 'مرفوض':
        return request_models.RequestStatus.rejected;
      case 'cancelled':
      case 'ملغي':
        return request_models.RequestStatus.cancelled;
      default:
        return request_models.RequestStatus.pending;
    }
  }

  List<request_models.EmployeeRequest> _getFilteredRequests(String lang) {
    final query = _searchController.text.trim().toLowerCase();
    final selectedType = _selectedRequestTypeValue.trim().toLowerCase();

    final filtered = _requests.where((r) {
      if (selectedType.isNotEmpty &&
          selectedType != _allRequestTypeValue.toLowerCase()) {
        if (r.title.trim().toLowerCase() != selectedType) {
          return false;
        }
      }

      if (query.isEmpty) {
        return true;
      }

      final statusText = _getStatusText(r.status, lang).toLowerCase();
      return r.requestNumber.toLowerCase().contains(query) ||
          r.employeeName.toLowerCase().contains(query) ||
          r.title.toLowerCase().contains(query) ||
          statusText.contains(query);
    }).toList();

    filtered.sort((a, b) {
      switch (_sort) {
        case _RequestSort.newestFirst:
          return b.createdAt.compareTo(a.createdAt);
        case _RequestSort.oldestFirst:
          return a.createdAt.compareTo(b.createdAt);
      }
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageService>().currentLocale.languageCode;
    final filteredRequests = _getFilteredRequests(lang);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.primary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: true,
        title: Text(
          Translations.getText('my_requests', lang),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: scheme.onPrimary,
              ),
        ),
        foregroundColor: scheme.onPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(132),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: _buildFilterBarContent(lang, scheme),
            ),
          ),
        ),
      ),
      body: _buildBody(filteredRequests),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CreateRequestScreen(
                employeeData: widget.employeeData,
              ),
            ),
          );

          if (result == true) {
            _loadRequests();
          }
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(Translations.getText('new_request', lang)),
      ),
    );
  }

  Widget _buildBody(List<request_models.EmployeeRequest> filteredRequests) {
    final lang = context.watch<LanguageService>().currentLocale.languageCode;
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              Translations.getText(
                'loading',
                Provider.of<LanguageService>(context).currentLocale.languageCode,
              ),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              Translations.getText('error_occurred', lang),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                Translations.getTextWithParams(
                  'error_fetching_requests_with_error',
                  lang,
                  {'error': _errorMessage},
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadRequests,
              icon: const Icon(Icons.refresh),
              label: Text(Translations.getText('retry', lang)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0EA5E9),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    if (_requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_outlined,
              size: 88,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.65),
            ),
            const SizedBox(height: 14),
            Text(
              Translations.getText('no_requests', lang),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                Translations.getText('tap_plus_to_create_request', lang),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: filteredRequests.length,
        itemBuilder: (context, index) {
          final request = filteredRequests[index];
          return _buildRequestCard(request, lang);
        },
      ),
    );
  }

  Widget _buildFilterBarContent(String lang, ColorScheme scheme) {
    return Column(
      children: [
        TextField(
          controller: _searchController,
          onChanged: (_) => setState(() {}),
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: Translations.getText('search_hint', lang),
            suffixIcon: _searchController.text.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                    },
                    icon: const Icon(Icons.close),
                  ),
            filled: true,
            fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return DropdownMenu<String>(
                    width: constraints.maxWidth,
                    initialSelection: _selectedRequestTypeValue,
                    onSelected: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _selectedRequestTypeValue = value);
                    },
                    label: Text(Translations.getText('request_type', lang)),
                    leadingIcon: const Icon(Icons.filter_list),
                    trailingIcon: _isLoadingRequestTypes
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    inputDecorationTheme: InputDecorationTheme(
                      filled: true,
                      fillColor:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: scheme.primary, width: 2),
                      ),
                    ),
                    dropdownMenuEntries: _requestTypeOptions.map((t) {
                      if (t == _allRequestTypeValue) {
                        return DropdownMenuEntry<String>(
                          value: _allRequestTypeValue,
                          label: Translations.getText('all', lang),
                        );
                      }
                      return DropdownMenuEntry<String>(
                        value: t,
                        label: t,
                      );
                    }).toList(),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return DropdownMenu<_RequestSort>(
                    width: constraints.maxWidth,
                    initialSelection: _sort,
                    onSelected: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _sort = value);
                    },
                    label: Text(Translations.getText('sort', lang)),
                    leadingIcon: const Icon(Icons.sort),
                    inputDecorationTheme: InputDecorationTheme(
                      filled: true,
                      fillColor:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: scheme.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: scheme.primary, width: 2),
                      ),
                    ),
                    dropdownMenuEntries: [
                      DropdownMenuEntry<_RequestSort>(
                        value: _RequestSort.newestFirst,
                        label: Translations.getText(
                          'sort_newest_first',
                          lang,
                        ),
                      ),
                      DropdownMenuEntry<_RequestSort>(
                        value: _RequestSort.oldestFirst,
                        label: Translations.getText(
                          'sort_oldest_first',
                          lang,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRequestCard(request_models.EmployeeRequest request, String lang) {
    Color statusColor;
    final statusText = _getStatusText(request.status, lang);
    IconData statusIcon;

    switch (request.status) {
      case request_models.RequestStatus.pending:
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.pending;
        break;
      case request_models.RequestStatus.approved:
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle;
        break;
      case request_models.RequestStatus.rejected:
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.cancel;
        break;
      case request_models.RequestStatus.cancelled:
        statusColor = Colors.grey;
        statusIcon = Icons.block;
        break;
    }

    // تحديد لون الأولوية
    Color priorityColor;
    String priorityText;
    switch (request.priority.toLowerCase()) {
      case 'high':
      case 'عالية':
        priorityColor = const Color(0xFFEF4444);
        priorityText = Translations.getText('priority_high', lang);
        break;
      case 'medium':
      case 'متوسطة':
        priorityColor = const Color(0xFFF59E0B);
        priorityText = Translations.getText('priority_medium', lang);
        break;
      case 'low':
      case 'منخفضة':
        priorityColor = const Color(0xFF10B981);
        priorityText = Translations.getText('priority_low', lang);
        break;
      default:
        priorityColor = const Color(0xFF6B7280);
        priorityText = Translations.getText('priority_normal', lang);
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _showRequestDetails(request),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // الصف الأول: رقم الطلب ونوع الطلب
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _getRequestTypeIcon(request.type),
                            size: 16,
                            color: const Color(0xFF0EA5E9),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            request.title,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF0EA5E9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            statusIcon,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // رقم الطلب
                Row(
                  children: [
                    Icon(
                      Icons.numbers,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${Translations.getText('request_number', lang)}: ${request.requestNumber}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // اسم الموظف
                Row(
                  children: [
                    Icon(
                      Icons.person,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request.employeeName,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // الصف الأخير: التاريخ والأولوية
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatDate(request.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        priorityText,
                        style: TextStyle(
                          fontSize: 10,
                          color: priorityColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getRequestTypeIcon(request_models.RequestType type) {
    switch (type) {
      case request_models.RequestType.loan:
        return Icons.account_balance;
      case request_models.RequestType.leave:
        return Icons.beach_access;
      case request_models.RequestType.overtime:
        return Icons.access_time;
      case request_models.RequestType.sick:
        return Icons.local_hospital;
      case request_models.RequestType.vacation:
        return Icons.flight;
      case request_models.RequestType.other:
        return Icons.assignment;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _showRequestDetails(request_models.EmployeeRequest request) async {
    // إظهار مؤشر التحميل أولاً
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    try {
      // جلب تفاصيل الطلب من API
      final details = await _fetchRequestDetails(request.id);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(); // إغلاق مؤشر التحميل

      // عرض تفاصيل الطلب
      _showRequestDetailsDialog(request, details);
    } catch (e) {
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(); // إغلاق مؤشر التحميل
      // عرض تفاصيل الطلب بدون معلومات إضافية
      _showRequestDetailsDialog(request, null);
    }
  }

  Future<Map<String, dynamic>?> _fetchRequestDetails(String requestId) async {
    try {
      final response = await ApiService.getRequestDetails(
        widget.employeeData.clientID,
        int.parse(requestId),
      );

      if (response['Success'] == true) {
        return response['Data'];
      }
      return null;
    } catch (e) {
      debugPrint('فشل في جلب تفاصيل الطلب: $e');
      return null;
    }
  }

  void _showRequestDetailsDialog(
      request_models.EmployeeRequest request, Map<String, dynamic>? details) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final lang = Provider.of<LanguageService>(context).currentLocale.languageCode;
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getRequestTypeIcon(request.type),
                  color: const Color(0xFF0EA5E9),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      request.requestNumber,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow(
                  '${Translations.getText('employee_name', lang)}:',
                  request.employeeName,
                ),
                _buildDetailRow(
                  '${Translations.getText('status', lang)}:',
                  _getStatusText(request.status, lang),
                ),
                _buildDetailRow(
                  '${Translations.getText('priority', lang)}:',
                  _getPriorityText(request.priority, lang),
                ),
                _buildDetailRow(
                  '${Translations.getText('created_date', lang)}:',
                  _formatDate(request.createdAt),
                ),
                if (details != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text(
                    Translations.getText('additional_details', lang),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // عرض التفاصيل الإضافية حسب نوع الطلب
                  if (details['AdditionalDetails'] != null) ...[
                    _buildAdditionalDetails(details['AdditionalDetails'], lang),
                  ],

                  // عرض الموافقات إذا وجدت
                  if (details['Approvals'] != null &&
                      details['Approvals'].isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      Translations.getText('approval_flow', lang),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildApprovalsList(details['Approvals']),
                  ],
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                Translations.getText('close', lang),
                style: TextStyle(
                  color: Color(0xFF0EA5E9),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalDetails(Map<String, dynamic> details, String lang) {
    List<Widget> widgets = [];

    details.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        String label = _getDetailLabel(key, lang);
        String displayValue = _formatDetailValue(key, value, lang);
        widgets.add(_buildDetailRow(label, displayValue));
      }
    });

    return Column(children: widgets);
  }

  String _getDetailLabel(String key, String lang) {
    switch (key) {
      case 'LoanType':
        return '${Translations.getText('loan_type_label', lang)}:';
      case 'LoanAmount':
        return '${Translations.getText('loan_amount_label', lang)}:';
      case 'MonthlyInstallment':
        return '${Translations.getText('monthly_installment_label', lang)}:';
      case 'NumberOfInstallments':
        return '${Translations.getText('installments_count_label', lang)}:';
      case 'LoanStartDate':
        return '${Translations.getText('loan_start_date', lang)}:';
      case 'LoanEndDate':
        return '${Translations.getText('loan_end_date', lang)}:';
      case 'LoanDescription':
        return '${Translations.getText('description', lang)}:';
      case 'LeaveTypeName':
        return '${Translations.getText('leave_type', lang)}:';
      case 'LeaveStartDate':
        return '${Translations.getText('start_date', lang)}:';
      case 'LeaveEndDate':
        return '${Translations.getText('end_date', lang)}:';
      case 'LeaveDays':
        return '${Translations.getText('number_of_days', lang)}:';
      case 'LeaveReason':
        return '${Translations.getText('leave_reason', lang)}:';
      case 'ExitReturnFromDate':
        return 'من تاريخ:';
      case 'ExitReturnToDate':
        return 'إلى تاريخ:';
      case 'ExitReturnReason':
        return 'سبب الطلب:';
      case 'ExitReturnNotes':
        return 'الملاحظات:';
      case 'PermissionDate':
        return 'التاريخ:';
      case 'PermissionFromTime':
        return 'من وقت:';
      case 'PermissionToTime':
        return 'إلى وقت:';
      case 'PermissionReason':
        return 'سبب الطلب:';
      case 'PermissionNotes':
        return 'الملاحظات:';
      default:
        return '$key:';
    }
  }

  String _formatDetailValue(String key, dynamic value, String lang) {
    if (key.contains('Amount') || key.contains('Installment')) {
      return '${value.toString()} ${Translations.getText('currency_sar', lang)}';
    } else if (key.contains('Date')) {
      return value.toString();
    } else if (key.contains('Days')) {
      return '${value.toString()} ${Translations.getText('days_count', lang)}';
    } else if (key.contains('Installments')) {
      return '${value.toString()} ${Translations.getText('installments', lang)}';
    }
    return value.toString();
  }

  Widget _buildApprovalsList(List<dynamic> approvals) {
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;
    return Column(
      children: approvals.map<Widget>((approval) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.person,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      approval['ApproverName'] ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getApprovalStatusColor(approval['Status'])
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _getApprovalStatusText(approval['Status'], lang),
                      style: TextStyle(
                        fontSize: 10,
                        color: _getApprovalStatusColor(approval['Status']),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (approval['Comments'] != null &&
                  approval['Comments'].toString().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${Translations.getText('notes', lang)}: ${approval['Comments']}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
              if (approval['ApprovalDate'] != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${Translations.getText('date', lang)}: ${approval['ApprovalDate']}',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Color _getApprovalStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'approved':
      case 'معتمد':
        return const Color(0xFF10B981);
      case 'rejected':
      case 'مرفوض':
        return const Color(0xFFEF4444);
      case 'pending':
      case 'معلق':
        return const Color(0xFFF59E0B);
      default:
        return Colors.grey;
    }
  }

  String _getApprovalStatusText(String? status, String lang) {
    switch (status?.toLowerCase()) {
      case 'approved':
      case 'معتمد':
        return Translations.getText('approved', lang);
      case 'rejected':
      case 'مرفوض':
        return Translations.getText('rejected', lang);
      case 'pending':
      case 'معلق':
        return Translations.getText('pending', lang);
      default:
        return Translations.getText('unknown', lang);
    }
  }

  String _getStatusText(request_models.RequestStatus status, String lang) {
    switch (status) {
      case request_models.RequestStatus.pending:
        return Translations.getText('pending', lang);
      case request_models.RequestStatus.approved:
        return Translations.getText('approved', lang);
      case request_models.RequestStatus.rejected:
        return Translations.getText('rejected', lang);
      case request_models.RequestStatus.cancelled:
        return Translations.getText('cancelled', lang);
    }
  }

  String _getPriorityText(String? priority, String lang) {
    switch (priority?.toLowerCase()) {
      case 'high':
      case 'عالية':
        return Translations.getText('priority_high', lang);
      case 'medium':
      case 'متوسطة':
        return Translations.getText('priority_medium', lang);
      case 'low':
      case 'منخفضة':
        return Translations.getText('priority_low', lang);
      default:
        return Translations.getText('priority_normal', lang);
    }
  }
}

enum _RequestSort {
  newestFirst,
  oldestFirst,
}
