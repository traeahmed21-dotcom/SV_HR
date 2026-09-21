
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../models/managed_employee.dart';
import '../models/task_group.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../theme/app_semantic_colors.dart';
import 'task_group_details_screen.dart';

class TaskCreatorScreen extends StatefulWidget {
  final int clientId;
  final int creatorEmployeeId;

  const TaskCreatorScreen({
    super.key,
    required this.clientId,
    required this.creatorEmployeeId,
  });

  @override
  State<TaskCreatorScreen> createState() => _TaskCreatorScreenState();
}

class _TaskCreatorScreenState extends State<TaskCreatorScreen> {
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _isLoadingTasks = false;
  String? _tasksLoadError;

  List<ManagedEmployee> _managedEmployees = const [];
  Set<int> _selectedEmployeeIds = <int>{};
  List<PlatformFile> _attachments = const [];

  bool _canCreate = false;
  bool _canApprove = false;
  bool _canDelete = false;
  String? _permissionMessage;
  Map<String, dynamic>? _permissionRaw;

  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _dueDateTime = DateTime.now().add(const Duration(hours: 2));
  bool _autoApprove = true;

  String _tasksFilter = 'All';
  List<TaskGroupSummary> _allCreatedTaskGroups = const [];
  List<TaskGroupSummary> _createdTaskGroups = const [];

  Map<String, int> _taskStats(List<TaskGroupSummary> groups) {
    final map = <String, int>{
      'Total': 0,
      'Pending': 0,
      'InProgress': 0,
      'AwaitingApproval': 0,
      'Completed': 0,
      'Cancelled': 0,
    };
    for (final g in groups) {
      map['Total'] = (map['Total'] ?? 0) + g.totalEmployees;
      map['Pending'] = (map['Pending'] ?? 0) + g.pendingCount;
      map['InProgress'] = (map['InProgress'] ?? 0) + g.inProgressCount;
      map['AwaitingApproval'] = (map['AwaitingApproval'] ?? 0) + g.awaitingApprovalCount;
      map['Completed'] = (map['Completed'] ?? 0) + g.completedCount;
      map['Cancelled'] = (map['Cancelled'] ?? 0) + g.cancelledCount;
    }
    return map;
  }

  Widget _buildStatCard({
    required ColorScheme scheme,
    required String title,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: scheme.onSurface,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _asBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y';
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final resp = await ApiService.getTaskCreatorManagedEmployees(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
      );

      final ok = resp['Success'] == true;
      final data = (resp['Data'] as List?) ?? const [];
      final perm = resp['Permission'];
      final msg = resp['Message']?.toString();

      final canCreate = perm is Map && _asBool(perm['CanCreate']);
      final canApprove = perm is Map && _asBool(perm['CanApprove']);
      final canDelete = perm is Map && _asBool(perm['CanDelete']);

      final employees = ok
          ? data
              .whereType<Map<String, dynamic>>()
              .map(ManagedEmployee.fromJson)
              .where((e) => e.employeeId > 0 && e.name.trim().isNotEmpty)
              .toList()
          : <ManagedEmployee>[];

      if (!mounted) return;
      setState(() {
        _managedEmployees = employees;
        _canCreate = canCreate;
        _canApprove = canApprove;
        _canDelete = canDelete;
        _permissionMessage = msg;
        _permissionRaw =
            perm is Map<String, dynamic> ? perm : (perm is Map ? Map<String, dynamic>.from(perm) : null);
        if (_selectedEmployeeIds.isNotEmpty) {
          _selectedEmployeeIds =
              _selectedEmployeeIds.intersection(employees.map((e) => e.employeeId).toSet());
        }
      });

      await _loadCreatedTasks();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCreatedTasks() async {
    setState(() => _isLoadingTasks = true);
    try {
      final respAll = await ApiService.getCreatorTaskGroups(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        status: null,
        page: 1,
        pageSize: 200,
      );
      final okAll = respAll['Success'] == true;
      final msgAll = respAll['Message']?.toString();
      final dataAll = (respAll['Data'] as List?) ?? const [];
      final allGroups = okAll
          ? dataAll.whereType<Map<String, dynamic>>().map(TaskGroupSummary.fromJson).toList()
          : <TaskGroupSummary>[];

      final status = _tasksFilter == 'All' ? null : _tasksFilter;
      final resp = status == null
          ? respAll
          : await ApiService.getCreatorTaskGroups(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        status: status,
        page: 1,
        pageSize: 100,
      );
      final ok = resp['Success'] == true;
      final msg = resp['Message']?.toString();
      final data = (resp['Data'] as List?) ?? const [];
      final groups = ok
          ? data.whereType<Map<String, dynamic>>().map(TaskGroupSummary.fromJson).toList()
          : <TaskGroupSummary>[];

      if (!mounted) return;
      setState(() {
        _allCreatedTaskGroups = allGroups;
        _createdTaskGroups = groups;
        _tasksLoadError = okAll && ok ? null : (msg ?? msgAll);
      });

      if ((!okAll || !ok) && mounted) {
        final text = (_tasksLoadError ?? '').trim().isEmpty ? 'تعذر تحميل المهام' : _tasksLoadError!.trim();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      }
    } finally {
      if (mounted) setState(() => _isLoadingTasks = false);
    }
  }

  Future<void> _pickDueDateTime() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _dueDateTime.isAfter(now) ? _dueDateTime : now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dueDateTime),
    );
    if (pickedTime == null || !mounted) return;

    setState(() {
      _dueDateTime = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  Future<void> _selectEmployees() async {
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    final selected = Set<int>.from(_selectedEmployeeIds);

    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            Translations.getText('task_creator_choose_employees', lang),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, selected),
                          child: Text(Translations.getText('ok', lang)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _managedEmployees.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final e = _managedEmployees[index];
                          final isSelected = selected.contains(e.employeeId);
                          return CheckboxListTile(
                            value: isSelected,
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true) {
                                  selected.add(e.employeeId);
                                } else {
                                  selected.remove(e.employeeId);
                                }
                              });
                            },
                            title: Text(e.name),
                            subtitle: Text(
                              [
                                if ((e.departmentName ?? '').trim().isNotEmpty)
                                  e.departmentName!.trim(),
                                if ((e.employeeNumber ?? '').trim().isNotEmpty)
                                  e.employeeNumber!.trim(),
                              ].join(' • '),
                            ),
                          );
                        },
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

    if (!mounted) return;
    if (result != null) {
      setState(() => _selectedEmployeeIds = result);
    }
  }

  String? _guessContentType(PlatformFile f) {
    final ext = (f.extension ?? '').toLowerCase().trim();
    if (ext == 'pdf') return 'application/pdf';
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'doc') return 'application/msword';
    if (ext == 'docx') {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (ext == 'xls') return 'application/vnd.ms-excel';
    if (ext == 'xlsx') {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return null;
  }

  Future<void> _pickAttachments() async {
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    if (_isSubmitting) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'pdf',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'jpg',
        'jpeg',
        'png',
      ],
      allowMultiple: true,
      withData: true,
    );

    if (!mounted) return;
    if (result == null || result.files.isEmpty) return;

    final existingKeys = _attachments.map((f) => '${f.name}|${f.size}').toSet();
    final merged = <PlatformFile>[
      ..._attachments,
      ...result.files.where((f) => !existingKeys.contains('${f.name}|${f.size}')),
    ];

    setState(() => _attachments = merged);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${Translations.getText('attachments', lang)}: ${_attachments.length}',
        ),
      ),
    );
  }

  Future<void> _uploadAttachmentsForTasks(List<int> taskIds) async {
    if (_attachments.isEmpty) return;
    for (final taskId in taskIds) {
      for (final f in _attachments) {
        final bytes = f.bytes ?? (f.path != null ? await File(f.path!).readAsBytes() : null);
        if (bytes == null || bytes.isEmpty) continue;

        await ApiService.uploadCreatorTaskAttachment(
          widget.clientId,
          creatorEmployeeId: widget.creatorEmployeeId,
          taskId: taskId,
          fileName: f.name,
          bytes: bytes,
          contentType: _guessContentType(f),
        );
      }
    }
  }

  Future<void> _createTask() async {
    final lang = Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
    if (!_canCreate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Translations.getText('task_creator_no_access', lang))),
      );
      return;
    }

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Translations.getText('error_required_fields', lang))),
      );
      return;
    }

    if (_selectedEmployeeIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Translations.getText('task_creator_choose_employees', lang))),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final resp = await ApiService.createTaskAsCreator(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        title: title,
        description: _descriptionController.text.trim(),
        dueDateTime: _dueDateTime,
        assignedEmployeeIds: _selectedEmployeeIds.toList()..sort(),
        requiresApproval: !_autoApprove,
      );

      final ok = resp['Success'] == true;
      final msg = resp['Message']?.toString() ?? (ok ? 'تم' : 'حدث خطأ');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (ok) {
        final createdIds = (resp['CreatedTaskIDs'] as List?)?.whereType<int>().toList() ?? const <int>[];
        if (createdIds.isNotEmpty && _attachments.isNotEmpty) {
          await _uploadAttachmentsForTasks(createdIds);
        }
        setState(() {
          _titleController.clear();
          _descriptionController.clear();
          _selectedEmployeeIds = <int>{};
          _attachments = const [];
          _dueDateTime = DateTime.now().add(const Duration(hours: 2));
          _autoApprove = true;
        });
        await _loadCreatedTasks();
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _approveTaskGroup(int taskGroupId) async {
    if (!_canApprove) return;
    setState(() => _isSubmitting = true);
    try {
      final resp = await ApiService.approveCreatorTaskGroup(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        taskGroupId: taskGroupId,
      );
      if (!mounted) return;
      final ok = resp['Success'] == true;
      final msg = resp['Message']?.toString() ?? (ok ? 'تم' : 'حدث خطأ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (ok) await _loadCreatedTasks();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _cancelTaskGroup(int taskGroupId) async {
    if (!_canDelete) return;
    setState(() => _isSubmitting = true);
    try {
      final resp = await ApiService.cancelCreatorTaskGroup(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        taskGroupId: taskGroupId,
      );
      if (!mounted) return;
      final ok = resp['Success'] == true;
      final msg = resp['Message']?.toString() ?? (ok ? 'تم' : 'حدث خطأ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (ok) await _loadCreatedTasks();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _statusLabel(String lang, String status) {
    switch (status) {
      case 'Pending':
        return Translations.getText('tasks_status_pending', lang);
      case 'InProgress':
        return Translations.getText('tasks_status_inprogress', lang);
      case 'AwaitingApproval':
        return Translations.getText('tasks_status_awaiting', lang);
      case 'Completed':
        return Translations.getText('tasks_status_completed', lang);
      case 'Cancelled':
        return Translations.getText('cancelled', lang);
      case 'Mixed':
        return lang == 'ar' ? 'متعددة الحالات' : 'Mixed';
      default:
        return status;
    }
  }

  Color _statusColor(ColorScheme scheme, AppSemanticColors semantic, String status) {
    switch (status) {
      case 'Completed':
        return semantic.success;
      case 'InProgress':
        return semantic.info;
      case 'AwaitingApproval':
        return semantic.warning;
      case 'Pending':
        return scheme.outline;
      case 'Cancelled':
        return scheme.error;
      default:
        return scheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageService>(context).currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('task_creator_title', lang)),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (!_canCreate && !_canApprove && !_canDelete)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Translations.getText('task_creator_no_access', lang),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          (_permissionMessage ?? '').trim().isEmpty
                              ? Translations.getText('error', lang)
                              : _permissionMessage!.trim(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                Translations.getText('additional_details', lang),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'API: ${ApiConfig.baseUrl}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                'clientId: ${widget.clientId}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                'creatorEmployeeId: ${widget.creatorEmployeeId}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                'managedEmployees: ${_managedEmployees.length}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'permission: ${_permissionRaw == null ? 'null' : jsonEncode(_permissionRaw)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final statsSource =
                            _allCreatedTaskGroups.isNotEmpty ? _allCreatedTaskGroups : _createdTaskGroups;
                        final stats = _taskStats(statsSource);
                        final cardWidth = (constraints.maxWidth - 12) / 2;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    Translations.getText('task_creator_dashboard', lang),
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w900,
                                        ),
                                  ),
                                ),
                                if (_isLoadingTasks)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: [
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildStatCard(
                                    scheme: scheme,
                                    title: Translations.getText('task_creator_stats_total', lang),
                                    value: stats['Total'] ?? 0,
                                    icon: Icons.dashboard_rounded,
                                    color: scheme.primary,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildStatCard(
                                    scheme: scheme,
                                    title: Translations.getText('task_creator_stats_completed', lang),
                                    value: stats['Completed'] ?? 0,
                                    icon: Icons.check_circle_rounded,
                                    color: semantic.success,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildStatCard(
                                    scheme: scheme,
                                    title: Translations.getText('task_creator_stats_pending', lang),
                                    value: stats['Pending'] ?? 0,
                                    icon: Icons.pending_actions_rounded,
                                    color: scheme.outline,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildStatCard(
                                    scheme: scheme,
                                    title: Translations.getText('task_creator_stats_inprogress', lang),
                                    value: stats['InProgress'] ?? 0,
                                    icon: Icons.timelapse_rounded,
                                    color: semantic.info,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildStatCard(
                                    scheme: scheme,
                                    title: Translations.getText('task_creator_stats_awaiting', lang),
                                    value: stats['AwaitingApproval'] ?? 0,
                                    icon: Icons.fact_check_rounded,
                                    color: semantic.warning,
                                  ),
                                ),
                                SizedBox(
                                  width: cardWidth,
                                  child: _buildStatCard(
                                    scheme: scheme,
                                    title: Translations.getText('task_creator_stats_cancelled', lang),
                                    value: stats['Cancelled'] ?? 0,
                                    icon: Icons.cancel_rounded,
                                    color: scheme.error,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                          ],
                        );
                      },
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                        boxShadow: [
                          BoxShadow(
                            color: scheme.shadow.withValues(alpha: 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Translations.getText('task_creator_create_title', lang),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _managedEmployees.isEmpty ? null : _selectEmployees,
                            icon: const Icon(Icons.group_add_outlined),
                            label: Text(
                              '${Translations.getText('task_creator_choose_employees', lang)} (${Translations.getText('task_creator_selected', lang)}: ${_selectedEmployeeIds.length})',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              labelText: Translations.getText('task_creator_task_title', lang),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _descriptionController,
                            minLines: 2,
                            maxLines: 4,
                            decoration: InputDecoration(
                              labelText: Translations.getText('task_creator_task_description', lang),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  Translations.getText('attachments', lang),
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _isSubmitting ? null : _pickAttachments,
                                icon: const Icon(Icons.attach_file),
                                label: Text(Translations.getText('add_attachment', lang)),
                              ),
                            ],
                          ),
                          if (_attachments.isNotEmpty) ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _attachments.map((f) {
                                return Chip(
                                  label: Text(
                                    f.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onDeleted: _isSubmitting
                                      ? null
                                      : () {
                                          setState(() {
                                            _attachments = _attachments
                                                .where((x) => '${x.name}|${x.size}' != '${f.name}|${f.size}')
                                                .toList();
                                          });
                                        },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 8),
                          ],
                          const SizedBox(height: 12),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.schedule_rounded),
                            title: Text(Translations.getText('task_creator_due', lang)),
                            subtitle: Text(
                              '${_dueDateTime.year.toString().padLeft(4, '0')}-${_dueDateTime.month.toString().padLeft(2, '0')}-${_dueDateTime.day.toString().padLeft(2, '0')} ${_dueDateTime.hour.toString().padLeft(2, '0')}:${_dueDateTime.minute.toString().padLeft(2, '0')}',
                            ),
                            trailing: TextButton(
                              onPressed: _pickDueDateTime,
                              child: Text(Translations.getText('edit', lang)),
                            ),
                          ),
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _autoApprove,
                            onChanged: _isSubmitting
                                ? null
                                : (v) => setState(() => _autoApprove = v == true),
                            title: Text(
                              Translations.getText('task_creator_auto_approve', lang),
                            ),
                            subtitle: Text(
                              Translations.getText('task_creator_auto_approve_hint', lang),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: (_isSubmitting || !_canCreate) ? null : _createTask,
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.send_rounded),
                              label: Text(Translations.getText('task_creator_send', lang)),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            Translations.getText('task_creator_my_tasks', lang),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        DropdownButton<String>(
                          value: _tasksFilter,
                          onChanged: (v) async {
                            if (v == null) return;
                            setState(() => _tasksFilter = v);
                            await _loadCreatedTasks();
                          },
                          items: [
                            DropdownMenuItem(
                              value: 'All',
                              child: Text(Translations.getText('tasks_status_all', lang)),
                            ),
                            DropdownMenuItem(
                              value: 'Pending',
                              child: Text(Translations.getText('tasks_status_pending', lang)),
                            ),
                            DropdownMenuItem(
                              value: 'AwaitingApproval',
                              child: Text(Translations.getText('tasks_status_awaiting', lang)),
                            ),
                            DropdownMenuItem(
                              value: 'Completed',
                              child: Text(Translations.getText('tasks_status_completed', lang)),
                            ),
                            DropdownMenuItem(
                              value: 'Cancelled',
                              child: Text(Translations.getText('cancelled', lang)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_isLoadingTasks)
                      const Center(child: CircularProgressIndicator())
                    else if (_createdTaskGroups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Column(
                          children: [
                            Text(
                              Translations.getText('tasks_empty', lang),
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                            if ((_tasksLoadError ?? '').trim().isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                _tasksLoadError!.trim(),
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.error),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      for (final g in _createdTaskGroups) ...[
                        Builder(
                          builder: (context) {
                            final statusColor = _statusColor(scheme, semantic, g.status);
                            final canApprove = _canApprove && g.awaitingApprovalCount > 0;
                            final canCancel = _canDelete && g.status != 'Completed' && g.status != 'Cancelled';

                            Widget countChip(String label, int value, Color color) {
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: color.withValues(alpha: 0.22)),
                                ),
                                child: Text(
                                  '$label: $value',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                ),
                              );
                            }

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TaskGroupDetailsScreen(
                                      clientId: widget.clientId,
                                      creatorEmployeeId: widget.creatorEmployeeId,
                                      taskGroupId: g.taskGroupId,
                                      canApprove: _canApprove,
                                      canDelete: _canDelete,
                                    ),
                                  ),
                                );
                                if (!mounted) return;
                                await _loadCreatedTasks();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: scheme.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            g.title,
                                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(999),
                                            border: Border.all(
                                              color: statusColor.withValues(alpha: 0.35),
                                            ),
                                          ),
                                          child: Text(
                                            _statusLabel(lang, g.status),
                                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                  color: statusColor,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Icon(Icons.group_rounded, size: 18, color: scheme.onSurfaceVariant),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            '${Translations.getText('task_creator_selected', lang)}: ${g.totalEmployees}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(color: scheme.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(Icons.schedule_rounded, size: 18, color: scheme.onSurfaceVariant),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            g.dueDateTime ?? '-',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(color: scheme.onSurfaceVariant),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        if (g.completedCount > 0)
                                          countChip(
                                            Translations.getText('tasks_status_completed', lang),
                                            g.completedCount,
                                            semantic.success,
                                          ),
                                        if (g.awaitingApprovalCount > 0)
                                          countChip(
                                            Translations.getText('tasks_status_awaiting', lang),
                                            g.awaitingApprovalCount,
                                            semantic.warning,
                                          ),
                                        if (g.inProgressCount > 0)
                                          countChip(
                                            Translations.getText('tasks_status_inprogress', lang),
                                            g.inProgressCount,
                                            semantic.info,
                                          ),
                                        if (g.pendingCount > 0)
                                          countChip(
                                            Translations.getText('tasks_status_pending', lang),
                                            g.pendingCount,
                                            scheme.outline,
                                          ),
                                        if (g.cancelledCount > 0)
                                          countChip(
                                            Translations.getText('cancelled', lang),
                                            g.cancelledCount,
                                            scheme.error,
                                          ),
                                      ],
                                    ),
                                    if (canApprove || canCancel) ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          if (canApprove)
                                            Expanded(
                                              child: FilledButton(
                                                onPressed: _isSubmitting ? null : () => _approveTaskGroup(g.taskGroupId),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: semantic.success,
                                                  foregroundColor: Colors.white,
                                                ),
                                                child: Text(Translations.getText('task_creator_approve', lang)),
                                              ),
                                            ),
                                          if (canApprove && canCancel) const SizedBox(width: 10),
                                          if (canCancel)
                                            Expanded(
                                              child: OutlinedButton(
                                                onPressed: _isSubmitting ? null : () => _cancelTaskGroup(g.taskGroupId),
                                                child: Text(Translations.getText('task_creator_cancel', lang)),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                  ],
                ),
    );
  }
}
