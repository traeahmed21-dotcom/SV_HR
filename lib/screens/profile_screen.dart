import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/employee.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../widgets/custom_card.dart';
import 'about_us_screen.dart';
import 'contact_us_screen.dart';
import 'privacy_policy_screen.dart';
import 'terms_conditions_screen.dart';
import 'login_screen.dart';
import 'employee_full_info_screen.dart';
import 'change_password_screen.dart';

class ProfileScreen extends StatefulWidget {
  final Employee employee;
  final int clientId;

  const ProfileScreen({
    super.key,
    required this.employee,
    required this.clientId,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final isRTL = languageService.isArabic;
    final lang = languageService.isArabic ? 'ar' : 'en';
    return Directionality(
      textDirection: isRTL ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(Translations.getText('profile', lang)),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Profile Header
              _buildProfileHeader(context),
              const SizedBox(height: 24),

              // Profile Details
              _buildProfileDetails(context),
              const SizedBox(height: 24),

              // Actions
              _buildActions(context),
              const SizedBox(height: 24),
              _buildAppInfo(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: scheme.onPrimary.withValues(alpha: 0.2),
            child: Icon(
              Icons.person,
              size: 35,
              color: scheme.onPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.employee.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.employee.position,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 4),
                if (widget.employee.department.isNotEmpty)
                  Text(
                    widget.employee.department,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileDetails(BuildContext context) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.isArabic ? 'ar' : 'en';

    return CustomCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Translations.getText('personal_information', lang),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildDetailRow(Translations.getText('employee_number', lang),
              widget.employee.employeeNumber, Icons.badge),
          _buildDetailRow(
              Translations.getText('email', lang), widget.employee.email, Icons.email),
          _buildDetailRow(Translations.getText('phone_number', lang),
              widget.employee.phone, Icons.phone),
          _buildDetailRow(
              Translations.getText('hire_date', lang),
              widget.employee.hireDate.toString().substring(0, 10),
              Icons.calendar_today),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: scheme.onPrimaryContainer,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.isArabic ? 'ar' : 'en';

    return CustomCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Translations.getText('settings', lang),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildActionTile(
            Translations.getText('language', lang),
            Icons.language,
            () {
              _showLanguagePicker(context);
            },
          ),
          _buildActionTile(
            Translations.getText('user_information', lang),
            Icons.person,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EmployeeFullInfoScreen(
                    clientId: widget.clientId,
                    email: widget.employee.email,
                  ),
                ),
              );
            },
          ),
          _buildActionTile(
            Translations.getText('change_password', lang),
            Icons.lock,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChangePasswordScreen(
                    email: widget.employee.email,
                    clientId: widget.clientId,
                  ),
                ),
              );
            },
          ),
          _buildActionTile(
            Translations.getText('logout', lang),
            Icons.logout,
            () {
              _handleLogout(context);
            },
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  Widget _buildAppInfo(BuildContext context) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.isArabic ? 'ar' : 'en';
    final scheme = Theme.of(context).colorScheme;

    return CustomCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Translations.getText('app_info', lang),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildActionTile(
            Translations.getText('about_us', lang),
            Icons.info_outline,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutUsScreen()),
              );
            },
          ),
          _buildActionTile(
            Translations.getText('privacy_policy', lang),
            Icons.privacy_tip_outlined,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              );
            },
          ),
          _buildActionTile(
            Translations.getText('terms_conditions', lang),
            Icons.description_outlined,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TermsConditionsScreen()),
              );
            },
          ),
          _buildActionTile(
            Translations.getText('contact_us', lang),
            Icons.support_agent_outlined,
            () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ContactUsScreen()),
              );
            },
          ),
          const SizedBox(height: 8),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.hasData
                  ? (() {
                      final v = snapshot.data!.version;
                      final b = snapshot.data!.buildNumber.trim();
                      return b.isEmpty ? v : '$v+$b';
                    })()
                  : '-';
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.system_update_alt,
                        color: scheme.onPrimaryContainer,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        Translations.getText('app_version', lang),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    Text(
                      version,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile(String title, IconData icon, VoidCallback onTap,
      {bool isDestructive = false}) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive
              ? scheme.errorContainer
              : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: isDestructive ? scheme.onErrorContainer : scheme.onPrimaryContainer,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? scheme.error : scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: onTap,
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context, listen: false);
    final langCode = languageService.currentLocale.languageCode;
    final lang = languageService.isArabic ? 'ar' : 'en';

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(Translations.getText('select_language', lang)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: LanguageService.supportedLanguages.map((l) {
              final code = l['code'] as String;
              final country = l['country'] as String;
              final nativeName = l['nativeName'] as String;

              return RadioListTile<String>(
                value: code,
                groupValue: langCode,
                title: Text(nativeName),
                onChanged: (value) async {
                  if (value == null) return;
                  await languageService.changeLanguage(code, country);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(Translations.getText('cancel', lang)),
            ),
          ],
        );
      },
    );
  }

  void _handleLogout(BuildContext context) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.isArabic ? 'ar' : 'en';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Translations.getText('logout_confirmation', lang)),
        content: Text(Translations.getText('logout_confirm_message', lang)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Translations.getText('cancel', lang)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // مسح الجلسة والتوجيه إلى صفحة تسجيل الدخول
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('user_data');
              await prefs.setBool('is_logged_in', false);
              
              if (context.mounted) {
                Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(Translations.getText('logout', lang)),
          ),
        ],
      ),
    );
  }
}
