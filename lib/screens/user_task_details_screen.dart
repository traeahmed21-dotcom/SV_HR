import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_task.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../theme/app_semantic_colors.dart';
import '../utils/file_actions.dart';
import 'package:path_provider/path_provider.dart';

class UserTaskDetailsScreen extends StatefulWidget {
  final int clientId;
  final int employeeId;
  final int taskId;

  const UserTaskDetailsScreen({
    super.key,
    required this.clientId,
    required this.employeeId,
    required this.taskId,
  });

  @override
  State<UserTaskDetailsScreen> createState() => _UserTaskDetailsScreenState();
}

class _UserTaskDetailsScreenState extends State<UserTaskDetailsScreen> {
  bool _isLoading = false;
  bool _isUpdating = false;
  UserTask? _task;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService.getUserTaskDetails(
        widget.clientId,
        employeeId: widget.employeeId,
        taskId: widget.taskId,
      );

      final ok = response['Success'] == true;
      final msg = response['Message']?.toString();
      final data = response['Data'];
      final task = (ok && data is Map<String, dynamic>) ? UserTask.fromJson(data) : null;

      if (!mounted) return;
      setState(() {
        _task = task;
        _lastError = ok ? null : (msg?.isNotEmpty == true ? msg : 'تعذر تحميل تفاصيل المهمة');
      });

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_lastError!)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _task = null;
        _lastError = 'خطأ في الاتصال: $e';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_lastError!)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markDone() async {
    if (_task == null) return;
    setState(() => _isUpdating = true);
    try {
      final response = await ApiService.updateUserTaskStatus(
        widget.clientId,
        employeeId: widget.employeeId,
        taskId: widget.taskId,
        status: 'Completed',
      );

      if (!mounted) return;
      final ok = response['Success'] == true;
      if (!ok) {
        final msg = response['Message']?.toString() ?? 'حدث خطأ';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      await _load();
      if (!mounted) return;
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _markInProgress() async {
    if (_task == null) return;
    setState(() => _isUpdating = true);
    try {
      final response = await ApiService.updateUserTaskStatus(
        widget.clientId,
        employeeId: widget.employeeId,
        taskId: widget.taskId,
        status: 'InProgress',
      );

      if (!mounted) return;
      final ok = response['Success'] == true;
      if (!ok) {
        final msg = response['Message']?.toString() ?? 'حدث خطأ';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        return;
      }

      await _load();
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _downloadAttachment(UserTaskAttachment a) async {
    final response = await ApiService.downloadUserTaskAttachment(
      widget.clientId,
      employeeId: widget.employeeId,
      taskId: widget.taskId,
      attachmentId: a.attachmentId,
    );

    final ok = response['Success'] == true;
    if (!ok) {
      final msg = response['Message']?.toString() ?? 'فشل التحميل';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    final bytes = response['Data'];
    if (bytes is! List<int>) return;
    if (!mounted) return;

    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('عرض/تحميل المرفقات غير مدعوم على الويب حالياً')),
      );
      return;
    }

    if (Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS) {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${a.fileName}';
      await writeBytesToFile(filePath, Uint8List.fromList(bytes));
      await openFilePath(filePath);
      return;
    }

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/${a.fileName}';
    await writeBytesToFile(filePath, Uint8List.fromList(bytes));
    await openFilePath(filePath);
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

    final task = _task;
    final bottomAction = task == null
        ? null
        : switch (task.status) {
            'Pending' => (
                label: Translations.getText('tasks_mark_inprogress', lang),
                icon: Icons.play_circle_outline_rounded,
                onPressed: _markInProgress,
              ),
            'InProgress' => (
                label: Translations.getText('tasks_mark_done', lang),
                icon: Icons.check_circle_outline_rounded,
                onPressed: _markDone,
              ),
            _ => null,
          };

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
      bottomNavigationBar: bottomAction == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: FilledButton.icon(
                  onPressed: _isUpdating ? null : bottomAction.onPressed,
                  icon: _isUpdating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(bottomAction.icon),
                  label: Text(bottomAction.label),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : task == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _lastError ?? Translations.getText('tasks_empty', lang),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 12),
                        if (_lastError != null)
                          OutlinedButton.icon(
                            onPressed: _load,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(Translations.getText('retry', lang)),
                          ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
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
                            task.title,
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 18, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  task.dueDateTime ?? '-',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: scheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Builder(
                            builder: (context) {
                              final statusColor = _statusColor(scheme, semantic, task.status);
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: statusColor.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  _statusLabel(lang, task.status),
                                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: statusColor,
                                      ),
                                ),
                              );
                            },
                          ),
                          if ((task.description ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Text(
                              task.description!.trim(),
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (task.attachments.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              Translations.getText('attachments_title', lang),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 10),
                            for (final a in task.attachments) ...[
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: const Icon(Icons.attach_file_rounded),
                                title: Text(
                                  a.fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${(a.fileSize / 1024).round()} KB',
                                ),
                                trailing: TextButton(
                                  onPressed: () => _downloadAttachment(a),
                                  child: Text(Translations.getText('download', lang)),
                                ),
                              ),
                              if (a != task.attachments.last)
                                Divider(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}
