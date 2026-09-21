class TaskGroupSummary {
  final int taskGroupId;
  final String title;
  final String? description;
  final String? dueDateTime;
  final String status;
  final int totalEmployees;
  final int pendingCount;
  final int inProgressCount;
  final int awaitingApprovalCount;
  final int completedCount;
  final int cancelledCount;
  final int attachmentsCount;

  const TaskGroupSummary({
    required this.taskGroupId,
    required this.title,
    required this.description,
    required this.dueDateTime,
    required this.status,
    required this.totalEmployees,
    required this.pendingCount,
    required this.inProgressCount,
    required this.awaitingApprovalCount,
    required this.completedCount,
    required this.cancelledCount,
    required this.attachmentsCount,
  });

  factory TaskGroupSummary.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return TaskGroupSummary(
      taskGroupId: toInt(json['TaskGroupID']),
      title: (json['Title'] ?? '') as String,
      description: json['Description']?.toString(),
      dueDateTime: json['DueDateTime']?.toString(),
      status: (json['Status'] ?? 'Pending') as String,
      totalEmployees: toInt(json['TotalEmployees']),
      pendingCount: toInt(json['PendingCount']),
      inProgressCount: toInt(json['InProgressCount']),
      awaitingApprovalCount: toInt(json['AwaitingApprovalCount']),
      completedCount: toInt(json['CompletedCount']),
      cancelledCount: toInt(json['CancelledCount']),
      attachmentsCount: toInt(json['AttachmentsCount']),
    );
  }
}

class TaskGroupAssignment {
  final int taskId;
  final int? assignedEmployeeId;
  final String? employeeName;
  final String status;
  final String? completedDate;
  final String? approvedDate;
  final int attachmentsCount;

  const TaskGroupAssignment({
    required this.taskId,
    required this.assignedEmployeeId,
    required this.employeeName,
    required this.status,
    required this.completedDate,
    required this.approvedDate,
    required this.attachmentsCount,
  });

  factory TaskGroupAssignment.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return TaskGroupAssignment(
      taskId: toInt(json['TaskID']),
      assignedEmployeeId: json['AssignedEmployeeID'] == null
          ? null
          : toInt(json['AssignedEmployeeID']),
      employeeName: json['EmployeeName']?.toString(),
      status: (json['Status'] ?? 'Pending') as String,
      completedDate: json['CompletedDate']?.toString(),
      approvedDate: json['ApprovedDate']?.toString(),
      attachmentsCount: toInt(json['AttachmentsCount']),
    );
  }
}

class TaskGroupDetails {
  final int taskGroupId;
  final String title;
  final String? description;
  final String? dueDateTime;
  final bool requiresApproval;
  final int createdByEmployeeId;
  final String? createdDate;
  final List<TaskGroupAssignment> assignments;

  const TaskGroupDetails({
    required this.taskGroupId,
    required this.title,
    required this.description,
    required this.dueDateTime,
    required this.requiresApproval,
    required this.createdByEmployeeId,
    required this.createdDate,
    required this.assignments,
  });

  factory TaskGroupDetails.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }

    final assignmentsJson = (json['Assignments'] as List?) ?? const [];
    return TaskGroupDetails(
      taskGroupId: toInt(json['TaskGroupID']),
      title: (json['Title'] ?? '') as String,
      description: json['Description']?.toString(),
      dueDateTime: json['DueDateTime']?.toString(),
      requiresApproval: json['RequiresApproval'] == true,
      createdByEmployeeId: toInt(json['CreatedByEmployeeID']),
      createdDate: json['CreatedDate']?.toString(),
      assignments: assignmentsJson
          .whereType<Map<String, dynamic>>()
          .map(TaskGroupAssignment.fromJson)
          .toList(),
    );
  }
}

