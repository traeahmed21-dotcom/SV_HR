import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../models/api_models.dart' as api_models;
import '../models/pending_counts.dart';
import '../models/request.dart' as request_models;
import '../models/employee_full_info.dart';
import '../models/shift.dart';
import '../models/notification_model.dart';
import '../models/mobile_advertisement.dart';
import '../models/app_notice.dart';

import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../services/approval_permission_service.dart';
import 'attendance_screen.dart';
import 'attendance_history_screen.dart';
import 'requests_screen.dart';
import 'approvals_screen.dart'
    if (dart.library.html) 'approvals_screen_web_stub.dart';
import 'profile_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'payroll_screen.dart';
import 'shift_info_screen.dart';
import 'salary_details_screen.dart';
import 'user_tasks_screen.dart';
import 'task_creator_screen.dart';
import '../widgets/responsive_center.dart';
import '../widgets/ads_slider.dart';
import '../widgets/app_notice_banner.dart';
import '../theme/app_semantic_colors.dart';

class HomeScreen extends StatefulWidget {
  final String employeeId;
  final api_models.EmployeeData? employeeData;

  const HomeScreen({
    super.key,
    required this.employeeId,
    this.employeeData,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Employee? _currentEmployee;
  Map<String, dynamic> _attendanceStats = {};
  List<String> expiryNotifications = [];
  EmployeeFullInfo? employeeFullInfo;
  List<ShiftData> _shifts = [];
  List<api_models.CompanyHoliday> _companyHolidays = [];
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

  // Dashboard Data
  List<request_models.EmployeeRequest> _recentRequests = [];
  int _unreadNotificationsCount = 0;
  int _newTasksCount = 0;
  PendingCounts? _pendingCounts;
  int _pendingApprovalsCount = 0;
  int _myPendingRequestsCount = 0;
  SecureApprovalPermission? _cachedApprovalPermission;
  bool _hasApprovalAccess = false;
  bool _hasTaskCreatorAccess = false;
  int _managedEmployeesCount = 0;
  List<MobileAdvertisement> _mobileAds = [];
  AppNotice? _homeNotice;
  bool _isLoadingDashboard = false;

  // دالة تسجيل الأحداث للتطوير
  void _log(String message) {
    if (kDebugMode) {
      print(message);
    }
  }

  bool _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  bool _hasShownExpiryWarning = false;
  bool _hasShownLoginNotification = false;

  ShiftData? get _currentShift {
    if (_shifts.isEmpty) return null;
    final active = _shifts.where((s) => s.isActive).toList();
    return active.isNotEmpty ? active.first : _shifts.first;
  }

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    // Sync setup
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    if (widget.employeeData != null) {
      _currentEmployee = Employee(
        id: widget.employeeData!.employeeID.toString(),
        name: widget.employeeData!.name,
        email: widget.employeeData!.email,
        position:
            '${Translations.getText('employee_number_short', lang)}: ${widget.employeeData!.employeeNumber}',
        department: '',
        phone: '',
        employeeNumber: widget.employeeData!.employeeNumber,
        hireDate: DateTime.now(),
        salary: 0,
      );
    } else {
      _currentEmployee = null;
    }

    _attendanceStats = {
      'hasCheckedIn': false,
      'hasCheckedOut': false,
      'todayAttendance': [],
    };

    if (widget.employeeData == null) return;

    setState(() => _isLoadingDashboard = true);

    try {
      final clientId = widget.employeeData!.clientID;
      final empId = widget.employeeData!.employeeID;
      final employeeNumber = widget.employeeData!.employeeNumber;
      final email = widget.employeeData!.email;
      final rules = (widget.employeeData?.rules ?? '').toLowerCase();
      final creatorIdForApi = int.tryParse(employeeNumber) ?? empId;
      final month = _calendarMonth;
      final monthFrom = DateTime(month.year, month.month, 1);
      final monthTo = DateTime(
        month.year,
        month.month,
        DateUtils.getDaysInMonth(month.year, month.month),
      );

      var effectivePermission = ApprovalPermissionService.currentCached;
      final embeddedFromEmployee = widget.employeeData?.embeddedApprovalPermission;
      if (embeddedFromEmployee != null &&
          embeddedFromEmployee.isValid &&
          embeddedFromEmployee.verifySignatureIntegrity()) {
        effectivePermission = embeddedFromEmployee;
      } else if (widget.employeeData?.secureApprovalToken != null &&
          widget.employeeData!.secureApprovalToken!.isNotEmpty) {
        try {
          final decoded = SecureApprovalPermission.fromSecureJson(
              widget.employeeData!.secureApprovalToken!);
          if (decoded.isValid && decoded.verifySignatureIntegrity()) {
            effectivePermission = decoded;
          }
        } catch (_) {}
      }
      _cachedApprovalPermission = effectivePermission;
      ApprovalPermissionService.updateCached(effectivePermission);

      final bool isApprover = effectivePermission.isValid &&
          effectivePermission.verifySignatureIntegrity() &&
          effectivePermission.isApprover;

      // Parallel fetch with isolated error handling
      final results = await Future.wait([
        // 0. Employee Info
        ApiService()
            .getEmployeeFullInfo(clientId, email)
            .then<EmployeeFullInfo?>((v) => v)
            .catchError((e) {
          _log('Error fetching info: $e');
          return null;
        }),

        // 1. Requests (Default to empty map on error)
        ApiService.getRequests(clientId,
                employeeId: empId, page: 1, pageSize: 5)
            .catchError((e) {
          _log('Error fetching requests: $e');
          return {'Success': false, 'Data': []};
        }),

        // 2. Notifications Count (Default to 0)
        ApiService.getUnreadNotificationsCount(clientId, empId).catchError((e) {
          _log('Error fetching notifs count: $e');
          return 0;
        }),

        // 3. Pending Counts (Default to null)
        ApiService.getPendingCounts(clientId, empId).catchError((e) {
          _log('Error fetching pending counts: $e');
          return null;
        }),

        // 5. Pending Approvals (Fetch ONLY if verified approver rights to avoid server-side leaks)
        if (isApprover)
          ApiService.getPendingRequestsForApproval(
            clientId,
            approverId:
                int.tryParse(widget.employeeData!.employeeNumber) ?? empId,
          ).catchError((e) {
            _log('Error fetching approvals: $e');
            return {'Success': false, 'Data': []};
          })
        else
          Future.value({'Success': false, 'Data': [], '_Skip_': true}),

        // 5. My Pending Requests Count (Fallback/Reliable check - Fetch recent history to manually count pending)
        ApiService.getRequests(clientId,
                employeeId: empId, page: 1, pageSize: 50)
            .catchError((e) {
          _log('Error fetching my pending count: $e');
          return {'Success': false, 'Data': []};
        }),

        // 6. Shifts (to compute working days)
        ApiService.getEmployeeShiftsAll(clientId, widget.employeeData!.employeeNumber)
            .catchError((e) {
          _log('Error fetching shifts: $e');
          return <ShiftData>[];
        }),

        ApiService.getTaskCreatorManagedEmployees(
          clientId,
          creatorEmployeeId: creatorIdForApi,
        ).catchError((e) {
          _log('Error fetching task creator access: $e');
          return {'Success': false, 'Data': [], 'Permission': null};
        }),

        ApiService.getActiveMobileAdvertisements(clientId).catchError((e) {
          _log('Error fetching mobile ads: $e');
          return <MobileAdvertisement>[];
        }),

        ApiService.getActiveAppNotices(placement: 'home').catchError((e) {
          _log('Error fetching app notices: $e');
          return <AppNotice>[];
        }),

        ApiService.getUserTasks(
          clientId,
          employeeId: empId,
          status: 'Pending',
          page: 1,
          pageSize: 200,
        ).then<int>((resp) {
          if (resp['Success'] != true) return 0;
          final data = resp['Data'];
          if (data is List) return data.length;
          return 0;
        }).catchError((e) {
          _log('Error fetching tasks count: $e');
          return 0;
        }),
        ApiService.getCompanyHolidaysInRange(
          clientId,
          employeeId: empId,
          fromDate: monthFrom,
          toDate: monthTo,
        ).catchError((e) {
          _log('Error fetching company holidays: $e');
          return <api_models.CompanyHoliday>[];
        }),
      ]);

      if (!mounted) return;

      setState(() {
        // 1. Employee Full Info & Expiry
        final info = results[0];
        if (info != null && info is EmployeeFullInfo) {
          employeeFullInfo = info;
          if (!_hasShownExpiryWarning) {
            _checkDocumentExpiry(updateState: false);
            _hasShownExpiryWarning = true;
          }
        }

        // 2. Recent Requests
        final requestsResponse = results[1] as Map<String, dynamic>;
        if (requestsResponse['Success'] == true) {
          final List<dynamic> data = requestsResponse['Data'] ?? [];
          _recentRequests =
              data.map((json) => _parseRequestFromAPI(json)).toList();
        }

        // 3. Notifications Count
        _unreadNotificationsCount = results[2] as int;

        // 4. Pending Counts
        _pendingCounts = results[3] as PendingCounts?;

        _newTasksCount = results[10] as int;

        // 5. Pending Approvals Count — STRICT SECURITY GATE
        final approvalsResponse = results[4] as Map<String, dynamic>;
        final wasSkipped = approvalsResponse['_Skip_'] == true;
        if (wasSkipped) {
          _pendingApprovalsCount = 0;
          _hasApprovalAccess = false;
          final finalPerm =
              ApprovalPermissionService.evaluateApproverFromSignals(
            clientId: clientId,
            employeeId: empId,
            employeeNumber: employeeNumber,
            rulesRaw: rules,
            serverApprovalAccess: false,
            pendingApprovalItems: const [],
          );
          _cachedApprovalPermission = finalPerm;
          ApprovalPermissionService.updateCached(finalPerm);
          _hasApprovalAccess = finalPerm.isValid &&
              finalPerm.verifySignatureIntegrity() &&
              finalPerm.isApprover;
          try {
            ApprovalPermissionService.persistSecurely(finalPerm.toSecureJson());
          } catch (_) {}
        } else {
          if (approvalsResponse['Success'] == true) {
            final List<dynamic> data = approvalsResponse['Data'] ?? [];
            _pendingApprovalsCount = data.length;
            final access = approvalsResponse['HasApprovalAccess'];
            final serverAccess = access == true ||
                (access is String && access.toLowerCase() == 'true');
            final finalPerm =
                ApprovalPermissionService.evaluateApproverFromSignals(
              clientId: clientId,
              employeeId: empId,
              employeeNumber: employeeNumber,
              rulesRaw: rules,
              serverApprovalAccess: serverAccess,
              pendingApprovalItems: data,
            );
            _cachedApprovalPermission = finalPerm;
            ApprovalPermissionService.updateCached(finalPerm);
            _hasApprovalAccess = finalPerm.isValid &&
                finalPerm.verifySignatureIntegrity() &&
                finalPerm.isApprover;
            try {
              ApprovalPermissionService.persistSecurely(finalPerm.toSecureJson());
            } catch (_) {}
          } else {
            _pendingApprovalsCount = 0;
            _hasApprovalAccess = false;
            final finalPerm =
                ApprovalPermissionService.evaluateApproverFromSignals(
              clientId: clientId,
              employeeId: empId,
              employeeNumber: employeeNumber,
              rulesRaw: rules,
              serverApprovalAccess: false,
              pendingApprovalItems: const [],
            );
            _cachedApprovalPermission = finalPerm;
            ApprovalPermissionService.updateCached(finalPerm);
            try {
              ApprovalPermissionService.persistSecurely(finalPerm.toSecureJson());
            } catch (_) {}
          }
        }

        // 6. My Pending Requests Count (Calculated from recent history)
        final myPendingResponse = results[5] as Map<String, dynamic>;
        if (myPendingResponse['Success'] == true) {
          final List<dynamic> data = myPendingResponse['Data'] ?? [];
          int calculatedPending = 0;
          for (var item in data) {
            final request = _parseRequestFromAPI(item);
            if (request.status == request_models.RequestStatus.pending) {
              calculatedPending++;
            }
          }
          _myPendingRequestsCount = calculatedPending;
        } else {
          _myPendingRequestsCount = 0;
        }

        _shifts = (results[6] as List).whereType<ShiftData>().toList();

        final taskCreatorResp = results[7] as Map<String, dynamic>;
        final taskOk = taskCreatorResp['Success'] == true;
        final List taskData = (taskCreatorResp['Data'] as List?) ?? const [];
        final perm = taskCreatorResp['Permission'];
        final canCreate = perm is Map && _asBool(perm['CanCreate']);
        _hasTaskCreatorAccess = taskOk && canCreate;
        _managedEmployeesCount = taskOk ? taskData.length : 0;

        _mobileAds =
            (results[8] as List).whereType<MobileAdvertisement>().toList();
        final notices = (results[9] as List).whereType<AppNotice>().toList();
        _homeNotice = notices.isNotEmpty ? notices.first : null;
        _companyHolidays = (results[11] as List)
            .whereType<api_models.CompanyHoliday>()
            .toList();

        _isLoadingDashboard = false;
      });

      await _showLoginNotificationIfNeeded();
    } catch (e) {
      _log('Data load error: $e');
      if (mounted) setState(() => _isLoadingDashboard = false);
    }
  }

  Future<void> _showLoginNotificationIfNeeded() async {
    if (_hasShownLoginNotification) return;
    if (!mounted) return;
    if (widget.employeeData == null) return;
    if (_unreadNotificationsCount <= 0) return;

    _hasShownLoginNotification = true;

    final clientId = widget.employeeData!.clientID;
    final empId = widget.employeeData!.employeeID;

    final unread = await ApiService.getNotifications(
      clientId,
      empId,
      unreadOnly: true,
    );

    if (!mounted) return;
    if (unread.isEmpty) return;

    final webNotifications =
        unread.where((n) => _isWebSentNotification(n)).toList();

    if (webNotifications.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      for (final notification in webNotifications) {
        if (!mounted) return;
        final wasMarkedRead = await _showNotificationDialogAndMarkRead(
          clientId: clientId,
          notification: notification,
        );
        if (!mounted) return;
        if (wasMarkedRead) {
          setState(() {
            _unreadNotificationsCount = _unreadNotificationsCount > 0
                ? _unreadNotificationsCount - 1
                : 0;
          });
        }
      }
    });
  }

  bool _isWebSentNotification(NotificationModel n) {
    final type = (n.type ?? '').trim();
    final metadata = (n.metadata ?? '').toLowerCase();

    if (metadata.contains('"event":"general"') ||
        metadata.contains('"event":"birthday"')) {
      return true;
    }

    if (type == 'إشعار عام' || type == 'تهنئة عيد ميلاد') {
      return true;
    }

    return false;
  }

  bool _isBirthdayNotification(NotificationModel n) {
    final type = (n.type ?? '').trim();
    final metadata = (n.metadata ?? '').toLowerCase();
    if (metadata.contains('"event":"birthday"')) return true;
    if (type == 'تهنئة عيد ميلاد') return true;
    return false;
  }

  Future<bool> _showNotificationDialogAndMarkRead({
    required int clientId,
    required NotificationModel notification,
  }) async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    var markedRead = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        var isSubmitting = false;
        return WillPopScope(
          onWillPop: () async => false,
          child: StatefulBuilder(
            builder: (context, setState) {
              final isBirthday = _isBirthdayNotification(notification);
              final scheme = Theme.of(context).colorScheme;
              final headerGradient = isBirthday
                  ? const LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [Color(0xFFB5179E), Color(0xFF7209B7)],
                    )
                  : LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        scheme.primary,
                        scheme.primaryContainer,
                      ],
                    );

              final titleText = (notification.title).trim().isEmpty
                  ? Translations.getText('notifications', lang)
                  : notification.title;

              final messageText = (notification.message).trim();

              Future<void> onOk() async {
                if (isSubmitting) return;
                setState(() {
                  isSubmitting = true;
                });

                final ok = await ApiService.markNotificationRead(
                  clientId,
                  notification.id,
                );

                if (!dialogContext.mounted) return;

                if (!ok) {
                  setState(() {
                    isSubmitting = false;
                  });
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'تعذر تسجيل قراءة الرسالة، يرجى التحقق من الاتصال',
                      ),
                    ),
                  );
                  return;
                }

                markedRead = true;
                Navigator.of(dialogContext).pop();
              }

              return Dialog(
                insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          gradient: headerGradient,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(24),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(
                                isBirthday
                                    ? Icons.cake_rounded
                                    : Icons.notifications_active_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                titleText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                        child: Align(
                          alignment:
                              isBirthday ? Alignment.center : Alignment.centerRight,
                          child: Text(
                            messageText,
                            textAlign:
                                isBirthday ? TextAlign.center : TextAlign.start,
                            style: TextStyle(
                              height: 1.6,
                              fontSize: 15,
                              color: scheme.onSurface,
                              fontWeight:
                                  isBirthday ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: isSubmitting ? null : onOk,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              backgroundColor:
                                  isBirthday ? const Color(0xFFB5179E) : null,
                              foregroundColor: Colors.white,
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    Translations.getText('ok', lang),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );

    return markedRead;
  }

  // Copied helper from RequestsScreen
  request_models.EmployeeRequest _parseRequestFromAPI(
      Map<String, dynamic> json) {
    return request_models.EmployeeRequest(
      id: json['ID']?.toString() ?? '',
      requestNumber: json['RequestNumber']?.toString() ?? '',
      employeeId: json['EmployeeID']?.toString() ?? '',
      employeeName: json['EmployeeName']?.toString() ?? '',
      type: _parseRequestType(json['RequestTypeName']),
      title: json['RequestTypeName'] ?? '',
      description: json['Description']?.toString() ?? '',
      startDate: DateTime.tryParse(json['StartDate'] ?? '') ??
          DateTime.tryParse(json['CreatedDate'] ?? '') ??
          DateTime.now(),
      endDate: DateTime.tryParse(json['EndDate'] ?? '') ??
          DateTime.tryParse(json['CreatedDate'] ?? '') ??
          DateTime.now(),
      status: _parseRequestStatus(json['Status']),
      priority: json['Priority']?.toString() ?? 'Normal',
      createdAt: DateTime.tryParse(json['CreatedDate'] ?? '') ?? DateTime.now(),
      approvedBy: null,
      rejectionReason: null,
    );
  }

  request_models.RequestType _parseRequestType(String? typeName) {
    if (typeName?.contains('loan') == true ||
        typeName?.contains('سلفة') == true) {
      return request_models.RequestType.loan;
    } else if (typeName?.contains('leave') == true ||
        typeName?.contains('إجازة') == true) {
      return request_models.RequestType.leave;
    }
    return request_models.RequestType.other;
  }

  request_models.RequestStatus _parseRequestStatus(String? status) {
    switch (status?.trim().toLowerCase()) {
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
      case 'cancelled':
      case 'ملغي':
        return request_models.RequestStatus.cancelled;
      default:
        return request_models.RequestStatus.pending;
    }
  }

  void _checkDocumentExpiry({bool updateState = true}) {
    // ... existing logic ...
    // Keeping minimal logic here for brevity in rewrite, assuming original logic is preserved if I don't touch it?
    // Wait, I am overwriting the file. I MUST include the logic.
    if (employeeFullInfo == null) return;
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;
    final now = DateTime.now();
    final notifications = <String>[];

    if (employeeFullInfo!.nationalIdExpiryDate.isNotEmpty) {
      try {
        final expiryDate =
            DateTime.parse(employeeFullInfo!.nationalIdExpiryDate);
        final daysUntilExpiry = expiryDate.difference(now).inDays;
        if (daysUntilExpiry < 0) {
          notifications
              .add('⚠️ ${Translations.getText('national_id_expired', lang)}');
        } else if (daysUntilExpiry <= 60) {
          notifications.add(
              '⚠️ ${Translations.getTextWithParams('national_id_expiring', lang, {
                'days': daysUntilExpiry.toString()
              })}');
        }
      } catch (e) {}
    }
    if (employeeFullInfo!.passportExpiryDate.isNotEmpty) {
      try {
        final expiryDate = DateTime.parse(employeeFullInfo!.passportExpiryDate);
        final daysUntilExpiry = expiryDate.difference(now).inDays;
        if (daysUntilExpiry < 0) {
          notifications
              .add('⚠️ ${Translations.getText('passport_expired', lang)}');
        } else if (daysUntilExpiry <= 60) {
          notifications.add(
              '⚠️ ${Translations.getTextWithParams('passport_expiring', lang, {
                'days': daysUntilExpiry.toString()
              })}');
        }
      } catch (e) {}
    }

    if (updateState) {
      setState(() {
        expiryNotifications = notifications;
      });
    } else {
      expiryNotifications = notifications;
    }

    if (notifications.isNotEmpty) {
      // Defer dialog show to next frame to avoid "setState during build" or similar issues if called from init
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showExpiryNotifications(notifications);
      });
    }
  }

  void _showExpiryNotifications(List<String> notifications) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange),
            const SizedBox(width: 8),
            Text(Translations.getText('document_expiry_warning', lang)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: notifications
              .map((notification) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(notification,
                        overflow: TextOverflow.ellipsis, maxLines: 3),
                  ))
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(Translations.getText('close', lang)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    // ... existing logout logic ...
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Translations.getText('logout', lang)),
        content: Text(Translations.getText('confirm_logout', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(Translations.getText('cancel', lang)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(Translations.getText('confirm', lang)),
          ),
        ],
      ),
    );

    if (shouldLogout != true) return;

    try {
      try {
        await ApiService.logout();
      } catch (e) {}

      // مسح بيانات الجلسة المحفوظة
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('user_data');
      await prefs.setBool('is_logged_in', false);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;

    if (_currentEmployee == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Translations.getText('dashboard', lang),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.person),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(
                  employee: _currentEmployee!,
                  clientId: widget.employeeData?.clientID ?? 30,
                ),
              ),
            );
          },
        ),
        actions: [
          // Notification Icon
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => NotificationsScreen(
                        clientId: widget.employeeData?.clientID ?? 30,
                        employeeId: widget.employeeData!.employeeID,
                        employeeNumber: widget.employeeData!.employeeNumber,
                      ),
                    ),
                  );
                  // Refresh dashboard when coming back (to update unread count)
                  _loadAllData();
                },
              ),
              if (_unreadNotificationsCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: scheme.error,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _unreadNotificationsCount > 99
                          ? '99+'
                          : _unreadNotificationsCount.toString(),
                      style: TextStyle(
                          color: scheme.onError,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          /*  IconButton(
            icon: const Icon(Icons.person),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(
                    employee: _currentEmployee!,
                    clientId: widget.employeeData?.clientID ?? 30,
                  ),
                ),
              );
            },
          ),*/
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadAllData();
        },
        child: ResponsiveCenter(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_homeNotice != null) ...[
                  AppNoticeBanner(
                    notice: _homeNotice!,
                    lang: lang,
                  ),
                  const SizedBox(height: 12),
                ],
                _buildWelcomeCard(lang),
                const SizedBox(height: 24),
                _buildAttendanceCard(lang),
                if (_mobileAds.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  AdsSlider(ads: _mobileAds),
                  const SizedBox(height: 24),
                ] else
                  const SizedBox(height: 24),
                _buildQuickActions(lang),
                const SizedBox(height: 24),
                _buildWorkCalendar(lang),
                const SizedBox(height: 24),
                _buildRecentRequestsCard(lang),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard(String lang) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.onPrimary.withValues(alpha: 0.22),
          width: 1.25,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.18),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.onPrimary.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: scheme.onPrimary.withValues(alpha: 0.18),
              child: Icon(Icons.person, size: 32, color: scheme.onPrimary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isSmall = constraints.maxWidth < 280;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      Translations.getTextWithParams(
                          'welcome_user', lang, {'name': _currentEmployee!.name}),
                      maxLines: isSmall ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: scheme.onPrimary,
                            height: 1.3,
                            fontSize: isSmall ? 17 : null,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _currentEmployee!.position,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onPrimary.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(String lang) {
    final hasCheckedIn = _attendanceStats['hasCheckedIn'] ?? false;
    final hasCheckedOut = _attendanceStats['hasCheckedOut'] ?? false;
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return _buildBorderedSectionCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: semantic.infoContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: semantic.info.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                child: Icon(Icons.access_time, size: 20, color: semantic.info),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(Translations.getText('today_attendance', lang),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final isCompact = width < 320;
              final btnHeight = isCompact ? 110.0 : 120.0;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      height: btnHeight,
                      child: _buildAttendanceButton(
                        title: Translations.getText('check_in', lang),
                        icon: Icons.login,
                        isEnabled: !hasCheckedIn,
                        tone: _AttendanceTone.primary,
                        onPressed: hasCheckedIn
                            ? null
                            : () => _navigateToAttendance(true),
                      ),
                    ),
                  ),
                  SizedBox(width: isCompact ? 10 : 14),
                  Expanded(
                    child: SizedBox(
                      height: btnHeight,
                      child: _buildAttendanceButton(
                        title: Translations.getText('check_out', lang),
                        icon: Icons.logout,
                        isEnabled: !hasCheckedOut,
                        tone: _AttendanceTone.secondary,
                        onPressed: hasCheckedOut
                            ? null
                            : () => _navigateToAttendance(false),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _navigateToAttendance(bool isCheckIn) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => AttendanceScreen(
                employeeNumber: _currentEmployee!.employeeNumber,
                clientId: widget.employeeData?.clientID ?? 1,
                isCheckIn: isCheckIn)));
  }

  Widget _buildAttendanceButton({
    required String title,
    required IconData icon,
    required bool isEnabled,
    required _AttendanceTone tone,
    VoidCallback? onPressed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    final Color bg =
        tone == _AttendanceTone.primary ? semantic.success : scheme.primary;
    final Color onBg = Colors.white;
    return Semantics(
      button: true,
      enabled: isEnabled,
      label: title,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isEnabled
                  ? [bg, bg.withValues(alpha: 0.88)]
                  : [
                      scheme.surfaceContainerHighest,
                      scheme.surfaceContainerHighest.withValues(alpha: 0.7),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isEnabled
                  ? bg.withValues(alpha: 0.35)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: 1.2,
            ),
            boxShadow: [
              if (isEnabled)
                BoxShadow(
                  color: bg.withValues(alpha: 0.22),
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: InkWell(
            onTap: isEnabled ? onPressed : null,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isEnabled ? onBg : scheme.onSurfaceVariant)
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 26,
                      color: isEnabled ? onBg : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isEnabled ? onBg : scheme.onSurfaceVariant,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBorderedSectionCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
    EdgeInsetsGeometry margin = const EdgeInsets.symmetric(vertical: 4),
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.9),
          width: 1.25,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _buildQuickActions(String lang) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    if (semantic == null) return const SizedBox();

    final cached = _cachedApprovalPermission;
    bool secureIsApprover = false;
    if (cached != null &&
        cached.isValid &&
        cached.verifySignatureIntegrity() &&
        cached.clientId == widget.employeeData?.clientID &&
        cached.employeeId == widget.employeeData?.employeeID &&
        cached.employeeNumber == widget.employeeData?.employeeNumber) {
      secureIsApprover = cached.isApprover;
    } else if (widget.employeeData?.hasValidSecureApprovalPermission == true) {
      secureIsApprover = widget.employeeData!.isApprover;
    }
    final showApprovalsCard = secureIsApprover && _hasApprovalAccess;
    return LayoutBuilder(
      builder: (context, constraints) {
        const childAspectRatio = 0.88;
        const horizontalSpacing = 16.0;
        const verticalSpacing = 16.0;

        Widget buildGroupSectionCard({
          required String title,
          required List<Widget> actions,
        }) {
          return _buildBorderedSectionCard(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.center,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 2,
                  crossAxisSpacing: horizontalSpacing,
                  mainAxisSpacing: verticalSpacing,
                  childAspectRatio: childAspectRatio,
                  children: actions,
                ),
              ],
            ),
          );
        }

        final attendanceAndShiftsActions = <Widget>[
          _buildActionCard(
            title: Translations.getText('attendance_history', lang),
            icon: Icons.history,
            color: semantic.success,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AttendanceHistoryScreen(
                    employeeNumber: _currentEmployee!.employeeNumber,
                    clientId: widget.employeeData?.clientID ?? 30,
                    employeeName: _currentEmployee!.name,
                  ),
                ),
              );
              _loadAllData();
            },
          ),
          _buildActionCard(
            title: Translations.getText('shifts_and_location', lang),
            icon: Icons.work_history,
            color: scheme.primary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShiftInfoScreen(
                  clientId: widget.employeeData!.clientID,
                  employeeNumber: widget.employeeData!.employeeNumber,
                  email: widget.employeeData!.email,
                  employeeId: widget.employeeData!.employeeID,
                ),
              ),
            ),
          ),
        ];

        final requestsAndApprovalsActions = <Widget>[
          _buildActionCard(
            title: Translations.getText('my_requests', lang),
            icon: Icons.assignment,
            color: scheme.primary,
            badgeCount: ((_pendingCounts?.loan ?? 0) +
                        (_pendingCounts?.leave ?? 0) +
                        (_pendingCounts?.other ?? 0)) >
                    _myPendingRequestsCount
                ? ((_pendingCounts?.loan ?? 0) +
                    (_pendingCounts?.leave ?? 0) +
                    (_pendingCounts?.other ?? 0))
                : _myPendingRequestsCount,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RequestsScreen(
                    employeeId: widget.employeeId,
                    employeeData: widget.employeeData!,
                  ),
                ),
              );
              _loadAllData();
            },
          ),
          if (showApprovalsCard)
            _buildActionCard(
              title: Translations.getText('approvals', lang),
              icon: Icons.approval,
              color: scheme.secondary,
              badgeCount: _pendingApprovalsCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ApprovalsScreen(
                      employeeId: widget.employeeId,
                      employeeData: widget.employeeData!,
                    ),
                  ),
                );
                _loadAllData();
              },
            ),
        ];

        final tasksAndFinanceActions = <Widget>[
          _buildActionCard(
            title: Translations.getText('tasks_title', lang),
            icon: Icons.task_alt_rounded,
            color: scheme.primary,
            badgeCount: _newTasksCount,
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserTasksScreen(
                    clientId: widget.employeeData!.clientID,
                    employeeId: widget.employeeData!.employeeID,
                  ),
                ),
              );
              _loadAllData();
            },
          ),
          if (_hasTaskCreatorAccess)
            _buildActionCard(
              title: Translations.getText('task_creator_title', lang),
              icon: Icons.playlist_add_check_rounded,
              color: scheme.secondary,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TaskCreatorScreen(
                      clientId: widget.employeeData!.clientID,
                      creatorEmployeeId:
                          int.tryParse(widget.employeeData!.employeeNumber) ??
                              widget.employeeData!.employeeID,
                    ),
                  ),
                );
                _loadAllData();
              },
            ),
          _buildActionCard(
            title: Translations.getText('salary_details_title', lang),
            icon: Icons.payments,
            color: scheme.tertiary,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => SalaryDetailsScreen(
                  employeeId: widget.employeeData!.employeeID,
                  clientId: widget.employeeData!.clientID,
                ),
              ),
            ),
          ),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildGroupSectionCard(
              title: Translations.getText(
                'quick_actions_section_attendance_shifts',
                lang,
              ),
              actions: attendanceAndShiftsActions,
            ),
            const SizedBox(height: 16),
            buildGroupSectionCard(
              title: Translations.getText(
                'quick_actions_section_requests_approvals',
                lang,
              ),
              actions: requestsAndApprovalsActions,
            ),
            const SizedBox(height: 16),
            buildGroupSectionCard(
              title: Translations.getText(
                'quick_actions_section_tasks_finance',
                lang,
              ),
              actions: tasksAndFinanceActions,
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return _ActionCardWidget(
      title: title,
      icon: icon,
      color: color,
      onTap: onTap,
      badgeCount: badgeCount,
      scheme: scheme,
      semantic: semantic,
      lang: lang,
    );
  }

  Widget _buildWorkCalendar(String lang) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    if (semantic == null) return const SizedBox();

    final month = _calendarMonth;
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateUtils.getDaysInMonth(month.year, month.month);
    final startOffset = _weekdayIndexSundayFirst(firstOfMonth);
    final now = DateTime.now();

    String monthKey(int m) {
      const keys = [
        'january',
        'february',
        'march',
        'april',
        'may',
        'june',
        'july',
        'august',
        'september',
        'october',
        'november',
        'december',
      ];
      return keys[m - 1];
    }

    final title = '${Translations.getText(monthKey(month.month), lang)} ${month.year}';
    final workBg = semantic.success.withValues(alpha: 0.20);
    final offBg = scheme.error.withValues(alpha: 0.20);
    final unknownBg = scheme.surfaceContainerHighest.withValues(alpha: 0.25);
    final workBorder = semantic.success.withValues(alpha: 0.62);
    final offBorder = scheme.error.withValues(alpha: 0.62);
    final unknownBorder = scheme.outlineVariant.withValues(alpha: 0.55);

    final headers = [
      Translations.getText('weekday_sunday_short', lang),
      Translations.getText('weekday_monday_short', lang),
      Translations.getText('weekday_tuesday_short', lang),
      Translations.getText('weekday_wednesday_short', lang),
      Translations.getText('weekday_thursday_short', lang),
      Translations.getText('weekday_friday_short', lang),
      Translations.getText('weekday_saturday_short', lang),
    ];

    return _buildBorderedSectionCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  Translations.getText('calendar', lang),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _calendarMonth =
                              DateTime(_calendarMonth.year, _calendarMonth.month - 1);
                        });
                        _reloadCompanyHolidaysForMonth();
                      },
                      icon: const Icon(Icons.chevron_left, size: 22),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _calendarMonth =
                              DateTime(_calendarMonth.year, _calendarMonth.month + 1);
                        });
                        _reloadCompanyHolidaysForMonth();
                      },
                      icon: const Icon(Icons.chevron_right, size: 22),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primaryContainer.withValues(alpha: 0.14),
                  scheme.surfaceContainerHighest.withValues(alpha: 0.18),
                  scheme.surface,
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.14),
                width: 1.25,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.08),
                  blurRadius: 18,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 2, 4, 12),
                  child: Row(
                    children: headers
                        .asMap()
                        .entries
                        .map(
                          (entry) {
                            final idx = entry.key;
                            final isFirst = idx == 0;
                            final isLast = idx == headers.length - 1;
                            return Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                margin: EdgeInsets.only(
                                  left: isFirst ? 0 : 1.0,
                                  right: isLast ? 0 : 0,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.vertical(
                                    top: const Radius.circular(10),
                                    bottom: const Radius.circular(6),
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      scheme.primary.withValues(alpha: 0.14),
                                      scheme.primaryContainer.withValues(alpha: 0.10),
                                    ],
                                  ),
                                  border: Border(
                                    bottom: BorderSide(
                                      color: scheme.primary.withValues(alpha: 0.25),
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    entry.value,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: scheme.primary.withValues(alpha: 0.92),
                                      fontSize: 12.5,
                                      letterSpacing: 0.4,
                                      height: 1.15,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                        .toList(),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final gridLineColor =
                        scheme.outlineVariant.withValues(alpha: 0.30);
                    return Container(
                      decoration: BoxDecoration(
                        color: gridLineColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(1.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 7,
                            crossAxisSpacing: 1.0,
                            mainAxisSpacing: 1.0,
                            childAspectRatio: 1.0,
                          ),
                          itemCount: 42,
                          itemBuilder: (context, index) {
                            final dayNumber = index - startOffset + 1;
                            if (dayNumber < 1 || dayNumber > daysInMonth) {
                              return Container(
                                color: scheme.surface.withValues(alpha: 0.78),
                                child: Center(
                                  child: Text(
                                    '',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant
                                          .withValues(alpha: 0.28),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              );
                            }

                            final date =
                                DateTime(month.year, month.month, dayNumber);
                            final isToday = DateUtils.isSameDay(date, now);
                            final shiftWorking = _isWorkingDate(date);
                            final holidays = _companyHolidaysForDate(date);
                            final isWorking =
                                holidays.isNotEmpty ? false : shiftWorking;
                            final weekday = (date.weekday % 7);
                            final isWeekend = weekday == 5 || weekday == 6;

                            return _CalendarDayCell(
                              dayNumber: dayNumber,
                              date: date,
                              isToday: isToday,
                              isWorking: isWorking,
                              isWeekend: isWeekend,
                              onTap: () => _showCalendarDayDetails(
                                lang: lang,
                                date: date,
                                isWorking: isWorking,
                                holidays: holidays,
                              ),
                              workBg: workBg,
                              offBg: offBg,
                              unknownBg: unknownBg,
                              workBorder: workBorder,
                              offBorder: offBorder,
                              unknownBorder: unknownBorder,
                              successColor: semantic.success,
                              errorColor: scheme.error,
                              onSurface: scheme.onSurface,
                              onSurfaceVariant: scheme.onSurfaceVariant,
                              onPrimary: scheme.onPrimary,
                              primaryColor: scheme.primary,
                              primaryContainer: scheme.primaryContainer,
                              outlineColor: scheme.outlineVariant,
                              surfaceColor: scheme.surface,
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _legendChip(
                  color: semantic.success,
                  label: Translations.getText('status_working', lang)),
              _legendChip(
                  color: scheme.error,
                  label: Translations.getText('status_holiday', lang)),
              _legendChip(
                  color: scheme.primary,
                  label: Translations.getText('today', lang),
                  outlined: true),
            ],
          ),
          if (_currentShift == null) ...[
            const SizedBox(height: 12),
            Text(
              Translations.getText('no_work_days', lang),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  int _weekdayIndexSundayFirst(DateTime date) {
    return date.weekday % 7;
  }

  bool? _isWorkingDate(DateTime date) {
    final shift = _currentShift;
    if (shift == null) return null;
    final days = shift.workDays;
    if (days.isEmpty) return null;

    int? sundayNumber;
    for (final d in days) {
      final n = _normalizeDayName(d.dayName);
      if (n.contains('sun') || n.contains('الاحد') || n == 'احد') {
        sundayNumber = d.dayNumber;
        break;
      }
    }

    final mappedDayNumber = _mapDateToShiftDayNumber(date, sundayNumber);
    for (final d in days) {
      if (d.dayNumber == mappedDayNumber) {
        return d.isWorkDay;
      }
    }

    final dateName = _weekdayNameKey(date.weekday);
    for (final d in days) {
      final n = _normalizeDayName(d.dayName);
      if (n.contains(dateName)) {
        return d.isWorkDay;
      }
    }

    return null;
  }

  List<api_models.CompanyHoliday> _companyHolidaysForDate(DateTime date) {
    if (_companyHolidays.isEmpty) return const [];
    final day = DateTime(date.year, date.month, date.day);
    final matches = <api_models.CompanyHoliday>[];
    for (final h in _companyHolidays) {
      final from = DateTime(h.fromDate.year, h.fromDate.month, h.fromDate.day);
      final to = DateTime(h.toDate.year, h.toDate.month, h.toDate.day);
      if (!day.isBefore(from) && !day.isAfter(to)) {
        matches.add(h);
      }
    }
    return matches;
  }

  Future<void> _reloadCompanyHolidaysForMonth() async {
    if (widget.employeeData == null) return;
    final clientId = widget.employeeData!.clientID;
    final empId = widget.employeeData!.employeeID;
    final month = _calendarMonth;
    final fromDate = DateTime(month.year, month.month, 1);
    final toDate = DateTime(
      month.year,
      month.month,
      DateUtils.getDaysInMonth(month.year, month.month),
    );

    final list = await ApiService.getCompanyHolidaysInRange(
      clientId,
      employeeId: empId,
      fromDate: fromDate,
      toDate: toDate,
    );

    if (!mounted) return;
    setState(() {
      _companyHolidays = list;
    });
  }

  void _showCalendarDayDetails({
    required String lang,
    required DateTime date,
    required bool? isWorking,
    required List<api_models.CompanyHoliday> holidays,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final locale = lang == 'ar' ? 'ar' : 'en';
    final df = DateFormat('yyyy-MM-dd', locale);
    final dateText = df.format(date);

    final title = lang == 'ar' ? 'تفاصيل اليوم' : 'Day details';
    final officialHolidayLabel =
        lang == 'ar' ? 'إجازة رسمية' : 'Official holiday';
    final holidayLabel = lang == 'ar' ? 'الإجازة' : 'Holiday';

    final statusText = holidays.isNotEmpty
        ? officialHolidayLabel
        : (isWorking == null
            ? Translations.getText('unknown', lang)
            : (isWorking
                ? Translations.getText('status_working', lang)
                : Translations.getText('status_holiday', lang)));

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '$dateText • $statusText',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (holidays.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final h in holidays) ...[
                    Text(
                      '$holidayLabel: ${h.holidayName}',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${df.format(h.fromDate)} → ${df.format(h.toDate)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    if ((h.scopeDepartmentName ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        lang == 'ar'
                            ? 'القسم: ${h.scopeDepartmentName}'
                            : 'Department: ${h.scopeDepartmentName}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  int _mapDateToShiftDayNumber(DateTime date, int? sundayNumber) {
    if (sundayNumber == 1) {
      return date.weekday == DateTime.sunday ? 1 : date.weekday + 1;
    }
    return date.weekday;
  }

  String _weekdayNameKey(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'mon';
      case DateTime.tuesday:
        return 'tue';
      case DateTime.wednesday:
        return 'wed';
      case DateTime.thursday:
        return 'thu';
      case DateTime.friday:
        return 'fri';
      case DateTime.saturday:
        return 'sat';
      case DateTime.sunday:
        return 'sun';
    }
    return '';
  }

  String _normalizeDayName(String value) {
    final v = value.trim().toLowerCase();
    return v
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه');
  }

  Widget _legendChip({
    required Color color,
    required String label,
    bool outlined = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: outlined ? scheme.surface : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: outlined ? color : Colors.transparent),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: outlined ? color : scheme.onSurface,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildRecentRequestsCard(String lang) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    return _buildBorderedSectionCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.tertiary.withValues(alpha: 0.22),
                    width: 1,
                  ),
                ),
                child: Icon(
                  Icons.assignment_rounded,
                  size: 20,
                  color: scheme.tertiary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  Translations.getText('my_requests', lang),
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              if (_recentRequests.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    '${_recentRequests.length}',
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (_recentRequests.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.85),
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.inbox_rounded,
                    size: 42,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    Translations.getText('no_recent_requests', lang),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                  width: 1.1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Column(
                  children: List.generate(_recentRequests.length, (i) {
                    final item = _recentRequests[i];
                    final isLast = i == _recentRequests.length - 1;
                    return Column(
                      children: [
                        _buildRequestItem(item),
                        if (!isLast)
                          Divider(
                            height: 1,
                            thickness: 1,
                            indent: 68,
                            endIndent: 16,
                            color: scheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                      ],
                    );
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRequestItem(request_models.EmployeeRequest request) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;
    Color statusColor;
    String statusText;
    switch (request.status) {
      case request_models.RequestStatus.pending:
        statusColor = semantic.warning;
        statusText = Translations.getText('pending', lang);
        break;
      case request_models.RequestStatus.approved:
        statusColor = semantic.success;
        statusText = Translations.getText('approved', lang);
        break;
      case request_models.RequestStatus.rejected:
        statusColor = scheme.error;
        statusText = Translations.getText('rejected', lang);
        break;
      case request_models.RequestStatus.cancelled:
        statusColor = scheme.outline;
        statusText = Translations.getText('cancelled', lang);
        break;
      default:
        statusColor = scheme.outline;
        statusText = Translations.getText('unknown', lang);
    }

    return _RequestItemTile(
      request: request,
      statusColor: statusColor,
      statusText: statusText,
      scheme: scheme,
      semantic: semantic,
      onTap: () => _showRequestDetails(request),
      requestTypeIcon: _getRequestTypeIcon(request.type),
      formattedDate: _formatDate(request.createdAt),
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
      default:
        return Icons.assignment;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // Copied from RequestsScreen
  void _showRequestDetails(request_models.EmployeeRequest request) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final response = await ApiService.getRequestDetails(
        widget.employeeData!.clientID,
        int.parse(request.id),
      );
      Navigator.of(context).pop();
      final details = response['Success'] == true ? response['Data'] : null;
      _showRequestDetailsDialog(request, details);
    } catch (e) {
      Navigator.of(context).pop();
      _showRequestDetailsDialog(request, null);
    }
  }

  void _showRequestDetailsDialog(
      request_models.EmployeeRequest request, Map<String, dynamic>? details) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    String statusText;
    switch (request.status) {
      case request_models.RequestStatus.pending:
        statusText = Translations.getText('pending', lang);
        break;
      case request_models.RequestStatus.approved:
        statusText = Translations.getText('approved', lang);
        break;
      case request_models.RequestStatus.rejected:
        statusText = Translations.getText('rejected', lang);
        break;
      case request_models.RequestStatus.cancelled:
        statusText = Translations.getText('cancelled', lang);
        break;
      default:
        statusText = Translations.getText('unknown', lang);
    }

    // simplified dialog reuse
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(request.title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    "${Translations.getText('request_number', lang)}: ${request.requestNumber}"),
                Text("${Translations.getText('status', lang)}: $statusText"),
                if (details != null) ...[
                  const Divider(),
                  Text("${Translations.getText('additional_details', lang)}:"),
                  // ... render details ...
                ]
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(Translations.getText('close', lang)))
          ],
        );
      },
    );
  }
}

class _RequestItemTile extends StatefulWidget {
  final request_models.EmployeeRequest request;
  final Color statusColor;
  final String statusText;
  final ColorScheme scheme;
  final AppSemanticColors semantic;
  final VoidCallback onTap;
  final IconData requestTypeIcon;
  final String formattedDate;

  const _RequestItemTile({
    required this.request,
    required this.statusColor,
    required this.statusText,
    required this.scheme,
    required this.semantic,
    required this.onTap,
    required this.requestTypeIcon,
    required this.formattedDate,
  });

  @override
  State<_RequestItemTile> createState() => _RequestItemTileState();
}

class _RequestItemTileState extends State<_RequestItemTile> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final double pressScale = _isPressed ? 0.985 : (_isHovered ? 1.005 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Semantics(
          label: '${widget.request.title} - ${widget.statusText}',
          button: true,
          enabled: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
            decoration: BoxDecoration(
              color: _isPressed
                  ? widget.scheme.primary.withValues(alpha: 0.06)
                  : _isHovered
                      ? widget.scheme.primary.withValues(alpha: 0.03)
                      : widget.scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isHovered
                    ? widget.statusColor.withValues(alpha: 0.35)
                    : widget.scheme.outlineVariant.withValues(alpha: 0.5),
                width: _isHovered ? 1.25 : 1,
              ),
              boxShadow: [
                if (_isHovered)
                  BoxShadow(
                    color: widget.statusColor.withValues(alpha: 0.08),
                    blurRadius: 10,
                    spreadRadius: 0,
                    offset: const Offset(0, 3),
                  ),
              ],
            ),
            transform: Matrix4.diagonal3Values(pressScale, pressScale, 1.0),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isHovered
                        ? widget.scheme.primaryContainer.withValues(alpha: 0.92)
                        : widget.scheme.primaryContainer,
                    border: Border.all(
                      color: widget.scheme.primary.withValues(alpha: 0.2),
                      width: 1.1,
                    ),
                    boxShadow: [
                      if (_isHovered)
                        BoxShadow(
                          color: widget.scheme.primary.withValues(alpha: 0.16),
                          blurRadius: 9,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(
                      widget.requestTypeIcon,
                      size: 21,
                      color: widget.scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          height: 1.3,
                          color: _isHovered
                              ? widget.scheme.primary
                              : widget.scheme.onSurface,
                        ),
                        child: Text(
                          widget.request.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: widget.scheme.onSurfaceVariant
                                  .withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.access_time_rounded,
                              size: 12,
                              color: widget.scheme.onSurfaceVariant
                                  .withValues(alpha: 0.82),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.formattedDate,
                            style: TextStyle(
                              color: widget.scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              fontSize: 12.5,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: widget.statusColor.withValues(
                      alpha: _isHovered ? 0.22 : 0.14,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: widget.statusColor.withValues(
                        alpha: _isHovered ? 0.5 : 0.32,
                      ),
                      width: 1.1,
                    ),
                    boxShadow: [
                      if (_isHovered)
                        BoxShadow(
                          color: widget.statusColor.withValues(alpha: 0.2),
                          blurRadius: 7,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: Text(
                    widget.statusText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: widget.statusColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      height: 1.15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionCardWidget extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final int? badgeCount;
  final ColorScheme scheme;
  final AppSemanticColors semantic;
  final String lang;

  const _ActionCardWidget({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.badgeCount,
    required this.scheme,
    required this.semantic,
    required this.lang,
  });

  @override
  State<_ActionCardWidget> createState() => _ActionCardWidgetState();
}

class _ActionCardWidgetState extends State<_ActionCardWidget> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final pressScale = _isPressed ? 0.97 : (_isHovered ? 1.01 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Semantics(
          label: widget.title,
          button: true,
          enabled: true,
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: widget.scheme.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: _isHovered
                        ? widget.color.withValues(alpha: 0.55)
                        : widget.scheme.outlineVariant
                            .withValues(alpha: 0.88),
                    width: _isHovered ? 1.5 : 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_isHovered ? widget.color : widget.scheme.shadow)
                          .withValues(alpha: _isPressed ? 0.18 : 0.06),
                      blurRadius: _isHovered ? 16 : 9,
                      spreadRadius: _isPressed ? 1 : 0,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                transform: Matrix4.diagonal3Values(
                  pressScale,
                  pressScale,
                  1.0,
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(22),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: widget.onTap,
                    borderRadius: BorderRadius.circular(22),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.all(12),
                            constraints: const BoxConstraints(
                              minWidth: 54,
                              minHeight: 54,
                            ),
                            decoration: BoxDecoration(
                              color: widget.color.withValues(
                                alpha: _isHovered ? 0.2 : 0.14,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: widget.color.withValues(alpha: 0.26),
                                width: 1.1,
                              ),
                            ),
                            child: Icon(
                              widget.icon,
                              color: widget.color,
                              size: 32,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Flexible(
                            fit: FlexFit.loose,
                            child: Text(
                              widget.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    height: 1.25,
                                    fontSize: 14,
                                  ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.badgeCount != null && widget.badgeCount! > 0)
                Positioned(
                  top: -8,
                  right: -8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: widget.semantic.warning,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: widget.scheme.surface, width: 2.2),
                      boxShadow: [
                        BoxShadow(
                          color:
                              widget.semantic.warning.withValues(alpha: 0.32),
                          blurRadius: 7,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      '${widget.badgeCount}',
                      style: TextStyle(
                        color: widget.semantic.onWarning,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarDayCell extends StatefulWidget {
  final int dayNumber;
  final DateTime date;
  final bool isToday;
  final bool? isWorking;
  final bool isWeekend;
  final VoidCallback? onTap;
  final Color workBg;
  final Color offBg;
  final Color unknownBg;
  final Color workBorder;
  final Color offBorder;
  final Color unknownBorder;
  final Color successColor;
  final Color errorColor;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color onPrimary;
  final Color primaryColor;
  final Color primaryContainer;
  final Color outlineColor;
  final Color surfaceColor;

  const _CalendarDayCell({
    required this.dayNumber,
    required this.date,
    required this.isToday,
    required this.isWorking,
    required this.isWeekend,
    required this.onTap,
    required this.workBg,
    required this.offBg,
    required this.unknownBg,
    required this.workBorder,
    required this.offBorder,
    required this.unknownBorder,
    required this.successColor,
    required this.errorColor,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.onPrimary,
    required this.primaryColor,
    required this.primaryContainer,
    required this.outlineColor,
    required this.surfaceColor,
  });

  @override
  State<_CalendarDayCell> createState() => _CalendarDayCellState();
}

class _CalendarDayCellState extends State<_CalendarDayCell> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isWork = widget.isWorking;
    final baseBg = isWork == null
        ? widget.unknownBg
        : (isWork ? widget.workBg : widget.offBg);
    final baseBorderColor = isWork == null
        ? widget.unknownBorder
        : (isWork ? widget.workBorder : widget.offBorder);
    final baseFg = isWork == null
        ? widget.onSurfaceVariant.withValues(alpha: 0.92)
        : (isWork
            ? widget.successColor.withValues(alpha: 0.96)
            : widget.errorColor.withValues(alpha: 0.96));

    final pressScale = _isPressed ? 0.94 : (_isHovered ? 1.03 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        child: Semantics(
          label: 'يوم ${widget.dayNumber}',
          button: true,
          enabled: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 230),
            curve: Curves.easeOutCubic,
            decoration: widget.isToday
                ? BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _isPressed
                          ? [
                              widget.primaryColor.withValues(alpha: 0.95),
                              widget.primaryColor,
                            ]
                          : _isHovered
                              ? [
                                  widget.primaryColor.withValues(alpha: 0.90),
                                  widget.primaryColor.withValues(alpha: 0.82),
                                ]
                              : [
                                  widget.primaryColor.withValues(alpha: 0.88),
                                  widget.primaryColor.withValues(alpha: 0.76),
                                ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: widget.onPrimary.withValues(alpha: 0.35),
                      width: 2.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.primaryColor.withValues(
                            alpha: _isPressed ? 0.42 : 0.28),
                        blurRadius: _isPressed ? 18 : 12,
                        spreadRadius: _isPressed ? 1.5 : 0.5,
                        offset: Offset(0, _isPressed ? 4 : 3),
                      ),
                    ],
                  )
                : BoxDecoration(
                    color: _isPressed
                        ? baseBg.withValues(
                            alpha: (baseBg.a + 0.18).clamp(0.0, 1.0))
                        : _isHovered
                            ? baseBg.withValues(
                                alpha: (baseBg.a + 0.10).clamp(0.0, 1.0))
                            : baseBg,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _isHovered
                          ? widget.primaryColor.withValues(alpha: 0.55)
                          : _isPressed
                              ? widget.primaryColor.withValues(alpha: 0.72)
                              : baseBorderColor,
                      width: _isHovered || _isPressed ? 1.4 : 1.1,
                    ),
                    boxShadow: [
                      if (_isHovered || _isPressed)
                        BoxShadow(
                          color: (_isPressed
                                  ? widget.primaryColor
                                  : widget.outlineColor)
                              .withValues(alpha: _isPressed ? 0.22 : 0.13),
                          blurRadius: _isPressed ? 10 : 6,
                          spreadRadius: _isPressed ? 0.8 : 0,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
            transform: Matrix4.diagonal3Values(
              pressScale,
              pressScale,
              1.0,
            ),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontWeight: widget.isToday
                      ? FontWeight.w900
                      : (_isHovered ? FontWeight.w900 : FontWeight.w800),
                  color: widget.isToday
                      ? widget.onPrimary
                      : (_isHovered
                          ? (isWork == null
                              ? widget.onSurface
                              : baseFg.withValues(alpha: 1.0))
                          : baseFg),
                  fontSize: widget.isToday
                      ? 16.0
                      : (_isHovered ? 15.0 : 14.5),
                  letterSpacing: widget.isToday ? 0.3 : 0.2,
                  height: 1.1,
                ),
                child: Text(widget.dayNumber.toString()),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _AttendanceTone { primary, secondary }
