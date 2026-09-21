import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import '../models/attendance.dart';
import '../services/api_service.dart';
import '../services/location_stability_service.dart';
import '../services/face_api_service.dart';
import 'face_enrollment_screen.dart';
import 'face_verification_screen.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../utils/platform_helper.dart';

class AttendanceScreen extends StatefulWidget {
  final String employeeNumber;
  final int clientId;
  final bool isCheckIn;
  final String? authenticationMethod;
  final String? employeeName;

  const AttendanceScreen({
    super.key,
    required this.employeeNumber,
    required this.clientId,
    required this.isCheckIn,
    this.authenticationMethod,
    this.employeeName,
  });

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with TickerProviderStateMixin {
  static const bool _enableRemoteDebugTelemetry = true;
  static const String _debugEnvPath =
      'd:\\new\\.dbg\\attendance-spoof-location.env';
  String? _debugServerUrl;
  String? _debugSessionId;
  // #region debug-point C:reporting-helper
  Future<void> _reportDebugEvent(
    String hypothesisId,
    String location,
    String msg, {
    Map<String, dynamic>? data,
  }) async {
    if (!_enableRemoteDebugTelemetry) return;
    try {
      if (_debugServerUrl == null || _debugSessionId == null) {
        try {
          final envText = await File(_debugEnvPath).readAsString();
          for (final line in envText.split('\n')) {
            if (line.startsWith('DEBUG_SERVER_URL=')) {
              _debugServerUrl =
                  line.substring('DEBUG_SERVER_URL='.length).trim();
            } else if (line.startsWith('DEBUG_SESSION_ID=')) {
              _debugSessionId =
                  line.substring('DEBUG_SESSION_ID='.length).trim();
            }
          }
        } catch (_) {}
      }
      final url = _debugServerUrl ?? 'http://192.168.1.163:7777/event';
      final session = _debugSessionId ?? 'attendance-spoof-location';
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(
        Uri.parse(url),
      );
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'sessionId': session,
        'runId': 'pre-fix',
        'hypothesisId': hypothesisId,
        'location': location,
        'msg': '[DEBUG] $msg',
        'data': data ?? const {},
        'ts': DateTime.now().millisecondsSinceEpoch,
        'traceId':
            '${widget.employeeNumber}-${DateTime.now().microsecondsSinceEpoch}',
      }));
      await (await req.close()).drain<void>();
      client.close(force: true);
    } catch (_) {}
  }
  // #endregion

  final ApiService _apiService = ApiService();
  final LocationStabilityService _locationStabilityService =
      LocationStabilityService();

  // متغيرات الحالة
  bool _isProcessing = false;
  bool _isInitializing = true;
  bool _usedFaceVerification = false;
  Map<String, dynamic>? _faceVerificationProof;
  bool _isFailureDialogVisible = false;
  static const Duration _maxFaceVerificationAge = Duration(minutes: 2);
  static const Duration _maxFaceVerificationFutureSkew =
      Duration(minutes: 10);
  String _currentStep = '';
  Position? _currentPosition;
  Timer? _locationTimer;

  // متغيرات جديدة لتحسين إدارة الأخطاء
  final int _retryCount = 0;
  static const int _maxRetries = 3;
  String? _lastError;
  final bool _isNetworkError = false;
  final bool _isLocationError = false;
  final bool _isBiometricError = false;

  // متغيرات الرسوم المتحركة
  late AnimationController _backgroundController;
  late AnimationController _cardController;
  late AnimationController _pulseController;
  late AnimationController _successController;
  late AnimationController _errorController;

  late Animation<double> _backgroundAnimation;
  late Animation<double> _cardAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _errorShakeAnimation;
  late Animation<Offset> _slideAnimation;

  // متغيرات النتيجة
  bool? _isSuccess;
  String _resultMessage = '';
  String _resultDetails = '';

  void _log(String message) {
    if (kDebugMode) {
      print('🔄 [AttendanceScreen] $message');
    }
  }

  Future<String> _getDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final packageInfo = await PackageInfo.fromPlatform().timeout(
        const Duration(seconds: 5), // زيادة من 3 إلى 5 ثواني لتحسين الدقة
      );
      String deviceInfoString = '';
      String appVersion = 'v${packageInfo.version}+${packageInfo.buildNumber}';

      if (kIsWeb) {
        deviceInfoString = 'Web Browser | App: $appVersion';
        _log('📱 معلومات الجهاز: $deviceInfoString');
        return deviceInfoString;
      }

      if (PlatformHelper.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo.timeout(
          const Duration(seconds: 5), // زيادة من 3 إلى 5 ثواني لتحسين الدقة
        );
        deviceInfoString =
            '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release}) - ID: ${androidInfo.id} | App: $appVersion';
      } else if (PlatformHelper.isIOS) {
        final iosInfo = await deviceInfo.iosInfo.timeout(
          const Duration(seconds: 5), // زيادة من 3 إلى 5 ثواني لتحسين الدقة
        );
        deviceInfoString =
            '${iosInfo.name} ${iosInfo.model} (iOS ${iosInfo.systemVersion}) - ID: ${iosInfo.identifierForVendor} | App: $appVersion';
      } else if (PlatformHelper.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo.timeout(
          const Duration(seconds: 5), // زيادة من 3 إلى 5 ثواني لتحسين الدقة
        );
        deviceInfoString =
            'Windows ${windowsInfo.majorVersion}.${windowsInfo.minorVersion} - ID: ${windowsInfo.deviceId} | App: $appVersion';
      } else if (PlatformHelper.isMacOS) {
        final macOsInfo = await deviceInfo.macOsInfo.timeout(
          const Duration(seconds: 5), // زيادة من 3 إلى 5 ثواني لتحسين الدقة
        );
        deviceInfoString =
            'macOS ${macOsInfo.osRelease} - ID: ${macOsInfo.computerName} | App: $appVersion';
      } else if (PlatformHelper.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo.timeout(
          const Duration(seconds: 5), // زيادة من 3 إلى 5 ثواني لتحسين الدقة
        );
        deviceInfoString =
            'Linux ${linuxInfo.name} ${linuxInfo.version} - ID: ${linuxInfo.machineId} | App: $appVersion';
      } else {
        deviceInfoString = 'Unknown Device | App: $appVersion';
      }

      _log('📱 معلومات الجهاز: $deviceInfoString');
      return deviceInfoString;
    } catch (e) {
      _log('❌ خطأ في جمع معلومات الجهاز: $e');
      return 'Flutter Mobile App';
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    // #region debug-point A:attendance-init
    unawaited(_reportDebugEvent(
      'A',
      'attendance_screen.dart:initState',
      'Attendance screen initialized',
      data: {
        'employeeNumber': widget.employeeNumber,
        'clientId': widget.clientId,
        'isCheckIn': widget.isCheckIn,
        'authenticationMethod': widget.authenticationMethod,
        'employeeName': widget.employeeName,
      },
    ));
    // #endregion
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final languageService =
          Provider.of<LanguageService>(context, listen: false);
      final lang = languageService.currentLocale.languageCode;
      setState(() {
        _currentStep = Translations.getText('preparing', lang);
      });
      unawaited(_runStartProcessSafely());
    });
  }

  void _initializeAnimations() {
    // تحريك الخلفية
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    _backgroundAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _backgroundController,
      curve: Curves.easeInOut,
    ));

    // تحريك البطاقة
    _cardController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _cardAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _cardController,
      curve: Curves.elasticOut,
    ));

    // نبض الزر
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    // نجاح العملية
    _successController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _successScaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    ));

    // خطأ العملية
    _errorController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _errorShakeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _errorController,
      curve: Curves.easeInOut,
    ));

    // بدء الرسوم المتحركة
    _backgroundController.forward();
    _cardController.forward();
    _pulseController.repeat(reverse: true);
  }

  Future<void> _refreshPage() async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;
    setState(() {
      _isProcessing = false;
      _isInitializing = true;
      _usedFaceVerification = false;
      _faceVerificationProof = null;
      _isSuccess = null;
      _resultMessage = '';
      _resultDetails = '';
      _currentStep = Translations.getText('preparing', lang);
    });
    _locationTimer?.cancel();
    _currentPosition = null;
    await _runStartProcessSafely();
  }

  Future<void> _runStartProcessSafely() async {
    try {
      await _startProcess();
    } catch (e) {
      if (!mounted) return;
      final languageService =
          Provider.of<LanguageService>(context, listen: false);
      final lang = languageService.currentLocale.languageCode;
      // #region debug-point A:start-process-guard
      unawaited(_reportDebugEvent(
        'A',
        'attendance_screen.dart:_runStartProcessSafely',
        'Guard intercepted attendance initialization exception',
        data: {
          'error': e.toString().split('\n').first,
          'currentStep': _currentStep,
        },
      ));
      // #endregion
      setState(() {
        _isInitializing = false;
      });
      _showError(
        Translations.getText('operation_error', lang),
        lang == 'ar'
            ? 'تعذر تجهيز شاشة الحضور بشكل صحيح. أعد المحاولة، وإذا استمرت المشكلة فتحقق من صلاحيات الموقع والكاميرا.'
            : 'Unable to prepare the attendance screen correctly. Retry, and if the issue persists check location and camera permissions.',
      );
    }
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _backgroundController.dispose();
    _cardController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    _errorController.dispose();
    super.dispose();
  }

  bool _isTruthyFaceResult(Object? navigationResult) {
    if (navigationResult == true) return true;
    if (navigationResult is Map) {
      final resultEmployee = (navigationResult['EmployeeNumber'] ??
              navigationResult['employeeNumber'] ??
              '')
          .toString();
      final employeeMatches =
          resultEmployee.isEmpty || resultEmployee == widget.employeeNumber;
      final reason = (navigationResult['Reason'] ?? '').toString();
      final context =
          (navigationResult['VerificationContext'] ?? '').toString();

      return employeeMatches &&
          (navigationResult['Success'] == true ||
              navigationResult['success'] == true ||
              navigationResult['Matched'] == true ||
              navigationResult['Completed'] == true ||
              navigationResult['Verified'] == true ||
              navigationResult['FaceVerified'] == true ||
              navigationResult['Enrolled'] == true ||
              (reason == 'verify-success' &&
                  context == 'ATTENDANCE_CHECKPOINT'));
    }
    if (navigationResult is int) return navigationResult > 0;
    if (navigationResult is String) {
      return const {'true', 'ok', 'success', 'done', 'verified', 'enrolled'}
          .contains(navigationResult.toLowerCase());
    }
    return false;
  }

  Map<String, String>? _validateFaceProofBeforeSubmit() {
    if (!_usedFaceVerification) {
      return {
        'title': 'التحقق من الوجه مطلوب',
        'details':
            'يجب إكمال التحقق من بصمة الوجه بنجاح قبل السماح بتسجيل الحضور أو الانصراف.',
      };
    }

    final proof = _faceVerificationProof;
    if (proof == null) {
      return {
        'title': 'تعذر اعتماد التحقق من الوجه',
        'details':
            'اكتملت شاشة التحقق لكن لم يصل إثبات النجاح إلى شاشة الحضور. أعد تنفيذ التحقق من الوجه مرة أخرى.',
      };
    }

    if (proof['passed'] != true) {
      return {
        'title': 'فشل التحقق من الوجه',
        'details':
            'التحقق الوجهي لم يكتمل بنجاح، لذلك تم إيقاف تسجيل الحضور لحماية العملية.',
      };
    }

    final proofEmployee = proof['employeeNumber']?.toString();
    if (proofEmployee == null || proofEmployee.isEmpty) {
      return {
        'title': 'بيانات التحقق ناقصة',
        'details':
            'إثبات التحقق من الوجه لا يحتوي على رقم الموظف. أعد التحقق من الوجه ثم حاول مجددًا.',
      };
    }

    if (proofEmployee != widget.employeeNumber) {
      return {
        'title': 'عدم تطابق بيانات التحقق',
        'details':
            'إثبات التحقق من الوجه يخص موظفًا آخر، لذلك تم رفض العملية. تأكد من تسجيل الدخول بالحساب الصحيح ثم أعد التحقق.',
      };
    }

    final verificationCapturedAtMs =
        int.tryParse(proof['verificationCapturedAtMs']?.toString() ?? '');
    if (verificationCapturedAtMs != null) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final ageMs = nowMs - verificationCapturedAtMs;
      if (ageMs < -_maxFaceVerificationFutureSkew.inMilliseconds) {
        return {
          'title': 'وقت التحقق غير متزامن',
          'details':
              'يوجد فرق كبير وغير متوقع في وقت التحقق من الوجه. تحقق من وقت الجهاز ثم أعد المحاولة.',
        };
      }

      final normalizedAge = Duration(
        milliseconds: ageMs < 0 ? 0 : ageMs,
      );
      if (normalizedAge > _maxFaceVerificationAge) {
        return {
          'title': 'انتهت صلاحية التحقق من الوجه',
          'details':
              'مر وقت طويل منذ آخر تحقق ناجح للوجه. أعد التحقق من الوجه مباشرة ثم حاول تسجيل الحضور.',
        };
      }

      return null;
    }

    final verificationAtRaw = proof['verificationAtUtc']?.toString();
    if (verificationAtRaw == null || verificationAtRaw.isEmpty) {
      return {
        'title': 'وقت التحقق غير متوفر',
        'details':
            'تمت مطابقة الوجه لكن بدون ختم زمني صالح، لذلك لا يمكن متابعة تسجيل الحضور. أعد التحقق من الوجه.',
      };
    }

    final verificationAt = DateTime.tryParse(verificationAtRaw)?.toUtc();
    if (verificationAt == null) {
      return {
        'title': 'وقت التحقق غير صالح',
        'details':
            'صيغة وقت التحقق من الوجه غير صحيحة. أعد التحقق ثم حاول مرة أخرى.',
      };
    }

    final nowUtc = DateTime.now().toUtc();
    final age = nowUtc.difference(verificationAt);
    if (age < -_maxFaceVerificationFutureSkew) {
      return {
        'title': 'وقت التحقق غير متزامن',
        'details':
            'يوجد فرق كبير وغير متوقع في توقيت التحقق من الوجه. تحقق من وقت الجهاز ثم أعد المحاولة.',
      };
    }

    if (age > _maxFaceVerificationAge) {
      return {
        'title': 'انتهت صلاحية التحقق من الوجه',
        'details':
            'مر وقت طويل منذ آخر تحقق ناجح للوجه. أعد التحقق من الوجه مباشرة ثم حاول تسجيل الحضور.',
      };
    }

    return null;
  }

  Future<void> _startProcess() async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    _log('🚀 بدء عملية ${widget.isCheckIn ? 'الحضور' : 'الانصراف'}');
    // #region debug-point A:start-process-entry
    unawaited(_reportDebugEvent(
      'A',
      'attendance_screen.dart:_startProcess',
      'Attendance start process entered',
      data: {
        'isCheckIn': widget.isCheckIn,
        'authenticationMethod': widget.authenticationMethod,
        'mounted': mounted,
      },
    ));
    // #endregion

    try {
      // التحقق من أذونات الموقع
      await _checkLocationPermission();

      // بدء تحديثات الموقع
      _startLocationUpdates();

      // انتظار تحديد الموقع
      await _waitForLocation();

      setState(() {
        _isInitializing = false;
        _currentStep = Translations.getText('ready_to_register', lang);
      });
      // #region debug-point B:start-process-ready
      unawaited(_reportDebugEvent(
        'B',
        'attendance_screen.dart:_startProcess',
        'Attendance start process completed initial preparation',
        data: {
          'hasPosition': _currentPosition != null,
          'isInitializing': _isInitializing,
          'currentStep': _currentStep,
        },
      ));
      // #endregion
    } catch (e) {
      // #region debug-point A:start-process-exception
      unawaited(_reportDebugEvent(
        'A',
        'attendance_screen.dart:_startProcess',
        'Attendance start process threw exception',
        data: {
          'error': e.toString().split('\n').first,
          'currentStep': _currentStep,
          'hasPosition': _currentPosition != null,
        },
      ));
      // #endregion
      rethrow;
    }
  }

  Future<void> _checkLocationPermission() async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    setState(() {
      _currentStep =
          Translations.getText('checking_location_permissions', lang);
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await _showLocationAccessDialog(
          title: Translations.getText('location_service_disabled', lang),
          details: Translations.getText('enable_location_service', lang),
          openDeviceLocationSettings: true,
        );
        _showError(Translations.getText('location_service_disabled', lang),
            Translations.getText('enable_location_service', lang));
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          await _showLocationAccessDialog(
            title: Translations.getText('location_permission_denied', lang),
            details: Translations.getText('allow_location_access', lang),
          );
          _showError(Translations.getText('location_permission_denied', lang),
              Translations.getText('allow_location_access', lang));
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        await _showLocationAccessDialog(
          title:
              Translations.getText('location_permission_denied_forever', lang),
          details: Translations.getText('enable_location_permissions', lang),
          openAppSettingsDirectly: true,
        );
        _showError(
            Translations.getText('location_permission_denied_forever', lang),
            Translations.getText('enable_location_permissions', lang));
        return;
      }

      _log('✅ أذونات الموقع مفعلة بنجاح');
    } catch (e) {
      _log('❌ خطأ في التحقق من أذونات الموقع: $e');
      _showError(Translations.getText('location_permission_error', lang),
          e.toString());
    }
  }

  Future<void> _showLocationAccessDialog({
    required String title,
    required String details,
    bool openAppSettingsDirectly = false,
    bool openDeviceLocationSettings = false,
  }) async {
    if (!mounted) return;
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(details),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(Translations.getText('cancel', lang)),
            ),
            if (openDeviceLocationSettings)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await Geolocator.openLocationSettings();
                },
                child: Text(
                  lang == 'ar' ? 'إعدادات الموقع' : 'Location Settings',
                ),
              ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (openAppSettingsDirectly || !openDeviceLocationSettings) {
                  await Geolocator.openAppSettings();
                }
              },
              child: Text(Translations.getText('app_settings', lang)),
            ),
          ],
        );
      },
    );
  }

  void _startLocationUpdates() {
    _locationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && !_isProcessing) {
        _updateLocation();
      }
    });
    _updateLocation();
  }

  Future<void> _updateLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit:
            const Duration(seconds: 8), // زيادة من 5 إلى 8 ثواني لتحسين الدقة
      );

      setState(() {
        _currentPosition = position;
      });

      _log('📍 تم تحديث الموقع: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      _log('❌ خطأ في تحديث الموقع: $e');
    }
  }

  Future<void> _waitForLocation() async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    int attempts = 0;
    const maxAttempts = 15; // زيادة من 10 إلى 15 محاولة لتحسين الدقة

    while (_currentPosition == null && attempts < maxAttempts) {
      await Future.delayed(
          const Duration(seconds: 1)); // زيادة من 0.5 إلى 1 ثانية
      attempts++;

      if (attempts % 5 == 0) {
        setState(() {
          _currentStep =
              '${Translations.getText('determining_location', lang)}... (${Translations.getText('location_attempt', lang)} ${attempts + 1})';
        });
      }
    }

    if (_currentPosition == null) {
      _showError(Translations.getText('location_determination_failed', lang),
          Translations.getText('enable_gps_location', lang));
    }
  }

  Future<void> _processAttendance() async {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    final selectedMethod = widget.authenticationMethod?.toUpperCase();
    bool requestUsesFace = false;

    if (_currentPosition == null) {
      _showError(Translations.getText('cannot_determine_location', lang),
          Translations.getText('wait_for_location', lang));
      return;
    }

    setState(() {
      _isProcessing = true;
      _currentStep = Translations.getText('checking_location', lang);
    });

    try {
      // --- إضافة التحقق من بصمة الوجه (Server-side) ---
      // يتم التحقق أولاً كما هو مطلوب في الـ Flow
      bool hasStoredFace = false;
      Map<String, dynamic> faceStatus = <String, dynamic>{};

      if (selectedMethod != null && selectedMethod.isNotEmpty) {
        requestUsesFace =
            selectedMethod == 'FACE' || widget.authenticationMethod == 'الوجه';
      } else {
        setState(() {
          _currentStep = 'جاري تحديد طريقة التحضير...';
        });

        faceStatus = await FaceApiService.getEmployeeFaceImageStatus(
          widget.clientId,
          widget.employeeNumber,
        );
        // #region debug-point D:face-status
        unawaited(_reportDebugEvent(
          'D',
          'attendance_screen.dart:_processAttendance',
          'Fetched face status before attendance',
          data: {
            'success': faceStatus['Success'],
            'attendanceMethod': faceStatus['AttendanceMethod'],
            'isFaceRequired': faceStatus['IsFaceRequired'],
            'hasFaceTemplate': faceStatus['HasFaceTemplate'],
            'hasFaceImage': faceStatus['HasFaceImage'],
            'hasImage': faceStatus['HasImage'],
            'isRegistered': faceStatus['IsRegistered'],
            'message': faceStatus['Message'],
          },
        ));
        // #endregion

        if (faceStatus['Success'] != true) {
          _showError(
            'تعذر تحديد طريقة التحضير',
            faceStatus['Message'] ?? 'لا يمكن الاتصال بسيرفر البصمة حالياً',
          );
          setState(() {
            _isProcessing = false;
          });
          return;
        }

        final attendanceMethod =
            int.tryParse(faceStatus['AttendanceMethod']?.toString() ?? '0') ?? 0;
        final isFaceRequired = faceStatus['IsFaceRequired'] == true;
        requestUsesFace =
            isFaceRequired || attendanceMethod == 1 || attendanceMethod == 2;
      }

      if (requestUsesFace && faceStatus.isEmpty) {
        setState(() {
          _currentStep = 'جاري التحقق من إعدادات الوجه...';
        });

        faceStatus = await FaceApiService.getEmployeeFaceImageStatus(
          widget.clientId,
          widget.employeeNumber,
        );
        // #region debug-point D:face-status
        unawaited(_reportDebugEvent(
          'D',
          'attendance_screen.dart:_processAttendance',
          'Fetched face status before attendance',
          data: {
            'success': faceStatus['Success'],
            'attendanceMethod': faceStatus['AttendanceMethod'],
            'isFaceRequired': faceStatus['IsFaceRequired'],
            'hasFaceTemplate': faceStatus['HasFaceTemplate'],
            'hasFaceImage': faceStatus['HasFaceImage'],
            'hasImage': faceStatus['HasImage'],
            'isRegistered': faceStatus['IsRegistered'],
            'message': faceStatus['Message'],
          },
        ));
        // #endregion

        if (faceStatus['Success'] != true) {
          _showError('خطأ في التحقق من الوجه',
              faceStatus['Message'] ?? 'لا يمكن الاتصال بسيرفر البصمة حالياً');
          setState(() {
            _isProcessing = false;
          });
          return;
        }

        hasStoredFace = faceStatus['HasFaceTemplate'] == true ||
            faceStatus['HasFaceImage'] == true ||
            faceStatus['HasImage'] == true ||
            faceStatus['IsRegistered'] == true;
      }

      if (requestUsesFace && faceStatus.isNotEmpty) {
        hasStoredFace = faceStatus['HasFaceTemplate'] == true ||
            faceStatus['HasFaceImage'] == true ||
            faceStatus['HasImage'] == true ||
            faceStatus['IsRegistered'] == true;
      }

      if (requestUsesFace) {
        bool faceVerified = false;
        bool enrollmentCompleted = false;
        Object? enrollmentResult;
        Object? navigationResult;

        if (!hasStoredFace) {
          // الموظف يحتاج أولاً إلى التسجيل ثم التحقق الإلزامي قبل الحضور.
          if (!mounted) return;
          // #region debug-point B:open-face-enrollment
          unawaited(_reportDebugEvent(
            'B',
            'attendance_screen.dart:_processAttendance',
            'Opening face enrollment screen before attendance',
            data: {
              'employeeNumber': widget.employeeNumber,
              'clientId': widget.clientId,
            },
          ));
          // #endregion
          try {
            enrollmentResult = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FaceEnrollmentScreen(
                  employeeNumber: widget.employeeNumber,
                  clientId: widget.clientId,
                ),
              ),
            );
          } catch (e) {
            // #region debug-point A:face-enrollment-open-failed
            unawaited(_reportDebugEvent(
              'A',
              'attendance_screen.dart:_processAttendance',
              'Opening face enrollment screen failed',
              data: {
                'error': e.toString().split('\n').first,
              },
            ));
            // #endregion
            _showError(
              'تعذر فتح شاشة تسجيل الوجه',
              'حدث خطأ أثناء تجهيز الكاميرا أو شاشة التسجيل. تحقق من صلاحية الكاميرا ثم أعد المحاولة.',
            );
            setState(() {
              _isProcessing = false;
            });
            return;
          }

          enrollmentCompleted = _isTruthyFaceResult(enrollmentResult);
          if (enrollmentCompleted) {
            faceStatus['HasFaceTemplate'] = true;
            faceStatus['HasFaceImage'] = true;
            FaceApiService.clearLastFaceSession();
            _log(
                '✅ اكتمل تسجيل الوجه. سيتم الآن تنفيذ التحقق الإلزامي قبل الحضور.');
          }
        }

        if (hasStoredFace || enrollmentCompleted) {
          if (!mounted) return;
          // #region debug-point B:open-face-camera
          unawaited(_reportDebugEvent(
            'B',
            'attendance_screen.dart:_processAttendance',
            'Opening face verification camera screen',
            data: {
              'employeeNumber': widget.employeeNumber,
              'clientId': widget.clientId,
              'hasStoredFace': hasStoredFace,
              'enrollmentCompleted': enrollmentCompleted,
            },
          ));
          // #endregion
          try {
            navigationResult = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => FaceVerificationScreen(
                  employeeNumber: widget.employeeNumber,
                  clientId: widget.clientId,
                  showResetButton: false,
                ),
              ),
            );
          } catch (e) {
            // #region debug-point A:face-camera-open-failed
            unawaited(_reportDebugEvent(
              'A',
              'attendance_screen.dart:_processAttendance',
              'Opening face verification camera screen failed',
              data: {
                'error': e.toString().split('\n').first,
              },
            ));
            // #endregion
            _showError(
              'تعذر فتح الكاميرا',
              'حدث خطأ أثناء فتح شاشة التحقق من الوجه. تحقق من صلاحية الكاميرا ثم أعد المحاولة.',
            );
            setState(() {
              _isProcessing = false;
            });
            return;
          }
          faceVerified = _isTruthyFaceResult(navigationResult);
        }
        // #region debug-point C:navigation-result
        unawaited(_reportDebugEvent(
          'C',
          'attendance_screen.dart:_processAttendance',
          'Returned from face screen',
          data: {
            'navigationResultType': navigationResult.runtimeType.toString(),
            'navigationResultValue': navigationResult?.toString(),
            'enrollmentResultType': enrollmentResult.runtimeType.toString(),
            'enrollmentResultValue': enrollmentResult?.toString(),
            'enrollmentCompleted': enrollmentCompleted,
            'faceVerifiedInitial': faceVerified,
            'hasStoredFace': hasStoredFace,
          },
        ));
        // #endregion

        if (faceVerified) {
          if (navigationResult is Map) {
            final proofEmployee =
                navigationResult['EmployeeNumber']?.toString() ??
                    navigationResult['employeeNumber']?.toString() ??
                    widget.employeeNumber;
            _faceVerificationProof = {
              'passed': true,
              'employeeNumber': proofEmployee,
              'verificationAtUtc':
                  navigationResult['VerificationAtUtc']?.toString() ??
                      DateTime.now().toUtc().toIso8601String(),
              'verificationCapturedAtMs':
                  int.tryParse(
                        navigationResult['VerificationCapturedAtMs']
                                ?.toString() ??
                            '',
                      ) ??
                      DateTime.now().millisecondsSinceEpoch,
              'confidenceScore':
                  (navigationResult['ConfidenceScore'] as num?)?.toDouble(),
              'livenessScore':
                  (navigationResult['LivenessScore'] as num?)?.toDouble(),
              'source': navigationResult['Reason']?.toString() ?? 'face-screen',
              'serverMessage': navigationResult['ServerMessage']?.toString(),
            };
          } else {
            _faceVerificationProof = {
              'passed': true,
              'employeeNumber': widget.employeeNumber,
              'verificationAtUtc': DateTime.now().toUtc().toIso8601String(),
              'verificationCapturedAtMs': DateTime.now().millisecondsSinceEpoch,
              'source': 'face-session-fallback',
            };
          }
        }

        // 🛡️ Failsafe — طبقة الحماية الفائقة والثالثة (Triple Protection):
        // 1. Failsafe الأساسي (العلامة العالمية الثابتة)
        // 2. إعادة فحص إضافي بعد Failsafe مباشرة للتأكد من عدم وجود علامة زمنية صالحة حتى لو
        //    لم يتحقق match رقم الموظف بشكل غامض (edge cases)
        // 3. حماية نهائية: إذا لم ينجح أي من السابقين، نعطي مهلة 800ms ثم نعيد الفحص مرة
        //    أخيرة في حالة أن الضغط المستخدم زر الإغلاق السريع جداً قبل وصول Navigator.result
        if (!faceVerified) {
          final fallbackOk = FaceApiService.verifyLastFaceSessionSuccess(
            employeeNumber: widget.employeeNumber,
            requiredSessionKind: 'verification',
          );
          // #region debug-point C:failsafe-1
          unawaited(_reportDebugEvent(
            'C',
            'attendance_screen.dart:_processAttendance',
            'Checked global success flag fallback',
            data: {
              'fallbackOk': fallbackOk,
              'debugLastSessionSuccess': FaceApiService.debugLastSessionSuccess,
              'debugLastSessionEmployee':
                  FaceApiService.debugLastSessionEmployee,
              'debugLastSessionKind': FaceApiService.debugLastSessionKind,
            },
          ));
          // #endregion
          if (fallbackOk) {
            faceVerified = true;
            _faceVerificationProof = {
              'passed': true,
              'employeeNumber': widget.employeeNumber,
              'verificationAtUtc': FaceApiService.debugLastSessionTimestamp
                      ?.toUtc()
                      .toIso8601String() ??
                  DateTime.now().toUtc().toIso8601String(),
              'verificationCapturedAtMs':
                  FaceApiService.debugLastSessionTimestamp
                          ?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch,
              'source': 'face-session-verification-fallback',
            };
            FaceApiService.clearLastFaceSession();
            _log(
                '🛡️ تم تفعيل الحماية الفائقة (Failsafe Global Flag) — التحقق ناجح | NavResult نوع: (${navigationResult.runtimeType})');
          }
        }

        // حماية إضافية (Fourth Fallback): تأخير قصير + فحص نهائي للتأكد من أن العلامة وصلت
        // (في حالات نادرة جداً حيث يتم فيها إغلاق الشاشة أسرع من وصول Navigator.pop إلى هنا)
        if (!faceVerified) {
          await Future.delayed(const Duration(milliseconds: 600));
          final fallback2 = FaceApiService.verifyLastFaceSessionSuccess(
            employeeNumber: widget.employeeNumber,
            requiredSessionKind: 'verification',
          );
          // #region debug-point C:failsafe-2
          unawaited(_reportDebugEvent(
            'C',
            'attendance_screen.dart:_processAttendance',
            'Checked delayed global success flag fallback',
            data: {
              'fallbackOk': fallback2,
              'debugLastSessionSuccess': FaceApiService.debugLastSessionSuccess,
              'debugLastSessionEmployee':
                  FaceApiService.debugLastSessionEmployee,
              'debugLastSessionKind': FaceApiService.debugLastSessionKind,
            },
          ));
          // #endregion
          if (fallback2) {
            faceVerified = true;
            _faceVerificationProof = {
              'passed': true,
              'employeeNumber': widget.employeeNumber,
              'verificationAtUtc': FaceApiService.debugLastSessionTimestamp
                      ?.toUtc()
                      .toIso8601String() ??
                  DateTime.now().toUtc().toIso8601String(),
              'verificationCapturedAtMs':
                  FaceApiService.debugLastSessionTimestamp
                          ?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch,
              'source': 'face-session-verification-fallback-delayed',
            };
            FaceApiService.clearLastFaceSession();
            _log(
                '🛡️🛡️ الحماية الرابعة (Delayed Fallback 2): تم تفعيلها بعد 600ms → التحقق ناجح.');
          }
        }

        // 🔍 DIAGNOSTIC نهائي: طباعة القيم النهائية قبل الشرط الأخير على الجهاز
        final lastTraceId =
            DateTime.now().millisecondsSinceEpoch.toRadixString(36);
        _log(
            '🔎 [TRACE-$lastTraceId] DIAGNOSTIC ATTENDANCE | faceVerified=$faceVerified | NavResult=(${navigationResult.runtimeType}) $navigationResult | Fallback-Exists=${FaceApiService.debugLastSessionSuccess ? "YES" : "NO"} | EmpMatch=${FaceApiService.debugLastSessionEmployee == widget.employeeNumber ? "YES" : "NO"} | HasTemplate=${faceStatus['HasFaceTemplate']} | HasStoredFace=$hasStoredFace');

        if (!faceVerified) {
          final serverHint = navigationResult is Map
              ? ((navigationResult['ServerMessage'] ??
                          navigationResult['Message'])
                      ?.toString() ??
                  '')
              : '';
          final hint = navigationResult == null
              ? ' (ملاحظة: تم إغلاق شاشة التحقق يدوياً).'
              : navigationResult is Map
                  ? ' (تم استلام رد فشل من شاشة التحقق ولم يؤكد نجاح المطابقة).'
                  : ' (تم استلام قيمة غير متوقعة: ${navigationResult.runtimeType}).';
          final verificationMessage = !hasStoredFace && !enrollmentCompleted
              ? 'لا توجد بصمة وجه محفوظة لهذا الموظف بعد، لذلك يجب إكمال تسجيل الوجه أولاً ثم تنفيذ التحقق قبل الحضور.$hint'
              : !hasStoredFace && enrollmentCompleted
                  ? 'تم تسجيل الوجه بنجاح، لكن التحقق الإلزامي بعد التسجيل لم يكتمل أو لم تصل نتيجته إلى شاشة الحضور.$hint'
                  : 'بصمة الوجه مسجلة لهذا الموظف، لكن المطابقة الحالية لم تنجح أو لم تصل نتيجة النجاح إلى شاشة الحضور.$hint\nإذا ظهرت داخل شاشة البصمة رسالة مثل "لا تتطابق" أو نسبة تشابه منخفضة، فهذا يعني أن الموظف مسجل فعلاً ولكن المطابقة فشلت بسبب اختلاف الصورة الحالية عن الصورة المحفوظة.${serverHint.isNotEmpty ? "\nرسالة الخادم: $serverHint" : ""}';
          // #region debug-point E:attendance-face-rejected
          unawaited(_reportDebugEvent(
            'E',
            'attendance_screen.dart:_processAttendance',
            'Attendance rejected after face verification flow',
            data: {
              'platform': Platform.operatingSystem,
              'navigationResultType': navigationResult.runtimeType.toString(),
              'navigationResultValue': navigationResult?.toString(),
              'serverHint': serverHint,
              'hasStoredFace': hasStoredFace,
              'enrollmentCompleted': enrollmentCompleted,
              'faceVerified': faceVerified,
              'proof': _faceVerificationProof?.toString(),
            },
          ));
          // #endregion
          _showError(
            'فشل التحقق من الوجه',
            verificationMessage,
          );
          setState(() {
            _isProcessing = false;
          });
          return;
        }

        // تسجيل أنه تم استخدام بصمة الوجه بنجاح
        _usedFaceVerification = true;

        final faceProofValidation = _validateFaceProofBeforeSubmit();
        if (faceProofValidation != null) {
          _showError(
            faceProofValidation['title']!,
            faceProofValidation['details']!,
          );
          setState(() {
            _isProcessing = false;
          });
          return;
        }
      }
      // ---------------------------------------------

      // تسجيل دقة GPS للمراجعة فقط
      double accuracy = _currentPosition!.accuracy;
      _log('📍 دقة GPS الحالية: ${accuracy.toStringAsFixed(2)} متر');

      setState(() {
        _currentStep = Translations.getText('checking_developer_mode', lang);
      });

      setState(() {
        _currentStep =
            Translations.getText('checking_location_stability', lang);
      });

      // فحص ثبات الموقع
      LocationStabilityResult stabilityResult =
          await _locationStabilityService.checkLocationStabilityWithUpdates(
        initialPosition: _currentPosition!,
        updateInterval:
            const Duration(milliseconds: 1500), // ثانية ونصف بين القراءات
        requiredUpdates: 5, // زيادة إلى 5 قراءات لتحسين الدقة
        minVariationPercentage: 0.05, // تقليل من 0.1 إلى 0.05% لتحسين المرونة
      );

      // #region debug-point C:location-stability-result
      unawaited(_reportDebugEvent(
        'C',
        'attendance_screen.dart:_processAttendance:location-stability',
        'Computed location stability result before attendance decision',
        data: {
          'currentAccuracy': _currentPosition?.accuracy,
          'currentLatitude': _currentPosition?.latitude,
          'currentLongitude': _currentPosition?.longitude,
          'isStable': stabilityResult.isStable,
          'isSuspiciouslyStable': stabilityResult.isSuspiciouslyStable,
          'isFakeLocation': stabilityResult.isFakeLocation,
          'maxDistanceVariation': stabilityResult.maxDistanceVariation,
          'averageDistance': stabilityResult.averageDistance,
          'totalReadings': stabilityResult.totalReadings,
          'errorMessage': stabilityResult.errorMessage,
        },
      ));
      // #endregion

      if (stabilityResult.isFakeLocation == true) {
        // #region debug-point C:location-rejected-fake
        unawaited(_reportDebugEvent(
          'C',
          'attendance_screen.dart:_processAttendance:location-rejected-fake',
          'Attendance rejected because location was flagged as fake',
          data: {
            'currentAccuracy': _currentPosition?.accuracy,
            'isStable': stabilityResult.isStable,
            'isSuspiciouslyStable': stabilityResult.isSuspiciouslyStable,
            'isFakeLocation': stabilityResult.isFakeLocation,
            'maxDistanceVariation': stabilityResult.maxDistanceVariation,
            'averageDistance': stabilityResult.averageDistance,
            'totalReadings': stabilityResult.totalReadings,
          },
        ));
        // #endregion
        _showError(Translations.getText('fake_location_detected', lang),
            Translations.getText('fake_location_warning', lang));
        return;
      }

      if (stabilityResult.isSuspiciouslyStable == true &&
          (_currentPosition?.accuracy ?? 999) < 25) {
        // #region debug-point C:location-warning-suspicious
        unawaited(_reportDebugEvent(
          'C',
          'attendance_screen.dart:_processAttendance:location-warning-suspicious',
          'Location looked unusually stable but attendance flow continued for server-side validation',
          data: {
            'currentAccuracy': _currentPosition?.accuracy,
            'accuracyThreshold': 25,
            'isStable': stabilityResult.isStable,
            'isSuspiciouslyStable': stabilityResult.isSuspiciouslyStable,
            'isFakeLocation': stabilityResult.isFakeLocation,
            'maxDistanceVariation': stabilityResult.maxDistanceVariation,
            'averageDistance': stabilityResult.averageDistance,
            'totalReadings': stabilityResult.totalReadings,
          },
        ));
        // #endregion
        _log(
            '⚠️ الموقع بدا ثابتاً بشكل غير معتاد، لكن سيتم المتابعة والتحقق من الموقع المسموح من الخادم لتفادي رفض مواقع iPhone الحقيقية.');
      }

      if (!stabilityResult.isStable) {
        // #region debug-point C:location-allowed-unstable
        unawaited(_reportDebugEvent(
          'C',
          'attendance_screen.dart:_processAttendance:location-allowed-unstable',
          'Location was not stable enough but flow continued',
          data: {
            'currentAccuracy': _currentPosition?.accuracy,
            'isStable': stabilityResult.isStable,
            'isSuspiciouslyStable': stabilityResult.isSuspiciouslyStable,
            'isFakeLocation': stabilityResult.isFakeLocation,
            'maxDistanceVariation': stabilityResult.maxDistanceVariation,
            'averageDistance': stabilityResult.averageDistance,
            'totalReadings': stabilityResult.totalReadings,
          },
        ));
        // #endregion
        _log(
            '⚠️ ثبات الموقع غير كافٍ، سيتم المتابعة لتفادي رفض الأجهزة الحقيقية');
      }

      setState(() {
        _currentStep = Translations.getText('checking_location_validity', lang);
      });

      // التحقق من المواقع المسموح بها
      final locationsResponse =
          await _apiService.getAttendanceLocations(widget.clientId);
      bool isLocationValid = false;

      if (locationsResponse['Success'] == true) {
        List<dynamic> locations = locationsResponse['Locations'];

        for (var location in locations) {
          try {
            double officeLat =
                double.tryParse(location['Latitude'].toString()) ?? 0.0;
            double officeLng =
                double.tryParse(location['Longitude'].toString()) ?? 0.0;
            int radiusMeters =
                int.tryParse(location['RadiusMeters'].toString()) ?? 100;

            double distance = Geolocator.distanceBetween(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              officeLat,
              officeLng,
            );

            if (distance <= radiusMeters) {
              isLocationValid = true;
              break;
            }
          } catch (e) {
            continue;
          }
        }
      }

      if (!isLocationValid) {
        _showError(Translations.getText('outside_allowed_area', lang),
            Translations.getText('move_to_work_location', lang));
        return;
      }

      setState(() {
        _currentStep = Translations.getText('registering_data', lang);
      });

      setState(() {
        _currentStep = Translations.getText('registering_data', lang);
      });

      // جمع معلومات الجهاز
      final rawDeviceInfo = await _getDeviceInfo();
      final deviceInfo = requestUsesFace
          ? jsonEncode({
              'device': rawDeviceInfo,
              'attendanceAuth': 'FACE',
              'faceVerification': _faceVerificationProof,
            })
          : rawDeviceInfo;

      final proof = requestUsesFace ? _faceVerificationProof : null;
      final bool? faceVerificationPassed =
          requestUsesFace ? _usedFaceVerification : null;
      final String? faceVerificationAtUtc = requestUsesFace
          ? (proof == null ? null : proof['verificationAtUtc']?.toString())
          : null;
      final int? faceVerificationCapturedAtMs = requestUsesFace
          ? int.tryParse(
              (proof == null ? null : proof['verificationCapturedAtMs']?.toString()) ??
                  '',
            )
          : null;
      final String? faceVerificationEmployeeNumber = requestUsesFace
          ? (proof == null ? null : proof['employeeNumber']?.toString())
          : null;
      final double? faceVerificationConfidence = requestUsesFace
          ? ((proof == null ? null : proof['confidenceScore']) as num?)?.toDouble()
          : null;
      final double? faceLivenessScore = requestUsesFace
          ? ((proof == null ? null : proof['livenessScore']) as num?)?.toDouble()
          : null;
      final String? faceVerificationSource = requestUsesFace
          ? (proof == null ? null : proof['source']?.toString())
          : null;

      // إنشاء نموذج الحضور - punchTime سيتم تعيينه من السيرفر وليس من الجوال
      // هذا يضمن دقة الوقت المسجل في قاعدة البيانات ومنع التلاعب
      final attendance = AttendanceModel(
        employeeNumber: widget.employeeNumber,
        punchState: widget.isCheckIn ? "0" : "1",
        longitude: _currentPosition!.longitude,
        latitude: _currentPosition!.latitude,
        gpsLocation:
            '${_currentPosition!.latitude}, ${_currentPosition!.longitude}',
        mobile: 'Mobile App',
        notes: widget.isCheckIn ? 'Check In' : 'Check Out',
        deviceInfo: deviceInfo,
        temperature: null,
        authenticationMethod: requestUsesFace ? 'FACE' : 'GPS',
        faceVerificationPassed: faceVerificationPassed,
        faceVerificationAtUtc: faceVerificationAtUtc,
        faceVerificationCapturedAtMs: faceVerificationCapturedAtMs,
        faceVerificationEmployeeNumber: faceVerificationEmployeeNumber,
        faceVerificationConfidence: faceVerificationConfidence,
        faceLivenessScore: faceLivenessScore,
        faceVerificationSource: faceVerificationSource,
        isLocationStable: stabilityResult.isStable,
        locationMaxVariation: stabilityResult.maxDistanceVariation,
        locationAverageDistance: stabilityResult.averageDistance,
        locationTotalReadings: stabilityResult.totalReadings,
        locationStabilityDescription:
            _locationStabilityService.getStabilityDescription(stabilityResult),
        isLocationSuspiciouslyStable: stabilityResult.isSuspiciouslyStable,
        isLocationFake: stabilityResult.isFakeLocation,
        locationAverageVariationPercentage:
            stabilityResult.averageVariationPercentage,
        locationMinVariationPercentage: stabilityResult.minVariationPercentage,
      );

      // إرسال البيانات إلى API
      Map<String, dynamic> result;
      if (widget.isCheckIn) {
        result = await _apiService.checkIn(widget.clientId, attendance);
      } else {
        result = await _apiService.checkOut(widget.clientId, attendance);
      }

      if (result['Success'] == true || result['success'] == true) {
        // تحليل رسالة النجاح من API
        String successMessage = result['Message'] ??
            result['message'] ??
            (widget.isCheckIn
                ? Translations.getText('check_in_success', lang)
                : Translations.getText('check_out_success', lang));

        Map<String, String> parsedSuccess =
            _parseApiSuccessMessage(successMessage);

        _showSuccess(parsedSuccess['title']!, parsedSuccess['details']!);
      } else {
        // تحليل رسالة الخطأ من API
        String errorMessage = result['Message'] ??
            result['message'] ??
            Translations.getText('unexpected_error', lang);

        Map<String, String> parsedError = _parseApiErrorMessage(errorMessage);

        _showError(parsedError['title']!, parsedError['details']!);
      }
    } catch (e) {
      _log('❌ خطأ في تسجيل الحضور: $e');
      _showError(Translations.getText('operation_error', lang),
          Translations.getText('contact_support', lang));
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _showSuccess(String message, String details) {
    setState(() {
      _isSuccess = true;
      _resultMessage = message;
      _resultDetails = details;
    });
    _successController.forward();

    // العودة للصفحة الرئيسية بعد 3 ثوانٍ
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.pop(context, true);
      }
    });
  }

  void _showError(String message, String details) {
    // #region debug-point E:show-error
    unawaited(_reportDebugEvent(
      'E',
      'attendance_screen.dart:_showError',
      'Attendance screen displayed error state',
      data: {
        'message': message,
        'details': details,
        'isInitializing': _isInitializing,
        'isProcessing': _isProcessing,
        'currentStep': _currentStep,
      },
    ));
    // #endregion
    setState(() {
      _isSuccess = false;
      _resultMessage = message;
      _resultDetails = details;
    });
    _errorController.forward();
    unawaited(_showFailureDialog(message, details));
  }

  Future<void> _showFailureDialog(String title, String details) async {
    if (!mounted || _isFailureDialogVisible) return;
    _isFailureDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: Text(details),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('موافق'),
              ),
            ],
          );
        },
      );
    } finally {
      _isFailureDialogVisible = false;
    }
  }

  // ⚡ إصلاح: توسيع منطق إعادة المحاولة ليكون أكثر ذكاءً وشمولاً
  bool _canRetry(String errorMessage) {
    if (errorMessage.isEmpty) return false;
    final msgLower = errorMessage.toLowerCase();

    // أولاً: الأخطاء التي ABSOLUTELY لا يجب إعادة المحاولة لها نهائياً (Stop-List)
    final neverRetryKeywords = [
      'الموظف غير نشط',
      'employee inactive',
      'الموظف غير موجود',
      'not found',
      'غير مصرح',
      'unauthorized',
      'غير مفعل',
      'disabled',
      'محظور',
      'blocked',
      'suspended',
      'انتهت فترة تعيين',
      'expired',
      'لا يمكن تسجيل الحضور مرتين',
      'already checked in',
      'لا يمكن تسجيل الانصراف بدون',
      'cannot checkout without',
      'تعيين الموظف للموقع يبدأ من',
      'not started',
      'إثبات التحقق من الوجه',
      'التحقق من الوجه مطلوب',
      'انتهت صلاحية التحقق من الوجه',
      'عدم تطابق بيانات التحقق',
    ];
    final isBlocked = neverRetryKeywords.any(
        (k) => errorMessage.contains(k) || msgLower.contains(k.toLowerCase()));
    if (isBlocked) return false;

    // ثانياً: الأخطاء التي يُنصح دائماً بإعادة المحاولة لها (Go-List)
    final alwaysRetryKeywords = [
      // أخطاء شبكة / اتصال
      'timeout', 'timed out', 'connection', 'socket', 'network',
      'انتهت المهلة', 'خطأ في الاتصال', 'غير متصل',
      // أخطاء موقع GPS
      'خارج نطاق', 'outside', 'outside_allowed_area',
      'الموقع المعين', 'الموقع صحيح', 'location',
      'التحقق من الموقع', 'تحديد الموقع',
      'cannot_determine_location', 'location_determination_failed',
      'wait_for_location', 'gps',
      // أخطاء تخزين / قاعدة بيانات مؤقتة
      'خطأ في حفظ', 'save', 'database', 'unexpected',
      // أخطاء بصمة الوجه / تحقق قابلة للإعادة
      'فشل التحقق من الوجه', 'verification_failed',
      'تعطل بدء عملية', 'retry',
      'try_again_later', 'operation_error',
      // أخطاء عامة قابلة للإعادة
      'error', 'failed', 'خطأ', 'فشل',
    ];
    return alwaysRetryKeywords.any(
        (k) => errorMessage.contains(k) || msgLower.contains(k.toLowerCase()));
  }

  // دالة إعادة المحاولة
  Future<void> _retryOperation() async {
    setState(() {
      _isSuccess = null;
      _resultMessage = '';
      _resultDetails = '';
    });
    await _refreshPage();
  }

  // دالة جديدة لتحليل رسائل الخطأ من API
  Map<String, String> _parseApiErrorMessage(String apiMessage) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    String title = '';
    String details = '';

    // تحليل الرسائل العربية أو الإنجليزية
    if (apiMessage.contains('الموظف غير معين لأي موقع') ||
        apiMessage.toLowerCase().contains('not assigned')) {
      title = Translations.getText('employee_not_assigned', lang);
      details = Translations.getText('contact_admin_for_assignment', lang);
    } else if (apiMessage.contains('أنت خارج نطاق الموقع المعين لك') ||
        apiMessage.toLowerCase().contains('outside')) {
      title = Translations.getText('outside_assigned_location', lang);
      // استخراج اسم الموقع المعين من الرسالة إذا كان متوفراً
      String locationName = '';
      if (apiMessage.contains('الموقع المعين:')) {
        locationName = apiMessage.split('الموقع المعين:').last.trim();
      }
      if (locationName.isNotEmpty) {
        details =
            '${Translations.getText('move_to_your_assigned_location', lang)}\n${Translations.getText('assigned_location', lang)}: $locationName';
      } else {
        details = Translations.getText('move_to_your_assigned_location', lang);
      }
    } else if (apiMessage.contains('تعيين الموظف للموقع يبدأ من')) {
      title = Translations.getText('assignment_not_started', lang);
      details = apiMessage; // عرض التاريخ من الرسالة
    } else if (apiMessage.contains('انتهت فترة تعيين الموظف للموقع')) {
      title = Translations.getText('assignment_expired', lang);
      details = apiMessage; // عرض التاريخ من الرسالة
    } else if (apiMessage.contains('الموقع المعين غير نشط')) {
      title = Translations.getText('assigned_location_inactive', lang);
      details = Translations.getText('contact_admin_activate_location', lang);
    } else if (apiMessage.contains('إحداثيات الموقع المعين غير محددة')) {
      title = Translations.getText('location_coordinates_missing', lang);
      details = Translations.getText('contact_admin_set_coordinates', lang);
    } else if (apiMessage
        .contains('لا يمكن تسجيل الانصراف بدون تسجيل الحضور')) {
      title = Translations.getText('cannot_checkout_without_checkin', lang);
      details = Translations.getText('check_in_first_then_checkout', lang);
    } else if (apiMessage.contains('لا يمكن تسجيل الحضور مرتين') ||
        apiMessage.toLowerCase().contains('already checked in')) {
      title = Translations.getText('already_checked_in', lang);
      details = Translations.getText('cannot_check_in_twice', lang);
    } else if (apiMessage.contains('الموظف غير نشط')) {
      title = Translations.getText('employee_inactive', lang);
      details = Translations.getText('contact_admin_activate_employee', lang);
    } else if (apiMessage.contains('الموظف غير موجود')) {
      title = Translations.getText('employee_not_found', lang);
      details = Translations.getText('check_employee_number', lang);
    } else if (apiMessage.contains('إحداثيات الموقع مطلوبة')) {
      title = Translations.getText('location_coordinates_required', lang);
      details = Translations.getText('enable_gps_location', lang);
    } else if (apiMessage.contains('نوع العملية غير صحيح')) {
      title = Translations.getText('invalid_operation_type', lang);
      details = Translations.getText('use_correct_operation_type', lang);
    } else if (apiMessage.contains('رقم الموظف مطلوب')) {
      title = Translations.getText('employee_number_required', lang);
      details = Translations.getText('enter_valid_employee_number', lang);
    } else if (apiMessage.contains('بيانات الحضور مطلوبة')) {
      title = Translations.getText('attendance_data_required', lang);
      details = Translations.getText('provide_attendance_information', lang);
    } else if (apiMessage.contains('العميل غير موجود أو غير نشط')) {
      title = Translations.getText('client_not_found', lang);
      details = Translations.getText('contact_support_client_issue', lang);
    } else if (apiMessage.contains('خطأ في التحقق من الموقع')) {
      title = Translations.getText('location_verification_error', lang);
      details = Translations.getText('try_again_later', lang);
    } else if (apiMessage.contains('خطأ في حفظ سجل الحضور')) {
      title = Translations.getText('attendance_save_error', lang);
      details = Translations.getText('contact_support_database_issue', lang);
    } else if (apiMessage.contains('التحقق من الوجه مطلوب') ||
        apiMessage.contains('إثبات التحقق من الوجه مفقود')) {
      title = 'التحقق من الوجه مطلوب';
      details =
          'يجب إكمال التحقق من بصمة الوجه من الكاميرا أولاً ثم إعادة محاولة تسجيل الحضور.';
    } else if (apiMessage.contains('انتهت صلاحية التحقق من الوجه')) {
      title = 'انتهت صلاحية التحقق من الوجه';
      details =
          'انتهت مدة صلاحية التحقق السابق. افتح الكاميرا وأعد التحقق من الوجه مباشرة قبل تسجيل الحضور.';
    } else if (apiMessage.contains('رقم الموظف في إثبات التحقق لا يطابق')) {
      title = 'عدم تطابق بيانات التحقق';
      details =
          'تم رفض العملية لأن إثبات الوجه لا يخص نفس الموظف الحالي. أعد تسجيل الدخول بالحساب الصحيح ثم كرر التحقق.';
    } else if (apiMessage
        .contains('تعذر تأكيد التحقق من الوجه من سجلات الخادم')) {
      title = 'تعذر اعتماد التحقق من الوجه';
      details =
          'تحقق الوجه لم يُسجل بشكل مكتمل على الخادم. أعد التحقق من الوجه ثم حاول مرة أخرى.';
    } else {
      // الرسائل العامة
      title = Translations.getText('operation_failed', lang);
      details = apiMessage;
    }

    return {
      'title': title,
      'details': details,
    };
  }

  // دالة جديدة لتحليل رسائل النجاح من API
  Map<String, String> _parseApiSuccessMessage(String apiMessage) {
    final languageService =
        Provider.of<LanguageService>(context, listen: false);
    final lang = languageService.currentLocale.languageCode;

    String title = '';
    String details = '';

    if (apiMessage.contains('تم تسجيل الحضور بنجاح')) {
      title = Translations.getText('check_in_success', lang);
      details =
          Translations.getText('attendance_registered_successfully', lang);
    } else if (apiMessage.contains('تم تسجيل الانصراف بنجاح')) {
      title = Translations.getText('check_out_success', lang);
      details = Translations.getText('departure_registered_successfully', lang);
    } else if (apiMessage.contains('الموقع صحيح')) {
      title = Translations.getText('location_verified', lang);
      // استخراج معلومات إضافية من الرسالة
      String additionalInfo = '';
      if (apiMessage.contains('المسافة:')) {
        additionalInfo = apiMessage.split('المسافة:').last.trim();
        if (additionalInfo.contains('متر')) {
          details =
              '${Translations.getText('location_verified_successfully', lang)}\n$additionalInfo';
        } else {
          details = apiMessage;
        }
      } else {
        details = apiMessage;
      }
    } else {
      title = Translations.getText('operation_successful', lang);
      details = apiMessage;
    }

    return {
      'title': title,
      'details': details,
    };
  }

  @override
  Widget build(BuildContext context) {
    final languageService = Provider.of<LanguageService>(context);
    final lang = languageService.currentLocale.languageCode;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              widget.isCheckIn ? Colors.green.shade50 : Colors.red.shade50,
              widget.isCheckIn ? Colors.green.shade100 : Colors.red.shade100,
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // شريط العنوان
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: widget.isCheckIn
                        ? [Colors.green.shade600, Colors.green.shade800]
                        : [Colors.red.shade600, Colors.red.shade800],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon:
                          const Icon(Icons.arrow_back_ios, color: Colors.white),
                    ),
                    Expanded(
                      child: Text(
                        widget.isCheckIn
                            ? Translations.getText(
                                'register_attendance_title', lang)
                            : Translations.getText(
                                'register_departure_title', lang),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48), // لموازنة الزر
                  ],
                ),
              ),

              // المحتوى الرئيسي
              Expanded(
                child: AnimatedBuilder(
                  animation: _backgroundAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: 0.9 + (_backgroundAnimation.value * 0.1),
                      child: RefreshIndicator(
                        onRefresh: _refreshPage,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              // البطاقة الرئيسية
                              AnimatedBuilder(
                                animation: _cardAnimation,
                                builder: (context, child) {
                                  return Transform.scale(
                                    scale: _cardAnimation.value,
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(30),
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.white,
                                            Colors.grey.shade50,
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        ),
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.1),
                                            blurRadius: 20,
                                            offset: const Offset(0, 10),
                                          ),
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.05),
                                            blurRadius: 40,
                                            offset: const Offset(0, 20),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          // أيقونة ثلاثية الأبعاد
                                          Container(
                                            width: 120,
                                            height: 120,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: widget.isCheckIn
                                                    ? [
                                                        Colors.green.shade400,
                                                        Colors.green.shade600
                                                      ]
                                                    : [
                                                        Colors.red.shade400,
                                                        Colors.red.shade600
                                                      ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(60),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: (widget.isCheckIn
                                                          ? Colors.green
                                                          : Colors.red)
                                                      .withOpacity(0.3),
                                                  blurRadius: 20,
                                                  offset: const Offset(0, 10),
                                                ),
                                              ],
                                            ),
                                            child: Icon(
                                              widget.isCheckIn
                                                  ? Icons.login
                                                  : Icons.logout,
                                              size: 60,
                                              color: Colors.white,
                                            ),
                                          ),
                                          const SizedBox(height: 24),

                                          // اسم الموظف
                                          Text(
                                            widget.employeeName ??
                                                Translations.getText(
                                                    'employee', lang),
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 8),

                                          // رقم الموظف
                                          Text(
                                            '${Translations.getText('employee_number_label', lang)}: ${widget.employeeNumber}',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                          const SizedBox(height: 20),

                                          // حالة العملية
                                          if (_isInitializing ||
                                              _isProcessing) ...[
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 20,
                                                vertical: 12,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                                border: Border.all(
                                                  color: Colors.blue.shade200,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      valueColor:
                                                          AlwaysStoppedAnimation<
                                                              Color>(
                                                        Colors.blue.shade600,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Text(
                                                    _currentStep,
                                                    style: TextStyle(
                                                      color:
                                                          Colors.blue.shade700,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ] else if (_isSuccess != null) ...[
                                            // نتيجة العملية
                                            AnimatedBuilder(
                                              animation: _isSuccess!
                                                  ? _successController
                                                  : _errorController,
                                              builder: (context, child) {
                                                return Transform.scale(
                                                  scale: _isSuccess!
                                                      ? _successScaleAnimation
                                                          .value
                                                      : 1.0,
                                                  child: Container(
                                                    padding:
                                                        const EdgeInsets.all(
                                                            20),
                                                    decoration: BoxDecoration(
                                                      color: _isSuccess!
                                                          ? Colors.green.shade50
                                                          : Colors.red.shade50,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              16),
                                                      border: Border.all(
                                                        color: _isSuccess!
                                                            ? Colors
                                                                .green.shade200
                                                            : Colors
                                                                .red.shade200,
                                                      ),
                                                    ),
                                                    child: Column(
                                                      children: [
                                                        Icon(
                                                          _isSuccess!
                                                              ? Icons
                                                                  .check_circle
                                                              : Icons.error,
                                                          size: 48,
                                                          color: _isSuccess!
                                                              ? Colors.green
                                                              : Colors.red,
                                                        ),
                                                        const SizedBox(
                                                            height: 12),
                                                        Text(
                                                          _resultMessage,
                                                          style: TextStyle(
                                                            fontSize: 18,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            color: _isSuccess!
                                                                ? Colors.green
                                                                    .shade700
                                                                : Colors.red
                                                                    .shade700,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                        const SizedBox(
                                                            height: 8),
                                                        Text(
                                                          _resultDetails,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            color: _isSuccess!
                                                                ? Colors.green
                                                                    .shade600
                                                                : Colors.red
                                                                    .shade600,
                                                          ),
                                                          textAlign:
                                                              TextAlign.center,
                                                        ),
                                                        // زر إعادة المحاولة للرسائل التي يمكن إعادة المحاولة فيها
                                                        if (!_isSuccess! &&
                                                            _canRetry(
                                                                _resultMessage)) ...[
                                                          const SizedBox(
                                                              height: 16),
                                                          Container(
                                                            width:
                                                                double.infinity,
                                                            height: 45,
                                                            decoration:
                                                                BoxDecoration(
                                                              gradient:
                                                                  LinearGradient(
                                                                colors: [
                                                                  Colors.orange
                                                                      .shade400,
                                                                  Colors.orange
                                                                      .shade600,
                                                                ],
                                                                begin: Alignment
                                                                    .topLeft,
                                                                end: Alignment
                                                                    .bottomRight,
                                                              ),
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          22),
                                                              boxShadow: [
                                                                BoxShadow(
                                                                  color: Colors
                                                                      .orange
                                                                      .withOpacity(
                                                                          0.3),
                                                                  blurRadius:
                                                                      10,
                                                                  offset:
                                                                      const Offset(
                                                                          0, 4),
                                                                ),
                                                              ],
                                                            ),
                                                            child: Material(
                                                              color: Colors
                                                                  .transparent,
                                                              child: InkWell(
                                                                onTap:
                                                                    _retryOperation,
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            22),
                                                                child: Center(
                                                                  child: Row(
                                                                    mainAxisAlignment:
                                                                        MainAxisAlignment
                                                                            .center,
                                                                    children: [
                                                                      Icon(
                                                                        Icons
                                                                            .refresh,
                                                                        color: Colors
                                                                            .white,
                                                                        size:
                                                                            20,
                                                                      ),
                                                                      const SizedBox(
                                                                          width:
                                                                              8),
                                                                      Text(
                                                                        Translations.getText(
                                                                            'retry',
                                                                            lang),
                                                                        style:
                                                                            const TextStyle(
                                                                          color:
                                                                              Colors.white,
                                                                          fontSize:
                                                                              16,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        // معلومات إضافية في حالة النجاح - الوقت المسجل من السيرفر
                                                        if (_isSuccess! &&
                                                            _currentPosition !=
                                                                null) ...[
                                                          const SizedBox(
                                                              height: 16),
                                                          Container(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(12),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: Colors
                                                                  .green
                                                                  .shade50,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          12),
                                                              border:
                                                                  Border.all(
                                                                color: Colors
                                                                    .green
                                                                    .shade200,
                                                              ),
                                                            ),
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .check_circle_outline,
                                                                  color: Colors
                                                                      .green
                                                                      .shade600,
                                                                  size: 20,
                                                                ),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    children: [
                                                                      Text(
                                                                        Translations.getText(
                                                                            'registered_location',
                                                                            lang),
                                                                        style:
                                                                            TextStyle(
                                                                          fontSize:
                                                                              12,
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          color: Colors
                                                                              .green
                                                                              .shade700,
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              4),
                                                                      Text(
                                                                        '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                                                                        style:
                                                                            TextStyle(
                                                                          fontSize:
                                                                              11,
                                                                          color: Colors
                                                                              .green
                                                                              .shade600,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ] else ...[
                                            // زر التأكيد
                                            AnimatedBuilder(
                                              animation: _pulseAnimation,
                                              builder: (context, child) {
                                                return Transform.scale(
                                                  scale: _pulseAnimation.value,
                                                  child: Container(
                                                    width: double.infinity,
                                                    height: 60,
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        colors: widget.isCheckIn
                                                            ? [
                                                                Colors.green
                                                                    .shade500,
                                                                Colors.green
                                                                    .shade700
                                                              ]
                                                            : [
                                                                Colors.red
                                                                    .shade500,
                                                                Colors.red
                                                                    .shade700
                                                              ],
                                                        begin:
                                                            Alignment.topLeft,
                                                        end: Alignment
                                                            .bottomRight,
                                                      ),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              30),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: (widget
                                                                      .isCheckIn
                                                                  ? Colors.green
                                                                  : Colors.red)
                                                              .withOpacity(0.3),
                                                          blurRadius: 15,
                                                          offset: const Offset(
                                                              0, 8),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Material(
                                                      color: Colors.transparent,
                                                      child: InkWell(
                                                        onTap:
                                                            _processAttendance,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(30),
                                                        child: Center(
                                                          child: Text(
                                                            widget.isCheckIn
                                                                ? Translations
                                                                    .getText(
                                                                        'register_attendance',
                                                                        lang)
                                                                : Translations
                                                                    .getText(
                                                                        'register_departure',
                                                                        lang),
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 18,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(height: 30),

                              // معلومات إضافية
                              if (!_isInitializing &&
                                  !_isProcessing &&
                                  _isSuccess == null) ...[
                                Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.grey.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.info_outline,
                                            color: Colors.blue.shade600,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            Translations.getText(
                                                'important_information', lang),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.blue.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Text(
                                        Translations.getText(
                                            'location_requirements', lang),
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey.shade600,
                                          height: 1.5,
                                        ),
                                      ),
                                      // عرض معلومات الموقع الحالي
                                      if (_currentPosition != null) ...[
                                        const SizedBox(height: 16),
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                              color: Colors.green.shade200,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.location_on,
                                                color: Colors.green.shade600,
                                                size: 20,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      Translations.getText(
                                                          'current_location',
                                                          lang),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors
                                                            .green.shade700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      '${_currentPosition!.latitude.toStringAsFixed(6)}, ${_currentPosition!.longitude.toStringAsFixed(6)}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .green.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
