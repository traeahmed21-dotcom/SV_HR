import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/task_group.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../theme/app_semantic_colors.dart';

class TaskGroupDetailsScreen extends StatefulWidget {
  final int clientId;
  final int creatorEmployeeId;
  final int taskGroupId;
  final bool canApprove;
  final bool canDelete;

  const TaskGroupDetailsScreen({
    super.key,
    required this.clientId,
    required this.creatorEmployeeId,
    required this.taskGroupId,
    required this.canApprove,
    required this.canDelete,
  });

  @override
  State<TaskGroupDetailsScreen> createState() => _TaskGroupDetailsScreenState();
}

class _TaskGroupDetailsScreenState extends State<TaskGroupDetailsScreen> {
  bool _isLoading = false;
  bool _isUpdating = false;
  TaskGroupDetails? _data;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final resp = await ApiService.getCreatorTaskGroupDetails(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        taskGroupId: widget.taskGroupId,
      );

      final ok = resp['Success'] == true;
      final msg = resp['Message']?.toString();
      final data = resp['Data'];
      final parsed = (ok && data is Map<String, dynamic>) ? TaskGroupDetails.fromJson(data) : null;

      if (!mounted) return;
      setState(() {
        _data = parsed;
        _lastError = ok ? null : (msg?.isNotEmpty == true ? msg : 'تعذر تحميل تفاصيل المهمة');
      });

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lastError!)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _data = null;
        _lastError = 'خطأ في الاتصال: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_lastError!)));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _countByStatus(String status) {
    final a = _data?.assignments ?? const <TaskGroupAssignment>[];
    return a.where((x) => x.status == status).length;
  }

  bool get _hasAwaitingApproval => _countByStatus('AwaitingApproval') > 0;

  bool get _allCompleted {
    final a = _data?.assignments ?? const <TaskGroupAssignment>[];
    if (a.isEmpty) return false;
    return a.every((x) => x.status == 'Completed');
  }

  Future<void> _approveAwaiting() async {
    if (!widget.canApprove || !_hasAwaitingApproval) return;
    setState(() => _isUpdating = true);
    try {
      final resp = await ApiService.approveCreatorTaskGroup(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        taskGroupId: widget.taskGroupId,
      );
      if (!mounted) return;
      final ok = resp['Success'] == true;
      final msg = resp['Message']?.toString() ?? (ok ? 'تم' : 'حدث خطأ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (ok) await _load();
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _cancelAll() async {
    if (!widget.canDelete) return;
    setState(() => _isUpdating = true);
    try {
      final resp = await ApiService.cancelCreatorTaskGroup(
        widget.clientId,
        creatorEmployeeId: widget.creatorEmployeeId,
        taskGroupId: widget.taskGroupId,
      );
      if (!mounted) return;
      final ok = resp['Success'] == true;
      final msg = resp['Message']?.toString() ?? (ok ? 'تم' : 'حدث خطأ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      if (ok) await _load();
    } finally {
      if (mounted) setState(() => _isUpdating = false);
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
        return Translations.getText('task_creator_stats_cancelled', lang);
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

  Widget _chip({
    required ColorScheme scheme,
    required AppSemanticColors semantic,
    required String lang,
    required String status,
  }) {
    final color = _statusColor(scheme, semantic, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Text(
        _statusLabel(lang, status),
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageService>(context).currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<AppSemanticColors>()!;

    final data = _data;
    final showApprove = widget.canApprove && _hasAwaitingApproval;
    final showCancel = widget.canDelete && !_allCompleted;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('tasks_details_title', lang)),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      bottomNavigationBar: data == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Row(
                  children: [
                    if (showCancel) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isUpdating ? null : _cancelAll,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isUpdating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(Translations.getText('task_creator_cancel', lang)),
                        ),
                      ),
                    ],
                    if (showCancel && showApprove) const SizedBox(width: 12),
                    if (showApprove) ...[
                      Expanded(
                        child: FilledButton(
                          onPressed: _isUpdating ? null : _approveAwaiting,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: _isUpdating
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(Translations.getText('task_creator_approve', lang)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : data == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_lastError ?? Translations.getText('unknown', lang)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(Translations.getText('reload', lang)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          if ((data.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              data.description!.trim(),
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const Icon(Icons.calendar_month_rounded, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${Translations.getText('task_creator_due', lang)}: ${data.dueDateTime ?? '-'}',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_countByStatus('Completed') > 0)
                                _chip(
                                  scheme: scheme,
                                  semantic: semantic,
                                  lang: lang,
                                  status: 'Completed',
                                ),
                              if (_countByStatus('AwaitingApproval') > 0)
                                _chip(
                                  scheme: scheme,
                                  semantic: semantic,
                                  lang: lang,
                                  status: 'AwaitingApproval',
                                ),
                              if (_countByStatus('InProgress') > 0)
                                _chip(
                                  scheme: scheme,
                                  semantic: semantic,
                                  lang: lang,
                                  status: 'InProgress',
                                ),
                              if (_countByStatus('Pending') > 0)
                                _chip(
                                  scheme: scheme,
                                  semantic: semantic,
                                  lang: lang,
                                  status: 'Pending',
                                ),
                              if (_countByStatus('Cancelled') > 0)
                                _chip(
                                  scheme: scheme,
                                  semantic: semantic,
                                  lang: lang,
                                  status: 'Cancelled',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      Translations.getText('task_creator_choose_employees', lang),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 10),
                    for (final a in data.assignments)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (a.employeeName ?? '').trim().isEmpty ? '-' : a.employeeName!.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${Translations.getText('status', lang)}: ${_statusLabel(lang, a.status)}',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            _chip(
                              scheme: scheme,
                              semantic: semantic,
                              lang: lang,
                              status: a.status,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
