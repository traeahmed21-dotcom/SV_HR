import '../services/approval_permission_service.dart';

class EmployeeLoginRequest {
  final String email;
  final String password;
  final bool rememberMe;

  EmployeeLoginRequest({
    required this.email,
    required this.password,
    this.rememberMe = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'password': password,
      'rememberMe': rememberMe,
    };
  }
}

class EmployeeLoginResponse {
  final bool success;
  final String message;
  final EmployeeData? employee;
  final SecureApprovalPermission? approvalPermission;

  EmployeeLoginResponse({
    required this.success,
    required this.message,
    this.employee,
    this.approvalPermission,
  });

  factory EmployeeLoginResponse.fromJson(Map<String, dynamic> json) {
    final employee = json['employee'] != null
        ? EmployeeData.fromJson(json['employee'])
        : null;
    SecureApprovalPermission? approvalPermission;
    if (employee != null) {
      try {
        final permToken = json['approvalPermissionToken']?.toString();
        if (permToken != null && permToken.trim().isNotEmpty) {
          approvalPermission =
              SecureApprovalPermission.fromSecureJson(permToken);
        }
      } catch (_) {}
    }
    return EmployeeLoginResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
      employee: employee,
      approvalPermission: approvalPermission,
    );
  }
}

class EmployeeData {
  final int employeeID;
  final String employeeNumber;
  final String name;
  final String email;
  final String rules;
  final int clientID;
  final String databaseName;
  final String clientName;
  final SecureApprovalPermission? embeddedApprovalPermission;
  final String? secureApprovalToken;

  EmployeeData({
    required this.employeeID,
    required this.employeeNumber,
    required this.name,
    required this.email,
    required this.rules,
    required this.clientID,
    required this.databaseName,
    required this.clientName,
    this.embeddedApprovalPermission,
    this.secureApprovalToken,
  });

  bool get hasValidSecureApprovalPermission {
    final perm = embeddedApprovalPermission;
    if (perm == null) return false;
    if (!perm.isValid) return false;
    if (!perm.verifySignatureIntegrity()) return false;
    if (perm.clientId != clientID) return false;
    if (perm.employeeId != employeeID) return false;
    if (perm.employeeNumber != employeeNumber) return false;
    return true;
  }

  bool get isApprover {
    if (hasValidSecureApprovalPermission) {
      return embeddedApprovalPermission!.isApprover;
    }
    return rules.toLowerCase().contains('approver');
  }

  factory EmployeeData.fromJson(Map<String, dynamic> json) {
    final rules = json['rules'] ?? '';
    SecureApprovalPermission? embeddedPerm;
    String? secureToken;
    try {
      final token = json['approvalPermissionToken']?.toString() ??
          json['secureApprovalToken']?.toString() ??
          json['approvalToken']?.toString();
      if (token != null && token.trim().isNotEmpty) {
        secureToken = token.trim();
        embeddedPerm = SecureApprovalPermission.fromSecureJson(secureToken);
      }
    } catch (_) {
      embeddedPerm = null;
      secureToken = null;
    }
    return EmployeeData(
      employeeID: json['employeeID'] ?? 0,
      employeeNumber: json['employeeNumber'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      rules: rules,
      clientID: json['clientID'] ?? 0,
      databaseName: json['databaseName'] ?? '',
      clientName: json['clientName'] ?? '',
      embeddedApprovalPermission: embeddedPerm,
      secureApprovalToken: secureToken,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'employeeID': employeeID,
      'employeeNumber': employeeNumber,
      'name': name,
      'email': email,
      'rules': rules,
      'clientID': clientID,
      'databaseName': databaseName,
      'clientName': clientName,
    };
    if (secureApprovalToken != null && secureApprovalToken!.isNotEmpty) {
      map['approvalPermissionToken'] = secureApprovalToken;
    }
    return map;
  }
}

class LogoutResponse {
  final bool success;
  final String message;

  LogoutResponse({
    required this.success,
    required this.message,
  });

  factory LogoutResponse.fromJson(Map<String, dynamic> json) {
    return LogoutResponse(
      success: json['success'] ?? false,
      message: json['message'] ?? '',
    );
  }
}

// أنواع الطلبات
class RequestType {
  final String value;
  final String text;
  final int requestTypeID;

  RequestType({
    required this.value,
    required this.text,
    required this.requestTypeID,
  });

  factory RequestType.fromJson(Map<String, dynamic> json) {
    return RequestType(
      value: json['Value'] ?? '',
      text: json['Text'] ?? '',
      requestTypeID: json['RequestTypeID'] ?? 0,
    );
  }
}

// خطوة في المسار
class WorkflowStep {
  final int stepOrder;
  final String stepName;
  final String approverType;
  final String approverName;
  final String actualApproverName;

  WorkflowStep({
    required this.stepOrder,
    required this.stepName,
    required this.approverType,
    required this.approverName,
    required this.actualApproverName,
  });

  factory WorkflowStep.fromJson(Map<String, dynamic> json) {
    return WorkflowStep(
      stepOrder: json['StepOrder'] ?? 0,
      stepName: json['StepName'] ?? '',
      approverType: json['ApproverType'] ?? '',
      approverName: json['ApproverName'] ?? '',
      actualApproverName: json['ActualApproverName'] ?? '',
    );
  }
}

// بيانات المسار
class WorkflowData {
  final int workflowID;
  final String workflowName;
  final List<WorkflowStep> steps;

  WorkflowData({
    required this.workflowID,
    required this.workflowName,
    required this.steps,
  });

  factory WorkflowData.fromJson(Map<String, dynamic> json) {
    return WorkflowData(
      workflowID: json['WorkflowID'] ?? 0,
      workflowName: json['WorkflowName'] ?? '',
      steps: (json['Steps'] as List<dynamic>?)
              ?.map((step) => WorkflowStep.fromJson(step))
              .toList() ??
          [],
    );
  }
}

class CompanyHoliday {
  final int holidayId;
  final String holidayName;
  final DateTime fromDate;
  final DateTime toDate;
  final String scopeType;
  final int? scopeDepartmentId;
  final String? scopeDepartmentName;
  final String? notes;

  CompanyHoliday({
    required this.holidayId,
    required this.holidayName,
    required this.fromDate,
    required this.toDate,
    required this.scopeType,
    required this.scopeDepartmentId,
    required this.scopeDepartmentName,
    required this.notes,
  });

  factory CompanyHoliday.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.fromMillisecondsSinceEpoch(0);
      if (v is DateTime) return v;
      final s = v.toString().trim();
      return DateTime.tryParse(s) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }

    return CompanyHoliday(
      holidayId: json['HolidayID'] ?? 0,
      holidayName: (json['HolidayName'] ?? '').toString(),
      fromDate: parseDate(json['FromDate']),
      toDate: parseDate(json['ToDate']),
      scopeType: (json['ScopeType'] ?? '').toString(),
      scopeDepartmentId: json['ScopeDepartmentID'] is int
          ? json['ScopeDepartmentID'] as int
          : int.tryParse((json['ScopeDepartmentID'] ?? '').toString()),
      scopeDepartmentName: json['ScopeDepartmentName']?.toString(),
      notes: json['Notes']?.toString(),
    );
  }
}
