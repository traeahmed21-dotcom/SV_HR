import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/request.dart' as request_models;
import '../models/api_models.dart' as api_models;
import '../services/api_service.dart';
import '../services/approval_permission_service.dart';
import '../config/api_config.dart';
import '../widgets/attachments_widget.dart';
import 'package:provider/provider.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../utils/file_actions.dart';
import '../theme/app_semantic_colors.dart';
import '../widgets/custom_card.dart';

/// شاشة الموافقات - المعتمد نفسه هو من يقوم بالموافقة أو الرفض
/// يتم تحديد المعتمد في الرابط: /api/{ClientId}/approvals/{requestId}/approve/{approverId}
/// أو /api/{ClientId}/approvals/{requestId}/reject/{approverId}
class ApprovalsScreen extends StatefulWidget {
  final String employeeId;
  final api_models.EmployeeData employeeData;

  const ApprovalsScreen({
    super.key,
    required this.employeeId,
    required this.employeeData,
  });

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  List<request_models.EmployeeRequest> _pendingRequests = [];
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  bool _permissionVerified = false;
  bool _isRequestDetailsBusy = false;
  final Map<String, _ApprovalGateInfo> _approvalGateInfo = {};
  final Set<String> _approvalGateLoading = {};
  final Set<String> _cancelledRejectedRequestIds = {};

  @override
  void initState() {
    super.initState();
    _verifyApprovalPermissionGate();
  }

  Future<void> _verifyApprovalPermissionGate() async {
    bool hasPermission = false;

    try {
      final perm = ApprovalPermissionService.currentCached;
      if (perm.isValid && perm.verifySignatureIntegrity()) {
        hasPermission = perm.canApproveForContext(
          targetClientId: widget.employeeData.clientID,
          targetEmployeeId: widget.employeeData.employeeID,
          targetEmployeeNumber: widget.employeeData.employeeNumber,
        );
      }
    } catch (_) {}

    if (!hasPermission) {
      try {
        final persisted = await ApprovalPermissionService.loadPersisted();
        if (persisted != null && persisted.isNotEmpty) {
          final decoded = SecureApprovalPermission.fromSecureJson(persisted);
          if (decoded.isValid && decoded.verifySignatureIntegrity()) {
            hasPermission = decoded.canApproveForContext(
              targetClientId: widget.employeeData.clientID,
              targetEmployeeId: widget.employeeData.employeeID,
              targetEmployeeNumber: widget.employeeData.employeeNumber,
            );
            if (hasPermission) {
              ApprovalPermissionService.updateCached(decoded);
            }
          }
        }
      } catch (_) {}
    }

    if (!hasPermission) {
      try {
        final embedded = widget.employeeData.embeddedApprovalPermission;
        if (embedded != null &&
            embedded.isValid &&
            embedded.verifySignatureIntegrity()) {
          hasPermission = embedded.canApproveForContext(
            targetClientId: widget.employeeData.clientID,
            targetEmployeeId: widget.employeeData.employeeID,
            targetEmployeeNumber: widget.employeeData.employeeNumber,
          );
          if (hasPermission) {
            ApprovalPermissionService.updateCached(embedded);
          }
        }
      } catch (_) {}
    }

    if (!hasPermission) {
      final rules = (widget.employeeData.rules).toLowerCase();
      final serverProbe = await ApiService.getPendingRequestsForApproval(
        widget.employeeData.clientID,
        approverId: int.tryParse(widget.employeeData.employeeNumber) ??
            widget.employeeData.employeeID,
      ).catchError((_) => <String, dynamic>{'Success': false, 'Data': []});
      final probeData = serverProbe['Data'] as List<dynamic>?;
      final hasAccess = serverProbe['HasApprovalAccess'] == true ||
          (serverProbe['HasApprovalAccess'] is String &&
              serverProbe['HasApprovalAccess'].toString().toLowerCase() ==
                  'true') ||
          (probeData != null && probeData.isNotEmpty);
      if (hasAccess) {
        final finalPerm = ApprovalPermissionService.evaluateApproverFromSignals(
          clientId: widget.employeeData.clientID,
          employeeId: widget.employeeData.employeeID,
          employeeNumber: widget.employeeData.employeeNumber,
          rulesRaw: rules,
          serverApprovalAccess: serverProbe['HasApprovalAccess'] == true ||
              (serverProbe['HasApprovalAccess'] is String &&
                  serverProbe['HasApprovalAccess']
                      .toString()
                      .toLowerCase() ==
                      'true'),
          pendingApprovalItems: probeData ?? const [],
        );
        hasPermission = finalPerm.isValid &&
            finalPerm.verifySignatureIntegrity() &&
            finalPerm.isApprover;
        if (hasPermission) {
          ApprovalPermissionService.updateCached(finalPerm);
          try {
            await ApprovalPermissionService.persistSecurely(
                finalPerm.toSecureJson());
          } catch (_) {}
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _permissionVerified = true;
      _hasError = !hasPermission;
      _errorMessage = hasPermission
          ? ''
          : Translations.getText(
              'approvals_no_permission',
              Provider.of<LanguageService>(context, listen: false)
                  .currentLocale
                  .languageCode,
            ).isEmpty
              ? 'ليس لديك صلاحية للوصول إلى قسم الموافقات'
              : Translations.getText(
                  'approvals_no_permission',
                  Provider.of<LanguageService>(context, listen: false)
                      .currentLocale
                      .languageCode,
                );
      _isLoading = false;
    });

    if (hasPermission) {
      _loadPendingRequests();
    }
  }

  Future<void> _denyAccessAndPop() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage.isEmpty
                    ? 'ليس لديك صلاحية للوصول إلى قسم الموافقات'
                    : _errorMessage,
                style: const TextStyle(
                  fontFamily: 'Tajawal',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted) Navigator.of(context).maybePop();
  }

  String get _cancelledRejectedPrefsKey =>
      'cancelled_rejected_requests_${widget.employeeData.clientID}_${widget.employeeData.employeeID}';

  Future<void> _loadCancelledRejectedRequestIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_cancelledRejectedPrefsKey) ?? const <String>[];
    _cancelledRejectedRequestIds
      ..clear()
      ..addAll(ids);
  }

  Future<void> _saveCancelledRejectedRequestIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _cancelledRejectedPrefsKey,
      _cancelledRejectedRequestIds.toList(),
    );
  }

  Future<void> _loadPendingRequests() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      await _loadCancelledRejectedRequestIds();

      // جلب الطلبات المعلقة من API
      final result = await _fetchPendingRequestsFromAPI();
      final filtered = result.requests
          .where((r) =>
              !(r.status == request_models.RequestStatus.rejected &&
                  _cancelledRejectedRequestIds.contains(r.id)))
          .toList();
      setState(() {
        _pendingRequests = filtered;
        _approvalGateInfo
          ..clear()
          ..addAll(result.gateInfo);
        _isLoading = false;
      });
      _prefetchApprovalGateInfo(filtered);
    } catch (e) {
      if (mounted) {
        setState(() {
          final languageService = Provider.of<LanguageService>(context, listen: false);
          final lang = languageService.currentLocale.languageCode;
          _errorMessage = '${Translations.getText('error_fetching_requests', lang)}: $e';
          _hasError = true;
          _isLoading = false;
        });
      }
    }
  }

  void _prefetchApprovalGateInfo(List<request_models.EmployeeRequest> requests) {
    for (final r in requests) {
      _loadApprovalGateInfo(r.id);
    }
  }

  Future<_ApprovalGateInfo?> _loadApprovalGateInfo(String requestId) async {
    if (_approvalGateInfo.containsKey(requestId) ||
        _approvalGateLoading.contains(requestId)) {
      return _approvalGateInfo[requestId];
    }

    _approvalGateLoading.add(requestId);
    try {
      final response = await ApiService.getApprovalDetails(
        widget.employeeData.clientID,
        requestId,
      );

      if (response['Success'] == true) {
        final data = response['Data'];
        final approvalsRaw = data is Map<String, dynamic> ? data['Approvals'] : null;
        final approvals = approvalsRaw is List ? approvalsRaw : const <dynamic>[];
        final info = _computeApprovalGateInfo(approvals);
        if (mounted) {
          setState(() {
            _approvalGateInfo[requestId] = info;
          });
        } else {
          _approvalGateInfo[requestId] = info;
        }
        return info;
      }

      return null;
    } finally {
      _approvalGateLoading.remove(requestId);
    }
  }

  _ApprovalGateInfo _computeApprovalGateInfo(List approvals) {
    final approverIdCandidates = <int>{widget.employeeData.employeeID};
    final employeeNumberInt = int.tryParse(widget.employeeData.employeeNumber);
    if (employeeNumberInt != null) {
      approverIdCandidates.add(employeeNumberInt);
    }

    int? myStepOrder;
    int? minPendingStepOrder;
    int? firstStepOrder;
    final stepOrders = <int>{};

    final parsed = approvals
        .whereType<Map>()
        .map((a) => Map<String, dynamic>.from(a as Map))
        .toList();

    for (final a in parsed) {
      final step = a['StepOrder'];
      final status = (a['Status']?.toString() ?? '').trim();
      final stepOrder = step is int ? step : int.tryParse(step?.toString() ?? '');
      if (stepOrder == null) continue;

      stepOrders.add(stepOrder);
      firstStepOrder = firstStepOrder == null ? stepOrder : min(firstStepOrder!, stepOrder);

      if (status.toLowerCase() == 'pending') {
        minPendingStepOrder = minPendingStepOrder == null
            ? stepOrder
            : min(minPendingStepOrder!, stepOrder);
      }

      final aApproverId = a['ApproverID'];
      final aApproverIdInt = aApproverId is int ? aApproverId : int.tryParse(aApproverId?.toString() ?? '');
      if (aApproverIdInt != null &&
          approverIdCandidates.contains(aApproverIdInt) &&
          status.toLowerCase() == 'pending') {
        myStepOrder = myStepOrder == null ? stepOrder : min(myStepOrder!, stepOrder);
      }
    }

    if (myStepOrder == null || firstStepOrder == null) {
      return const _ApprovalGateInfo.unknown();
    }

    final isSecondOrLater = myStepOrder! > firstStepOrder!;
    final sortedSteps = stepOrders.toList()..sort();
    final totalSteps = sortedSteps.length;
    int completedSteps = 0;
    if (totalSteps > 0) {
      if (minPendingStepOrder == null) {
        completedSteps = totalSteps;
      } else {
        final idx = sortedSteps.indexOf(minPendingStepOrder!);
        completedSteps = idx >= 0 ? idx : 0;
      }
    }

    bool firstStepApproved = false;
    final firstStepApprovals = parsed.where((a) {
      final step = a['StepOrder'];
      final stepOrder = step is int ? step : int.tryParse(step?.toString() ?? '');
      return stepOrder == firstStepOrder;
    }).toList();

    if (firstStepApprovals.isNotEmpty) {
      firstStepApproved = firstStepApprovals.every((a) {
        final status = (a['Status']?.toString() ?? '').trim().toLowerCase();
        return status == 'approved';
      });
    }

    String? blockedByNames;
    bool canAct = true;
    if (minPendingStepOrder != null && myStepOrder != minPendingStepOrder) {
      canAct = false;
      final blockingStep = minPendingStepOrder!;
      final names = parsed.where((a) {
        final step = a['StepOrder'];
        final status = (a['Status']?.toString() ?? '').trim().toLowerCase();
        final stepOrder = step is int ? step : int.tryParse(step?.toString() ?? '');
        return stepOrder == blockingStep && status != 'approved';
      }).map((a) => (a['ApproverName']?.toString() ?? '').trim()).where((n) => n.isNotEmpty).toSet().toList();
      if (names.isNotEmpty) {
        blockedByNames = names.join('، ');
      }
    }

    return _ApprovalGateInfo(
      canAct: canAct,
      myStepOrder: myStepOrder,
      currentStepOrder: minPendingStepOrder,
      isSecondOrLater: isSecondOrLater,
      firstStepApproved: firstStepApproved,
      blockedByNames: blockedByNames,
      totalSteps: totalSteps,
      completedSteps: completedSteps,
    );
  }

  Future<bool> _ensureCanActOnRequest(request_models.EmployeeRequest request) async {
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    final info = _approvalGateInfo[request.id] ?? await _loadApprovalGateInfo(request.id);
    if (info == null) return true;
    if (info.isUnknown) return true;

    if (!info.canAct) {
      final message = info.blockedByNames != null && info.blockedByNames!.isNotEmpty
          ? 'لا يمكنك اتخاذ إجراء الآن. الطلب بانتظار موافقة: ${info.blockedByNames}.'
          : 'لا يمكنك اتخاذ إجراء الآن. الطلب بانتظار موافقة المعتمد السابق.';

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(Translations.getText('cannot_approve_now', lang)),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(Translations.getText('ok', lang)),
              ),
            ],
          ),
        );
      }
      return false;
    }

    return true;
  }

  String _formatApprovalErrorMessage(String rawMessage) {
    var msg = rawMessage.trim();
    msg = msg.replaceFirst(RegExp(r'^\s*this\s*:\s*', caseSensitive: false), '');
    msg = msg.replaceAll(RegExp(r'\s+'), ' ').trim();

    final lower = msg.toLowerCase();

    if (msg.contains('لا يمكن الموافقة/الرفض قبل موافقة المعتمد السابق') ||
        msg.contains('لا يمكن الموافقة قبل موافقة المعتمد السابق')) {
      return 'لا يمكنك الموافقة الآن لأن الطلب بانتظار موافقة المعتمد السابق حسب التسلسل.';
    }

    if (lower.contains('sqltransaction has completed')) {
      return 'لا يمكنك الموافقة الآن لأن الطلب بانتظار موافقة المعتمد السابق. حدّث الصفحة وحاول بعد موافقته.';
    }

    if (msg.contains('لا توجد موافقة معلقة لهذا المعتمد')) {
      return 'لا يمكنك تنفيذ الإجراء لأن هذا الطلب ليس ضمن قائمة الموافقات الخاصة بك حالياً. حدّث القائمة ثم حاول مرة أخرى.';
    }

    if (lower.contains('timeout') || msg.contains('انتهت مهلة')) {
      return 'تعذر الاتصال بالخادم. حاول مرة أخرى.';
    }

    if (msg.isEmpty) return 'تعذر تنفيذ العملية حالياً. حاول مرة أخرى.';
    return msg;
  }

  Future<_PendingRequestsResult> _fetchPendingRequestsFromAPI() async {
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;
    try {
      print('🔍 جلب الطلبات المعلقة للموافقة...');
      print('👤 المعتمد: ${widget.employeeData.employeeID}');
      print('🏢 Client ID: ${widget.employeeData.clientID}');

      final approverIdToSend =
          int.tryParse(widget.employeeData.employeeNumber) ??
              widget.employeeData.employeeID;

      // استخدام API لجلب الطلبات المعلقة للموافقة للمعتمد الحالي
      final response = await ApiService.getPendingRequestsForApproval(
        widget.employeeData.clientID,
        approverId: approverIdToSend, // المعتمد الحالي
      );

      print('📡 استجابة جلب الطلبات المعلقة: $response');

      if (response['Success'] == true) {
        final List<dynamic> data = response['Data'] ?? [];
        print('✅ تم جلب ${data.length} طلب معلق');
        final requests = <request_models.EmployeeRequest>[];
        final gateInfo = <String, _ApprovalGateInfo>{};

        for (final item in data) {
          if (item is! Map<String, dynamic>) continue;

          final request = _parseRequestFromAPI(item);
          requests.add(request);

          final totalSteps = int.tryParse(item['TotalSteps']?.toString() ?? '') ??
              (item['TotalSteps'] is int ? item['TotalSteps'] as int : 0);
          final completedSteps = int.tryParse(item['CompletedSteps']?.toString() ?? '') ??
              (item['CompletedSteps'] is int ? item['CompletedSteps'] as int : 0);
          final currentStepOrder = int.tryParse(item['CurrentStepOrder']?.toString() ?? '') ??
              (item['CurrentStepOrder'] is int ? item['CurrentStepOrder'] as int : 0);
          final firstStepOrder = int.tryParse(item['FirstStepOrder']?.toString() ?? '') ??
              (item['FirstStepOrder'] is int ? item['FirstStepOrder'] as int : 0);
          final myStepOrder = int.tryParse(item['MyStepOrder']?.toString() ?? '') ??
              (item['MyStepOrder'] is int ? item['MyStepOrder'] as int : 0);
          final firstStepApprovedRaw = item['FirstStepApproved'];
          final firstStepApproved = firstStepApprovedRaw == true ||
              (firstStepApprovedRaw is String &&
                  firstStepApprovedRaw.toLowerCase() == 'true');

          if (totalSteps > 0) {
            final canAct = myStepOrder > 0 && currentStepOrder > 0
                ? myStepOrder == currentStepOrder
                : true;
            gateInfo[request.id] = _ApprovalGateInfo(
              canAct: canAct,
              myStepOrder: myStepOrder > 0 ? myStepOrder : null,
              currentStepOrder: currentStepOrder > 0 ? currentStepOrder : null,
              isSecondOrLater:
                  myStepOrder > 0 && firstStepOrder > 0 && myStepOrder > firstStepOrder,
              firstStepApproved: firstStepApproved,
              blockedByNames: null,
              totalSteps: totalSteps,
              completedSteps: completedSteps,
            );
          }
        }

        return _PendingRequestsResult(
          requests: requests,
          gateInfo: gateInfo,
        );
      } else {
        final message =
            (response['Message'] ?? 'فشل في جلب الطلبات المعلقة').toString();
        print('❌ فشل في جلب الطلبات المعلقة: $message');
        throw Exception(message);
      }
    } catch (e) {
      print('💥 فشل في جلب الطلبات المعلقة من API: $e');
      rethrow;
    }
  }

  request_models.EmployeeRequest _parseRequestFromAPI(
      Map<String, dynamic> json) {
    try {
      // تحويل البيانات من API إلى نموذج EmployeeRequest
      String statusStr = json['Status']?.toString() ?? 'pending';
      request_models.RequestStatus status;

      switch (statusStr.toLowerCase()) {
        case 'pending':
          status = request_models.RequestStatus.pending;
          break;
        case 'approved':
          status = request_models.RequestStatus.approved;
          break;
        case 'rejected':
          status = request_models.RequestStatus.rejected;
          break;
        case 'cancelled':
          status = request_models.RequestStatus.cancelled;
          break;
        default:
          status = request_models.RequestStatus.pending;
      }

      // التأكد من أن RequestID هو رقم صحيح
      String requestId = '';
      if (json['RequestID'] != null) {
        if (json['RequestID'] is int) {
          requestId = json['RequestID'].toString();
        } else if (json['RequestID'] is String) {
          requestId = json['RequestID'];
        } else {
          requestId = json['RequestID'].toString();
        }
      }

      // تحليل التواريخ
      DateTime startDate = DateTime.now();
      DateTime endDate = DateTime.now();
      DateTime createdAt = DateTime.now();

      try {
        if (json['StartDate'] != null &&
            json['StartDate'].toString().isNotEmpty) {
          startDate = DateTime.parse(json['StartDate'].toString());
        }
        if (json['EndDate'] != null && json['EndDate'].toString().isNotEmpty) {
          endDate = DateTime.parse(json['EndDate'].toString());
        }
        if (json['CreatedDate'] != null &&
            json['CreatedDate'].toString().isNotEmpty) {
          createdAt = DateTime.parse(json['CreatedDate'].toString());
        }
      } catch (e) {
        print('خطأ في تحليل التواريخ: $e');
      }

      return request_models.EmployeeRequest(
        id: requestId,
        requestNumber: json['RequestNumber']?.toString() ?? '',
        employeeId: json['EmployeeID']?.toString() ?? '',
        employeeName: json['EmployeeName']?.toString() ?? 'موظف غير محدد',
        type: _parseRequestType(json['RequestTypeName']?.toString()),
        title: json['RequestTypeName']?.toString() ?? '',
        description:
            json['Description']?.toString() ?? json['Reason']?.toString() ?? '',
        startDate: startDate,
        endDate: endDate,
        status: status,
        priority: json['Priority']?.toString() ?? 'Normal',
        createdAt: createdAt,
        approvedBy: json['Approvers']?.toString(),
        rejectionReason: null,
        employeeNumber: json['RequestNumber']?.toString() ?? '',
      );
    } catch (e) {
      print('خطأ في تحليل بيانات الطلب: $e');
      // إرجاع طلب افتراضي في حالة الخطأ
      return request_models.EmployeeRequest(
        id: 'error',
        requestNumber: 'ERROR',
        employeeId: '',
        employeeName: 'خطأ في تحميل البيانات',
        type: request_models.RequestType.other,
        title: 'خطأ في تحميل البيانات',
        description: 'حدث خطأ في تحميل بيانات الطلب',
        startDate: DateTime.now(),
        endDate: DateTime.now(),
        status: request_models.RequestStatus.pending,
        priority: 'Normal',
        createdAt: DateTime.now(),
        approvedBy: null,
        rejectionReason: null,
        employeeNumber: '',
      );
    }
  }

  request_models.RequestType _parseRequestType(String? typeName) {
    if (typeName == null || typeName.isEmpty) {
      return request_models.RequestType.other;
    }

    if (typeName.contains('سلفة')) {
      return request_models.RequestType.loan;
    } else if (typeName.contains('إجازة')) {
      return request_models.RequestType.leave;
    }
    return request_models.RequestType.other;
  }

  Future<void> _approveRequest(request_models.EmployeeRequest request) async {
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    final canAct = await _ensureCanActOnRequest(request);
    if (!canAct) return;

    // إظهار dialog للتأكيد
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(Translations.getText('confirm_approval', lang)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Translations.getText('confirm_approval_msg', lang)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      Translations.getText('auto_execute_info', lang),
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(Translations.getText('cancel', lang)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: Text(Translations.getText('approve', lang)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // إظهار loading dialog
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    bool loadingVisible = false;

    void closeLoadingIfVisible() {
      if (!mounted) return;
      if (!loadingVisible) return;
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      loadingVisible = false;
    }

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text(Translations.getText('approving_request', lang)),
              ],
            ),
          ),
        );
      },
    );
    loadingVisible = true;

    try {
      print('🚀 بدء عملية الموافقة على الطلب...');
      print('🆔 Request ID: ${request.id}');
      print('👤 Approver ID: ${widget.employeeData.employeeID}');
      print('🏢 Client ID: ${widget.employeeData.clientID}');
      print(
          '🔗 API URL: ${ApiConfig.baseUrl}/api/${widget.employeeData.clientID}/approvals/${request.id}/approve/${widget.employeeData.employeeID}');
      print('📋 Method: POST');
      print('📋 Headers: Content-Type: application/json');
      print('📋 Body: {"Comments": "تمت الموافقة"}');

      // استدعاء API للموافقة على الطلب من قبل المعتمد نفسه
      final response = await ApiService.approveRequest(
        widget.employeeData.clientID,
        requestId: request.id,
        approverId: widget.employeeData.employeeID, // المعتمد نفسه
        approved: true,
        rejectionReason: null, // لا يوجد سبب رفض للموافقة
      );

      print('📡 استجابة الموافقة على الطلب: $response');

      // إغلاق loading dialog
      closeLoadingIfVisible();

      if (response['Success'] == true) {
        // إزالة الطلب من القائمة
        setState(() {
          _pendingRequests.removeWhere((r) => r.id == request.id);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response['Message'] ?? Translations.getText('request_approved_success', lang)),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final message = (response['Message'] ??
                Translations.getText('approval_failed', lang))
            .toString();
        final formatted = _formatApprovalErrorMessage(message);
        if (mounted) {
          await showDialog(
            context: context,
            useRootNavigator: true,
            builder: (context) => AlertDialog(
              title: Text(Translations.getText('cannot_approve_now', lang)),
              content: Text(formatted),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(Translations.getText('ok', lang)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      // إغلاق loading dialog
      closeLoadingIfVisible();

      if (mounted) {
        await showDialog(
          context: context,
          useRootNavigator: true,
          builder: (context) => AlertDialog(
            title: Text(Translations.getText('cannot_approve_now', lang)),
            content: Text(_formatApprovalErrorMessage(e.toString())),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(Translations.getText('ok', lang)),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(request_models.EmployeeRequest request) async {
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    final canAct = await _ensureCanActOnRequest(request);
    if (!canAct) return;

    // إظهار dialog للتأكيد أولاً
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(Translations.getText('confirm_rejection', lang)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Translations.getText('confirm_rejection_msg', lang)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      Translations.getText('rejection_final_warning', lang),
                      style: const TextStyle(
                        color: Colors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(Translations.getText('cancel', lang)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: Text(Translations.getText('reject', lang)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // إظهار dialog لإدخال سبب الرفض
    final TextEditingController reasonController = TextEditingController();

    final rejectionReason = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: Text(Translations.getText('rejection_reason', lang)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(Translations.getText('enter_rejection_reason', lang)),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: Translations.getText('rejection_reason_hint', lang),
                labelText: Translations.getText('rejection_reason', lang),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                Translations.getText('rejection_visible_to_employee', lang),
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(Translations.getText('cancel', lang)),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(Translations.getText('enter_rejection_reason', lang)),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(reasonController.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: Text(Translations.getText('reject', lang)),
          ),
        ],
      ),
    );

    if (rejectionReason == null || rejectionReason.isEmpty) return;

    // إظهار loading dialog
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    bool loadingVisible = false;

    void closeLoadingIfVisible() {
      if (!mounted) return;
      if (!loadingVisible) return;
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      loadingVisible = false;
    }

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text(Translations.getText('approving_request', lang)),
              ],
            ),
          ),
        );
      },
    );
    loadingVisible = true;

    try {
      print('🚀 بدء عملية رفض الطلب...');
      print('🆔 Request ID: ${request.id}');
      print('👤 Approver ID: ${widget.employeeData.employeeID}');
      print('🏢 Client ID: ${widget.employeeData.clientID}');
      print('❌ سبب الرفض: $rejectionReason');
      print(
          '🔗 API URL: ${ApiConfig.baseUrl}/api/${widget.employeeData.clientID}/approvals/${request.id}/reject/${widget.employeeData.employeeID}');
      print('📋 Method: POST');
      print('📋 Headers: Content-Type: application/json');
      print('📋 Body: {"Comments": "$rejectionReason"}');

      // استدعاء API لرفض الطلب من قبل المعتمد نفسه
      final response = await ApiService.approveRequest(
        widget.employeeData.clientID,
        requestId: request.id,
        approverId: widget.employeeData.employeeID, // المعتمد نفسه
        approved: false,
        rejectionReason: rejectionReason,
      );

      print('📡 استجابة رفض الطلب: $response');

      // إغلاق loading dialog
      closeLoadingIfVisible();

      if (response['Success'] == true) {
        // إزالة الطلب من القائمة
        setState(() {
          _pendingRequests.removeWhere((r) => r.id == request.id);
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(response['Message'] ?? Translations.getText('request_rejected_success', lang)),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        final message =
            (response['Message'] ?? Translations.getText('rejection_failed', lang))
                .toString();
        final formatted = _formatApprovalErrorMessage(message);
        if (mounted) {
          await showDialog(
            context: context,
            useRootNavigator: true,
            builder: (context) => AlertDialog(
              title: Text(Translations.getText('cannot_reject_now', lang)),
              content: Text(formatted),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(Translations.getText('ok', lang)),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      // إغلاق loading dialog
      closeLoadingIfVisible();

      if (mounted) {
        await showDialog(
          context: context,
          useRootNavigator: true,
          builder: (context) => AlertDialog(
            title: Text(Translations.getText('cannot_reject_now', lang)),
            content: Text(_formatApprovalErrorMessage(e.toString())),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(Translations.getText('ok', lang)),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Translations.getText('approvals', lang),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${Translations.getText('approver', lang)}: ${widget.employeeData.name}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingRequests,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(Translations.getText('approval_info', lang)),
                  content: Text(Translations.getText('approval_info_details', lang)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(Translations.getText('confirm', lang)),
                    ),
                  ],
                ),
              );
            },
            tooltip: 'معلومات',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              Translations.getText('loading', lang),
              style: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    if (_hasError) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: scheme.error,
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
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadPendingRequests,
              icon: const Icon(Icons.refresh),
              label: Text(Translations.getText('retry', lang)),
            ),
          ],
        ),
      );
    }

    if (_pendingRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.approval,
                size: 80,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              Translations.getText('no_pending_requests', lang),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Translations.getText('all_requests_processed', lang),
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPendingRequests,
              icon: const Icon(Icons.refresh),
              label: Text(Translations.getText('refresh', lang)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header with statistics
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.approval,
                  color: Color(0xFF0EA5E9),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الطلبات المعلقة',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${_pendingRequests.length} طلب يحتاج موافقة',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _loadPendingRequests,
                icon: const Icon(Icons.refresh),
                tooltip: 'تحديث',
              ),
            ],
          ),
        ),
        // Requests list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadPendingRequests,
            color: const Color(0xFF0EA5E9),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pendingRequests.length,
              itemBuilder: (context, index) {
                final request = _pendingRequests[index];
                return _buildRequestCard(request);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(request_models.EmployeeRequest request) {
    try {
      final lang =
          Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
      // تحديد حالة الطلب
      final bool canApprove =
          request.status == request_models.RequestStatus.pending;
      final gateInfo = _approvalGateInfo[request.id];
      final bool canActOnThisRequest =
          gateInfo == null || gateInfo.isUnknown || gateInfo.canAct;
      String? gateIndicatorText;
      Color? gateIndicatorColor;
      IconData? gateIndicatorIcon;
      String? gateProgressText;
      Color? gateProgressColor;
      IconData? gateProgressIcon;
      String? firstApproverStatusText;
      Color? firstApproverStatusColor;
      IconData? firstApproverStatusIcon;

      if (gateInfo != null &&
          !gateInfo.isUnknown &&
          gateInfo.totalSteps > 1) {
        gateProgressText = 'الاعتمادات: ${gateInfo.completedSteps}/${gateInfo.totalSteps}';
        gateProgressColor = gateInfo.completedSteps > 0
            ? const Color(0xFF10B981)
            : const Color(0xFFF59E0B);
        gateProgressIcon = Icons.format_list_numbered;

        if (gateInfo.totalSteps >= 2) {
          firstApproverStatusText = gateInfo.firstStepApproved
              ? 'اعتماد المعتمد الأول: تم'
              : 'اعتماد المعتمد الأول: لم يتم';
          firstApproverStatusColor = gateInfo.firstStepApproved
              ? const Color(0xFF10B981)
              : const Color(0xFFF59E0B);
          firstApproverStatusIcon = gateInfo.firstStepApproved
              ? Icons.verified
              : Icons.pending_actions;
        }
      }

      if (gateInfo != null && !gateInfo.isUnknown && gateInfo.isSecondOrLater) {
        if (!gateInfo.canAct) {
          gateIndicatorText = gateInfo.blockedByNames != null &&
                  gateInfo.blockedByNames!.isNotEmpty
              ? 'بانتظار موافقة: ${gateInfo.blockedByNames}'
              : 'بانتظار موافقة المعتمد الأول';
          gateIndicatorColor = const Color(0xFFF59E0B);
          gateIndicatorIcon = Icons.lock_clock;
        }
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showRequestDetails(request),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _getRequestTypeColor(request.type)
                              .withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _getRequestTypeIcon(request.type),
                          color: _getRequestTypeColor(request.type),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.title ?? 'طلب غير محدد',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'من: ${request.employeeName ?? 'موظف غير محدد'} (${request.employeeNumber ?? 'غير محدد'})',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                            if (request.description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                request.description,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getStatusColor(request.status)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _getStatusIcon(request.status),
                                  size: 16,
                                  color: _getStatusColor(request.status),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getStatusText(request.status.name),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _getStatusColor(request.status),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (gateIndicatorText != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: gateIndicatorColor!.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: gateIndicatorColor!.withOpacity(0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    gateIndicatorIcon!,
                                    size: 14,
                                    color: gateIndicatorColor,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    gateIndicatorText!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: gateIndicatorColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (gateProgressText != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: gateProgressColor!.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: gateProgressColor!.withOpacity(0.25),
                                ),
                              ),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 220),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      gateProgressIcon!,
                                      size: 14,
                                      color: gateProgressColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        gateProgressText!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: gateProgressColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (firstApproverStatusText != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color:
                                    firstApproverStatusColor!.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: firstApproverStatusColor!
                                      .withOpacity(0.25),
                                ),
                              ),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 220),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      firstApproverStatusIcon!,
                                      size: 14,
                                      color: firstApproverStatusColor,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        firstApproverStatusText!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: firstApproverStatusColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        '${_formatDate(request.startDate)} - ${_formatDate(request.endDate)}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Spacer(),
                      Icon(Icons.access_time, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(request.createdAt),
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  // عرض أزرار الموافقة فقط إذا كان الطلب معلق
                  if (canApprove) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: canActOnThisRequest
                                ? () => _approveRequest(request)
                                : null,
                            icon: const Icon(Icons.check, size: 16),
                            label: Text(Translations.getText('approve', lang)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  const Color(0xFF10B981).withOpacity(0.35),
                              disabledForegroundColor:
                                  Colors.white.withOpacity(0.9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: canActOnThisRequest
                                ? () => _rejectRequest(request)
                                : null,
                            icon: const Icon(Icons.close, size: 16),
                            label: Text(Translations.getText('reject', lang)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  const Color(0xFFEF4444).withOpacity(0.35),
                              disabledForegroundColor:
                                  Colors.white.withOpacity(0.9),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    // عرض رسالة حالة الطلب إذا لم يكن معلق
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStatusColor(request.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              _getStatusColor(request.status).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getStatusIcon(request.status),
                            color: _getStatusColor(request.status),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getStatusMessage(request.status),
                              style: TextStyle(
                                color: _getStatusColor(request.status),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (request.status == request_models.RequestStatus.rejected) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: OutlinedButton.icon(
                          onPressed: () => _cancelRejectedRequestCard(request),
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('إلغاء'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6B7280),
                            side: BorderSide(
                              color: const Color(0xFF6B7280).withOpacity(0.4),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      print('خطأ في بناء بطاقة الطلب: $e');
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'خطأ في عرض الطلب',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'حدث خطأ في عرض بيانات الطلب: $e',
              style: TextStyle(
                fontSize: 14,
                color: Colors.red,
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cancelRejectedRequestCard(
      request_models.EmployeeRequest request) async {
    if (request.status != request_models.RequestStatus.rejected) return;

    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('سيتم إلغاء عرض هذا الطلب ولن يظهر لك مرة أخرى.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(Translations.getText('cancel', lang)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    _cancelledRejectedRequestIds.add(request.id);
    await _saveCancelledRejectedRequestIds();

    if (!mounted) return;

    setState(() {
      _pendingRequests.removeWhere((r) => r.id == request.id);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم الإلغاء ولن يظهر الطلب مرة أخرى')),
    );
  }

  Color _getRequestTypeColor(request_models.RequestType type) {
    switch (type) {
      case request_models.RequestType.loan:
        return const Color(0xFF8B5CF6); // Purple
      case request_models.RequestType.leave:
        return const Color(0xFF06B6D4); // Cyan
      case request_models.RequestType.overtime:
        return const Color(0xFFF59E0B); // Amber
      case request_models.RequestType.sick:
        return const Color(0xFFEF4444); // Red
      case request_models.RequestType.vacation:
        return const Color(0xFF10B981); // Green
      case request_models.RequestType.other:
        return const Color(0xFF6B7280); // Gray
      default:
        return const Color(0xFF6B7280); // default return
    }
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
      default:
        return Icons.assignment; // default return
    }
  }

  String _formatDate(DateTime date) {
    try {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (e) {
      print('خطأ في تنسيق التاريخ: $e');
      return 'غير محدد';
    }
  }

  String _formatDateTime(String? dateString) {
    if (dateString == null || dateString.isEmpty) return 'غير محدد';

    try {
      final date = DateTime.parse(dateString);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      print('خطأ في تنسيق التاريخ: $e');
      return dateString;
    }
  }

  void _showRequestDetails(request_models.EmployeeRequest request) async {
    if (_isRequestDetailsBusy) return;
    _isRequestDetailsBusy = true;

    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    bool loadingVisible = false;

    void closeLoadingIfVisible() {
      if (!mounted) return;
      if (!loadingVisible) return;
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }
      loadingVisible = false;
    }

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Text(Translations.getText('loading_request_details', lang)),
              ],
            ),
          ),
        );
      },
    );
    loadingVisible = true;

    try {
      // تحويل request.id إلى رقم
      int requestId;
      try {
        requestId = int.parse(request.id);
      } catch (e) {
        closeLoadingIfVisible();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Translations.getTextWithParams(
                'invalid_request_id_with_id',
                lang,
                {'id': request.id},
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // جلب تفاصيل الطلب باستخدام الدالة الجديدة
      final requestDetails = await _loadRequestDetails(requestId);

      // إغلاق loading dialog
      closeLoadingIfVisible();

      if (requestDetails == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Translations.getText('no_request_data_available', lang)),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final requestData = requestDetails['Request'];
      final additionalDetails = requestDetails['AdditionalDetails'];
      final approvals = requestDetails['Approvals'];
      final attachments = requestDetails['Attachments'];

      print('📋 تفاصيل الطلب: $requestData');
      print('📋 التفاصيل الإضافية: $additionalDetails');
      print('📋 نوع التفاصيل الإضافية: ${additionalDetails?.runtimeType}');
      print('📋 الموافقات: $approvals');
      print('📋 المرفقات: $attachments');

      // تحليل مفصل للتفاصيل الإضافية
      if (additionalDetails != null) {
        print('🔍 تحليل مفصل للتفاصيل الإضافية:');
        if (additionalDetails is Map<String, dynamic>) {
          final details = additionalDetails;
          print('📋 نوع البيانات: Map<String, dynamic>');
          print('📋 المفاتيح المتاحة: ${details.keys.toList()}');
          print('📋 محتوى البيانات: $details');

          // التحقق من وجود حقول الإجازة
          if (details.containsKey('LeaveTypeName')) {
            print('✅ يوجد LeaveTypeName: ${details['LeaveTypeName']}');
          }
          if (details.containsKey('LeaveDays')) {
            print('✅ يوجد LeaveDays: ${details['LeaveDays']}');
          }
          if (details.containsKey('LeaveStartDate')) {
            print('✅ يوجد LeaveStartDate: ${details['LeaveStartDate']}');
          }
          if (details.containsKey('LeaveEndDate')) {
            print('✅ يوجد LeaveEndDate: ${details['LeaveEndDate']}');
          }
          if (details.containsKey('StartDate')) {
            print('✅ يوجد StartDate: ${details['StartDate']}');
          }
          if (details.containsKey('EndDate')) {
            print('✅ يوجد EndDate: ${details['EndDate']}');
          }
          if (details.containsKey('Days')) {
            print('✅ يوجد Days: ${details['Days']}');
          }

          // التحقق من نوع الطلب
          if (requestData != null && requestData is Map<String, dynamic>) {
            final request = requestData;
            print('📋 نوع الطلب: ${request['RequestTypeName']}');
            print('📋 RequestTypeID: ${request['RequestTypeID']}');
          }
        } else {
          print('❌ نوع البيانات غير متوقع: ${additionalDetails.runtimeType}');
        }
      } else {
        print('❌ التفاصيل الإضافية فارغة');
      }

      // عرض تفاصيل الطلب بتحسين التصميم
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (BuildContext context) {
          final scheme = Theme.of(context).colorScheme;
          final semantic = Theme.of(context).extension<AppSemanticColors>();

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: min(720.0, MediaQuery.sizeOf(context).height * 0.86),
                maxWidth: min(560.0, MediaQuery.sizeOf(context).width * 0.94),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: scheme.onPrimary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _getRequestTypeIcon(request.type),
                            color: scheme.onPrimary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'تفاصيل الطلب',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                requestData?['RequestNumber']?.toString() ??
                                    request.requestNumber,
                                style: TextStyle(
                                  color:
                                      scheme.onPrimary.withValues(alpha: 0.78),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(Icons.close, color: scheme.onPrimary),
                        ),
                      ],
                    ),
                  ),
                  // Content
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // معلومات الطلب الأساسية
                          _buildDetailSection(
                            'معلومات الطلب',
                            Icons.info_outline,
                            [
                              _buildDetailRow(
                                  'رقم الطلب:',
                                  requestData?['RequestNumber']?.toString() ??
                                      request.requestNumber),
                              _buildDetailRow(
                                  'نوع الطلب:',
                                  requestData?['RequestTypeName']?.toString() ??
                                      request.title),
                              _buildDetailRow(
                                  'الموظف:',
                                  requestData?['EmployeeName']?.toString() ??
                                      request.employeeName),
                              _buildDetailRow(
                                  'تاريخ الإنشاء:',
                                  _formatDateTime(requestData?['CreatedDate']
                                          ?.toString()) ??
                                      _formatDate(request.createdAt)),
                              _buildDetailRow(
                                  'أيام الانتظار:',
                                  requestData?['DaysPending']?.toString() ??
                                      '0'),
                              _buildDetailRow(
                                  'الحالة:',
                                  requestData?['Status']?.toString() ??
                                      _getStatusText(
                                          request.status.name)),
                              if (requestData?['Description'] != null &&
                                  requestData!['Description']
                                      .toString()
                                      .isNotEmpty)
                                _buildDetailRow('الوصف:',
                                    requestData['Description'].toString()),
                            ],
                          ),

                          const SizedBox(height: 20),

                          // تفاصيل إضافية حسب نوع الطلب
                          if (additionalDetails != null) ...[
                            _buildDetailSection(
                              'التفاصيل الإضافية',
                              Icons.description,
                              _buildAdditionalDetails(additionalDetails),
                            ),
                            const SizedBox(height: 20),
                          ] else if (requestData != null &&
                              requestData is Map<String, dynamic>) ...[
                            // إذا كانت التفاصيل الإضافية فارغة وكان الطلب إجازة، استخدم بيانات الطلب
                            Builder(
                              builder: (context) {
                                final request =
                                    requestData;
                                final requestTypeName =
                                    request['RequestTypeName']?.toString() ??
                                        '';
                                final requestTypeId = request['RequestTypeID'];

                                print(
                                    '📋 نوع الطلب: $requestTypeName (ID: $requestTypeId)');

                                if (requestTypeName.contains('إجازة') ||
                                    requestTypeId == 2) {
                                  print(
                                      '🏖️ إنشاء تفاصيل الإجازة من بيانات الطلب');
                                  final leaveDetails = <String, dynamic>{
                                    'LeaveTypeName': 'إجازة عادية',
                                    'LeaveStartDate':
                                        request['StartDate']?.toString(),
                                    'LeaveEndDate':
                                        request['EndDate']?.toString(),
                                    'StartDate':
                                        request['StartDate']?.toString(),
                                    'EndDate': request['EndDate']?.toString(),
                                    'LeaveReason':
                                        request['Reason']?.toString(),
                                    'Reason': request['Reason']?.toString(),
                                  };

                                  // حساب عدد الأيام إذا كانت التواريخ متوفرة
                                  if (request['StartDate'] != null &&
                                      request['EndDate'] != null) {
                                    try {
                                      final startDate = DateTime.parse(
                                          request['StartDate'].toString());
                                      final endDate = DateTime.parse(
                                          request['EndDate'].toString());
                                      final days =
                                          endDate.difference(startDate).inDays +
                                              1;
                                      leaveDetails['LeaveDays'] = days;
                                      leaveDetails['Days'] = days;
                                      print('📅 عدد الأيام المحسوب: $days');
                                    } catch (e) {
                                      print('❌ خطأ في حساب عدد الأيام: $e');
                                    }
                                  }

                                  return _buildDetailSection(
                                    'تفاصيل الإجازة',
                                    Icons.beach_access,
                                    _buildAdditionalDetails(leaveDetails),
                                  );
                                }

                                return const SizedBox.shrink();
                              },
                            ),
                            const SizedBox(height: 20),
                          ],

                          // المرفقات
                          if (attachments != null) ...[
                            _buildDetailSection(
                              'المرفقات',
                              Icons.attach_file,
                              _buildAttachmentsList(attachments, requestId),
                            ),
                            const SizedBox(height: 20),
                          ] else ...[
                            // عرض قسم المرفقات حتى لو لم تكن موجودة
                            _buildDetailSection(
                              'المرفقات',
                              Icons.attach_file,
                              [
                                CustomCard(
                                  padding: const EdgeInsets.all(14),
                                  borderRadius: 14,
                                  enableHover: false,
                                  gloss: false,
                                  color: scheme.surfaceContainerHighest,
                                  boxShadow: const [],
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.attach_file,
                                        color: scheme.onSurfaceVariant,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'لا توجد مرفقات لهذا الطلب',
                                        style: TextStyle(
                                          color: scheme.onSurfaceVariant,
                                          fontStyle: FontStyle.italic,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                          ],

                          // الموافقات
                          if (approvals != null &&
                              approvals is List &&
                              approvals.isNotEmpty) ...[
                            _buildDetailSection(
                              'سجل الموافقات',
                              Icons.approval,
                              _buildApprovalsList(approvals),
                            ),
                            const SizedBox(height: 20),
                          ],

                          // عرض أزرار الموافقة إذا كان الطلب معلق
                          if (request.status ==
                              request_models.RequestStatus.pending) ...[
                            _buildDetailSection(
                              'إجراءات الموافقة',
                              Icons.approval,
                              [
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _approveRequest(request);
                                        },
                                        icon: const Icon(Icons.check, size: 16),
                                        label: Text(Translations.getText('approve', lang)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              semantic?.success ?? scheme.tertiary,
                                          foregroundColor:
                                              semantic?.onSuccess ?? scheme.onTertiary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                          _rejectRequest(request);
                                        },
                                        icon: const Icon(Icons.close, size: 16),
                                        label: Text(Translations.getText('reject', lang)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor:
                                              scheme.error,
                                          foregroundColor: scheme.onError,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      closeLoadingIfVisible();

      // عرض رسالة خطأ
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translations.getTextWithParams(
              'error_loading_request_details_with_error',
              lang,
              {'error': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _isRequestDetailsBusy = false;
    }
  }

  Widget _buildDetailSection(
      String title, IconData icon, List<Widget> children) {
    try {
      final scheme = Theme.of(context).colorScheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: scheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CustomCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 16,
            enableHover: false,
            gloss: false,
            color: scheme.surfaceContainerHighest,
            boxShadow: const [],
            child: Column(children: children),
          ),
        ],
      );
    } catch (e) {
      print('خطأ في بناء قسم التفاصيل: $e');
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: Colors.red, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'خطأ في عرض التفاصيل: $e',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildDetailRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: label.contains('الحالة:')
                ? _buildStatusChip(value)
                : label.contains('الأولوية:')
                    ? _buildPriorityChip(value)
                    : label.contains('المبلغ:') ||
                            label.contains('قيمة السلفة:') ||
                            label.contains('القسط الشهري:') ||
                            label.contains('إجمالي المبلغ:')
                        ? _buildAmountChip(value)
                        : label.contains('عدد الأيام:') ||
                                label.contains('عدد الأقساط:') ||
                                label.contains('مدة السلفة:') ||
                                label.contains('أيام العمل:')
                            ? _buildNumberChip(value)
                            : Text(
                                value.isNotEmpty ? value : 'غير محدد',
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                  color: scheme.onSurface,
                                ),
                              ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (status.isEmpty) {
      statusColor = scheme.onSurfaceVariant;
      statusText = 'غير محدد';
      statusIcon = Icons.help;
    } else {
      final normalizedStatus = _normalizeStatusKey(status);
      switch (normalizedStatus) {
        case 'pending':
          statusColor = semantic?.warning ?? const Color(0xFFF59E0B);
          statusText = 'معلق';
          statusIcon = Icons.pending;
          break;
        case 'approved':
          statusColor = semantic?.success ?? const Color(0xFF22C55E);
          statusText = 'موافق عليه';
          statusIcon = Icons.check_circle;
          break;
        case 'rejected':
          statusColor = scheme.error;
          statusText = 'مرفوض';
          statusIcon = Icons.cancel;
          break;
        case 'cancelled':
          statusColor = scheme.outline;
          statusText = 'ملغي';
          statusIcon = Icons.block;
          break;
        default:
          statusColor = scheme.onSurfaceVariant;
          statusText = status;
          statusIcon = Icons.help;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: statusColor.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _normalizeStatusKey(String status) {
    final raw = status.trim();
    if (raw.isEmpty) return '';

    final lower = raw.toLowerCase();
    final lastPart = lower.contains('.') ? lower.split('.').last : lower;

    if (lastPart.contains('معلق')) return 'pending';
    if (lastPart.contains('موافق') || lastPart.contains('قبول')) {
      return 'approved';
    }
    if (lastPart.contains('مرفوض') || lastPart.contains('رفض')) {
      return 'rejected';
    }
    if (lastPart.contains('ملغي') || lastPart.contains('إلغاء')) {
      return 'cancelled';
    }

    if (lastPart == 'canceled') return 'cancelled';

    return lastPart;
  }

  String _getStatusText(String status) {
    if (status.isEmpty) return 'غير محدد';

    final normalizedStatus = _normalizeStatusKey(status);
    switch (normalizedStatus) {
      case 'pending':
        return 'معلق';
      case 'approved':
        return 'موافق عليه';
      case 'rejected':
        return 'مرفوض';
      case 'cancelled':
        return 'ملغي';
      case 'completed':
        return 'مكتمل';
      default:
        return status;
    }
  }

  List<Widget> _buildAdditionalDetails(Map<String, dynamic> details) {
    final widgets = <Widget>[];

    try {
      print('🔍 تحليل التفاصيل الإضافية: $details');
      print('🔍 نوع البيانات: ${details.runtimeType}');
      print('🔍 المفاتيح المتاحة: ${details.keys.toList()}');

      // تفاصيل السلفة
      if (details['LoanType'] != null || details['LoanAmount'] != null) {
        widgets.add(_buildDetailRow(
            'نوع السلفة:', details['LoanType']?.toString() ?? 'غير محدد'));
        widgets.add(_buildDetailRow(
            'قيمة السلفة:',
            details['FormattedLoanAmount']?.toString() ??
                details['LoanAmount']?.toString() ??
                '0 ريال'));
        widgets.add(_buildDetailRow(
            'القسط الشهري:',
            details['FormattedMonthlyInstallment']?.toString() ??
                details['MonthlyInstallment']?.toString() ??
                '0 ريال'));
        widgets.add(_buildDetailRow('عدد الأقساط:',
            details['NumberOfInstallments']?.toString() ?? '0'));
        widgets.add(_buildDetailRow(
            'إجمالي المبلغ:',
            details['FormattedTotalAmount']?.toString() ??
                details['TotalAmount']?.toString() ??
                '0 ريال'));
        widgets.add(_buildDetailRow(
            'مدة السلفة:', details['LoanDuration']?.toString() ?? '0 شهر'));
        widgets.add(_buildDetailRow('تاريخ البداية:',
            _formatDateTime(details['LoanStartDate']?.toString())));
        widgets.add(_buildDetailRow('تاريخ النهاية:',
            _formatDateTime(details['LoanEndDate']?.toString())));
        if (details['LoanDescription'] != null &&
            details['LoanDescription'].toString().isNotEmpty) {
          widgets.add(_buildDetailRow(
              'الوصف:', details['LoanDescription']?.toString() ?? ''));
        }
      }
      // تفاصيل الإجازة
      else if (details['LeaveTypeName'] != null ||
          details['LeaveDays'] != null ||
          details['LeaveType'] != null ||
          details['LeaveStartDate'] != null ||
          details['LeaveEndDate'] != null ||
          details['StartDate'] != null ||
          details['EndDate'] != null ||
          details['Days'] != null) {
        print('📋 عرض تفاصيل الإجازة: $details');

        // تاريخ البداية
        final startDate = details['LeaveStartDate']?.toString() ??
            details['StartDate']?.toString();
        if (startDate != null && startDate.isNotEmpty) {
          widgets.add(
              _buildDetailRow('تاريخ البداية:', _formatDateTime(startDate)));
        }

        // تاريخ النهاية
        final endDate = details['LeaveEndDate']?.toString() ??
            details['EndDate']?.toString();
        if (endDate != null && endDate.isNotEmpty) {
          widgets
              .add(_buildDetailRow('تاريخ النهاية:', _formatDateTime(endDate)));
        }

        // حساب عدد الأيام إذا لم يكن متوفراً
        if (startDate != null &&
            endDate != null &&
            (details['LeaveDays'] == null ||
                details['LeaveDays'].toString().isEmpty)) {
          try {
            final start = DateTime.parse(startDate);
            final end = DateTime.parse(endDate);
            final days = end.difference(start).inDays + 1;
            widgets.add(_buildDetailRow('عدد الأيام:', days.toString()));
          } catch (e) {
            print('❌ خطأ في حساب عدد الأيام: $e');
          }
        }

        // عدد الأيام
        final leaveDays = details['LeaveDays']?.toString();
        if (leaveDays != null && leaveDays.isNotEmpty) {
          widgets.add(_buildDetailRow('عدد الأيام:', leaveDays));
        }

        // أيام العمل
        final workingDays = details['WorkingDays']?.toString();
        if (workingDays != null && workingDays.isNotEmpty) {
          widgets.add(_buildDetailRow('أيام العمل:', workingDays));
        }

        // مدة الإجازة
        final leaveDuration = details['LeaveDuration']?.toString();
        if (leaveDuration != null && leaveDuration.isNotEmpty) {
          widgets.add(_buildDetailRow('مدة الإجازة:', leaveDuration));
        }

        // السبب
        final leaveReason = details['LeaveReason']?.toString();
        if (leaveReason != null && leaveReason.isNotEmpty) {
          widgets.add(_buildDetailRow('السبب:', leaveReason));
        }

        print('✅ تم إضافة تفاصيل الإجازة بنجاح');
      }
      // تفاصيل طلبات أخرى - بناءً على البيانات المذكورة
      else if (details['Amount'] != null ||
          details['Reason'] != null ||
          details['StartDate'] != null ||
          details['RequestType'] != null) {
        // عرض نوع الطلب إذا كان متوفراً
        if (details['RequestType'] != null) {
          widgets.add(_buildDetailRow(
              'نوع الطلب:', details['RequestType']?.toString() ?? 'غير محدد'));
        }

        // عرض المبلغ إذا كان متوفراً
        if (details['FormattedAmount'] != null || details['Amount'] != null) {
          widgets.add(_buildDetailRow(
              'المبلغ:',
              details['FormattedAmount']?.toString() ??
                  details['Amount']?.toString() ??
                  'غير محدد'));
        }

        // عرض الفترة
        if (details['StartDate'] != null || details['EndDate'] != null) {
          widgets.add(_buildDetailRow('الفترة:',
              '${_formatDateTime(details['StartDate']?.toString())} إلى ${_formatDateTime(details['EndDate']?.toString())}'));
        }

        // عرض السبب
        if (details['Reason'] != null &&
            details['Reason'].toString().isNotEmpty) {
          widgets.add(_buildDetailRow(
              'سبب الطلب:', details['Reason']?.toString() ?? ''));
        }

        // عرض الوصف
        if (details['Description'] != null &&
            details['Description'].toString().isNotEmpty) {
          widgets.add(_buildDetailRow(
              'الوصف:', details['Description']?.toString() ?? ''));
        }

        // عرض المدة
        if (details['Duration'] != null) {
          widgets.add(_buildDetailRow(
              'المدة:', details['Duration']?.toString() ?? 'غير محدد'));
        }

        // عرض التصنيف
        if (details['RequestCategory'] != null) {
          widgets.add(_buildDetailRow(
              'التصنيف:', details['RequestCategory']?.toString() ?? 'طلب عام'));
        }
      }
      // إذا لم تكن هناك تفاصيل إضافية، عرض رسالة
      else {
        print('⚠️ لا توجد تفاصيل إضافية متاحة');
        widgets.add(
          Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              return CustomCard(
                padding: const EdgeInsets.all(12),
                borderRadius: 12,
                enableHover: false,
                gloss: false,
                color: scheme.surfaceContainerHighest,
                boxShadow: const [],
                child: Text(
                  'لا توجد تفاصيل إضافية متاحة',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            },
          ),
        );
      }
    } catch (e) {
      print('❌ خطأ في تحليل التفاصيل الإضافية: $e');
      // في حالة حدوث خطأ، عرض رسالة خطأ
      widgets.add(
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Text(
            'خطأ في تحميل التفاصيل الإضافية: $e',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  List<Widget> _buildApprovalsList(List approvals) {
    return approvals.map<Widget>((approval) {
      try {
        final scheme = Theme.of(context).colorScheme;
        final semantic = Theme.of(context).extension<AppSemanticColors>();
        final status = approval['Status']?.toString() ?? '';
        final approverName = approval['ApproverName']?.toString() ?? '';
        final approverPosition = approval['ApproverPosition']?.toString() ?? '';
        final comments = approval['Comments']?.toString() ?? '';
        final approvalDate = approval['ApprovalDate']?.toString() ?? '';
        final isCurrentApprover = approval['IsCurrentApprover'] == true;

        Color statusColor;
        String statusText;
        IconData statusIcon;

        switch (status.toLowerCase()) {
          case 'approved':
            statusColor = semantic?.success ?? const Color(0xFF22C55E);
            statusText = 'موافق';
            statusIcon = Icons.check_circle;
            break;
          case 'rejected':
            statusColor = scheme.error;
            statusText = 'مرفوض';
            statusIcon = Icons.cancel;
            break;
          case 'pending':
            statusColor = semantic?.warning ?? const Color(0xFFF59E0B);
            statusText = 'معلق';
            statusIcon = Icons.pending;
            break;
          default:
            statusColor = scheme.onSurfaceVariant;
            statusText = status;
            statusIcon = Icons.help;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isCurrentApprover
                ? statusColor.withValues(alpha: 0.10)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isCurrentApprover
                  ? statusColor.withValues(alpha: 0.32)
                  : scheme.outlineVariant.withValues(alpha: 0.70),
              width: isCurrentApprover ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          approverName.isNotEmpty
                              ? approverName
                              : 'معتمد غير محدد',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                            color: scheme.onSurface,
                          ),
                        ),
                        if (approverPosition.isNotEmpty)
                          Text(
                            approverPosition,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCurrentApprover) ...[
                          Icon(Icons.person,
                              size: 12, color: scheme.primary),
                          const SizedBox(width: 4),
                        ],
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (comments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ملاحظات:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        comments,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
              if (approvalDate.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.access_time,
                        size: 14, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      'التاريخ: ${_formatDateTime(approvalDate)}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      } catch (e) {
        // في حالة حدوث خطأ في معالجة موافقة واحدة، عرض رسالة خطأ
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.withOpacity(0.3)),
          ),
          child: Text(
            'خطأ في تحميل بيانات الموافقة: $e',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 12,
            ),
          ),
        );
      }
    }).toList();
  }

  Color _getStatusColor(request_models.RequestStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    switch (status) {
      case request_models.RequestStatus.pending:
        return semantic?.warning ?? const Color(0xFFF59E0B);
      case request_models.RequestStatus.approved:
        return semantic?.success ?? const Color(0xFF22C55E);
      case request_models.RequestStatus.rejected:
        return scheme.error;
      case request_models.RequestStatus.cancelled:
        return scheme.outline;
      default:
        return scheme.onSurfaceVariant;
    }
  }

  IconData _getStatusIcon(request_models.RequestStatus status) {
    switch (status) {
      case request_models.RequestStatus.pending:
        return Icons.pending;
      case request_models.RequestStatus.approved:
        return Icons.check_circle;
      case request_models.RequestStatus.rejected:
        return Icons.cancel;
      case request_models.RequestStatus.cancelled:
        return Icons.block;
      default:
        return Icons.help;
    }
  }

  String _getStatusMessage(request_models.RequestStatus status) {
    switch (status) {
      case request_models.RequestStatus.pending:
        return 'الطلب معلق بانتظار الموافقة';
      case request_models.RequestStatus.approved:
        return 'تمت الموافقة على الطلب';
      case request_models.RequestStatus.rejected:
        return 'تم رفض الطلب';
      case request_models.RequestStatus.cancelled:
        return 'تم إلغاء الطلب';
      default:
        return 'حالة غير معروفة';
    }
  }

  String _getPriorityText(String priority) {
    if (priority.isEmpty) return 'غير محدد';

    switch (priority.toLowerCase()) {
      case 'high':
        return 'عالية';
      case 'normal':
        return 'عادية';
      case 'low':
        return 'منخفضة';
      default:
        return priority;
    }
  }

  Widget _buildPriorityChip(String priority) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    Color priorityColor;
    String priorityText;
    IconData priorityIcon;

    if (priority.isEmpty) {
      priorityColor = scheme.onSurfaceVariant;
      priorityText = 'غير محدد';
      priorityIcon = Icons.help;
    } else {
      switch (priority.toLowerCase()) {
        case 'high':
          priorityColor = scheme.error;
          priorityText = 'عالية';
          priorityIcon = Icons.priority_high;
          break;
        case 'normal':
          priorityColor = semantic?.warning ?? const Color(0xFFF59E0B);
          priorityText = 'عادية';
          priorityIcon = Icons.remove;
          break;
        case 'low':
          priorityColor = semantic?.success ?? const Color(0xFF22C55E);
          priorityText = 'منخفضة';
          priorityIcon = Icons.keyboard_arrow_down;
          break;
        default:
          priorityColor = scheme.onSurfaceVariant;
          priorityText = priority;
          priorityIcon = Icons.help;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: priorityColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: priorityColor.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(priorityIcon, color: priorityColor, size: 16),
          const SizedBox(width: 4),
          Text(
            priorityText,
            style: TextStyle(
              color: priorityColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountChip(String amount) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final color = semantic?.success ?? scheme.tertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_money, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            amount,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberChip(String number) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    final color = semantic?.info ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.numbers, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            number,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _loadRequestDetails(int requestId) async {
    try {
      print('🔍 جلب تفاصيل الطلب: $requestId');
      print('🏢 Client ID: ${widget.employeeData.clientID}');
      print(
          '🔗 API URL: ${ApiConfig.baseUrl}/api/${widget.employeeData.clientID}/approvals/$requestId');

      // جلب تفاصيل الطلب من API باستخدام نقطة الموافقات
      final response = await ApiService.getApprovalDetails(
        widget.employeeData.clientID,
        requestId.toString(),
      );

      print('📡 استجابة API: $response');

      if (response['Success'] == true && response['Data'] != null) {
        final data = response['Data'] as Map<String, dynamic>;
        print('✅ تم جلب البيانات بنجاح');
        print('📋 البيانات: $data');

        // المرفقات موجودة بالفعل في تفاصيل الطلب
        final attachments = data['Attachments'] as List? ?? [];
        print('✅ المرفقات من تفاصيل الطلب: ${attachments.length} مرفق');

        // إذا لم تكن المرفقات موجودة، جرب جلبها بشكل منفصل
        if (attachments.isEmpty) {
          print('🔍 جلب المرفقات بشكل منفصل للطلب: $requestId');
          print(
              '🔗 API URL للمرفقات: ${ApiConfig.baseUrl}/api/${widget.employeeData.clientID}/approvals/$requestId/attachments');

          try {
            final attachmentsResponse = await ApiService.getRequestAttachments(
              widget.employeeData.clientID,
              requestId,
            );

            print('📡 استجابة المرفقات المنفصلة: $attachmentsResponse');

            if (attachmentsResponse['Success'] == true) {
              final separateAttachments =
                  attachmentsResponse['Data'] as List? ?? [];
              print(
                  '✅ تم جلب المرفقات المنفصلة: ${separateAttachments.length} مرفق');
              data['Attachments'] = separateAttachments;
            } else {
              print(
                  '❌ فشل في جلب المرفقات المنفصلة: ${attachmentsResponse['Message']}');
              // عدم استخدام بيانات وهمية
              data['Attachments'] = [];
            }
          } catch (e) {
            print('❌ خطأ في جلب المرفقات المنفصلة: $e');
            // عدم استخدام بيانات وهمية
            data['Attachments'] = [];
          }
        }

        return data;
      } else {
        print('❌ فشل في جلب تفاصيل الطلب: ${response['Message']}');
        return null;
      }
    } catch (e) {
      print('💥 خطأ في جلب تفاصيل الطلب: $e');
      return null;
    }
  }

  List<Widget> _buildAttachmentsList(List attachments, int requestId) {
    return [
      AttachmentsWidget(
        attachments: attachments,
        requestId: requestId,
        clientId: widget.employeeData.clientID,
      ),
    ];
  }

  IconData _getFileTypeIcon(String fileType) {
    if (fileType.toLowerCase().contains('pdf')) {
      return Icons.picture_as_pdf;
    } else if (fileType.toLowerCase().contains('doc') ||
        fileType.toLowerCase().contains('docx')) {
      return Icons.description;
    } else if (fileType.toLowerCase().contains('xls') ||
        fileType.toLowerCase().contains('xlsx')) {
      return Icons.table_chart;
    } else if (fileType.toLowerCase().contains('zip') ||
        fileType.toLowerCase().contains('rar')) {
      return Icons.archive;
    } else {
      return Icons.attachment;
    }
  }

  Color _getFileTypeColor(String fileType) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>();
    if (fileType.toLowerCase().contains('pdf')) {
      return scheme.error;
    } else if (fileType.toLowerCase().contains('doc') ||
        fileType.toLowerCase().contains('docx')) {
      return scheme.primary;
    } else if (fileType.toLowerCase().contains('xls') ||
        fileType.toLowerCase().contains('xlsx')) {
      return semantic?.warning ?? const Color(0xFFF59E0B);
    } else if (fileType.toLowerCase().contains('zip') ||
        fileType.toLowerCase().contains('rar')) {
      return scheme.secondary;
    } else {
      return scheme.outline;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes == 0) return '0 Bytes';
    final k = 1024;
    final sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(k)).floor();
    return '${(bytes / pow(k, i)).toStringAsFixed(2)} ${sizes[i]}';
  }

  Future<void> _viewAttachment(
      Map<String, dynamic> attachment, int requestId) async {
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;
    try {
      final fileName = attachment['FileName'] as String? ??
          attachment['Name'] as String? ??
          Translations.getText('file_not_specified', lang);
      final fileType = attachment['FileType'] as String? ??
          attachment['Type'] as String? ??
          Translations.getText('not_specified', lang);
      final attachmentId =
          attachment['ID'] as int? ?? attachment['AttachmentID'] as int? ?? 0;

      print('🔍 فتح المرفق: $fileName (ID: $attachmentId, Type: $fileType)');

      // إظهار dialog لخيارات المرفق
      final action = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(Translations.getText('attachment_options', lang)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(_getFileTypeIcon(fileType),
                    color: _getFileTypeColor(fileType)),
                title: Text(fileName),
                subtitle: Text(
                  Translations.getTextWithParams(
                    'file_type_with_value',
                    lang,
                    {'type': fileType},
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(Translations.getText('choose_action', lang)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop('download'),
              child: Text(Translations.getText('download', lang)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('view'),
              child: Text(Translations.getText('view', lang)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(Translations.getText('cancel', lang)),
            ),
          ],
        ),
      );

      if (action == null) return;

      if (action == 'download') {
        await _downloadAttachment(attachment, requestId);
      } else if (action == 'view') {
        await _openAttachment(attachment, requestId);
      }
    } catch (e) {
      print('❌ خطأ في معالجة المرفق: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translations.getTextWithParams(
              'error_processing_attachment_with_error',
              lang,
              {'error': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // تحميل المرفق
  Future<void> _downloadAttachment(
      Map<String, dynamic> attachment, int requestId) async {
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;
    try {
      final fileName = attachment['FileName'] as String? ??
          attachment['Name'] as String? ??
          Translations.getText('file_not_specified', lang);
      final attachmentId =
          attachment['ID'] as int? ?? attachment['AttachmentID'] as int? ?? 0;

      print('📥 بدء تحميل المرفق: $fileName (ID: $attachmentId)');
      print(
          '🔗 API URL للتحميل: ${ApiConfig.baseUrl}/api/${widget.employeeData.clientID}/approvals/$requestId/attachments/$attachmentId/download');
      print('📋 جدول المرفقات: RequestAttachments');
      print(
          '📋 SQL Query: SELECT FileName, FileContent, FileType, FileSize FROM RequestAttachments WHERE ID = @AttachmentID AND RequestID = @RequestID');

      // طلب إذن الكتابة
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Translations.getText('write_permission_required', lang)),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // إظهار مؤشر التحميل
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(
                Translations.getTextWithParams(
                  'downloading_file',
                  lang,
                  {'fileName': fileName},
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.blue,
        ),
      );

      // جلب المرفق من API
      final response = await ApiService.downloadAttachment(
        widget.employeeData.clientID,
        requestId,
        attachmentId,
      );

      if (response['Success'] == true) {
        if (kIsWeb) {
          final downloadUrl =
              '${ApiConfig.baseUrl}/api/${widget.employeeData.clientID}/approvals/$requestId/attachments/$attachmentId/download';
          await launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.platformDefault);
          return;
        }

        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          final filePath = '${directory.path}/$fileName';
          await writeBytesToFile(
            filePath,
            Uint8List.fromList((response['Data'] as List).cast<int>()),
          );

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Translations.getTextWithParams(
                  'downloaded_file',
                  lang,
                  {'fileName': fileName},
                ),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Translations.getTextWithParams(
                'error_downloading_attachment_with_error',
                lang,
                {'error': (response['Message'] ?? '').toString()},
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ خطأ في تحميل المرفق: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translations.getTextWithParams(
              'error_downloading_attachment_with_error',
              lang,
              {'error': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // فتح المرفق
  Future<void> _openAttachment(
      Map<String, dynamic> attachment, int requestId) async {
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;
    try {
      final fileName = attachment['FileName'] as String? ??
          attachment['Name'] as String? ??
          Translations.getText('file_not_specified', lang);
      final fileType = attachment['FileType'] as String? ??
          attachment['Type'] as String? ??
          Translations.getText('not_specified', lang);
      final attachmentId =
          attachment['ID'] as int? ?? attachment['AttachmentID'] as int? ?? 0;

      print('👁️ فتح المرفق: $fileName (ID: $attachmentId, Type: $fileType)');
      print(
          '🔗 API URL للفتح: ${ApiConfig.baseUrl}/api/${widget.employeeData.clientID}/approvals/$requestId/attachments/$attachmentId/download');
      print('📋 جدول المرفقات: RequestAttachments');
      print(
          '📋 SQL Query: SELECT FileName, FileContent, FileType, FileSize FROM RequestAttachments WHERE ID = @AttachmentID AND RequestID = @RequestID');

      // إظهار مؤشر التحميل
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 16),
              Text(
                Translations.getTextWithParams(
                  'opening_file',
                  lang,
                  {'fileName': fileName},
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );

      // جلب رابط المرفق من API
      final response = await ApiService.getAttachmentUrl(
        widget.employeeData.clientID,
        requestId,
        attachmentId,
      );

      if (response['Success'] == true) {
        final url = response['Data'] as String?;
        if (url != null && url.isNotEmpty) {
          // فتح المرفق باستخدام url_launcher
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(Translations.getText('cannot_open_file_type', lang)),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Translations.getText('attachment_url_not_available', lang),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Translations.getTextWithParams(
                'error_opening_attachment_with_error',
                lang,
                {'error': (response['Message'] ?? '').toString()},
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('❌ خطأ في فتح المرفق: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Translations.getTextWithParams(
              'error_opening_attachment_with_error',
              lang,
              {'error': e.toString()},
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _ApprovalGateInfo {
  final bool canAct;
  final int? myStepOrder;
  final int? currentStepOrder;
  final bool isSecondOrLater;
  final bool firstStepApproved;
  final String? blockedByNames;
  final int totalSteps;
  final int completedSteps;
  final bool isUnknown;

  const _ApprovalGateInfo({
    required this.canAct,
    required this.myStepOrder,
    required this.currentStepOrder,
    required this.isSecondOrLater,
    required this.firstStepApproved,
    required this.blockedByNames,
    required this.totalSteps,
    required this.completedSteps,
  }) : isUnknown = false;

  const _ApprovalGateInfo.unknown()
      : canAct = true,
        myStepOrder = null,
        currentStepOrder = null,
        isSecondOrLater = false,
        firstStepApproved = false,
        blockedByNames = null,
        totalSteps = 0,
        completedSteps = 0,
        isUnknown = true;
}

class _PendingRequestsResult {
  final List<request_models.EmployeeRequest> requests;
  final Map<String, _ApprovalGateInfo> gateInfo;

  const _PendingRequestsResult({
    required this.requests,
    required this.gateInfo,
  });
}
