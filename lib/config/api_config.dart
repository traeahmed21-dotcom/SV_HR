import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'api_discovery.dart';

class ApiConfig {
  static const String _prefsBaseUrlKey = 'api_base_url';
  static const String _debugServerUrl = 'http://192.168.1.163:7777/event';
  static const String _debugSessionId = 'face-legacy-server';
  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://linktek.dyndns.org:334/',
  );

  // الرابط الأساسي للـ API - متغير
  static String _baseUrl = _defaultBaseUrl;
  // static String _baseUrl = 'http://linktek.dyndns.org:334/';
  // static String _baseUrl =
  // 'http://linktek.dyndns.org:334/'; // تم التغيير من localhost لدعم الهاتف الحقيقي
  // 'http://www.perfect-solutions.net:334/HR/API'; // تم التغيير من localhost لدعم الهاتف الحقيقي
  static bool _isInitialized = false;

  // دالة للحصول على الرابط الأساسي
  static String get baseUrl => _normalizeBaseUrl(_baseUrl);

  // بادئة وكيل الويب الاختياري لتجاوز CORS في بيئة التطوير
  // مثال التشغيل:
  // flutter run -d chrome --dart-define=WEB_PROXY_PREFIX=https://cors.isomorphic-git.org
  static const String webProxyPrefix =
      String.fromEnvironment('WEB_PROXY_PREFIX', defaultValue: '');

  // يغلّف عنواناً كاملاً عبر وكيل الويب إن تم تعريفه
  static String wrapUrlForWeb(String url) {
    if (!kIsWeb) return url;
    final prefix = webProxyPrefix.trim();
    if (prefix.isEmpty) return url;
    if (prefix.endsWith('/')) {
      return '$prefix$url';
    }
    return '$prefix/$url';
  }

  static String _normalizeBaseUrl(String url) {
    var u = url.trim();
    u = u.replaceAll('`', '').trim();
    u = u.replaceAll(RegExp(r'\s+'), '');
    try {
      final parsed = Uri.parse(u);
      if (parsed.scheme.isEmpty || parsed.host.isEmpty) {
        return u;
      }

      final segments = parsed.pathSegments.toList();
      int? extractedPort;
      if (!parsed.hasPort && segments.isNotEmpty) {
        final last = segments.last;
        final idx = last.lastIndexOf(':');
        if (idx > 0 && idx < last.length - 1) {
          final portPart = last.substring(idx + 1);
          final namePart = last.substring(0, idx);
          final maybePort = int.tryParse(portPart);
          if (maybePort != null) {
            extractedPort = maybePort;
            segments[segments.length - 1] = namePart;
          }
        }
      }

      final rebuilt = Uri(
        scheme: parsed.scheme,
        userInfo: parsed.userInfo,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : extractedPort,
        path: segments.isEmpty ? '' : '/${segments.join('/')}',
      );
      var result = rebuilt.toString();
      // إزالة أي '/' زائد في النهاية
      if (result.endsWith('/')) {
        result = result.substring(0, result.length - 1);
      }
      return result;
    } catch (_) {
      return u;
    }
  }

  // ضم المسارات بشكل صحيح لضمان عدم تكرار '/'
  static String _join(String base, String endpoint) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final e = endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
    return '$b/$e';
  }

  static Future<void> _reportDebugEvent({
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, dynamic>? data,
  }) async {
    try {
      await http.post(
        Uri.parse(_debugServerUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'sessionId': _debugSessionId,
          'runId': 'pre-fix',
          'hypothesisId': hypothesisId,
          'location': location,
          'msg': '[DEBUG] $message',
          'data': data ?? const <String, dynamic>{},
          'ts': DateTime.now().millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  // دالة لتهيئة النظام وجلب الرابط المحول
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      debugPrint('🔍 جاري اكتشاف الرابط المحول...');
      // #region debug-point A:api-config-init-start
      _reportDebugEvent(
        hypothesisId: 'A',
        location: 'api_config.dart:initialize:start',
        message: 'ApiConfig initialization started',
        data: {
          'defaultBaseUrl': _defaultBaseUrl,
          'currentBaseUrl': _baseUrl,
          'isInitialized': _isInitialized,
        },
      );
      // #endregion

      final prefs = await SharedPreferences.getInstance();
      final savedBaseUrl = prefs.getString(_prefsBaseUrlKey);
      // #region debug-point A:api-config-saved-base-url
      _reportDebugEvent(
        hypothesisId: 'A',
        location: 'api_config.dart:initialize:savedBaseUrl',
        message: 'Loaded saved base URL preference',
        data: {
          'savedBaseUrl': savedBaseUrl,
          'hasSavedBaseUrl':
              savedBaseUrl != null && savedBaseUrl.trim().isNotEmpty,
        },
      );
      // #endregion
      if (savedBaseUrl != null && savedBaseUrl.trim().isNotEmpty) {
        _baseUrl = savedBaseUrl.trim();
      }

      _baseUrl = _normalizeBaseUrl(_baseUrl);
      final discovered = await discoverBaseUrl(_baseUrl);
      // #region debug-point A:api-config-discovery-result
      _reportDebugEvent(
        hypothesisId: 'A',
        location: 'api_config.dart:initialize:discoverBaseUrl',
        message: 'Base URL discovery finished',
        data: {
          'normalizedBaseUrl': _baseUrl,
          'discoveredBaseUrl': discovered,
        },
      );
      // #endregion
      if (discovered != null && discovered.isNotEmpty) {
        _baseUrl = _normalizeBaseUrl(discovered);
        debugPrint('✅ تم اكتشاف رابط محول: $_baseUrl');
      } else {
        debugPrint('✅ تم استخدام الرابط الافتراضي: $_baseUrl');
      }

      _isInitialized = true;
      // #region debug-point A:api-config-init-finish
      _reportDebugEvent(
        hypothesisId: 'A',
        location: 'api_config.dart:initialize:finish',
        message: 'ApiConfig initialization finished',
        data: {
          'finalBaseUrl': _baseUrl,
          'isUsingCustomBaseUrl': isUsingCustomBaseUrl,
        },
      );
      // #endregion
    } catch (e) {
      debugPrint(
          '⚠️ فشل اكتشاف الرابط التلقائي، سيتم استخدام الرابط الافتراضي: $_baseUrl');
      debugPrint('Error: $e');
      _isInitialized = true;
      // #region debug-point A:api-config-init-error
      _reportDebugEvent(
        hypothesisId: 'A',
        location: 'api_config.dart:initialize:error',
        message: 'ApiConfig initialization failed',
        data: {
          'baseUrlAtFailure': _baseUrl,
          'error': e.toString(),
        },
      );
      // #endregion
    }
  }

  // دالة لإعادة تهيئة النظام
  static Future<void> reinitialize() async {
    _isInitialized = false;
    await initialize();
  }

  static bool get isUsingCustomBaseUrl =>
      _normalizeBaseUrl(_baseUrl) != _normalizeBaseUrl(_defaultBaseUrl);

  static Future<void> setBaseUrl(String url, {bool persist = true}) async {
    _baseUrl = _normalizeBaseUrl(url);
    _isInitialized = true;

    if (!persist) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBaseUrlKey, _baseUrl);
  }

  static Future<void> resetBaseUrl() async {
    _baseUrl = _normalizeBaseUrl(_defaultBaseUrl);
    _isInitialized = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsBaseUrlKey);
  }

  static Future<bool> verifyBaseUrl(String candidateUrl) async {
    final normalizedBase = _normalizeBaseUrl(candidateUrl);
    final loginUrl = _join(normalizedBase, loginEndpoint);

    try {
      final response = await http
          .post(
            Uri.parse(loginUrl),
            headers: headers,
            body: jsonEncode({
              'email': '',
              'password': '',
              'macAddress': 'connectivity-check',
              'deviceName': 'connectivity-check',
              'deviceType': 'connectivity-check',
            }),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode != 404;
    } catch (_) {
      return false;
    }
  }

  // أو استخدم عنوان IP المحلي إذا كان الخادم يعمل على نفس الشبكة
  // static const String baseUrl = 'http://192.168.1.100';

  // أو استخدم عنوان الخادم في الإنتاج
  // static const String baseUrl = 'https://your-domain.com';

  // نقاط النهاية (Endpoints)
  static const String loginEndpoint = '/api/employee/login';
  static const String logoutEndpoint = '/api/employee/logout';
  static const String valuesEndpoint = '/api/values';

  // معلومات قاعدة البيانات
  static const String databaseName = 'HR_ONLINE_Central_DB';
  static const String tableName = 'Users_Employees';

  // الحقول المطلوبة في جدول المستخدمين
  static const List<String> requiredFields = [
    'ID',
    'EmployeeID',
    'Name',
    'Mail',
    'Password',
    'Rules',
    'DatabaseName',
    'IsActive',
    'ClientID',
    'ModifiedDate'
  ];

  // الحسابات التجريبية المتوفرة في قاعدة البيانات
  static const Map<String, String> demoAccounts = {
    'admin@example.com': 'admin123',
    'employee@example.com': 'employee123',
  };

  // رسائل الخطأ
  static const String connectionError = 'خطأ في الاتصال بالخادم';
  static const String serverError = 'خطأ في الخادم';
  static const String invalidCredentials =
      'البريد الإلكتروني أو كلمة المرور غير صحيحة';
  static const String inactiveAccount =
      'حسابك غير نشط. يرجى التواصل مع الإدارة.';
  static const String invalidData = 'البيانات المرسلة غير صحيحة';

  // Client ID - سيتم تحديثه من بيانات تسجيل الدخول
  static const int defaultClientId = 30;

  // API Endpoints - Multi-tenant structure
  static String get loginUrl => _join(baseUrl, loginEndpoint);
  static String get logoutUrl => _join(baseUrl, logoutEndpoint);

  // Attendance endpoints with client ID
  // ملاحظة: نوع العملية يتم تحديده من خلال الـ punchState:
  // - punchState = "0" (دخول)
  // - punchState = "1" (خروج)
  static String getCheckInUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/attendance/checkin');
  static String getCheckOutUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/attendance/checkout');
  static String getEmployeeAttendanceUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/attendance/employee');
  static String getAttendanceStatsUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/attendance/stats');
  static String getEmployeeInfoUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/employee/info');

  // Biometric endpoints with client ID
  static String getBiometricRegisterUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/biometric/register');
  static String getBiometricCheckUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/biometric/check');
  static String getBiometricDeleteUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/biometric/delete');

  // Face Biometric endpoints (الأصلي - للإرث فقط)
  static String getFaceEnrollUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/biometric/face/enroll');
  static String getFaceVerifyUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/biometric/face/verify');
  static String getFaceStatusUrl(int clientId, String empNo) =>
      _join(baseUrl, '/api/$clientId/biometric/face/status/$empNo');
  static String getFaceResetUrl(int clientId, String empNo) =>
      _join(baseUrl, '/api/$clientId/biometric/face/reset/$empNo');
  static String getFaceEmployeesUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/biometric/face/employees');

  // ========================================================================
  // 🆕 الـ Endpoints الجديدة حسب متطلبات إعادة الهيكلة (المحدثة:
  // ------------------------------------------------------------------------
  // 1. Enrollment: حفظ صورة الوجه في جدول Users_Employees (بدون فحص حياة)
  // 2. Verification: مطابقة وجه في الحضور/الانصراف مع الصورة المخزنة + فحص حياة
  // ========================================================================
  static String getSaveEmployeeFaceImageUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/employee/face/save');
  static String getVerifyFaceWithStoredImageUrl(int clientId) =>
      _join(baseUrl, '/api/$clientId/employee/face/verify');
  static String getEmployeeFaceImageStatusUrl(int clientId, String empNo) =>
      _join(baseUrl, '/api/$clientId/employee/face/status/$empNo');

  // Headers
  static const Map<String, String> headers = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // Timeout settings
  static const int connectionTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000; // 30 seconds

  // Retry settings
  static const int maxRetries = 3;
  static const int retryDelay = 1000; // 1 second
}
