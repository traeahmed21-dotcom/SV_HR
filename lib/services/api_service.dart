import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/api_models.dart' as api_models;
import '../models/shift.dart' as shift_models;
import '../models/pending_counts.dart';
import '../models/notification_model.dart';
import '../models/attendance.dart';
import '../models/request.dart' as request_models;
import '../models/employee_full_info.dart';
import '../models/work_info_models.dart';
import '../models/location.dart';
import '../models/salary_details.dart';
import '../models/mobile_advertisement.dart';
import '../models/app_notice.dart';


class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  static String? lastEmployeeShiftMessage;

  // تسجيل الأحداث - في الإنتاج استخدم نظام تسجيل مناسب مثل logger
  static void _log(String message) {
    // مؤقت للتطوير - في الإنتاج استخدم:
    // import 'package:logger/logger.dart';
    // static final Logger _logger = Logger();
    // _logger.i(message);
    if (kDebugMode) {
      print(message);
    }
  }

  static bool _looksLikeHtml(String body) {
    final trimmed = body.trimLeft();
    return trimmed.startsWith('<!DOCTYPE') ||
        trimmed.startsWith('<html') ||
        trimmed.startsWith('<HTML') ||
        trimmed.startsWith('<!doctype');
  }

  static Future<http.Response> _postWithRetry({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
    Duration timeout = const Duration(seconds: 60),
    int maxAttempts = 2,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await http
            .post(uri, headers: headers, body: body)
            .timeout(timeout);
      } on TimeoutException {
        if (attempt >= maxAttempts) rethrow;
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    return http.post(uri, headers: headers, body: body).timeout(timeout);
  }

  static Future<http.Response> _postWithRetryUris({
    required List<Uri> uris,
    required Map<String, String> headers,
    required String body,
    Duration timeout = const Duration(seconds: 60),
    int maxAttemptsPerUri = 2,
  }) async {
    for (final uri in uris) {
      for (int attempt = 1; attempt <= maxAttemptsPerUri; attempt++) {
        try {
          _log('🌐 Trying POST $uri (attempt $attempt/$maxAttemptsPerUri)');
          return await http
              .post(uri, headers: headers, body: body)
              .timeout(timeout);
        } on TimeoutException {
          if (attempt >= maxAttemptsPerUri) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 800));
        } on http.ClientException catch (e) {
          if (!kIsWeb) rethrow;
          final msg = e.toString();
          final isCors = msg.contains('Failed to fetch') || msg.contains('TypeError');
          _log('⚠️ Web POST failed for $uri | $msg (CORS=$isCors)');
          if (!isCors || attempt >= maxAttemptsPerUri) {
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    throw http.ClientException('All URIs failed');
  }

  // تسجيل الدخول
  static Future<api_models.EmployeeLoginResponse> login(
      String email,
      String password,
      String deviceUUID,
      String deviceName,
      String deviceType) async {
    try {
      _log('🚀 بدء طلب تسجيل الدخول...');
      _log('📧 البريد الإلكتروني: $email');
      _log('🔗 URL: ${ApiConfig.loginUrl}');
      _log('📋 Headers: ${ApiConfig.headers}');

      final requestBody = {
        'email': email,
        'password': password,
        'macAddress': deviceUUID, // سيتم استخدامه كمعرف فريد للجهاز
        'deviceName': deviceName,
        'deviceType': deviceType,
      };
      _log('📦 Request Body: ${json.encode(requestBody)}');

      http.Response response;
      if (kIsWeb) {
        final loginUri = Uri.parse(ApiConfig.wrapUrlForWeb(ApiConfig.loginUrl));
        final proxyUris = <Uri>[
          loginUri,
          if (ApiConfig.webProxyPrefix.isEmpty) ...[
            Uri.parse('https://cors.isomorphic-git.org/${ApiConfig.loginUrl}'),
            Uri.parse('https://thingproxy.freeboard.io/fetch/${ApiConfig.loginUrl}'),
            Uri.parse('https://cors.bridged.cc/${ApiConfig.loginUrl}'),
          ]
        ];
        response = await _postWithRetryUris(
          uris: proxyUris,
          headers: ApiConfig.headers,
          body: json.encode(requestBody),
          timeout: const Duration(seconds: 60),
          maxAttemptsPerUri: 2,
        );
      } else {
        response = await _postWithRetry(
          uri: Uri.parse(ApiConfig.loginUrl),
          headers: ApiConfig.headers,
          body: json.encode(requestBody),
          timeout: const Duration(seconds: 60),
          maxAttempts: 2,
        );
      }

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم تحليل الاستجابة بنجاح: $data');
        return api_models.EmployeeLoginResponse.fromJson(data);
      } else {
        if (response.statusCode == 404 || _looksLikeHtml(response.body)) {
          return api_models.EmployeeLoginResponse(
            success: false,
            message:
                'عنوان API غير صحيح أو المسار غير موجود.\nتحقق من baseUrl: ${ApiConfig.baseUrl}',
            employee: null,
          );
        }

        _log('❌ خطأ في الاستجابة: ${response.statusCode}');
        _log('📄 Response Body: ${response.body}');

        // معالجة خاصة لخطأ 401 (غير مصرح)
        if (response.statusCode == 401) {
          try {
            final errorData = json.decode(response.body);
            return api_models.EmployeeLoginResponse(
              success: false,
              message: errorData['message'] ?? 'بيانات تسجيل الدخول غير صحيحة',
              employee: null,
            );
          } catch (parseError) {
            return api_models.EmployeeLoginResponse(
              success: false,
              message: 'بيانات تسجيل الدخول غير صحيحة',
              employee: null,
            );
          }
        }

        // معالجة خاصة لخطأ 400 (طلب سيء)
        if (response.statusCode == 400) {
          try {
            final errorData = json.decode(response.body);
            return api_models.EmployeeLoginResponse(
              success: false,
              message: errorData['message'] ?? 'بيانات الطلب غير صحيحة',
              employee: null,
            );
          } catch (parseError) {
            return api_models.EmployeeLoginResponse(
              success: false,
              message: 'بيانات الطلب غير صحيحة',
              employee: null,
            );
          }
        }

        // معالجة خاصة لخطأ 500 (خطأ في الخادم)
        if (response.statusCode == 500) {
          try {
            final errorData = json.decode(response.body);
            _log('📋 Error Data (500): $errorData');
            return api_models.EmployeeLoginResponse(
              success: false,
              message: errorData['message'] ?? 'خطأ في الخادم',
              employee: null,
            );
          } catch (parseError) {
            _log('❌ خطأ في تحليل رسالة الخطأ 500: $parseError');
            return api_models.EmployeeLoginResponse(
              success: false,
              message: 'خطأ في الخادم',
              employee: null,
            );
          }
        }

        // معالجة عامة للأخطاء الأخرى
        try {
          final errorData = json.decode(response.body);
          _log('📋 Error Data (${response.statusCode}): $errorData');
          return api_models.EmployeeLoginResponse(
            success: false,
            message: errorData['message'] ?? 'حدث خطأ في تسجيل الدخول',
            employee: null,
          );
        } catch (parseError) {
          _log('❌ خطأ في تحليل رسالة الخطأ: $parseError');
          return api_models.EmployeeLoginResponse(
            success: false,
            message: 'حدث خطأ في الخادم',
            employee: null,
          );
        }
      }
    } on SocketException catch (e) {
      _log('💥 خطأ شبكة (SocketException): $e');
      return api_models.EmployeeLoginResponse(
        success: false,
        message:
            'تعذر الوصول إلى الخادم من الجهاز.\n'
            'تأكد من أن الهاتف على نفس الشبكة مع الخادم وأن العنوان صحيح:\n'
            '${ApiConfig.loginUrl}',
        employee: null,
      );
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      final msg = e.toString();
      final isLikelyCors = kIsWeb &&
          (msg.contains('Failed to fetch') ||
              msg.contains('TypeError') ||
              msg.contains('All URIs failed'));
      final isAndroidHttpPolicyIssue = !kIsWeb &&
          (msg.contains('CLEARTEXT') ||
              msg.contains('Cleartext') ||
              msg.contains('not permitted'));
      return api_models.EmployeeLoginResponse(
        success: false,
        message: isLikelyCors
            ? 'تعذر الاتصال من الويب بسبب سياسات المتصفح (CORS).\n'
                'الحلول:\n'
                '1) فعّل CORS على خادم الـ API للسماح لمصدر الويب.\n'
                '2) أو شغّل الويب في وضع تطوير يتجاوز CORS.\n'
                'الرابط الحالي: ${ApiConfig.baseUrl}'
            : isAndroidHttpPolicyIssue
                ? 'أندرويد منع الاتصال عبر HTTP غير المشفر.\n'
                    'تم ضبط التطبيق للسماح بالاتصال بالخادم المحلي، أعد بناء التطبيق ثم جرّب مرة أخرى.\n'
                    'الرابط الحالي: ${ApiConfig.loginUrl}'
                : 'خطأ في الاتصال بالخادم',
        employee: null,
      );
    } on TimeoutException catch (e) {
      _log('💥 Timeout: $e');
      return api_models.EmployeeLoginResponse(
        success: false,
        message:
            'انتهت مهلة الاتصال بالخادم.\nتحقق من أن الرابط يعمل من المتصفح:\n${ApiConfig.loginUrl}',
        employee: null,
      );
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return api_models.EmployeeLoginResponse(
        success: false,
        message: 'خطأ في الاتصال',
        employee: null,
      );
    }
  }

  // طلب استعادة كلمة المرور
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      _log('🚀 بدء طلب استعادة كلمة المرور...');
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/employee/forgot-password'),
        headers: ApiConfig.headers,
        body: json.encode({'Email': email}),
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      return json.decode(response.body);
    } catch (e) {
      _log('💥 خطأ: $e');
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  // التحقق من رمز OTP
  static Future<Map<String, dynamic>> verifyOTP(String email, String otp) async {
    try {
      _log('🚀 بدء التحقق من رمز OTP...');
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/employee/verify-otp'),
        headers: ApiConfig.headers,
        body: json.encode({'Email': email, 'OTP': otp}),
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      return json.decode(response.body);
    } catch (e) {
      _log('💥 خطأ: $e');
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  // إعادة تعيين كلمة المرور
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      _log('🚀 بدء إعادة تعيين كلمة المرور...');
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/employee/reset-password'),
        headers: ApiConfig.headers,
        body: json.encode({
          'Email': email,
          'OTP': otp,
          'NewPassword': newPassword,
          'ConfirmPassword': confirmPassword,
        }),
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      return json.decode(response.body);
    } catch (e) {
      _log('💥 خطأ: $e');
      return {'success': false, 'message': 'خطأ في الاتصال: $e'};
    }
  }

  // تسجيل الخروج
  static Future<api_models.LogoutResponse> logout() async {
    try {
      _log('🚀 بدء عملية تسجيل الخروج...');

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.logoutEndpoint}'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      _log('📡 Response Status: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        _log('✅ تم تسجيل الخروج بنجاح من الخادم');
        return api_models.LogoutResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 404) {
        _log('⚠️ نقطة تسجيل الخروج غير موجودة، لكن العملية مكتملة محلياً');
        return api_models.LogoutResponse(
          success: true,
          message: 'تم تسجيل الخروج بنجاح (محلياً)',
        );
      } else {
        _log('⚠️ تحذير: استجابة غير متوقعة من الخادم (${response.statusCode})');
        return api_models.LogoutResponse(
          success: true,
          message: 'تم تسجيل الخروج بنجاح (مع تحذير)',
        );
      }
    } catch (e) {
      _log('⚠️ تحذير: فشل في الاتصال بالخادم لتسجيل الخروج: $e');
      // نعيد نجاح حتى لو فشل الاتصال بالخادم
      return api_models.LogoutResponse(
        success: true,
        message: 'تم تسجيل الخروج بنجاح (محلياً)',
      );
    }
  }

  // اختبار الاتصال بالخادم
  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.valuesEndpoint}'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // اختبار الاتصال بنقطة تسجيل الدخول
  static Future<bool> testLoginEndpoint() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}${ApiConfig.loginEndpoint}'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));
      // حتى لو كان الخطأ 405 (Method Not Allowed) فهذا يعني أن النقطة موجودة
      return response.statusCode == 405 || response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // اختبار الاتصال بالخادم الجديد
  static Future<Map<String, dynamic>> testApiConnection() async {
    try {
      _log('🔍 اختبار الاتصال بـ API...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/employee/login');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/employee/login'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      _log('📡 Response Status: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      return {
        'success': true,
        'statusCode': response.statusCode,
        'message': response.statusCode == 405
            ? 'API متاح (Method Not Allowed يعني أن النقطة موجودة)'
            : 'API متاح',
        'body': response.body,
      };
    } on http.ClientException catch (e) {
      _log('💥 ClientException: $e');
      return {
        'success': false,
        'statusCode': 0,
        'message': 'خطأ في الاتصال بالخادم: $e',
        'body': '',
      };
    } on Exception catch (e) {
      _log('💥 Exception: $e');
      return {
        'success': false,
        'statusCode': 0,
        'message': 'خطأ في الاتصال: $e',
        'body': '',
      };
    }
  }

  // Punch Attendance - تسجيل الحضور أو الانصراف
  Future<Map<String, dynamic>> punchAttendance(
      int clientId, AttendanceModel attendance) async {
    try {
      final url = '${ApiConfig.baseUrl}/api/$clientId/attendance/punch';
      _log(
          '🚀 بدء تسجيل ${attendance.punchState == "0" ? "الحضور" : "الانصراف"}...');
      _log('👤 رقم الموظف: ${attendance.employeeNumber}');
      _log('🏢 ClientID: $clientId');
      _log(
          '📝 نوع العملية: ${attendance.punchState == "0" ? "دخول" : "خروج"} (punchState = "${attendance.punchState}")');
      _log('🔗 URL: $url');
      _log('📦 Request Body: ${jsonEncode(attendance.toJson())}');
      _log('📋 Headers: ${ApiConfig.headers}');

      final response = await http
          .post(
            Uri.parse(url),
            headers: ApiConfig.headers,
            body: jsonEncode(attendance.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status: ${response.statusCode}');
      _log('📄 Response Headers: ${response.headers}');
      _log('📄 Response Body: ${response.body}');

      // تحليل الاستجابة بغض النظر عن status code
      final result = jsonDecode(response.body);
      _log('📋 Parsed Response: $result');

      // التحقق من أن الاستجابة تحتوي على Success
      if (result is Map<String, dynamic>) {
        // إذا كان status code 200 أو 400، نعيد النتيجة كما هي
        // لأن 400 قد يكون رسالة خطأ من API (مثل "لقد سجلت الحضور مسبقاً")
        if (response.statusCode == 200 || response.statusCode == 400) {
          if (response.statusCode == 200) {
            _log(
                '✅ تم تسجيل ${attendance.punchState == "0" ? "الحضور" : "الانصراف"} بنجاح');
          } else {
            _log('⚠️ رسالة من API: ${result['Message'] ?? result['message']}');
          }
          return result;
        } else {
          // للأخطاء الأخرى (500, 404, إلخ)، نعتبرها أخطاء في الاتصال
          throw Exception(result['Message'] ??
              result['message'] ??
              'فشل في تسجيل ${attendance.punchState == "0" ? "الحضور" : "الانصراف"}: ${response.statusCode}');
        }
      } else {
        throw Exception('استجابة غير صحيحة من الخادم');
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      throw Exception('خطأ في الاتصال بالخادم: $e');
    } catch (e) {
      _log('💥 خطأ عام: $e');
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  // Check In - تسجيل الحضور (للتوافق مع الكود القديم)
  Future<Map<String, dynamic>> checkIn(
      int clientId, AttendanceModel attendance) async {
    // تحديث punchState إلى "0" للحضور
    attendance.punchState = "0";
    return await punchAttendance(clientId, attendance);
  }

  // Check Out - تسجيل الانصراف (للتوافق مع الكود القديم)
  Future<Map<String, dynamic>> checkOut(
      int clientId, AttendanceModel attendance) async {
    // تحديث punchState إلى "1" للانصراف
    attendance.punchState = "1";
    return await punchAttendance(clientId, attendance);
  }

  // جلب سجل الحضور للموظف في تاريخ محدد
  static Future<Map<String, dynamic>> getEmployeeAttendance(
      int clientId, String employeeNumber, DateTime date) async {
    try {
      _log('🚀 جلب سجل الحضور للموظف...');
      _log('👤 EmployeeNumber: $employeeNumber');
      _log('🏢 ClientID: $clientId');
      _log('📅 التاريخ: ${date.toIso8601String().split('T')[0]}');
      _log('📅 التاريخ الكامل: $date');

      final url =
          '${ApiConfig.baseUrl}/api/$clientId/attendance/employee/$employeeNumber?date=${date.toIso8601String().split('T')[0]}';
      _log('🔗 URL: $url');
      _log('🔗 Base URL: ${ApiConfig.baseUrl}');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📡 Response Headers: ${response.headers}');
      _log('📡 Response Body: ${response.body}');
      _log('📡 Response Body Length: ${response.body.length}');

      if (response.statusCode == 200) {
        try {
          final data = json.decode(response.body);
          _log('✅ تم جلب سجل الحضور بنجاح');
          _log('✅ نوع البيانات المحللة: ${data.runtimeType}');
          _log('✅ محتوى البيانات: $data');

          if (data is Map<String, dynamic>) {
            _log('✅ البيانات هي Map');
            _log('✅ مفاتيح البيانات: ${data.keys.toList()}');
            if (data.containsKey('Attendances')) {
              _log('✅ محتوى Attendances: ${data['Attendances']}');
              _log('✅ نوع Attendances: ${data['Attendances']?.runtimeType}');
            }
          }

          return data;
        } catch (parseError) {
          _log('❌ خطأ في تحليل JSON: $parseError');
          _log('❌ محتوى الاستجابة: ${response.body}');
          return {
            'Success': false,
            'Message': 'خطأ في تحليل استجابة الخادم: $parseError',
            'Attendances': [],
          };
        }
      } else {
        _log('❌ خطأ في جلب سجل الحضور: ${response.statusCode}');
        _log('❌ محتوى الخطأ: ${response.body}');
        return {
          'Success': false,
          'Message': 'فشل في جلب سجل الحضور: ${response.statusCode}',
          'Attendances': [],
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب سجل الحضور: $e');
      _log('💥 نوع الخطأ: ${e.runtimeType}');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Attendances': [],
      };
    }
  }

  // جلب إحصائيات الحضور للموظف في تاريخ محدد
  static Future<Map<String, dynamic>> getEmployeeAttendanceStats(
      int clientId, int employeeId, DateTime date) async {
    try {
      _log('🚀 جلب إحصائيات الحضور للموظف...');
      _log('👤 EmployeeID: $employeeId');
      _log('📅 التاريخ: ${date.toIso8601String().split('T')[0]}');

      final url =
          '${ApiConfig.baseUrl}/api/$clientId/attendance/stats/$employeeId?date=${date.toIso8601String().split('T')[0]}';
      _log('🔗 URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب إحصائيات الحضور بنجاح');
        return data;
      } else {
        _log('❌ خطأ في جلب إحصائيات الحضور: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب إحصائيات الحضور: ${response.statusCode}',
          'Data': {},
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب إحصائيات الحضور: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': {},
      };
    }
  }

  // جلب معلومات الموظف
  static Future<Map<String, dynamic>> getEmployeeInfo(
      int clientId, int employeeId) async {
    try {
      _log('🚀 جلب معلومات الموظف...');
      _log('👤 EmployeeID: $employeeId');

      final url =
          '${ApiConfig.baseUrl}/api/$clientId/employee/info/$employeeId';
      _log('🔗 URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب معلومات الموظف بنجاح');
        return data;
      } else {
        _log('❌ خطأ في جلب معلومات الموظف: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب معلومات الموظف: ${response.statusCode}',
          'Data': {},
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب معلومات الموظف: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': {},
      };
    }
  }

  // جلب حالة الحضور للموظف
  static Future<Map<String, dynamic>> getEmployeeAttendanceStatus(
      int clientId, int employeeId) async {
    try {
      _log('🚀 جلب حالة الحضور للموظف...');
      _log('👤 EmployeeID: $employeeId');

      final url =
          '${ApiConfig.baseUrl}/api/$clientId/attendance/status/$employeeId';
      _log('🔗 URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب حالة الحضور بنجاح');
        return data;
      } else {
        _log('❌ خطأ في جلب حالة الحضور: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب حالة الحضور: ${response.statusCode}',
          'Data': {},
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب حالة الحضور: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': {},
      };
    }
  }

  // جلب حالة الحضور الحالية للموظف (للتوافق مع الكود)
  Future<Map<String, dynamic>> getCurrentAttendanceStatus(
      int clientId, String employeeNumber) async {
    try {
      // تحويل employeeNumber إلى employeeId
      final employeeId = int.tryParse(employeeNumber);
      if (employeeId == null) {
        throw Exception('رقم الموظف غير صحيح: $employeeNumber');
      }

      final result =
          await ApiService.getEmployeeAttendanceStatus(clientId, employeeId);

      // إذا كانت النتيجة تحتوي على Data، نعيد Data فقط
      if (result['Success'] == true && result['Data'] != null) {
        return result['Data'];
      }

      // إذا لم تكن النتيجة ناجحة، نعيد النتيجة كما هي
      return result;
    } catch (e) {
      ApiService._log('💥 خطأ في جلب حالة الحضور الحالية: $e');
      return {
        'HasCheckedIn': false,
        'HasCheckedOut': false,
        'Message': e.toString(),
      };
    }
  }

  // جلب إحصائيات الحضور للموظف (للتوافق مع الكود)
  Future<Map<String, dynamic>> getAttendanceStats(
      int clientId, String employeeNumber, DateTime date) async {
    try {
      // تحويل employeeNumber إلى employeeId
      final employeeId = int.tryParse(employeeNumber);
      if (employeeId == null) {
        throw Exception('رقم الموظف غير صحيح: $employeeNumber');
      }

      final result = await ApiService.getEmployeeAttendanceStats(
          clientId, employeeId, date);

      // إذا كانت النتيجة تحتوي على Data، نعيد Data فقط
      if (result['Success'] == true && result['Data'] != null) {
        return result['Data'];
      }

      // إذا لم تكن النتيجة ناجحة، نعيد النتيجة كما هي
      return result;
    } catch (e) {
      ApiService._log('💥 خطأ في جلب إحصائيات الحضور: $e');
      return {
        'CheckInTime': null,
        'CheckOutTime': null,
        'TotalHours': null,
        'Status': 'غير محدد',
        'Message': e.toString(),
      };
    }
  }

  // الحصول على المواقع المسموح بها للحضور
  Future<Map<String, dynamic>> getAttendanceLocations([int? clientId]) async {
    try {
      if (clientId == null) {
        throw Exception("Client ID is required to get locations.");
      }

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      final url = '${ApiConfig.baseUrl}/api/$clientId/attendance/locations';
      _log('جاري الاتصال بـ: $url');

      final response = await http
          .get(
            Uri.parse(url),
            headers: headers,
          )
          .timeout(const Duration(
              seconds: 15)); // زيادة من 10 إلى 15 ثانية لتحسين الدقة

      _log('استجابة السيرفر: ${response.statusCode}');
      _log('محتوى الاستجابة: ${response.body}');

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'فشل في الحصول على المواقع: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      _log('خطأ في الحصول على المواقع: $e');
      rethrow;
    }
  }

  // إنشاء طلب سلفة
  static Future<request_models.RequestCreateResponse> createLoanRequest(
    int clientId,
    request_models.LoanRequestCreateModel model,
  ) async {
    try {
      _log('🚀 إنشاء طلب سلفة...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(model.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم إنشاء الطلب بنجاح: $data');
        return request_models.RequestCreateResponse.fromJson(data);
      } else {
        _log('❌ خطأ في الاستجابة: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          _log('📋 Error Data: $errorData');
          return request_models.RequestCreateResponse(
            success: false,
            message: errorData['Message'] ?? 'حدث خطأ في إنشاء الطلب',
          );
        } catch (parseError) {
          _log('❌ خطأ في تحليل رسالة الخطأ: $parseError');
          return request_models.RequestCreateResponse(
            success: false,
            message: 'حدث خطأ في الخادم (${response.statusCode})',
          );
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return request_models.RequestCreateResponse(
        success: false,
        message:
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      );
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return request_models.RequestCreateResponse(
        success: false,
        message: 'خطأ في الاتصال: $e',
      );
    }
  }

  // إنشاء طلب إجازة
  static Future<request_models.RequestCreateResponse> createLeaveRequest(
    int clientId,
    request_models.LeaveRequestCreateModel model,
  ) async {
    try {
      _log('🚀 إنشاء طلب إجازة...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(model.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم إنشاء الطلب بنجاح: $data');
        return request_models.RequestCreateResponse.fromJson(data);
      } else {
        _log('❌ خطأ في الاستجابة: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          _log('📋 Error Data: $errorData');
          return request_models.RequestCreateResponse(
            success: false,
            message: errorData['Message'] ?? 'حدث خطأ في إنشاء الطلب',
          );
        } catch (parseError) {
          _log('❌ خطأ في تحليل رسالة الخطأ: $parseError');
          return request_models.RequestCreateResponse(
            success: false,
            message: 'حدث خطأ في الخادم (${response.statusCode})',
          );
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return request_models.RequestCreateResponse(
        success: false,
        message:
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      );
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return request_models.RequestCreateResponse(
        success: false,
        message: 'خطأ في الاتصال: $e',
      );
    }
  }

  // إنشاء طلب من نوع "أخرى"
  static Future<request_models.RequestCreateResponse> createOtherRequest(
    int clientId,
    request_models.OtherRequestCreateModel model,
  ) async {
    try {
      _log('🚀 إنشاء طلب أخرى...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(model.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم إنشاء الطلب بنجاح: $data');
        return request_models.RequestCreateResponse.fromJson(data);
      } else {
        _log('❌ خطأ في الاستجابة: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          _log('📋 Error Data: $errorData');
          return request_models.RequestCreateResponse(
            success: false,
            message: errorData['Message'] ?? 'حدث خطأ في إنشاء الطلب',
          );
        } catch (parseError) {
          _log('❌ خطأ في تحليل رسالة الخطأ: $parseError');
          return request_models.RequestCreateResponse(
            success: false,
            message: 'حدث خطأ في الخادم (${response.statusCode})',
          );
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return request_models.RequestCreateResponse(
        success: false,
        message:
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      );
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return request_models.RequestCreateResponse(
        success: false,
        message: 'خطأ في الاتصال: $e',
      );
    }
  }

  // إنشاء طلب إضافة بصمة
  static Future<request_models.RequestCreateResponse> createManualPunchRequest(
    int clientId,
    request_models.ManualPunchRequestCreateModel model,
  ) async {
    try {
      _log('🚀 إنشاء طلب إضافة بصمة...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests/manual-punch');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests/manual-punch'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(model.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم إنشاء طلب البصمة بنجاح: $data');
        return request_models.RequestCreateResponse.fromJson(data);
      } else {
        _log('❌ خطأ في الاستجابة: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          _log('📋 Error Data: $errorData');
          return request_models.RequestCreateResponse(
            success: false,
            message: errorData['Message'] ?? 'حدث خطأ في إنشاء طلب البصمة',
          );
        } catch (parseError) {
          _log('❌ خطأ في تحليل رسالة الخطأ: $parseError');
          return request_models.RequestCreateResponse(
            success: false,
            message: 'حدث خطأ في الخادم (${response.statusCode})',
          );
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return request_models.RequestCreateResponse(
        success: false,
        message:
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      );
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return request_models.RequestCreateResponse(
        success: false,
        message: 'خطأ في الاتصال: $e',
      );
    }
  }

  static Future<request_models.RequestCreateResponse> createExitReturnRequest(
    int clientId,
    request_models.ExitReturnRequestCreateModel model,
  ) async {
    try {
      _log('🚀 إنشاء طلب تأشيرة خروج وعودة...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(model.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم إنشاء الطلب بنجاح: $data');
        return request_models.RequestCreateResponse.fromJson(data);
      } else {
        _log('❌ خطأ في الاستجابة: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          _log('📋 Error Data: $errorData');
          return request_models.RequestCreateResponse(
            success: false,
            message: errorData['Message'] ?? 'حدث خطأ في إنشاء الطلب',
          );
        } catch (_) {
          return request_models.RequestCreateResponse(
            success: false,
            message: 'حدث خطأ في الخادم (${response.statusCode})',
          );
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return request_models.RequestCreateResponse(
        success: false,
        message:
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      );
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return request_models.RequestCreateResponse(
        success: false,
        message: 'خطأ في الاتصال: $e',
      );
    }
  }

  static Future<request_models.RequestCreateResponse> createPermissionRequest(
    int clientId,
    request_models.PermissionRequestCreateModel model,
  ) async {
    try {
      _log('🚀 إنشاء طلب استئذان...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests');

      final response = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(model.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم إنشاء الطلب بنجاح: $data');
        return request_models.RequestCreateResponse.fromJson(data);
      } else {
        _log('❌ خطأ في الاستجابة: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          _log('📋 Error Data: $errorData');
          return request_models.RequestCreateResponse(
            success: false,
            message: errorData['Message'] ?? 'حدث خطأ في إنشاء الطلب',
          );
        } catch (_) {
          return request_models.RequestCreateResponse(
            success: false,
            message: 'حدث خطأ في الخادم (${response.statusCode})',
          );
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return request_models.RequestCreateResponse(
        success: false,
        message:
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      );
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return request_models.RequestCreateResponse(
        success: false,
        message: 'خطأ في الاتصال: $e',
      );
    }
  }

  // جلب أنواع السلف
  static Future<List<request_models.LoanType>> getLoanTypes(
      int clientId) async {
    try {
      _log('🚀 جلب أنواع السلف...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests/loan-types');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests/loan-types'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);

        // التحقق من نوع البيانات المستلمة
        List<dynamic> data;
        if (responseData is List) {
          // إذا كانت البيانات مباشرة كـ List
          data = responseData;
        } else if (responseData is Map<String, dynamic>) {
          // إذا كانت البيانات في Map مع field "Data"
          data = responseData['Data'] ?? [];
        } else {
          _log('❌ نوع بيانات غير متوقع: ${responseData.runtimeType}');
          return [];
        }

        final loanTypes =
            data.map((json) => request_models.LoanType.fromJson(json)).toList();
        _log('✅ تم جلب أنواع السلف بنجاح: ${loanTypes.length} نوع');
        return loanTypes;
      } else {
        _log('❌ خطأ في جلب أنواع السلف: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _log('💥 خطأ في جلب أنواع السلف: $e');
      return [];
    }
  }

  // جلب أنواع الإجازات
  static Future<List<request_models.LeaveType>> getLeaveTypes(
      int clientId) async {
    try {
      _log('🚀 جلب أنواع الإجازات...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests/leave-types');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests/leave-types'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);

        // التحقق من نوع البيانات المستلمة
        List<dynamic> data;
        if (responseData is List) {
          // إذا كانت البيانات مباشرة كـ List
          data = responseData;
        } else if (responseData is Map<String, dynamic>) {
          // إذا كانت البيانات في Map مع field "Data"
          data = responseData['Data'] ?? [];
        } else {
          _log('❌ نوع بيانات غير متوقع: ${responseData.runtimeType}');
          return [];
        }

        final leaveTypes = data
            .map((json) => request_models.LeaveType.fromJson(json))
            .toList();
        _log('✅ تم جلب أنواع الإجازات بنجاح: ${leaveTypes.length} نوع');
        return leaveTypes;
      } else {
        _log('❌ خطأ في جلب أنواع الإجازات: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _log('💥 خطأ في جلب أنواع الإجازات: $e');
      return [];
    }
  }

  // جلب الطلبات
  static Future<Map<String, dynamic>> getRequests(
    int clientId, {
    int? employeeId,
    String? requestType,
    String? status,
    String? priority,
    String? startDate,
    String? endDate,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      _log('🚀 جلب الطلبات...');

      // بناء query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };

      if (employeeId != null) {
        queryParams['employeeId'] = employeeId.toString();
      }
      if (requestType != null) {
        queryParams['requestType'] = requestType;
      }
      if (status != null) {
        queryParams['status'] = status;
      }
      if (priority != null) {
        queryParams['priority'] = priority;
      }
      if (startDate != null) {
        queryParams['startDate'] = startDate;
      }
      if (endDate != null) {
        queryParams['endDate'] = endDate;
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests')
          .replace(queryParameters: queryParams);

      _log('🔗 URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب الطلبات بنجاح');
        return data;
      } else {
        _log('❌ خطأ في جلب الطلبات: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب الطلبات: ${response.statusCode}',
          'Data': [],
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب الطلبات: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  // جلب الطلبات المعلقة للموافقة
  static Future<Map<String, dynamic>> getPendingRequestsForApproval(
    int clientId, {
    int? approverId,
  }) async {
    try {
      _log('🚀 جلب الطلبات المعلقة للموافقة...');

      // بناء query parameters
      final queryParams = <String, String>{};

      if (approverId != null) {
        queryParams['approverId'] = approverId.toString();
      }

      // استخدام endpoint الموافقات الصحيح
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/approvals')
          .replace(queryParameters: queryParams);

      _log('🔗 URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب الطلبات المعلقة بنجاح');
        return data;
      } else {
        _log('❌ خطأ في جلب الطلبات المعلقة: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          return {
            'Success': false,
            'Message': errorData['Message'] ??
                'فشل في جلب الطلبات المعلقة: ${response.statusCode}',
            'Data': const [],
          };
        } catch (_) {
          return {
            'Success': false,
            'Message': 'فشل في جلب الطلبات المعلقة: ${response.statusCode}',
            'Data': const [],
          };
        }
      }
    } catch (e) {
      _log('💥 خطأ في جلب الطلبات المعلقة: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  // الموافقة أو رفض الطلب من قبل المعتمد نفسه
  static Future<Map<String, dynamic>> approveRequest(
    int clientId, {
    required String requestId,
    required int approverId,
    required bool approved,
    String? rejectionReason,
  }) async {
    try {
      _log(
          '🚀 ${approved ? 'الموافقة على' : 'رفض'} الطلب من قبل المعتمد نفسه...');
      _log('🆔 Request ID: $requestId');
      _log('👤 Approver ID: $approverId');
      _log('✅ Approved: $approved');
      if (rejectionReason != null) {
        _log('❌ Rejection Reason: $rejectionReason');
      }

      final requestBody = {
        'Comments': rejectionReason ?? (approved ? 'تمت الموافقة' : 'تم الرفض'),
      };

      // استخدام endpoint جديد مع المعتمد في الرابط
      final String endpoint = approved ? 'approve' : 'reject';
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/approvals/$requestId/$endpoint/$approverId');
      _log('🔗 URL: $uri');
      _log('📋 Method: POST');
      _log(
          '📋 Headers: Content-Type: application/json, Accept: application/json');
      _log('📋 Body: ${json.encode(requestBody)}');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم ${approved ? 'الموافقة على' : 'رفض'} الطلب بنجاح');
        return data;
      } else {
        _log(
            '❌ خطأ في ${approved ? 'الموافقة على' : 'رفض'} الطلب: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          return {
            'Success': false,
            'Message': errorData['Message'] ??
                'فشل في ${approved ? 'الموافقة على' : 'رفض'} الطلب',
          };
        } catch (parseError) {
          return {
            'Success': false,
            'Message': 'حدث خطأ في الخادم (${response.statusCode})',
          };
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return {
        'Success': false,
        'Message':
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      };
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
      };
    }
  }

  // جلب تفاصيل طلب
  static Future<Map<String, dynamic>> getRequestDetails(
    int clientId,
    int requestId,
  ) async {
    try {
      _log('🚀 جلب تفاصيل الطلب...');
      _log('🆔 Request ID: $requestId');

      final uri =
          Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests/$requestId');
      _log('🔗 URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب تفاصيل الطلب بنجاح');
        return data;
      } else {
        _log('❌ خطأ في جلب تفاصيل الطلب: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب تفاصيل الطلب: ${response.statusCode}',
          'Data': null,
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب تفاصيل الطلب: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': null,
      };
    }
  }

  // جلب تفاصيل طلب للموافقة
  static Future<Map<String, dynamic>> getApprovalDetails(
    int clientId,
    String requestId,
  ) async {
    try {
      _log('🚀 جلب تفاصيل الطلب للموافقة...');
      _log('🆔 Request ID: $requestId');

      final uri =
          Uri.parse('${ApiConfig.baseUrl}/api/$clientId/approvals/$requestId');
      _log('🔗 URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب تفاصيل الطلب بنجاح');
        return data;
      } else {
        _log('❌ خطأ في جلب تفاصيل الطلب: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب تفاصيل الطلب: ${response.statusCode}',
          'Data': null,
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب تفاصيل الطلب: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': null,
      };
    }
  }

  // جلب معلومات الموظف الكاملة
  Future<EmployeeFullInfo> getEmployeeFullInfo(
      int clientId, String email) async {
    try {
      _log('🚀 جلب معلومات الموظف الكاملة...');
      _log('👤 البريد الإلكتروني: $email');
      _log('🏢 ClientID: $clientId');

      final url = '${ApiConfig.baseUrl}/api/employee-full-info/$clientId/get';
      _log('🔗 URL: $url');

      final requestBody = {
        'Email': email,
      };
      _log('📦 Request Body: ${json.encode(requestBody)}');

      final response = await http
          .post(
            Uri.parse(url),
            headers: ApiConfig.headers,
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب معلومات الموظف الكاملة بنجاح');
        return EmployeeFullInfo.fromJson(data);
      } else {
        _log('❌ خطأ في جلب معلومات الموظف: ${response.statusCode}');
        throw Exception('فشل في جلب معلومات الموظف: ${response.statusCode}');
      }
    } catch (e) {
      _log('💥 خطأ في جلب معلومات الموظف: $e');
      throw Exception('خطأ في الاتصال: $e');
    }
  }

  Future<EmployeeInfo?> getEmployeeBasicInfo(int clientId, String employeeKey) async {
    try {
      final key = employeeKey.trim();
      if (key.isEmpty) return null;

      final url = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/employee/basic/$key');
      _log('🚀 جلب معلومات الموظف الأساسية...');
      _log('🔗 URL: $url');

      final response = await http
          .get(
            url,
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode != 200) return null;

      final jsonData = json.decode(response.body);
      if (jsonData is Map<String, dynamic>) {
        final data = jsonData['Data'];
        if (data is Map) {
          return EmployeeInfo.fromJson(Map<String, dynamic>.from(data));
        }
      }
      if (jsonData is Map) {
        return EmployeeInfo.fromJson(Map<String, dynamic>.from(jsonData));
      }
      return null;
    } catch (e) {
      _log('💥 خطأ في getEmployeeBasicInfo: $e');
      return null;
    }
  }

  // جلب معلومات وردية الموظف
  static Future<List<shift_models.ShiftData>> getEmployeeShift(
      int clientId, String? employeeNumber) async {
    try {
      lastEmployeeShiftMessage = null;
      if (employeeNumber == null || employeeNumber.isEmpty) {
        _log('⚠️ EmployeeNumber is null or empty, returning empty list');
        lastEmployeeShiftMessage = 'رقم الموظف غير متوفر';
        return [];
      }
      _log('🚀 جلب معلومات الورديات...');
      _log('👤 EmployeeNumber: $employeeNumber');
      _log('🏢 ClientID: $clientId');

      final url = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/attendance/shift/$employeeNumber');
      _log('🔗 URL: $url');

      final response = await http
          .get(
            url,
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        _log('✅ Raw Shift API Response: $jsonData');
        if (jsonData is Map<String, dynamic>) {
          lastEmployeeShiftMessage =
              (jsonData['Message'] ?? jsonData['message'])?.toString();
        }
        
        if (jsonData is Map<String, dynamic> && jsonData.containsKey('Data')) {
             final data = jsonData['Data'];
             if (data == null) {
                _log('⚠️ Data is null in response');
                lastEmployeeShiftMessage ??= 'لا توجد ورديات مسندة حالياً';
                return [];
             }
             
             if (data is List) {
                return data.map((e) => shift_models.ShiftData.fromJson(e)).toList();
             } else {
                return [shift_models.ShiftData.fromJson(data)];
             }
        }
        
        if (jsonData is List) {
           return jsonData.map((e) => shift_models.ShiftData.fromJson(e)).toList();
        }
        
        return [shift_models.ShiftData.fromJson(jsonData)];
      } else if (response.statusCode == 404) {
        _log('⚠️ API returned 404: Not Found');
        try {
          final jsonData = json.decode(response.body);
          if (jsonData is Map<String, dynamic>) {
            lastEmployeeShiftMessage =
                (jsonData['Message'] ?? jsonData['message'])?.toString();
          }
        } catch (_) {}
        return [];
      } else {
        _log('❌ خطأ في جلب معلومات الوردية: ${response.statusCode}');
        lastEmployeeShiftMessage = 'خطأ في جلب معلومات الوردية';
        return [];
      }
    } catch (e) {
      _log('💥 خطأ عام في getEmployeeShift: $e');
      lastEmployeeShiftMessage = 'خطأ في الاتصال بجلب الوردية';
      return [];
    }
  }

  static Future<List<EmployeeAssignedLocation>> getEmployeeAssignedLocations(
    int clientId,
    String employeeNumber,
  ) async {
    try {
      final key = employeeNumber.trim();
      if (key.isEmpty) return [];

      final url = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/employee/locations/$key');
      _log('🚀 جلب مواقع عمل الموظف...');
      _log('🔗 URL: $url');

      final response = await http
          .get(
            url,
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode != 200) return [];

      final jsonData = json.decode(response.body);
      if (jsonData is Map<String, dynamic>) {
        final list = jsonData['AssignedLocations'];
        if (list is List) {
          return list
              .whereType<Map>()
              .map((e) => EmployeeAssignedLocation.fromJson(
                    Map<String, dynamic>.from(e),
                  ))
              .toList();
        }
      }
      return [];
    } catch (e) {
      _log('💥 خطأ في getEmployeeAssignedLocations: $e');
      return [];
    }
  }

  static Future<List<shift_models.ShiftData>> getEmployeeShiftsAll(
      int clientId, String? employeeNumber) async {
    try {
      lastEmployeeShiftMessage = null;
      if (employeeNumber == null || employeeNumber.isEmpty) {
        lastEmployeeShiftMessage = 'رقم الموظف غير متوفر';
        return [];
      }

      final url =
          Uri.parse('${ApiConfig.baseUrl}/api/$clientId/attendance/shifts/$employeeNumber');
      _log('🚀 جلب جميع ورديات الموظف...');
      _log('🔗 URL: $url');

      final response = await http
          .get(
            url,
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        if (jsonData is Map<String, dynamic>) {
          lastEmployeeShiftMessage =
              (jsonData['Message'] ?? jsonData['message'])?.toString();
          final data = jsonData['Data'];
          if (data is List) {
            return data
                .whereType<Map>()
                .map((e) => shift_models.ShiftData.fromJson(
                    Map<String, dynamic>.from(e)))
                .toList();
          }
          if (data is Map) {
            return [
              shift_models.ShiftData.fromJson(Map<String, dynamic>.from(data))
            ];
          }
          return [];
        }
        if (jsonData is List) {
          return jsonData
              .whereType<Map>()
              .map((e) =>
                  shift_models.ShiftData.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        if (jsonData is Map<String, dynamic>) {
          return [shift_models.ShiftData.fromJson(jsonData)];
        }
        return [];
      }

      if (response.statusCode == 404) {
        return await getEmployeeShift(clientId, employeeNumber);
      }

      lastEmployeeShiftMessage = 'خطأ في جلب جميع الورديات';
      return [];
    } catch (e) {
      _log('💥 خطأ عام في getEmployeeShiftsAll: $e');
      return await getEmployeeShift(clientId, employeeNumber);
    }
  }

  static Future<List<MobileAdvertisement>> getActiveMobileAdvertisements(
      int clientId) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/ads/active');
      _log('🚀 جلب إعلانات التطبيق...');
      _log('🔗 URL: $uri');

      final response = await http
          .get(
            uri,
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 20));

      _log('📡 Response Status Code: ${response.statusCode}');

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['Data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) =>
                  MobileAdvertisement.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        return [];
      }

      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => MobileAdvertisement.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      return [];
    } catch (e) {
      _log('💥 خطأ في getActiveMobileAdvertisements: $e');
      return [];
    }
  }

  static Future<List<AppNotice>> getActiveAppNotices({
    required String placement,
  }) async {
    try {
      final base = Uri.parse('${ApiConfig.baseUrl}/api/app-notices/active');
      final uri = base.replace(queryParameters: {
        'placement': placement.trim(),
      });
      _log('🚀 جلب تنبيهات التطبيق...');
      _log('🔗 URL: $uri');

      final response = await http
          .get(
            uri,
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 20));

      _log('📡 Response Status Code: ${response.statusCode}');

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['Data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => AppNotice.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        return [];
      }

      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => AppNotice.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      return [];
    } catch (e) {
      _log('💥 خطأ في getActiveAppNotices: $e');
      return [];
    }
  }

  static Future<List<api_models.CompanyHoliday>> getCompanyHolidaysInRange(
    int clientId, {
    required int employeeId,
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    String fmt(DateTime d) {
      final y = d.year.toString().padLeft(4, '0');
      final m = d.month.toString().padLeft(2, '0');
      final day = d.day.toString().padLeft(2, '0');
      return '$y-$m-$day';
    }

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/company-holidays')
          .replace(queryParameters: {
        'from': fmt(fromDate),
        'to': fmt(toDate),
        'employeeId': employeeId.toString(),
      });
      _log('🚀 جلب الإجازات الرسمية...');
      _log('🔗 URL: $uri');

      final response = await http
          .get(
            uri,
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 25));

      _log('📡 Response Status Code: ${response.statusCode}');

      if (response.statusCode != 200) {
        return [];
      }

      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final data = decoded['Data'];
        if (data is List) {
          return data
              .whereType<Map>()
              .map((e) => api_models.CompanyHoliday.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList();
        }
      }

      return [];
    } catch (e) {
      _log('💥 خطأ في getCompanyHolidaysInRange: $e');
      return [];
    }
  }

  // تغيير كلمة المرور
  Future<Map<String, dynamic>> changePassword({
    required int clientId,
    required String email,
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      _log('🚀 بدء تغيير كلمة المرور...');
      _log('📧 البريد الإلكتروني: $email');
      _log(
          '🔗 URL: ${ApiConfig.baseUrl}/api/employee-full-info/$clientId/update-password');

      final requestBody = {
        'Email': email,
        'CurrentPassword': currentPassword,
        'NewPassword': newPassword,
        'ConfirmPassword': confirmPassword,
      };
      _log('📦 Request Body: ${json.encode(requestBody)}');

      final response = await http
          .post(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/employee-full-info/$clientId/update-password'),
            headers: ApiConfig.headers,
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم تغيير كلمة المرور بنجاح');
        return {
          'success': true,
          'message': 'تم تغيير كلمة المرور بنجاح',
          'data': data,
        };
      } else {
        _log('❌ خطأ في تغيير كلمة المرور: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          return {
            'success': false,
            'message': errorData['message'] ??
                errorData['Message'] ??
                'فشل في تغيير كلمة المرور',
          };
        } catch (parseError) {
          return {
            'success': false,
            'message': 'حدث خطأ في الخادم (${response.statusCode})',
          };
        }
      }
    } on http.ClientException catch (e) {
      _log('💥 خطأ في العميل (ClientException): $e');
      return {
        'success': false,
        'message':
            'خطأ في الاتصال بالخادم. تأكد من أن الخادم يعمل وأن العنوان صحيح.',
      };
    } on Exception catch (e) {
      _log('💥 خطأ عام: $e');
      return {
        'success': false,
        'message': 'خطأ في الاتصال: $e',
      };
    }
  }

  // جلب أنواع الطلبات المتاحة (التي تحتوي على مسارات)
  static Future<List<api_models.RequestType>> getRequestTypes(
      int clientId) async {
    try {
      _log('🚀 جلب أنواع الطلبات المتاحة...');
      _log('🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests/request-types');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests/request-types'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);

        // التحقق من نوع البيانات المستلمة
        List<dynamic> data;
        if (responseData is List) {
          // إذا كانت البيانات مباشرة كـ List
          data = responseData;
        } else if (responseData is Map<String, dynamic>) {
          // إذا كانت البيانات في Map مع field "Data"
          data = responseData['Data'] ?? [];
        } else {
          _log('❌ نوع بيانات غير متوقع: ${responseData.runtimeType}');
          return [];
        }

        final requestTypes =
            data.map((json) => api_models.RequestType.fromJson(json)).toList();
        _log('✅ تم جلب أنواع الطلبات بنجاح: ${requestTypes.length} نوع');
        return requestTypes;
      } else {
        _log('❌ خطأ في جلب أنواع الطلبات: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      _log('💥 خطأ في جلب أنواع الطلبات: $e');
      return [];
    }
  }

  // جلب مسار الطلب
  static Future<api_models.WorkflowData?> getWorkflow(
    int clientId,
    String requestType,
    int employeeId,
  ) async {
    try {
      _log('🚀 جلب مسار الطلب...');
      _log(
          '🔗 URL: ${ApiConfig.baseUrl}/api/$clientId/requests/workflow/$requestType/$employeeId');

      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/$clientId/requests/workflow/$requestType/$employeeId'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic responseData = json.decode(response.body);

        if (responseData is Map<String, dynamic> &&
            responseData['Success'] == true) {
          final data = responseData['Data'];
          if (data != null) {
            final workflowData = api_models.WorkflowData.fromJson(data);
            _log('✅ تم جلب المسار بنجاح: ${workflowData.workflowName}');
            return workflowData;
          }
        }

        _log('❌ لم يتم العثور على مسار لهذا النوع من الطلبات');
        return null;
      } else {
        _log('❌ خطأ في جلب المسار: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _log('💥 خطأ في جلب المسار: $e');
      return null;
    }
  }

  // جلب مرفقات طلب معين - النقطة الاحترافية
  static Future<Map<String, dynamic>> getRequestAttachments(
    int clientId,
    int requestId,
  ) async {
    try {
      _log('🚀 جلب مرفقات الطلب (النقطة الاحترافية)...');
      _log('🆔 Request ID: $requestId');
      _log('📋 جدول المرفقات: RequestAttachments');
      _log(
          '📋 حقول الجدول: ID, RequestID, FileName, FileContent, FileType, FileSize, CreatedBy, CreatedDate');

      // استخدام النقطة الصحيحة التي تعمل
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/approvals/$requestId/attachments');
      _log('🔗 URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب المرفقات بنجاح (النقطة الاحترافية)');

        // استخراج المرفقات من البيانات
        List<dynamic> attachments = [];
        if (data['Success'] == true && data['Data'] != null) {
          if (data['Data'] is List) {
            attachments = data['Data'] as List<dynamic>;
          } else if (data['Data'] is Map<String, dynamic>) {
            final requestData = data['Data'] as Map<String, dynamic>;
            if (requestData['Attachments'] != null) {
              attachments = requestData['Attachments'] as List<dynamic>;
            }
          }
          _log('📋 تم العثور على ${attachments.length} مرفق');
        }

        return {
          'Success': true,
          'Data': attachments,
          'Message': 'تم جلب المرفقات بنجاح',
        };
      } else {
        _log('❌ خطأ في جلب المرفقات: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب المرفقات: ${response.statusCode}',
          'Data': [],
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب المرفقات: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  // جلب مرفقات طلب معين - نقطة بديلة
  static Future<Map<String, dynamic>> getRequestAttachmentsAlternative(
    int clientId,
    int requestId,
  ) async {
    try {
      _log('🚀 جلب مرفقات الطلب (نقطة بديلة)...');
      _log('🆔 Request ID: $requestId');
      _log('📋 جدول المرفقات: RequestAttachments');
      _log(
          '📋 حقول الجدول: ID, RequestID, FileName, FileContent, FileType, FileSize, CreatedBy, CreatedDate');

      // استخدام نقطة API بديلة حسب View.aspx.cs
      final uri =
          Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests/$requestId');
      _log('🔗 URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب المرفقات بنجاح (نقطة بديلة)');

        // استخراج المرفقات من البيانات
        List<dynamic> attachments = [];
        if (data['Success'] == true && data['Data'] != null) {
          final requestData = data['Data'] as Map<String, dynamic>;
          if (requestData['Attachments'] != null) {
            attachments = requestData['Attachments'] as List<dynamic>;
            _log('📋 تم العثور على ${attachments.length} مرفق (نقطة بديلة)');
          }
        }

        return {
          'Success': true,
          'Data': attachments,
          'Message': 'تم جلب المرفقات بنجاح',
        };
      } else {
        _log('❌ خطأ في جلب المرفقات (نقطة بديلة): ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب المرفقات: ${response.statusCode}',
          'Data': [],
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب المرفقات (نقطة بديلة): $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  // تحميل مرفق معين
  static Future<Map<String, dynamic>> downloadAttachment(
    int clientId,
    int requestId,
    int attachmentId,
  ) async {
    try {
      _log('🚀 تحميل المرفق...');
      _log('🆔 Request ID: $requestId, Attachment ID: $attachmentId');

      // استخدام نقطة النهاية الصحيحة من ApprovalsController
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/approvals/$requestId/attachments/$attachmentId/download');
      _log('🔗 URL: $uri');
      _log('📋 جدول المرفقات: RequestAttachments');
      _log(
          '📋 SQL Query: SELECT FileName, FileContent, FileType, FileSize FROM RequestAttachments WHERE ID = @AttachmentID AND RequestID = @RequestID');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/octet-stream',
        },
      ).timeout(const Duration(seconds: 60));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body Length: ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        _log('✅ تم تحميل المرفق بنجاح');
        return {
          'Success': true,
          'Data': response.bodyBytes,
          'Message': 'تم التحميل بنجاح',
        };
      } else {
        _log('❌ خطأ في تحميل المرفق: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في تحميل المرفق: ${response.statusCode}',
          'Data': null,
        };
      }
    } catch (e) {
      _log('💥 خطأ في تحميل المرفق: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': null,
      };
    }
  }

  // جلب رابط المرفق
  static Future<Map<String, dynamic>> getAttachmentUrl(
    int clientId,
    int requestId,
    int attachmentId,
  ) async {
    try {
      _log('🚀 جلب رابط المرفق...');
      _log('🆔 Request ID: $requestId, Attachment ID: $attachmentId');

      // استخدام نقطة النهاية الصحيحة من ApprovalsController
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/approvals/$requestId/attachments/$attachmentId/download');
      _log('🔗 URL: $uri');
      _log('📋 جدول المرفقات: RequestAttachments');
      _log(
          '📋 SQL Query: SELECT FileName, FileContent, FileType, FileSize FROM RequestAttachments WHERE ID = @AttachmentID AND RequestID = @RequestID');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/octet-stream',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body Length: ${response.bodyBytes.length} bytes');

      if (response.statusCode == 200) {
        _log('✅ تم جلب المرفق بنجاح');
        return {
          'Success': true,
          'Data': response.bodyBytes,
          'Message': 'تم جلب المرفق بنجاح',
        };
      } else {
        _log('❌ خطأ في جلب المرفق: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب المرفق: ${response.statusCode}',
          'Data': null,
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب المرفق: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': null,
      };
    }
  }

  // جلب مرفقات الطلب من الطلب نفسه
  static Future<Map<String, dynamic>> getRequestAttachmentsFromRequest(
    int clientId,
    int requestId,
  ) async {
    try {
      _log('🚀 جلب مرفقات الطلب من الطلب نفسه...');
      _log('🆔 Request ID: $requestId');
      _log('📋 جدول المرفقات: RequestAttachments');
      _log(
          '📋 حقول الجدول: ID, RequestID, FileName, FileContent, FileType, FileSize, CreatedBy, CreatedDate');

      final uri =
          Uri.parse('${ApiConfig.baseUrl}/api/$clientId/requests/$requestId');
      _log('🔗 URL: $uri');

      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // البحث عن المرفقات في بيانات الطلب
        List<dynamic> attachments = [];

        if (data is Map<String, dynamic>) {
          // البحث في المستوى الأول
          if (data['Attachments'] != null) {
            attachments = data['Attachments'] as List<dynamic>;
          } else if (data['Data'] != null &&
              data['Data'] is Map<String, dynamic>) {
            // البحث في المستوى الثاني
            final requestData = data['Data'] as Map<String, dynamic>;
            if (requestData['Attachments'] != null) {
              attachments = requestData['Attachments'] as List<dynamic>;
            }
          }
        }

        _log('✅ تم جلب مرفقات الطلب بنجاح: ${attachments.length} مرفق');
        return {
          'Success': true,
          'Data': attachments,
          'Message': 'تم جلب المرفقات بنجاح',
        };
      } else {
        _log('❌ خطأ في جلب مرفقات الطلب: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في جلب مرفقات الطلب: ${response.statusCode}',
          'Data': [],
        };
      }
    } catch (e) {
      _log('💥 خطأ في جلب مرفقات الطلب: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  // رفض طلب
  static Future<Map<String, dynamic>> rejectRequest(
    int clientId,
    int requestId, {
    String? comments,
    int? approverId,
  }) async {
    try {
      _log('🚀 رفض الطلب...');
      _log('🆔 Request ID: $requestId, Approver ID: $approverId');

      String url;
      if (approverId != null) {
        url =
            '${ApiConfig.baseUrl}/api/$clientId/approvals/$requestId/reject/$approverId';
      } else {
        url = '${ApiConfig.baseUrl}/api/$clientId/approvals/$requestId/reject';
      }

      final uri = Uri.parse(url);
      _log('🔗 URL: $uri');

      final requestBody = {
        'Comments': comments ?? '',
        'ApproverID': approverId,
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم رفض الطلب بنجاح');
        return data;
      } else {
        _log('❌ خطأ في رفض الطلب: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في رفض الطلب: ${response.statusCode}',
        };
      }
    } catch (e) {
      _log('💥 خطأ في رفض الطلب: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
      };
    }
  }

  // الموافقة على طلب HR
  static Future<Map<String, dynamic>> approveHRRequest(
    int clientId,
    int approvalId, {
    String? comments,
  }) async {
    try {
      _log('🚀 الموافقة على طلب HR...');
      _log('🆔 Approval ID: $approvalId');

      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/approvals/$approvalId/approve-hr');
      _log('🔗 URL: $uri');

      final requestBody = {
        'Comments': comments ?? '',
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تمت الموافقة على طلب HR بنجاح');
        return data;
      } else {
        _log('❌ خطأ في الموافقة على طلب HR: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في الموافقة على طلب HR: ${response.statusCode}',
        };
      }
    } catch (e) {
      _log('💥 خطأ في الموافقة على طلب HR: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
      };
    }
  }

  // رفض طلب HR
  static Future<Map<String, dynamic>> rejectHRRequest(
    int clientId,
    int approvalId, {
    String? comments,
  }) async {
    try {
      _log('🚀 رفض طلب HR...');
      _log('🆔 Approval ID: $approvalId');

      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/approvals/$approvalId/reject-hr');
      _log('🔗 URL: $uri');

      final requestBody = {
        'Comments': comments ?? '',
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم رفض طلب HR بنجاح');
        return data;
      } else {
        _log('❌ خطأ في رفض طلب HR: ${response.statusCode}');
        return {
          'Success': false,
          'Message': 'فشل في رفض طلب HR: ${response.statusCode}',
        };
      }
    } catch (e) {
      _log('💥 خطأ في رفض طلب HR: $e');
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
      };
    }
  }

  // جلب الإشعارات
  static Future<List<NotificationModel>> getNotifications(
    int clientId,
    int employeeId, {
    bool unreadOnly = false,
  }) async {
    try {
      _log('🚀 جلب الإشعارات...');
      if (ApiConfig.baseUrl.isEmpty) {
        _log('❌ ApiConfig.baseUrl فارغ - لن يتم جلب الإشعارات');
        return [];
      }
      final uri = Uri.parse(
              '${ApiConfig.baseUrl}/api/$clientId/notifications/$employeeId')
          .replace(queryParameters: {'unreadOnly': unreadOnly.toString()});
      _log('📡 Notifications URI: $uri');

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          return decoded.map((e) => NotificationModel.fromJson(e)).toList();
        }
        if (decoded is Map) {
          final data = decoded['Data'] ?? decoded['data'] ?? decoded['result'];
          final success = decoded['Success'] ?? decoded['success'];
          final message = decoded['Message'] ?? decoded['message'];
          if ((success == null || success == true) && data is List) {
            return data.map((e) => NotificationModel.fromJson(e)).toList();
          }
          if ((success == null || success == true) && data is String) {
            try {
              final parsed = json.decode(data);
              if (parsed is List) {
                return parsed.map((e) => NotificationModel.fromJson(e)).toList();
              }
            } catch (_) {}
          }
          if (success == false) {
            throw Exception(message ?? 'فشل في تحميل الإشعارات');
          }
          _log('⚠️ صيغة رد الإشعارات غير متوقعة: $decoded');
        }
      } else {
        _log('❌ Notifications status: ${response.statusCode}');
        _log('📄 Notifications body: ${response.body}');
        throw Exception('Notifications API failed: ${response.statusCode}');
      }
      return [];
    } catch (e) {
      _log('💥 خطأ في جلب الإشعارات: $e');
      return [];
    }
  }

  // تحديث حالة الإشعار
  static Future<bool> markNotificationRead(
      int clientId, int notificationId) async {
    try {
      final response = await http.post(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/$clientId/notifications/mark-read/$notificationId'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> markAllNotificationsRead(int clientId, int employeeId) async {
    try {
      final response = await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/notifications/mark-all-read/$employeeId'),
            headers: {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> markNotificationsReadBulk(
    int clientId,
    int employeeId,
    List<int> notificationIds,
  ) async {
    try {
      if (notificationIds.isEmpty) return true;
      final response = await http
          .put(
            Uri.parse('${ApiConfig.baseUrl}/api/$clientId/notifications/read-bulk'),
            headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
            body: json.encode({
              'EmployeeID': employeeId,
              'NotificationIDs': notificationIds,
            }),
          )
          .timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // جلب عدد الإشعارات غير المقروءة
  static Future<int> getUnreadNotificationsCount(
      int clientId, int employeeId) async {
    try {
      final response = await http.get(
        Uri.parse(
            '${ApiConfig.baseUrl}/api/$clientId/notifications/count/$employeeId'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['Count'] ?? 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  // جلب أعداد الطلبات المعلقة
  static Future<PendingCounts?> getPendingCounts(
      int clientId, int employeeId) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                '${ApiConfig.baseUrl}/api/$clientId/requests/pending-counts/$employeeId'),
            headers: ApiConfig.headers,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['Success'] == true && data['Data'] != null) {
          return PendingCounts.fromJson(data['Data']);
        }
      }
      return null;
    } catch (e) {
      _log('💥 خطأ في جلب أعداد الطلبات المعلقة: $e');
      return null;
    }
  }

  // جلب تفاصيل الراتب
  static Future<Map<String, dynamic>> getSalaryDetails(
      int clientId, int employeeId, int month, int year) async {
    try {
      _log('🚀 جلب تفاصيل الراتب...');
      _log('👤 EmployeeID: $employeeId');
      _log('📅 التاريخ: $month/$year');

      final url =
          '${ApiConfig.baseUrl}/api/$clientId/payroll/details/$employeeId?month=$month&year=$year';
      _log('🔗 URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: ApiConfig.headers,
      ).timeout(const Duration(seconds: 30));

      _log('📡 Response Status Code: ${response.statusCode}');
      _log('📄 Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _log('✅ تم جلب تفاصيل الراتب بنجاح');
        return {
          'success': true,
          'data': data['data'],
        };
      } else {
        _log('❌ خطأ في جلب تفاصيل الراتب: ${response.statusCode}');
        try {
          final errorData = json.decode(response.body);
          return {
            'success': false,
            'message': errorData['message'] ?? 'فشل في جلب تفاصيل الراتب',
          };
        } catch (e) { 
          return {
            'success': false,
            'message': 'فشل في جلب تفاصيل الراتب: ${response.statusCode}',
          };
        }
      }
    } catch (e) {
      _log('💥 خطأ في جلب تفاصيل الراتب: $e');
      return {
        'success': false,
        'message': 'خطأ في الاتصال: $e',
      };
    }
  }

  static Future<Map<String, dynamic>> getUserTasks(
    int clientId, {
    required int employeeId,
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final qs = <String, String>{
        'employeeId': employeeId.toString(),
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (status != null && status.trim().isNotEmpty) {
        qs['status'] = status.trim();
      }

      final uri = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/user-tasks')
          .replace(queryParameters: qs);

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'Data': decoded['Data'] ?? [],
        };
      }

      try {
        final decoded = json.decode(response.body);
        final msg = decoded is Map ? decoded['Message']?.toString() : null;
        if (msg != null && msg.trim().isNotEmpty) {
          return {
            'Success': false,
            'Message': msg.trim(),
            'Data': [],
          };
        }
      } catch (_) {}

      if (response.statusCode == 404) {
        return {
          'Success': false,
          'Message': 'الخدمة غير متوفرة على السيرفر (تحتاج تحديث الـ API): /task-groups',
          'Data': [],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في جلب المهام: ${response.statusCode}',
        'Data': [],
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  static Future<Map<String, dynamic>> getUserTaskDetails(
    int clientId, {
    required int employeeId,
    required int taskId,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/$clientId/user-tasks/$taskId')
          .replace(queryParameters: {'employeeId': employeeId.toString()});

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'Data': decoded['Data'],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في جلب تفاصيل المهمة: ${response.statusCode}',
        'Data': null,
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> updateUserTaskStatus(
    int clientId, {
    required int employeeId,
    required int taskId,
    required String status,
  }) async {
    try {
      final uri = Uri.parse(
              '${ApiConfig.baseUrl}/api/$clientId/user-tasks/$taskId/status')
          .replace(queryParameters: {'employeeId': employeeId.toString()});

      final response = await http.put(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode({'Status': status}),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'Data': decoded['Data'],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في تحديث حالة المهمة: ${response.statusCode}',
        'Data': null,
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> downloadUserTaskAttachment(
    int clientId, {
    required int employeeId,
    required int taskId,
    required int attachmentId,
  }) async {
    try {
      final uri = Uri.parse(
              '${ApiConfig.baseUrl}/api/$clientId/user-tasks/$taskId/attachments/$attachmentId/download')
          .replace(queryParameters: {'employeeId': employeeId.toString()});

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/octet-stream'},
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        return {'Success': true, 'Data': response.bodyBytes, 'Message': 'تم التحميل بنجاح'};
      }

      return {'Success': false, 'Data': null, 'Message': 'فشل في تحميل المرفق: ${response.statusCode}'};
    } catch (e) {
      return {'Success': false, 'Data': null, 'Message': 'خطأ في الاتصال: $e'};
    }
  }

  static Future<Map<String, dynamic>> getTaskCreatorManagedEmployees(
    int clientId, {
    required int creatorEmployeeId,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/managed-employees');

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'Data': decoded['Data'] ?? [],
          'Permission': decoded['Permission'],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في جلب الموظفين: ${response.statusCode}',
        'Data': [],
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  static Future<Map<String, dynamic>> createTaskAsCreator(
    int clientId, {
    required int creatorEmployeeId,
    required String title,
    String? description,
    required DateTime dueDateTime,
    required List<int> assignedEmployeeIds,
    bool? requiresApproval,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/tasks');

      final payload = <String, dynamic>{
        'Title': title.trim(),
        'Description': (description ?? '').trim(),
        'DueDateTime':
            '${dueDateTime.year.toString().padLeft(4, '0')}-${dueDateTime.month.toString().padLeft(2, '0')}-${dueDateTime.day.toString().padLeft(2, '0')} ${dueDateTime.hour.toString().padLeft(2, '0')}:${dueDateTime.minute.toString().padLeft(2, '0')}',
        'AssignedEmployeeIDs': assignedEmployeeIds,
        if (requiresApproval != null) 'RequiresApproval': requiresApproval,
      };

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'CreatedTaskIDs': decoded['CreatedTaskIDs'] ?? [],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في إنشاء المهمة: ${response.statusCode}',
        'CreatedTaskIDs': [],
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'CreatedTaskIDs': [],
      };
    }
  }

  static Future<Map<String, dynamic>> uploadCreatorTaskAttachment(
    int clientId, {
    required int creatorEmployeeId,
    required int taskId,
    required String fileName,
    required List<int> bytes,
    String? contentType,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/tasks/$taskId/attachments');

      final req = http.MultipartRequest('POST', uri);
      req.headers['Accept'] = 'application/json';
      if (contentType != null && contentType.trim().isNotEmpty) {
        req.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: fileName,
            contentType: http_parser.MediaType.parse(contentType),
          ),
        );
      } else {
        req.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: fileName,
          ),
        );
      }

      final streamed = await req.send().timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'AttachmentID': decoded['AttachmentID'],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في رفع المرفق: ${response.statusCode}',
      };
    } catch (e) {
      return {'Success': false, 'Message': 'خطأ في الاتصال: $e'};
    }
  }

  static Future<Map<String, dynamic>> getCreatorTasks(
    int clientId, {
    required int creatorEmployeeId,
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final qs = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (status != null && status.trim().isNotEmpty) {
        qs['status'] = status.trim();
      }

      final uri = Uri.parse(
              '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/tasks')
          .replace(queryParameters: qs);

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'Data': decoded['Data'] ?? [],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في جلب المهام: ${response.statusCode}',
        'Data': [],
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  static Future<Map<String, dynamic>> getCreatorTaskGroups(
    int clientId, {
    required int creatorEmployeeId,
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final qs = <String, String>{
        'page': page.toString(),
        'pageSize': pageSize.toString(),
      };
      if (status != null && status.trim().isNotEmpty) {
        qs['status'] = status.trim();
      }

      final uri = Uri.parse(
              '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/task-groups')
          .replace(queryParameters: qs);

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'Data': decoded['Data'] ?? [],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في جلب المهام: ${response.statusCode}',
        'Data': [],
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': [],
      };
    }
  }

  static Future<Map<String, dynamic>> getCreatorTaskGroupDetails(
    int clientId, {
    required int creatorEmployeeId,
    required int taskGroupId,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/task-groups/$taskGroupId');

      final response = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
          'Data': decoded['Data'],
        };
      }

      return {
        'Success': false,
        'Message': 'فشل في جلب التفاصيل: ${response.statusCode}',
        'Data': null,
      };
    } catch (e) {
      return {
        'Success': false,
        'Message': 'خطأ في الاتصال: $e',
        'Data': null,
      };
    }
  }

  static Future<Map<String, dynamic>> approveCreatorTaskGroup(
    int clientId, {
    required int creatorEmployeeId,
    required int taskGroupId,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/task-groups/$taskGroupId/approve');

      final response = await http.put(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
        };
      }

      return {'Success': false, 'Message': 'فشل في اعتماد المهمة: ${response.statusCode}'};
    } catch (e) {
      return {'Success': false, 'Message': 'خطأ في الاتصال: $e'};
    }
  }

  static Future<Map<String, dynamic>> cancelCreatorTaskGroup(
    int clientId, {
    required int creatorEmployeeId,
    required int taskGroupId,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/task-groups/$taskGroupId/cancel');

      final response = await http.put(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
        };
      }

      return {'Success': false, 'Message': 'فشل في إلغاء المهمة: ${response.statusCode}'};
    } catch (e) {
      return {'Success': false, 'Message': 'خطأ في الاتصال: $e'};
    }
  }

  static Future<Map<String, dynamic>> approveCreatorTask(
    int clientId, {
    required int creatorEmployeeId,
    required int taskId,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/tasks/$taskId/approve');

      final response = await http.put(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
        };
      }

      return {'Success': false, 'Message': 'فشل في اعتماد المهمة: ${response.statusCode}'};
    } catch (e) {
      return {'Success': false, 'Message': 'خطأ في الاتصال: $e'};
    }
  }

  static Future<Map<String, dynamic>> cancelCreatorTask(
    int clientId, {
    required int creatorEmployeeId,
    required int taskId,
  }) async {
    try {
      final uri = Uri.parse(
          '${ApiConfig.baseUrl}/api/$clientId/task-creators/$creatorEmployeeId/tasks/$taskId/cancel');

      final response = await http.put(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        return {
          'Success': decoded['Success'] == true,
          'Message': decoded['Message']?.toString(),
        };
      }

      return {'Success': false, 'Message': 'فشل في إلغاء المهمة: ${response.statusCode}'};
    } catch (e) {
      return {'Success': false, 'Message': 'خطأ في الاتصال: $e'};
    }
  }
}
