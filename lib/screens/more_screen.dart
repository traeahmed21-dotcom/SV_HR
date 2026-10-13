import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart' as api_models;
import '../services/language_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import 'approvals_screen.dart'
    if (dart.library.html) 'approvals_screen_web_stub.dart';
import 'employee_chats_screen.dart';
import 'notifications_screen.dart';
import 'payroll_screen.dart';
import 'salary_details_screen.dart';
import 'task_creator_screen.dart';
import 'user_tasks_screen.dart';
import 'walkie_talkie_screen.dart';
import 'attendance_history_screen.dart';
import 'shift_info_screen.dart';

class MoreScreen extends StatelessWidget {
  final String employeeNumber;
  final api_models.EmployeeData employeeData;
  final int unreadNotifications;
  final int pendingApprovals;
  final bool hasTaskCreatorAccess;

  const MoreScreen({
    super.key,
    required this.employeeNumber,
    required this.employeeData,
    required this.unreadNotifications,
    required this.pendingApprovals,
    required this.hasTaskCreatorAccess,
  });

  String _lang(BuildContext context) =>
      context.read<LanguageService>().currentLocale.languageCode;

  String _t(BuildContext context, String key) =>
      Translations.getText(key, _lang(context));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRTL = context.watch<LanguageService>().isArabic;

    return Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t(context, 'more')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CustomCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: scheme.primaryContainer,
                    child: Icon(Icons.person, color: scheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employeeData.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          employeeData.clientName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (employeeData.isApprover || hasTaskCreatorAccess) ...[
              _Section(
                title: _t(context, 'admin_section_title'),
                children: [
                  if (employeeData.isApprover)
                    _MenuTile(
                      title: _t(context, 'approvals'),
                      icon: Icons.admin_panel_settings_outlined,
                      badge: pendingApprovals,
                      leadingBg: scheme.secondaryContainer,
                      leadingFg: scheme.onSecondaryContainer,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ApprovalsScreen(
                              employeeId: employeeNumber,
                              employeeData: employeeData,
                            ),
                          ),
                        );
                      },
                    ),
                  if (hasTaskCreatorAccess)
                    _MenuTile(
                      title: _t(context, 'task_creator_title'),
                      icon: Icons.playlist_add_check_rounded,
                      leadingBg: scheme.secondaryContainer,
                      leadingFg: scheme.onSecondaryContainer,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TaskCreatorScreen(
                              clientId: employeeData.clientID,
                              creatorEmployeeId:
                                  int.tryParse(employeeData.employeeNumber) ??
                                      employeeData.employeeID,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _Section(
              title: _t(context, 'quick_actions'),
              children: [
                _MenuTile(
                  title: _t(context, 'notifications'),
                  icon: Icons.notifications_outlined,
                  badge: unreadNotifications,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => NotificationsScreen(
                          employeeId: employeeData.employeeID,
                          clientId: employeeData.clientID,
                        ),
                      ),
                    );
                  },
                ),
                _MenuTile(
                  title: _t(context, 'tasks_title'),
                  icon: Icons.task_alt_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserTasksScreen(
                          clientId: employeeData.clientID,
                          employeeId: employeeData.employeeID,
                        ),
                      ),
                    );
                  },
                ),
                _MenuTile(
                  title: _t(context, 'employee_chats'),
                  icon: Icons.forum_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EmployeeChatsScreen(
                          clientId: employeeData.clientID,
                          employeeId: employeeData.employeeID,
                          employeeName: employeeData.name,
                        ),
                      ),
                    );
                  },
                ),
                _MenuTile(
                  title: _t(context, 'walkie_title'),
                  icon: Icons.headset_mic_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WalkieTalkieScreen(
                          clientId: employeeData.clientID,
                          employeeId: employeeData.employeeID,
                          employeeName: employeeData.name,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: _t(context, 'dashboard'),
              children: [
                _MenuTile(
                  title: _t(context, 'attendance_history'),
                  icon: Icons.history,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AttendanceHistoryScreen(
                          employeeNumber: employeeNumber,
                          clientId: employeeData.clientID,
                          employeeName: employeeData.name,
                        ),
                      ),
                    );
                  },
                ),
                _MenuTile(
                  title: _t(context, 'work_information'),
                  icon: Icons.schedule_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShiftInfoScreen(
                          clientId: employeeData.clientID,
                          employeeNumber: employeeNumber,
                          email: employeeData.email,
                          employeeId: employeeData.employeeID,
                        ),
                      ),
                    );
                  },
                ),
                _MenuTile(
                  title: _t(context, 'payroll'),
                  icon: Icons.payments_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PayrollScreen(
                          employeeId: employeeData.employeeID.toString(),
                        ),
                      ),
                    );
                  },
                ),
                _MenuTile(
                  title: _t(context, 'salary_details_title'),
                  icon: Icons.receipt_long_outlined,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SalaryDetailsScreen(
                          clientId: employeeData.clientID,
                          employeeId: employeeData.employeeID,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: _t(context, 'settings'),
              children: [
              ],
            ),
            const SizedBox(height: 22),
            Text(
              '${employeeData.clientName} • ${employeeData.employeeNumber}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      padding: const EdgeInsets.all(0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final int? badge;
  final VoidCallback onTap;
  final Color? leadingBg;
  final Color? leadingFg;

  const _MenuTile({
    required this.title,
    required this.icon,
    required this.onTap,
    this.badge,
    this.leadingBg,
    this.leadingFg,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final trailing = badge != null && (badge ?? 0) > 0
        ? Badge(label: Text('${badge ?? 0}'))
        : Icon(Icons.chevron_right, color: scheme.onSurfaceVariant);

    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: leadingBg ?? scheme.primaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: leadingFg ?? scheme.onPrimaryContainer),
      ),
      title: Text(
        title,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      trailing: trailing,
    );
  }
}
