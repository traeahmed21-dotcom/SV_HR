import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/api_models.dart' as api_models;
import '../services/language_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import 'attendance_screen.dart';
import 'attendance_history_screen.dart';
import 'shift_info_screen.dart';
import 'authentication_method_screen.dart';

class AttendanceHubScreen extends StatelessWidget {
  final String employeeNumber;
  final api_models.EmployeeData employeeData;

  const AttendanceHubScreen({
    super.key,
    required this.employeeNumber,
    required this.employeeData,
  });

  String _lang(BuildContext context) =>
      context.read<LanguageService>().currentLocale.languageCode;

  String _t(BuildContext context, String key) => Translations.getText(key, _lang(context));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRTL = context.watch<LanguageService>().isArabic;
    final lang = _lang(context);

    return Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t(context, 'attendance')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CustomCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t(context, 'quick_actions'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionTile(
                          title: Translations.getText('check_in', lang),
                          icon: Icons.login,
                          color: scheme.tertiary,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AttendanceScreen(
                                  employeeNumber: employeeNumber,
                                  clientId: employeeData.clientID,
                                  isCheckIn: true,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _ActionTile(
                          title: Translations.getText('check_out', lang),
                          icon: Icons.logout,
                          color: scheme.primary,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => AttendanceScreen(
                                  employeeNumber: employeeNumber,
                                  clientId: employeeData.clientID,
                                  isCheckIn: false,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ActionRow(
                    title: Translations.getText('attendance_history', lang),
                    icon: Icons.history,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AttendanceHistoryScreen(
                            employeeNumber: employeeNumber,
                            clientId: employeeData.clientID,
                            employeeName: employeeData.name,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _ActionRow(
                    title: Translations.getText('work_information', lang),
                    icon: Icons.schedule,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ShiftInfoScreen(
                            clientId: employeeData.clientID,
                            employeeNumber: employeeNumber,
                            email: employeeData.email,
                            employeeId: employeeData.employeeID,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _ActionRow(
                    title: isRTL ? 'اختيار طريقة التحقق' : 'Choose verification method',
                    icon: Icons.verified_user_outlined,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AuthenticationMethodScreen(
                            employeeNumber: employeeNumber,
                            clientId: employeeData.clientID,
                            isCheckIn: true,
                            employeeName: employeeData.name,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimary),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ActionRow({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.onPrimaryContainer, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
