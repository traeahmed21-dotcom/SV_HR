import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import 'dart:convert';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../services/language_service.dart';
import '../services/translations.dart';
import '../services/approval_permission_service.dart';
import '../models/api_models.dart' as api_models;
import 'app_shell.dart';
import 'forgot_password_email_screen.dart';
import '../widgets/responsive_center.dart';
import '../utils/platform_helper.dart';

import '../services/api_service.dart';
import '../services/face_api_service.dart';
import 'face_enrollment_screen.dart';
import '../models/app_notice.dart';
import '../widgets/app_notice_banner.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  static const bool _enableRemoteDebugTelemetry = true;
  static const String _debugServerUrl = 'http://192.168.1.163:7777/event';
  static const String _debugSessionId = 'camera-login-biometrics';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _rememberMe = false;
  bool _showPassword = false;
  bool _isLoading = false;
  String? _errorMessage;
  AppNotice? _loginNotice;

  // معلومات الجهاز
  String _deviceUUID = '';
  String _deviceName = '';
  String _deviceType = '';

  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late AnimationController _logoController;

  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _logoAnimation;

  // دالة تسجيل الأحداث للتطوير
  void _log(String message) {
    if (kDebugMode) {
      print(message);
    }
  }

  // #region debug-point C:reporting-helper
  Future<void> _reportDebugEvent(
    String hypothesisId,
    String location,
    String msg, {
    Map<String, dynamic>? data,
  }) async {
    if (!_enableRemoteDebugTelemetry) return;
    try {
      await http.post(
        Uri.parse(_debugServerUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sessionId': _debugSessionId,
          'runId': 'pre-fix',
          'hypothesisId': hypothesisId,
          'location': location,
          'msg': '[DEBUG] $msg',
          'data': data ?? const {},
          'ts': DateTime.now().millisecondsSinceEpoch,
          'traceId':
              '${_emailController.text.trim()}-${DateTime.now().microsecondsSinceEpoch}',
        }),
      );
    } catch (_) {}
  }
  // #endregion

  @override
  void initState() {
    super.initState();

    // Initialize animations
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _logoAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _logoController,
      curve: Curves.elasticOut,
    ));

    // Start animations
    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
    _logoController.forward();

    // تحميل البيانات المحفوظة وجلب معلومات الجهاز
    _loadSavedCredentials();
    _getDeviceInfo();
    _loadLoginNotice();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _logoController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadLoginNotice() async {
    try {
      final notices =
          await ApiService.getActiveAppNotices(placement: 'login');
      if (!mounted) return;
      setState(() {
        _loginNotice = notices.isNotEmpty ? notices.first : null;
      });
    } catch (_) {}
  }

  // دالة تحميل البيانات المحفوظة
  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email');
      final savedPassword = prefs.getString('saved_password');
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (mounted) {
        setState(() {
          if (savedEmail != null) {
            _emailController.text = savedEmail;
          }
          if (savedPassword != null) {
            _passwordController.text = savedPassword;
          }
          _rememberMe = rememberMe;
        });
      }
    } catch (e) {
      _log('❌ خطأ في تحميل البيانات المحفوظة: $e');
    }
  }

  // دالة حفظ البيانات
  Future<void> _saveCredentials(api_models.EmployeeData? employee) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('saved_email', _emailController.text.trim());
        await prefs.setString('saved_password', _passwordController.text);
        await prefs.setBool('remember_me', true);

        if (employee != null) {
          await prefs.setString('user_data', json.encode(employee.toJson()));
          await prefs.setBool('is_logged_in', true);
        }
        _log('✅ تم حفظ بيانات تسجيل الدخول والجلسة');
      } else {
        await prefs.remove('saved_email');
        await prefs.remove('saved_password');
        await prefs.remove('user_data');
        await prefs.setBool('is_logged_in', false);
        await prefs.setBool('remember_me', false);
        _log('🗑️ تم حذف بيانات تسجيل الدخول المحفوظة');
      }
    } catch (e) {
      _log('❌ خطأ في حفظ البيانات: $e');
    }
  }

  // دالة جلب معلومات الجهاز
  Future<void> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final prefs = await SharedPreferences.getInstance();

      if (kIsWeb) {
        _deviceName = 'Browser';
        _deviceType = 'Web';
      } else if (PlatformHelper.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceName = androidInfo.model;
        _deviceType = 'Android';
      } else if (PlatformHelper.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceName = iosInfo.model;
        _deviceType = 'iOS';
      }

      // جلب أو إنشاء UUID فريد للجهاز
      _deviceUUID = await _getOrCreateDeviceUUID(prefs);

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      // تجاهل الأخطاء في جلب معلومات الجهاز
    }
  }

  // دالة جلب أو إنشاء UUID فريد للجهاز
  Future<String> _getOrCreateDeviceUUID(SharedPreferences prefs) async {
    try {
      // محاولة جلب UUID محفوظ مسبقاً
      String? savedUUID = prefs.getString('device_uuid');

      if (savedUUID != null && savedUUID.isNotEmpty) {
        return savedUUID;
      }

      // إنشاء UUID جديد
      String newUUID = _generateUUID();

      // حفظ UUID الجديد
      await prefs.setString('device_uuid', newUUID);

      return newUUID;
    } catch (e) {
      // في حالة الخطأ، إنشاء UUID مؤقت
      return _generateUUID();
    }
  }

  // دالة إنشاء UUID فريد
  String _generateUUID() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));

    // تنسيق UUID v4
    return '${values[0].toRadixString(16).padLeft(2, '0')}'
        '${values[1].toRadixString(16).padLeft(2, '0')}'
        '${values[2].toRadixString(16).padLeft(2, '0')}'
        '${values[3].toRadixString(16).padLeft(2, '0')}-'
        '${values[4].toRadixString(16).padLeft(2, '0')}'
        '${values[5].toRadixString(16).padLeft(2, '0')}-'
        '${values[6].toRadixString(16).padLeft(2, '0')}'
        '${values[7].toRadixString(16).padLeft(2, '0')}-'
        '${values[8].toRadixString(16).padLeft(2, '0')}'
        '${values[9].toRadixString(16).padLeft(2, '0')}-'
        '${values[10].toRadixString(16).padLeft(2, '0')}'
        '${values[11].toRadixString(16).padLeft(2, '0')}'
        '${values[12].toRadixString(16).padLeft(2, '0')}'
        '${values[13].toRadixString(16).padLeft(2, '0')}'
        '${values[14].toRadixString(16).padLeft(2, '0')}'
        '${values[15].toRadixString(16).padLeft(2, '0')}';
  }

  Future<void> _handleLogin() async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;
    // التحقق من أن الحقول ليست فارغة
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() {
        _errorMessage =
            Translations.getText('error_enter_email_password', lang);
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    // #region debug-point C:login-start
    unawaited(_reportDebugEvent(
      'C',
      'login_screen.dart:_handleLogin',
      'Login flow started',
      data: {
        'email': _emailController.text.trim(),
        'deviceType': _deviceType,
        'hasDeviceUuid': _deviceUUID.isNotEmpty,
      },
    ));
    // #endregion

    try {
      // استدعاء API
      final response = await ApiService.login(
        _emailController.text.trim(),
        _passwordController.text,
        _deviceUUID,
        _deviceName,
        _deviceType,
      );

      _log('✅ نجح: ${response.success}');
      _log('📝 الرسالة: ${response.message}');
      _log(
          '👤 بيانات الموظف: ${response.employee != null ? "موجود" : "غير موجود"}');

      if (mounted) {
        if (response.success && response.employee != null) {
          final emp = response.employee!;
          var effectiveEmployee = emp;

          final embedded = emp.embeddedApprovalPermission;
          if (embedded != null &&
              embedded.isValid &&
              embedded.verifySignatureIntegrity() &&
              embedded.clientId == emp.clientID &&
              embedded.employeeId == emp.employeeID &&
              embedded.employeeNumber == emp.employeeNumber) {
            ApprovalPermissionService.updateCached(embedded);
            try {
              await ApprovalPermissionService.persistSecurely(
                  embedded.toSecureJson());
            } catch (_) {}
          } else if (emp.secureApprovalToken != null &&
              emp.secureApprovalToken!.isNotEmpty) {
            try {
              final decoded = SecureApprovalPermission.fromSecureJson(
                  emp.secureApprovalToken!);
              if (decoded.isValid && decoded.verifySignatureIntegrity()) {
                ApprovalPermissionService.updateCached(decoded);
                try {
                  await ApprovalPermissionService.persistSecurely(
                      decoded.toSecureJson());
                } catch (_) {}
              }
            } catch (_) {}
          } else {
            try {
              final probe = await ApiService.getPendingRequestsForApproval(
                emp.clientID,
                approverId: int.tryParse(emp.employeeNumber) ?? emp.employeeID,
              )
                  .timeout(
                    const Duration(seconds: 6),
                    onTimeout: () =>
                        <String, dynamic>{'Success': false, 'Data': []},
                  )
                  .catchError(
                      (_) => <String, dynamic>{'Success': false, 'Data': []});
              final probeData = probe['Data'] as List<dynamic>?;
              final finalPerm =
                  ApprovalPermissionService.evaluateApproverFromSignals(
                clientId: emp.clientID,
                employeeId: emp.employeeID,
                employeeNumber: emp.employeeNumber,
                rulesRaw: emp.rules,
                serverApprovalAccess: probe['HasApprovalAccess'] == true ||
                    (probe['HasApprovalAccess'] is String &&
                        probe['HasApprovalAccess'].toString().toLowerCase() ==
                            'true'),
                pendingApprovalItems: probeData ?? const [],
              );
              ApprovalPermissionService.updateCached(finalPerm);
              try {
                await ApprovalPermissionService.persistSecurely(
                    finalPerm.toSecureJson());
              } catch (_) {}
            } catch (_) {
              ApprovalPermissionService.invalidateCache();
            }
          }

          // إظهار رسالة نجاح مؤقتة
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      Translations.getTextWithParams('welcome_with_name', lang,
                          {'name': response.employee!.name}),
                      style: const TextStyle(
                        fontFamily: 'Tajawal',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;

          final canEnter = await _ensureFaceEnrollmentIfNeeded(
            response.employee!,
            lang,
          );
          if (!mounted || !canEnter) return;

          // حفظ الجلسة فقط بعد اجتياز البوابة البيومترية بنجاح
          await _saveCredentials(effectiveEmployee);

          Navigator.of(context, rootNavigator: true).pushReplacement(
            MaterialPageRoute(
              builder: (context) => AppShell(
                employeeNumber: response.employee!.employeeNumber,
                employeeData: response.employee!,
              ),
            ),
          );
        } else {
          // خطأ في تسجيل الدخول

          setState(() {
            _errorMessage = response.message;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = Translations.getText('error_connection', lang);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _ensureFaceEnrollmentIfNeeded(
    api_models.EmployeeData employee,
    String lang,
  ) async {
    if (kIsWeb) {
      return true;
    }

    final faceStatus = await FaceApiService.getEmployeeFaceImageStatus(
      employee.clientID,
      employee.employeeNumber,
    );

    final rawAttendanceMethod = faceStatus['AttendanceMethod'];
    final hasAttendanceMethod = rawAttendanceMethod != null;
    final attendanceMethod =
        int.tryParse(rawAttendanceMethod?.toString() ?? '0') ?? 0;
    final shouldRequireFace = hasAttendanceMethod
        ? attendanceMethod == 1 || attendanceMethod == 2
        : faceStatus['IsFaceRequired'] == true;
    final hasStoredFace = faceStatus['HasFaceTemplate'] == true ||
        faceStatus['HasFaceImage'] == true ||
        faceStatus['HasImage'] == true ||
        faceStatus['IsRegistered'] == true;

    unawaited(_reportDebugEvent(
      'D',
      'login_screen.dart:_ensureFaceEnrollmentIfNeeded',
      'Checked stored face status after password login',
      data: {
        'employeeNumber': employee.employeeNumber,
        'clientId': employee.clientID,
        'lang': lang,
        'statusSuccess': faceStatus['Success'] == true,
        'attendanceMethod': faceStatus['AttendanceMethod'],
        'hasAttendanceMethod': hasAttendanceMethod,
        'isFaceRequired': faceStatus['IsFaceRequired'],
        'shouldRequireFace': shouldRequireFace,
        'hasStoredFace': hasStoredFace,
        'endpointMode': faceStatus['EndpointMode'],
        'usedLegacyFallback': faceStatus['UsedLegacyFallback'],
        'message': faceStatus['Message'],
      },
    ));

    if (faceStatus['Success'] != true) {
      return true;
    }

    if (!shouldRequireFace) {
      return true;
    }

    if (hasStoredFace) {
      return true;
    }

    if (!mounted) return false;

    final enrollmentResult = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FaceEnrollmentScreen(
          employeeNumber: employee.employeeNumber,
          clientId: employee.clientID,
        ),
      ),
    );

    final enrolled = enrollmentResult == true ||
        (enrollmentResult is Map &&
            (enrollmentResult['Success'] == true ||
                enrollmentResult['Completed'] == true ||
                enrollmentResult['Enrolled'] == true ||
                enrollmentResult['Saved'] == true));

    unawaited(_reportDebugEvent(
      'D',
      'login_screen.dart:_ensureFaceEnrollmentIfNeeded',
      'Completed face enrollment gate after login',
      data: {
        'employeeNumber': employee.employeeNumber,
        'clientId': employee.clientID,
        'enrolled': enrolled,
        'enrollmentResult': enrollmentResult?.toString(),
      },
    ));

    if (enrolled) {
      return true;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            lang == 'ar'
                ? 'يجب تسجيل بصمة الوجه بنجاح قبل الدخول إلى التطبيق.'
                : 'Face enrollment must complete successfully before entering the app.',
            style: const TextStyle(fontFamily: 'Tajawal'),
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              scheme.tertiary,
              scheme.primaryContainer,
              scheme.primary,
            ],
            stops: const [0.0, 0.3, 0.7, 1.0],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                child: ResponsiveCenter(
                  child: Column(
                    children: [
                      if (_loginNotice != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 64, 16, 0),
                          child: AppNoticeBanner(
                            notice: _loginNotice!,
                            lang: lang,
                          ),
                        ),
                      _buildLogoSection(lang),
                      _buildLoginSection(lang),
                    ],
                  ),
                ),
              ),
              // زر اختيار اللغة في الأعلى
              Positioned(
                top: 16,
                left: languageService.currentDirection == TextDirection.ltr
                    ? 16
                    : null,
                right: languageService.currentDirection == TextDirection.rtl
                    ? 16
                    : null,
                child: _buildLanguageButton(context, languageService),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageButton(
      BuildContext context, LanguageService languageService) {
    final lang = languageService.currentLocale.languageCode;
    final current = languageService.getCurrentLanguageInfo();
    return FilledButton.tonalIcon(
      icon: Text(current['flag'], style: const TextStyle(fontSize: 20)),
      label: Text(
        Translations.getText('select_language', lang),
      ),
      onPressed: () => _showLanguageBottomSheet(context, languageService),
    );
  }

  void _showLanguageBottomSheet(
      BuildContext context, LanguageService languageService) {
    final lang = languageService.currentLocale.languageCode;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Translations.getText('select_language', lang),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...LanguageService.supportedLanguages.map((l) {
                final isSelected = l['code'] == lang;
                return ListTile(
                  leading:
                      Text(l['flag'], style: const TextStyle(fontSize: 24)),
                  title: Text(l['nativeName'],
                      style: Theme.of(context).textTheme.titleMedium),
                  trailing: isSelected
                      ? Icon(Icons.check,
                          color: Theme.of(context).colorScheme.primary)
                      : null,
                  onTap: () async {
                    await languageService.changeLanguage(
                        l['code'], l['country']);
                    if (context.mounted) Navigator.pop(context);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLogoSection(String lang) {
    return AnimatedBuilder(
      animation: _logoAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _logoAnimation.value,
          child: Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: Image.asset(
                            'assets/icon/icon.png',
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // App Name
                Text(
                  Translations.getText('app_name', lang),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                ),

                const SizedBox(height: 8),

                Text(
                  Translations.getText('app_subtitle', lang),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withOpacity(0.85),
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginSection(String lang) {
    return AnimatedBuilder(
      animation: _slideAnimation,
      builder: (context, child) {
        final scheme = Theme.of(context).colorScheme;
        return SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Material(
                color: scheme.surface,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(40),
                  topRight: Radius.circular(40),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        Translations.getText('welcome_back', lang),
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Translations.getText('login_subtitle', lang),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 32),
                      _buildLoginForm(lang),
                    ],
                  ),
                )),
          ),
        );
      },
    );
  }

  Widget _buildLoginForm(String lang) {
    return Column(
      children: [
        // Email Field
        _buildTextField(
          controller: _emailController,
          label: Translations.getText('email', lang),
          hint: Translations.getText('email_hint', lang),
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
        ),

        const SizedBox(height: 20),

        // Password Field
        _buildTextField(
          controller: _passwordController,
          label: Translations.getText('password', lang),
          hint: Translations.getText('password_hint', lang),
          icon: Icons.lock_outline,
          isPassword: true,
          showPassword: _showPassword,
          onTogglePassword: () {
            setState(() {
              _showPassword = !_showPassword;
            });
          },
        ),

        const SizedBox(height: 16),

        // Remember Me
        Row(
          children: [
            Transform.scale(
              scale: 0.9,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value ?? false;
                  });
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              Translations.getText('remember_me', lang),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // Error Message
        if (_errorMessage != null && _errorMessage!.isNotEmpty)
          Builder(
            builder: (context) {
              final scheme = Theme.of(context).colorScheme;
              final isSuccess = _errorMessage!.startsWith('✅');
              final bg =
                  isSuccess ? scheme.tertiaryContainer : scheme.errorContainer;
              final fg = isSuccess
                  ? scheme.onTertiaryContainer
                  : scheme.onErrorContainer;
              return Card(
                color: bg,
                margin: const EdgeInsets.only(bottom: 16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                              isSuccess
                                  ? Icons.check_circle
                                  : Icons.error_outline,
                              color: fg,
                              size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              isSuccess
                                  ? Translations.getText('login_success', lang)
                                  : Translations.getText('login_failed', lang),
                              style: TextStyle(
                                  color: fg,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: fg, fontSize: 14, height: 1.4),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),

        // Login Button
        SizedBox(
          width: double.infinity,
          height: 56,
          child: FilledButton(
            onPressed: _isLoading ? null : _handleLogin,
            child: _isLoading
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${Translations.getText('logging_in', lang)}...',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  )
                : Text(
                    Translations.getText('login', lang),
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
          ),
        ),

        const SizedBox(height: 16),

        // Forgot Password
        Center(
          child: TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ForgotPasswordEmailScreen(),
                ),
              );
            },
            child: Text(
              Translations.getText('forgot_password', lang),
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    bool? showPassword,
    VoidCallback? onTogglePassword,
    TextInputType? keyboardType,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: controller,
      obscureText: isPassword && !(showPassword ?? false),
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  showPassword ?? false
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: onTogglePassword,
              )
            : null,
        helperText: '',
        errorStyle: TextStyle(color: scheme.error),
      ),
    );
  }
}
