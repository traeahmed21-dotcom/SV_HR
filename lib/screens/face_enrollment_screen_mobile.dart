import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../services/face_api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

// ============================================================================
// 🔄 تمت إعادة الهيكلة بالكامل حسب متطلبات المستخدم:
// ----------------------------------------------------------------------------
// ✅ السلوك القديم: Enrollment = فحص الحياة + التحديات + تسجيل البصمة في Biometric
// ✅ السلوك الجديد: Enrollment = التقاط صورة وجه بسيطة + حفظها في جدول Users_Employees
//    (NO LIVENESS CHALLENGES - فقط تحقق وجود وجه + زوايا مناسبة + عيون مفتوحة)
// 🎯 مكان فحص الحياة والهوية الآن: صفحة تسجيل الحضور والانصراف (FaceVerificationScreen)
// ============================================================================
class FaceEnrollmentScreen extends StatefulWidget {
  final String employeeNumber;
  final int clientId;

  const FaceEnrollmentScreen({
    super.key,
    required this.employeeNumber,
    required this.clientId,
  });

  @override
  State<FaceEnrollmentScreen> createState() => _FaceEnrollmentScreenState();
}

class _FaceEnrollmentScreenState extends State<FaceEnrollmentScreen>
    with WidgetsBindingObserver {
  static const bool _enableRemoteDebugTelemetry = true;
  static const String _debugEnvPath = 'd:\\new\\.dbg\\ios-face-save-verify.env';
  String? _debugServerUrl;
  String? _debugSessionId;
  // #region debug-point A:reporting-helper
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
      final session = _debugSessionId ?? 'ios-face-save-verify';
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(Uri.parse(url));
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
  bool _isInitializingCamera = false;
  int _cameraInitToken = 0;
  bool _cameraInitRetryScheduled = false;
  AppLifecycleState? _lastLifecycleState;

  CameraController? _controller;
  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isSavingToServer = false;
  String _statusMessage = '';
  String _instructionMessage = '';
  String _poseHintMessage = '';
  Color _borderColor = Colors.white.withOpacity(0.5);
  double _progressValue =
      0.0; // النسبة المئوية لاستقرار وضع الوجه قبل التصوير التلقائي
  bool _completedSuccessfully = false;
  bool _isFailureDialogVisible = false;

  // ⚡ تتبع وقت بدء الجلسة لحساب المدة بشكل صحيح
  final DateTime _sessionStartTime = DateTime.now();

  // ⚡ نظام Pre-Capture JPG (الحل الجذري لمشكلة تنسيق الصورة):
  // التقاط استباقي لصورة JPG صالحة كل 3 ثوانٍ أثناء مرحلة انتظار الوجه
  Uint8List? _lastProactiveCapturedJpg;
  Face? _lastProactiveCapturedFace;
  DateTime? _lastProactiveCapturedAt;
  Timer? _proactiveCaptureTimer;
  bool _isProactiveCapturing = false;

  bool get _hasReadyIosStillImage =>
      _lastProactiveCapturedJpg != null && _lastProactiveCapturedFace != null;

  ({Uint8List bytes, Face face})? _getReadyProactiveCapture() {
    final bytes = _lastProactiveCapturedJpg;
    final face = _lastProactiveCapturedFace;
    if (bytes == null || face == null) return null;
    return (bytes: bytes, face: face);
  }

  // كاشف الوجه للكشف والتحقق من صحة الوضع
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  Face? _previousTrackedFace;
  Face? _currentDetectedFace;
  bool _isFaceCurrentlyDetected = false;
  int _frameCounter = 0;
  static const int _processEveryNthFrame = 3;
  int _lastTelemetryFaceCount = -999;
  bool _isStartingImageStream = false;
  bool _streamPausedForStillCapture = false;

  // حالة التثبيت قبل التصوير التلقائي:
  Timer? _stabilizationTimer;
  int _goodPoseFramesCount = 0;
  static const int _requiredGoodFrames =
      10; // ~10 إطارات جيدة متتالية قبل التصوير (تقريباً 1-2 ثانية)
  bool _autoCaptureInProgress = false;

  // تخزين آخر إطار وجه صالح للـ Fallback:
  Uint8List? _lastValidFrameBytes;
  Size? _lastValidFrameSize;
  InputImageRotation? _lastValidFrameRotation;
  Face? _lastValidFace;
  bool _captureCompleted = false;
  int _noFaceGraceStreak = 0;

  static const Map<DeviceOrientation, int> _cameraOrientationMap = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // معلومات جودة الوجه الحالية (للملاحظات في الـ UI):
  double _currentHeadY = 0;
  double _currentHeadX = 0;
  double _currentLeftEyeOpen = 1.0;
  double _currentRightEyeOpen = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;
    _statusMessage = Translations.getText('face_point_to_camera', lang);
    _instructionMessage = Translations.getText(
            'face_enrollment_instruction_simple', lang) ??
        'سيتم التقاط صورة لوجهك تلقائياً عندما يكون وضعك مناسباً. لا تحتاج لفعل أي حركات.';
    _poseHintMessage = '';
    _initializeCamera();
    _startProactiveCaptureLoop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stabilizationTimer?.cancel();
    _proactiveCaptureTimer?.cancel();
    _cameraInitToken++;
    _isInitializingCamera = false;
    _cameraInitRetryScheduled = false;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          unawaited(controller.stopImageStream().catchError((_) {}));
        }
      } catch (_) {}
      unawaited(controller.dispose().catchError((_) {}));
    }
    _faceDetector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
    unawaited(_handleAppLifecycleState(state));
  }

  Future<void> _handleAppLifecycleState(AppLifecycleState state) async {
    if (!mounted) return;

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _cameraInitToken++;
      _isInitializingCamera = false;
      _cameraInitRetryScheduled = false;
      await _disposeCameraController(updateUi: mounted);
      return;
    }

    if (state == AppLifecycleState.resumed &&
        mounted &&
        _controller == null &&
        !_completedSuccessfully) {
      await _initializeCamera();
    }
  }

  CameraController _buildCameraController(
    CameraDescription camera, {
    required ResolutionPreset preset,
    ImageFormatGroup? formatGroup,
  }) {
    return CameraController(
      camera,
      preset,
      enableAudio: false,
      imageFormatGroup: formatGroup,
    );
  }

  Future<void> _configureCameraController(CameraController controller) async {
    try {
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}
    try {
      await controller.setFocusMode(FocusMode.auto);
    } catch (_) {}
    try {
      await controller.setExposureMode(ExposureMode.auto);
    } catch (_) {}
    try {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    } catch (_) {}
  }

  Future<void> _disposeCameraController({bool updateUi = false}) async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }
    if (updateUi && mounted) {
      setState(() {
        _isInitializing = true;
      });
    }
  }

  // =========================================================
  // 📸 نظام التقاط الاستباقي لصور JPG (Fallback)
  // =========================================================
  void _startProactiveCaptureLoop() {
    if (Platform.isIOS) {
      return;
    }
    _proactiveCaptureTimer = Timer.periodic(
        Duration(milliseconds: Platform.isIOS ? 900 : 3000), (timer) async {
      if (!mounted ||
          _isInitializing ||
          _isProcessing ||
          _isSavingToServer ||
          _isProactiveCapturing ||
          _captureCompleted ||
          _autoCaptureInProgress) {
        return;
      }
      // نلتقط فقط عندما يكون هناك وجه في الإطار حالياً:
      if (!_isFaceCurrentlyDetected) return;
      if (Platform.isIOS &&
          _hasReadyIosStillImage &&
          _lastProactiveCapturedAt != null &&
          DateTime.now().difference(_lastProactiveCapturedAt!) <
              const Duration(seconds: 2)) {
        return;
      }
      try {
        _isProactiveCapturing = true;
        await _runProactiveCaptureOnce();
      } catch (_) {
      } finally {
        if (mounted) _isProactiveCapturing = false;
      }
    });
  }

  Future<void> _runProactiveCaptureOnce() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final XFile? img = await _tryTakePictureOrNull(timeoutMs: 2200);
    if (img == null) return;
    final bytes = await File(img.path)
        .readAsBytes()
        .timeout(const Duration(milliseconds: 1500));
    final inputImage = InputImage.fromFilePath(img.path);
    final faces = await _faceDetector
        .processImage(inputImage)
        .timeout(const Duration(milliseconds: 2000));
    if (faces.isNotEmpty) {
      if (faces.length > 1) {
        faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
            .compareTo(a.boundingBox.width * a.boundingBox.height));
      }
      if (kDebugMode) {
        print(
            '📸 [Enroll-Proactive] ✅ تم التقاط صورة JPG احتياطية بحجم ${bytes.length ~/ 1024}KB');
      }
      _lastProactiveCapturedJpg = bytes;
      _lastProactiveCapturedFace = faces.first;
      _lastProactiveCapturedAt = DateTime.now();
    } else if (Platform.isIOS &&
        (_currentDetectedFace != null || _lastValidFace != null)) {
      // على iPhone قد لا يلتقط ML Kit الوجه من الصورة الثابتة الأخيرة
      // رغم أن البث الحي أكد وجود وجه صالح قبلها مباشرة.
      final fallbackFace = _currentDetectedFace ?? _lastValidFace;
      if (fallbackFace == null) return;
      _lastProactiveCapturedJpg = bytes;
      _lastProactiveCapturedFace = fallbackFace;
      _lastProactiveCapturedAt = DateTime.now();
    }
  }

  Future<bool> _ensureFreshIosProactiveCapture({int attempts = 2}) async {
    if (!Platform.isIOS) {
      return _lastProactiveCapturedJpg != null &&
          _lastProactiveCapturedFace != null;
    }

    if (_hasReadyIosStillImage &&
        _lastProactiveCapturedAt != null &&
        DateTime.now().difference(_lastProactiveCapturedAt!) <
            const Duration(milliseconds: 1800)) {
      return true;
    }

    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        await _runProactiveCaptureOnce();
      } catch (_) {}

      if (_lastProactiveCapturedJpg != null &&
          _lastProactiveCapturedFace != null) {
        if (kDebugMode) {
          print(
              '📸 [Enroll-iPhone] تم تجهيز JPG نهائية صالحة قبل الحفظ (attempt=$attempt/$attempts)');
        }
        return true;
      }

      if (attempt < attempts) {
        await Future.delayed(const Duration(milliseconds: 180));
      }
    }

    return false;
  }

  Future<bool> _prepareIosStillImageBeforeSave() async {
    if (!Platform.isIOS) return true;
    final hasLiveFace = _currentDetectedFace != null || _lastValidFace != null;
    if (mounted && !_isProcessing && !_isSavingToServer) {
      setState(() {
        _statusMessage = hasLiveFace
            ? 'تم تثبيت الوجه على iPhone، سيتم التقاط صورة واحدة فقط الآن.'
            : 'لم يتم تثبيت الوجه بعد. ابق داخل الإطار للحظة ثم أعد المحاولة.';
      });
    }
    return hasLiveFace;
  }

  Future<Uint8List> _prepareImageBytesForServerUpload(
    Uint8List originalBytes, {
    required String purpose,
    Face? primaryFace,
  }) async {

    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        unawaited(_reportDebugEvent(
          'E',
          'face_enrollment_screen_mobile.dart:_prepareImageBytesForServerUpload',
          'Failed to decode iPhone image before upload; using original bytes',
          data: {
            'purpose': purpose,
            'originalKb': originalBytes.length ~/ 1024,
          },
        ));
        return originalBytes;
      }

      var normalized = img.bakeOrientation(decoded);
      final originalWidth = normalized.width;
      final originalHeight = normalized.height;

      bool cropApplied = false;
      if (primaryFace != null) {
        try {
          final bbox = primaryFace.boundingBox;
          final padX = bbox.width * 0.35;
          final padTop = bbox.height * 0.42;
          final padBottom = bbox.height * 0.30;
          final cropX = (bbox.left - padX).floor().clamp(0, normalized.width - 1);
          final cropY = (bbox.top - padTop).floor().clamp(0, normalized.height - 1);
          final cropRight =
              (bbox.right + padX).ceil().clamp(cropX + 1, normalized.width);
          final cropBottom = (bbox.bottom + padBottom)
              .ceil()
              .clamp(cropY + 1, normalized.height);
          final cropW = cropRight - cropX;
          final cropH = cropBottom - cropY;

          if (cropW >= 120 && cropH >= 140) {
            normalized = img.copyCrop(
              normalized,
              x: cropX,
              y: cropY,
              width: cropW,
              height: cropH,
            );
            cropApplied = true;
          }
        } catch (_) {}
      }

      final isFrontCamera =
          _controller?.description.lensDirection == CameraLensDirection.front;
      if (isFrontCamera) {
        normalized = img.flipHorizontal(normalized);
      }

      final encoded = Uint8List.fromList(
        img.encodeJpg(normalized, quality: 92),
      );
      unawaited(_reportDebugEvent(
        'E',
        'face_enrollment_screen_mobile.dart:_prepareImageBytesForServerUpload',
        'Normalized iPhone image before upload',
        data: {
          'purpose': purpose,
          'originalKb': originalBytes.length ~/ 1024,
          'normalizedKb': encoded.length ~/ 1024,
          'cropApplied': cropApplied,
          'isFrontCamera': isFrontCamera,
          'width': normalized.width,
          'height': normalized.height,
          'originalWidth': originalWidth,
          'originalHeight': originalHeight,
        },
      ));
      return encoded;
    } catch (e) {
      unawaited(_reportDebugEvent(
        'E',
        'face_enrollment_screen_mobile.dart:_prepareImageBytesForServerUpload',
        'Image normalization failed; using original iPhone bytes',
        data: {
          'purpose': purpose,
          'error': e.toString().split('\n').first,
        },
      ));
      return originalBytes;
    }
  }

  Future<XFile?> _tryTakePictureOrNull({required int timeoutMs}) async {
    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) return null;
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
        _streamPausedForStillCapture = true;
      }
      return await controller.takePicture().timeout(
            Duration(milliseconds: timeoutMs),
          );
    } catch (_) {
      return null;
    } finally {
      await _resumeImageStreamIfNeeded();
    }
  }

  Future<void> _resumeImageStreamIfNeeded() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_captureCompleted || _isSavingToServer) return;
    if (_streamPausedForStillCapture && !controller.value.isStreamingImages) {
      try {
        await _startFrameStreaming();
      } catch (_) {
      } finally {
        _streamPausedForStillCapture = false;
      }
    }
  }

  // =========================================================
  // 🎯 دوال مساعدة للترجمات والتنقل
  // =========================================================
  String _lang() => Provider.of<LanguageService>(context, listen: false)
      .currentLocale
      .languageCode;

  String _t(String key) => Translations.getText(key, _lang());

  String _tParams(String key, Map<String, String> params) =>
      Translations.getTextWithParams(key, _lang(), params);

  String _friendlyCameraErrorMessage(Object error) {
    final raw = error.toString().trim();
    final lower = raw.toLowerCase();

    if (lower.contains('null check operator used on a null value')) {
      return _lang() == 'ar'
          ? 'تعذر إكمال تشغيل الكاميرا لأن مرجعاً داخلياً أصبح غير جاهز مؤقتاً أثناء التسجيل. تمت الآن حماية شاشة التسجيل من هذا التعارض، ويمكنك إعادة المحاولة بدون إغلاق الصفحة.'
          : 'The camera could not continue because an internal reference became temporarily unavailable during enrollment. The screen now handles this safely, and you can retry without leaving the page.';
    }

    if (lower.contains('camera') && lower.contains('disposed')) {
      return _lang() == 'ar'
          ? 'تمت إعادة تهيئة الكاميرا أو إغلاقها مؤقتاً أثناء تسجيل الوجه. أعد المحاولة بعد ثبات الوجه داخل الإطار.'
          : 'The camera was reinitialized or temporarily closed during face enrollment. Try again while keeping the face steady inside the frame.';
    }

    return _tParams('camera_start_error_with_error', {'error': raw});
  }

  String _formatDialogMessage(String message, {String? rawDetails}) {
    final normalizedMessage = message.trim();
    final normalizedDetails = rawDetails?.trim();
    if (normalizedDetails == null ||
        normalizedDetails.isEmpty ||
        normalizedDetails == normalizedMessage) {
      return normalizedMessage;
    }

    if (_lang() == 'ar') {
      return '$normalizedMessage\n\nالتفاصيل الفنية:\n$normalizedDetails';
    }

    return '$normalizedMessage\n\nTechnical details:\n$normalizedDetails';
  }

  void _showFailureDialog({
    required String title,
    required String message,
    String? rawDetails,
  }) {
    if (!mounted || _isFailureDialogVisible) return;
    _isFailureDialogVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isFailureDialogVisible = false;
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Text(_formatDialogMessage(message, rawDetails: rawDetails)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(_t('ok')),
            ),
          ],
        ),
      ).whenComplete(() {
        _isFailureDialogVisible = false;
      });
    });
  }

  bool _isSuccessResult(dynamic result) {
    if (result is! Map) return false;
    if (result['Success'] == true) return true;
    if (result['success'] == true) return true;
    if (result['SUCCESS'] == true) return true;
    final s =
        (result['Status'] ?? result['status'] ?? '').toString().toLowerCase();
    if (s == 'ready' || s == 'success' || s == 'ok') return true;
    if (result['Enrolled'] == true ||
        result['Registered'] == true ||
        result['Saved'] == true) return true;
    return false;
  }

  void _smartClose() {
    final bool result = _completedSuccessfully;
    if (kDebugMode) {
      print('🚪 [Enrollment-SmartClose] إغلاق مع النتيجة: $result');
    }
    try {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(result);
      } else {
        SystemNavigator.pop();
      }
    } catch (e) {
      if (kDebugMode)
        print(
            '🚪 [Enrollment-SmartClose] استثناء: $e (الاعتماد على Global Flag).');
    }
  }

  // =========================================================
  // 🎥 تهيئة الكاميرا + معالجة الإطارات (بدون Liveness!)
  // =========================================================
  Future<void> _initializeCamera() async {
    if (_isInitializingCamera) return;
    _isInitializingCamera = true;
    final token = ++_cameraInitToken;

    final cameras = await availableCameras();
    if (!mounted || token != _cameraInitToken) {
      _isInitializingCamera = false;
      return;
    }
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    try {
      await _disposeCameraController();

      final attempts = <({ResolutionPreset preset, ImageFormatGroup? format})>[
        (
          preset:
              Platform.isIOS ? ResolutionPreset.high : ResolutionPreset.medium,
          format: Platform.isAndroid
              ? ImageFormatGroup.nv21
              : ImageFormatGroup.bgra8888,
        ),
        (
          preset: ResolutionPreset.medium,
          format: null,
        ),
        (
          preset: ResolutionPreset.low,
          format: null,
        ),
      ];

      Object? lastError;
      for (final attempt in attempts) {
        CameraController? trialController;
        try {
          trialController = _buildCameraController(
            frontCamera,
            preset: attempt.preset,
            formatGroup: attempt.format,
          );
          await trialController.initialize();
          if (!mounted || token != _cameraInitToken) {
            try {
              await trialController.dispose();
            } catch (_) {}
            return;
          }
          await _configureCameraController(trialController);
          if (!mounted || token != _cameraInitToken) {
            try {
              await trialController.dispose();
            } catch (_) {}
            return;
          }
          _controller = trialController;
          trialController = null;
          break;
        } catch (e) {
          lastError = e;
          try {
            await trialController?.dispose();
          } catch (_) {}
        }
      }

      if (_controller == null) {
        throw lastError ?? Exception('تعذر تهيئة الكاميرا على هذا الجهاز.');
      }

      if (!mounted || token != _cameraInitToken) {
        await _disposeCameraController();
        return;
      }

      _cameraInitRetryScheduled = false;

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        await _startFrameStreaming();
      }
    } catch (e) {
      if (token != _cameraInitToken) return;
      final lower = e.toString().toLowerCase();
      final isTransient = lower.contains('disposed') ||
          lower.contains('not ready') ||
          lower.contains('bad state') ||
          (lower.contains('camera') && lower.contains('closed'));
      final lifecycleOk = _lastLifecycleState == null ||
          _lastLifecycleState == AppLifecycleState.resumed;
      if (mounted && isTransient && lifecycleOk && !_cameraInitRetryScheduled) {
        _cameraInitRetryScheduled = true;
        final retryMessage = _lang() == 'ar'
            ? 'جاري إعادة تشغيل الكاميرا...'
            : 'Restarting camera...';
        setState(() {
          _isInitializing = false;
          _statusMessage = retryMessage;
          _poseHintMessage = '';
        });
        Future.delayed(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          _cameraInitRetryScheduled = false;
          unawaited(_initializeCamera());
        });
        return;
      }

      final friendlyMessage = _friendlyCameraErrorMessage(e);
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _statusMessage = friendlyMessage;
          _borderColor = Colors.red;
          _poseHintMessage = _lang() == 'ar'
              ? 'تم إيقاف المتابعة حتى تتمكن من قراءة سبب المشكلة.'
              : 'The flow has been paused so you can read the error message.';
        });
      }
      _showFailureDialog(
        title: _lang() == 'ar' ? 'خطأ في تشغيل الكاميرا' : 'Camera Error',
        message: friendlyMessage,
        rawDetails: e.toString(),
      );
    } finally {
      _isInitializingCamera = false;
    }
  }

  Future<void> _startFrameStreaming() async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isStreamingImages ||
        _isStartingImageStream) {
      return;
    }
    _isStartingImageStream = true;
    try {
      await controller.startImageStream(_processCameraImage);
    } finally {
      _isStartingImageStream = false;
    }
  }

  Future<
          ({
            InputImage inputImage,
            InputImageRotation rotation,
            InputImageFormat format,
            int bytesPerRow,
          })?>
      _buildMlKitInput(CameraImage image, CameraController controller) async {
    final camera = controller.description;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation) ??
              InputImageRotation.rotation0deg;
    } else {
      final deviceRotation =
          _cameraOrientationMap[controller.value.deviceOrientation];
      if (deviceRotation == null) {
        return null;
      }
      final adjustedRotation = camera.lensDirection == CameraLensDirection.front
          ? (camera.sensorOrientation + deviceRotation) % 360
          : (camera.sensorOrientation - deviceRotation + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(adjustedRotation);
      if (rotation == null) {
        return null;
      }
    }

    final inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) {
      return null;
    }

    if (Platform.isIOS && inputImageFormat != InputImageFormat.bgra8888) {
      return null;
    }

    late final Uint8List imageBytes;
    late final InputImageFormat effectiveFormat;
    late final int bytesPerRow;

    if (Platform.isAndroid) {
      if (image.planes.length == 1 &&
          inputImageFormat == InputImageFormat.nv21) {
        imageBytes = image.planes.first.bytes;
        effectiveFormat = InputImageFormat.nv21;
        bytesPerRow = image.width;
      } else if (image.planes.length == 3) {
        imageBytes = _convertYuv420ToNv21(image);
        effectiveFormat = InputImageFormat.nv21;
        bytesPerRow = image.width;
      } else {
        return null;
      }
    } else {
      if (image.planes.length != 1) {
        return null;
      }
      imageBytes = image.planes.first.bytes;
      effectiveFormat = inputImageFormat;
      bytesPerRow = image.planes.first.bytesPerRow;
    }

    final metadata = InputImageMetadata(
      size: imageSize,
      rotation: rotation,
      format: effectiveFormat,
      bytesPerRow: bytesPerRow,
    );

    return (
      inputImage: InputImage.fromBytes(bytes: imageBytes, metadata: metadata),
      rotation: rotation,
      format: effectiveFormat,
      bytesPerRow: bytesPerRow,
    );
  }

  Uint8List _convertYuv420ToNv21(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];
    final nv21 = Uint8List(width * height + (width * height ~/ 2));
    var index = 0;

    for (var row = 0; row < height; row++) {
      final rowStart = row * yPlane.bytesPerRow;
      nv21.setRange(index, index + width, yPlane.bytes, rowStart);
      index += width;
    }

    final uPixelStride = uPlane.bytesPerPixel ?? 1;
    final vPixelStride = vPlane.bytesPerPixel ?? 1;

    for (var row = 0; row < height ~/ 2; row++) {
      final uRowStart = row * uPlane.bytesPerRow;
      final vRowStart = row * vPlane.bytesPerRow;
      for (var col = 0; col < width ~/ 2; col++) {
        nv21[index++] = vPlane.bytes[vRowStart + col * vPixelStride];
        nv21[index++] = uPlane.bytes[uRowStart + col * uPixelStride];
      }
    }

    return nv21;
  }

  // 🔄 معالجة الإطار الواحد (بدون أي فحص Liveness - فقط كشف وجه + تحقق من الوضع)
  Future<void> _processCameraImage(CameraImage image) async {
    if (!mounted || _captureCompleted) return;

    _frameCounter++;
    if (_frameCounter % _processEveryNthFrame != 0) return;

    try {
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) {
        return;
      }

      final built = await _buildMlKitInput(image, controller);
      if (built == null) {
        if (_frameCounter % 45 == 0) {
          // #region debug-point B:stream-input-unsupported
          unawaited(_reportDebugEvent(
            'B',
            'face_enrollment_screen_mobile.dart:_processCameraImage',
            'Skipped live frame because ML Kit input was unsupported',
            data: {
              'platform': Platform.operatingSystem,
              'cameraName': controller.description.name,
              'lensDirection': controller.description.lensDirection.name,
              'sensorOrientation': controller.description.sensorOrientation,
              'deviceOrientation': controller.value.deviceOrientation.name,
              'imageWidth': image.width,
              'imageHeight': image.height,
              'planesLength': image.planes.length,
              'formatRaw': image.format.raw,
            },
          ));
          // #endregion
        }
        return;
      }

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());
      final camera = controller.description;
      final imageRotation = built.rotation;
      final inputImageFormat = built.format;
      final int bytesPerRow = built.bytesPerRow;
      final Uint8List singlePlaneBytes = image.planes.first.bytes;
      final faces = await _faceDetector.processImage(built.inputImage);

      Face? currentFace;
      if (faces.isNotEmpty) {
        if (faces.length > 1) {
          faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
              .compareTo(a.boundingBox.width * a.boundingBox.height));
        }
        currentFace = faces.first;
        _noFaceGraceStreak = 0;
        _lastValidFrameBytes = singlePlaneBytes;
        _lastValidFrameSize = imageSize;
        _lastValidFrameRotation = imageRotation;
        _lastValidFace = currentFace;
      } else if (_lastValidFace != null && _noFaceGraceStreak < 2) {
        _noFaceGraceStreak++;
        currentFace = _lastValidFace;
      } else {
        _noFaceGraceStreak = 0;
        _lastValidFrameBytes = null;
        _lastValidFrameSize = null;
        _lastValidFrameRotation = null;
        _lastValidFace = null;
      }

      final faceCount = currentFace != null ? 1 : faces.length;
      if (faceCount != _lastTelemetryFaceCount || _frameCounter % 45 == 0) {
        _lastTelemetryFaceCount = faceCount;
        // #region debug-point A:stream-face-detection
        unawaited(_reportDebugEvent(
          'A',
          'face_enrollment_screen_mobile.dart:_processCameraImage',
          'Processed live camera frame for enrollment detection',
          data: {
            'platform': Platform.operatingSystem,
            'cameraName': camera.name,
            'lensDirection': camera.lensDirection.name,
            'sensorOrientation': camera.sensorOrientation,
            'deviceOrientation': controller.value.deviceOrientation.name,
            'imageWidth': image.width,
            'imageHeight': image.height,
            'planesLength': image.planes.length,
            'formatRaw': image.format.raw,
            'inputImageFormat': inputImageFormat.name,
            'bytesPerRow': bytesPerRow,
            'faceCount': faceCount,
            'hasCurrentFace': currentFace != null,
            'boundingBoxWidth': currentFace?.boundingBox.width,
            'boundingBoxHeight': currentFace?.boundingBox.height,
          },
        ));
        // #endregion
      }

      // تحديث الحالات:
      final hadFaceBefore = _isFaceCurrentlyDetected;
      _currentDetectedFace = currentFace;
      _isFaceCurrentlyDetected = currentFace != null;
      if (currentFace != null) {
        _currentHeadY = currentFace.headEulerAngleY ?? 0;
        _currentHeadX = currentFace.headEulerAngleX ?? 0;
        _currentLeftEyeOpen = currentFace.leftEyeOpenProbability ?? 1.0;
        _currentRightEyeOpen = currentFace.rightEyeOpenProbability ?? 1.0;
      }

      // ✅ تحقق من صحة وضع الوجه (الزوايا + العيون):
      final bool isPoseValid = _validateFacePoseForEnrollment(currentFace);
      if (kDebugMode && _frameCounter % 30 == 0) {
        print(
            '🎥 [Enroll-Frame] وجه=$_isFaceCurrentlyDetected | poseValid=$isPoseValid | X=${_currentHeadX.toStringAsFixed(1)}° Y=${_currentHeadY.toStringAsFixed(1)}° | L-eye=${_currentLeftEyeOpen.toStringAsFixed(2)}');
      }

      // 🎯 منطق التصوير التلقائي عند استقرار الوضع الجيد:
      if (!_autoCaptureInProgress && !_isProcessing && !_isSavingToServer) {
        if (_isFaceCurrentlyDetected && isPoseValid) {
          _goodPoseFramesCount =
              (_goodPoseFramesCount + 1).clamp(0, _requiredGoodFrames * 2);
          // بدء مؤقت التثبيت عند أول إطار جيد:
          if (_stabilizationTimer == null || !_stabilizationTimer!.isActive) {
            _stabilizationTimer = Timer(const Duration(milliseconds: 1200), () {
              if (!mounted || _autoCaptureInProgress) return;
              if (_goodPoseFramesCount >= _requiredGoodFrames ~/ 2) {
                if (kDebugMode) {
                  print(
                      '🎯 [Auto-Capture] تم استقرار الوضع → بدء التصوير التلقائي!');
                }
                _manualOrAutoCapture();
              }
            });
          }
        } else {
          _goodPoseFramesCount = 0;
          _stabilizationTimer?.cancel();
          _stabilizationTimer = null;
        }
      }

      // تحديث الواجهة (رسائل التلميح + اللون + النسبة):
      _updatePoseFeedback(currentFace, isPoseValid, hadFaceBefore);

      _previousTrackedFace = currentFace;
    } catch (e) {
      // تجاهل أخطاء معالجة الإطارات الفردية
    }
  }

  // =========================================================
  // ✅ تحقق من صحة وضع الوجه قبل التسجيل (بدون Liveness)
  // =========================================================
  bool _validateFacePoseForEnrollment(Face? face) {
    if (face == null) return false;
    final double headY = face.headEulerAngleY ?? 0;
    final double headX = face.headEulerAngleX ?? 0;
    if (headY.abs() > 25 || headX.abs() > 25) return false;
    if (!_passesEyeOpennessForEnrollment(face)) return false;
    final double w = face.boundingBox.width;
    final double h = face.boundingBox.height;
    if (w < 100 || h < 120) return false;
    return true;
  }

  bool _passesEyeOpennessForEnrollment(Face face) {
    final left = face.leftEyeOpenProbability;
    final right = face.rightEyeOpenProbability;

    // على iPhone تقدير فتح العين من ML Kit يتذبذب أكثر من Android،
    // لذلك لا نرفض الصورة إلا إذا كانت الدلالات قوية على أن العينين مغلقتان فعلاً.
    if (Platform.isIOS) {
      if (left == null && right == null) return true;
      final leftClosed = left != null && left < 0.08;
      final rightClosed = right != null && right < 0.08;
      return !(leftClosed && rightClosed);
    }

    final double leftEye = left ?? 1.0;
    final double rightEye = right ?? 1.0;
    return leftEye >= 0.2 && rightEye >= 0.2;
  }

  // =========================================================
  // 💬 تحديث ملاحظات الوضع في الواجهة (للمستخدم)
  // =========================================================
  void _updatePoseFeedback(Face? face, bool isPoseValid, bool hadFaceBefore) {
    if (!mounted) return;
    String newHint = '';
    Color newBorder = _borderColor;
    double newProgress = _progressValue;

    if (face == null) {
      newHint = '🧐 قم بتوجيه وجهك نحو الكاميرا مباشرة...';
      newBorder = Colors.blue.withOpacity(0.6);
      newProgress = 0.0;
    } else {
      if (_currentHeadY.abs() > 25) {
        newHint = '↔️ انظر مباشرة إلى الأمام (لا تنظر لليمين أو لليسار)';
        newBorder = Colors.orange;
      } else if (_currentHeadX.abs() > 25) {
        newHint = '↕️ انظر مباشرة إلى الأمام (لا تنظر للأعلى أو للأسفل)';
        newBorder = Colors.orange;
      } else if (!Platform.isIOS &&
          (_currentLeftEyeOpen < 0.3 || _currentRightEyeOpen < 0.3)) {
        newHint = '👀 افتح عينيك بوضوح أثناء التقاط الصورة';
        newBorder = Colors.orange;
      } else if (!isPoseValid) {
        newHint = '📏 تقرب من الكاميرا قليلاً (الوجه صغير جداً في الإطار)';
        newBorder = Colors.orange;
      } else {
        newHint = '✅ ممتاز! ابقى ثابتاً للحظة...';
        newBorder = Colors.green;
        newProgress =
            (_goodPoseFramesCount / _requiredGoodFrames).clamp(0.0, 1.0);
      }
    }

    if (newHint != _poseHintMessage ||
        newBorder != _borderColor ||
        newProgress != _progressValue) {
      setState(() {
        _poseHintMessage = newHint;
        _borderColor = newBorder;
        _progressValue = newProgress;
      });
    }
  }

  // =========================================================
  // 📸 الدالة الرئيسية: التقاط الصورة + حفظها في Users_Employees
  // =========================================================
  Future<void> _manualOrAutoCapture() async {
    // #region debug-point B:capture-entry
    unawaited(_reportDebugEvent(
      'B',
      'face_enrollment_screen_mobile.dart:_manualOrAutoCapture',
      'Enrollment capture entry requested',
      data: {
        'platform': Platform.operatingSystem,
        'autoCaptureInProgress': _autoCaptureInProgress,
        'isProcessing': _isProcessing,
        'isSavingToServer': _isSavingToServer,
        'captureCompleted': _captureCompleted,
        'hasReadyIosStillImage': _hasReadyIosStillImage,
        'goodPoseFramesCount': _goodPoseFramesCount,
      },
    ));
    // #endregion
    if (_autoCaptureInProgress || _isProcessing || _isSavingToServer) return;
    _autoCaptureInProgress = true;
    try {
      if (Platform.isIOS) {
        final iosReady = await _prepareIosStillImageBeforeSave();
        if (!iosReady) {
          // #region debug-point B:ios-still-not-ready
          unawaited(_reportDebugEvent(
            'B',
            'face_enrollment_screen_mobile.dart:_manualOrAutoCapture',
            'Enrollment capture deferred because iPhone live face is not ready',
            data: {
              'hasReadyIosStillImage': _hasReadyIosStillImage,
              'isProactiveCapturing': _isProactiveCapturing,
              'lastProactiveFace': _lastProactiveCapturedFace != null,
              'lastProactiveJpg': _lastProactiveCapturedJpg != null,
              'hasCurrentFace': _currentDetectedFace != null,
              'hasLastValidFace': _lastValidFace != null,
            },
          ));
          // #endregion
          return;
        }
      }
      _stabilizationTimer?.cancel();
      _stabilizationTimer = null;
      await _captureAndSaveEmployeeFace();
    } finally {
      if (mounted) _autoCaptureInProgress = false;
    }
  }

  Future<void> _captureAndSaveEmployeeFace() async {
    final initialController = _controller;
    if (_isProcessing ||
        _isSavingToServer ||
        initialController == null ||
        !initialController.value.isInitialized) return;

    final perfTrace = DateTime.now();
    String tid = 'T${perfTrace.millisecondsSinceEpoch.toRadixString(36)}';
    String phase = 'START';
    int saveAttempt = 0;
    if (kDebugMode) {
      print('💾 [ENROLL-SAVE-$tid] ════════════════════════════════════');
      print(
          '💾 [ENROLL-SAVE-$tid] بدء حفظ صورة الوجه في جدول Users_Employees | Emp=${widget.employeeNumber}');
      print('💾 [ENROLL-SAVE-$tid] ════════════════════════════════════');
    }

    setState(() {
      _isSavingToServer = true;
      _isProcessing = true;
      _statusMessage = 'جاري التقاط الصورة وحفظها...';
    });

    Uint8List? finalImageBytes;
    Face? finalFace;
    String? failReason;

    try {
      // ----------------------------------------------------
      // المرحلة 1: التقاط الصورة بشكل متوافق مع iPhone/Android
      // نستخدم JPEG حقيقية فقط، ونفضل JPEG الاستباقية على iPhone.
      // ----------------------------------------------------
      phase = 'CAPTURE_IMAGE';
      String fallbackUsed = 'NONE';
      try {
        final proactiveCapture = _getReadyProactiveCapture();
        if (Platform.isIOS && proactiveCapture != null) {
          finalImageBytes = proactiveCapture.bytes;
          finalFace = proactiveCapture.face;
          fallbackUsed = 'IOS_PROACTIVE_JPG_PRIMARY';
          if (kDebugMode) {
            print(
                '💾 [$tid] PHASE 1A OK: استخدام JPEG استباقية كأساس على iPhone');
          }
        } else {
          final swCap = Stopwatch()..start();
          final activeController = _controller;
          if (activeController == null ||
              !activeController.value.isInitialized) {
            throw StateError(_lang() == 'ar'
                ? 'تم فقدان اتصال الكاميرا أثناء تسجيل الوجه. أعد فتح شاشة التسجيل.'
                : 'Camera connection was lost during enrollment. Reopen the enrollment screen.');
          }
          if (activeController.value.isStreamingImages) {
            await activeController.stopImageStream();
            _streamPausedForStillCapture = true;
          }
          final XFile rawImage = await activeController.takePicture().timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              failReason = 'TIMEOUT_TAKEPICTURE_8S';
              throw TimeoutException(
                  'مهلة التقاط الصورة انتهت → استخدام آخر صورة JPG محفوظة.');
            },
          );
          final bytesXFile = await File(rawImage.path)
              .readAsBytes()
              .timeout(const Duration(seconds: 4));
          final inputImage = InputImage.fromFilePath(rawImage.path);
          final faces = await _faceDetector
              .processImage(inputImage)
              .timeout(const Duration(seconds: 6));
          final t2 = swCap.elapsedMilliseconds;

          if (faces.isNotEmpty) {
            if (faces.length > 1) {
              faces.sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
                  .compareTo(a.boundingBox.width * a.boundingBox.height));
            }
            finalImageBytes = bytesXFile;
            finalFace = faces.first;
            fallbackUsed = 'DIRECT';
            if (kDebugMode)
              print('💾 [$tid] (${t2}ms) PHASE 1A OK: takePicture() مباشر');
          } else if (Platform.isIOS &&
              (_currentDetectedFace != null || _lastValidFace != null)) {
            final fallbackFace = _currentDetectedFace ?? _lastValidFace;
            if (fallbackFace == null) {
              failReason = 'IOS_LIVE_FACE_FALLBACK_NULL';
              throw StateError(_lang() == 'ar'
                  ? 'تم فقدان مرجع الوجه أثناء التقاط صورة التسجيل. أعد المحاولة مع إبقاء الوجه ثابتاً داخل الإطار.'
                  : 'The live face reference was lost during enrollment capture. Try again while keeping the face steady inside the frame.');
            }
            finalImageBytes = bytesXFile;
            finalFace = fallbackFace;
            fallbackUsed = 'IOS_LIVE_FACE_FALLBACK';
            if (kDebugMode) {
              print(
                  '💾 [$tid] (${t2}ms) PHASE 1A OK: iPhone fallback → استخدام وجه البث المباشر مع الصورة الثابتة');
            }
          } else {
            failReason = 'NO_FACE_IN_CAPTURED';
            throw Exception('لا يوجد وجه → Fallback JPG.');
          }
        }
      } catch (capErr) {
        if (kDebugMode) print('💾 [$tid] ⚠️ المرحلة 1A فشلت: $capErr');
        final proactiveCapture = _getReadyProactiveCapture();
        if (proactiveCapture != null) {
          finalImageBytes = proactiveCapture.bytes;
          finalFace = proactiveCapture.face;
          fallbackUsed = 'PROACTIVE_JPG';
          if (kDebugMode)
            print('💾 [$tid] PHASE 1B OK: Fallback → JPG استباقي (${finalImageBytes.length ~/ 1024}KB)');
        } else {
          throw StateError(_lang() == 'ar'
              ? 'تعذر الحصول على صورة وجه صالحة من الكاميرا. أعد المحاولة مع إبقاء الوجه ثابتاً داخل الإطار.'
              : 'Unable to obtain a valid face image from the camera. Try again while keeping your face steady inside the frame.');
        }
      }
      if (finalImageBytes == null || finalFace == null) {
        throw Exception('فشل الحصول على صورة وجه صالحة.');
      }

      // ----------------------------------------------------
      // المرحلة 2: فحص زوايا الرأس والعيون (التحقق النهائي)
      // ----------------------------------------------------
      phase = 'VALIDATE_POSE';
      double headY = finalFace.headEulerAngleY ?? 0;
      double headX = finalFace.headEulerAngleX ?? 0;
      if (headY.abs() > 25 || headX.abs() > 25) {
        throw StateError(_t('look_straight_no_tilt'));
      }
      if (!_passesEyeOpennessForEnrollment(finalFace)) {
        throw StateError(_t('open_eyes_clearly_for_photo'));
      }
      final t2 = DateTime.now().difference(perfTrace).inMilliseconds;
      if (kDebugMode) {
        print(
            '💾 [$tid] (${t2}ms) PHASE 2 OK: زاوية صالحة Y=${headY.toStringAsFixed(1)}° X=${headX.toStringAsFixed(1)}°');
      }

      // ----------------------------------------------------
      // المرحلة 3: Base64 + Metadata (GDPR + خصوصية الصور)
      // ----------------------------------------------------
      phase = 'BASE64_ENCODE';
      final uploadBytes = await _prepareImageBytesForServerUpload(
        finalImageBytes,
        purpose: 'enrollment',
        primaryFace: finalFace,
      );
      final base64Image = base64Encode(uploadBytes);
      final metadata = {
        // نبقي الـ DeviceInfo صغيراً جداً لأن بعض إصدارات الـ API القديمة
        // كانت تحفظه في عمود محدود الحجم وتفشل برسالة:
        // "String or binary data would be truncated".
        'captureTimestamp': DateTime.now().toIso8601String(),
        'imageSource': fallbackUsed,
        'platform': Platform.operatingSystem,
        'consentApproved': true,
        'retentionYears': 5,
        'flowVersion': 'ENROLL_V2',
        'captureBytesKb': finalImageBytes.length ~/ 1024,
        'uploadBytesKb': uploadBytes.length ~/ 1024,
      };
      final t3 = DateTime.now().difference(perfTrace).inMilliseconds;
      if (kDebugMode) {
        print(
            '💾 [$tid] (${t3}ms) PHASE 3 OK: Base64 (${base64Image.length ~/ 1024}KB) + Metadata | upload=${uploadBytes.length ~/ 1024}KB');
      }

      // ----------------------------------------------------
      // المرحلة 4: إرسال الحفظ إلى السيرفر (3 محاولات ذكية)
      // ----------------------------------------------------
      phase = 'SAVE_API_SEND';
      const maxAttempts = 3;
      Map<String, dynamic>? finalResult;
      String? lastApiErr;

      // #region debug-point C:save-request
      unawaited(_reportDebugEvent(
        'C',
        'face_enrollment_screen_mobile.dart:_captureAndSaveEmployeeFace',
        'Enrollment is sending save request',
        data: {
          'employeeNumber': widget.employeeNumber,
          'platform': Platform.operatingSystem,
          'imageSource': fallbackUsed,
          'captureBytesKb': finalImageBytes.length ~/ 1024,
          'uploadBytesKb': uploadBytes.length ~/ 1024,
          'base64Kb': base64Image.length ~/ 1024,
          'hasReadyIosStillImage': _hasReadyIosStillImage,
        },
      ));
      // #endregion

      for (saveAttempt = 1; saveAttempt <= maxAttempts; saveAttempt++) {
        try {
          if (kDebugMode)
            print('💾 [$tid] 🔄 محاولة $saveAttempt/$maxAttempts...');
          final sw = Stopwatch()..start();
          // 🆕 استخدام الدالة الجديدة: saveEmployeeFaceImage → Users_Employees (NO LIVENESS)
          final r = await FaceApiService.saveEmployeeFaceImage(
            clientId: widget.clientId,
            employeeNumber: widget.employeeNumber,
            imageBase64: base64Image,
            deviceInfo: jsonEncode(metadata),
          ).timeout(const Duration(seconds: 15));
          final t4 = sw.elapsedMilliseconds;
          finalResult = r;
          // #region debug-point C:save-response
          unawaited(_reportDebugEvent(
            'C',
            'face_enrollment_screen_mobile.dart:_captureAndSaveEmployeeFace',
            'Enrollment save request returned a response',
            data: {
              'attempt': saveAttempt,
              'elapsedMs': t4,
              'success': r['Success'] == true,
              'message': r['Message'],
              'statusCode': r['StatusCode'] ?? r['statusCode'],
              'updatedExisting': r['UpdatedExisting'] == true || r['Updated'] == true,
              'engineMode': r['EngineMode'],
            },
          ));
          // #endregion
          if (_isSuccessResult(r)) {
            if (kDebugMode)
              print(
                  '💾 [$tid] (${t4}ms) PHASE 4 OK: تم الحفظ بنجاح (محاولة $saveAttempt)');
            lastApiErr = null;
            break;
          } else {
            lastApiErr = r['Message'] ?? 'فشل الحفظ غير معروف';
            if (kDebugMode) print('💾 [$tid] ⚠️ رفض السيرفر: $lastApiErr');
            // إيقاف Retry عند الأخطاء المنطقية (الشبكية فقط نعيدها):
            final errLower = lastApiErr!.toLowerCase();
            final stopKeywords = [
              'غير موجود',
              'غير مفعل',
              'الموظف',
              'not found',
              'مسجلة مسبقاً',
              'already saved',
              'duplicate',
              'غير مصرح',
              'unauthorized',
              'permission',
              'القاعدة',
              'database',
              'invalid',
              'constraint',
              'جودة منخفضة',
              'quality',
              'no face',
              'no face detected',
              'غير واضح',
              'blurry',
            ];
            final shouldStop = stopKeywords.any((k) =>
                lastApiErr!.contains(k) || errLower.contains(k.toLowerCase()));
            if (shouldStop) {
              if (kDebugMode)
                print('💾 [$tid] 🛑 توقف Retry (خطأ منطقي): $lastApiErr');
              break;
            }
          }
        } catch (apiErr) {
          lastApiErr = apiErr.toString();
          if (kDebugMode) print('💾 [$tid] ❌ استثناء: $lastApiErr');
        }
        if (saveAttempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 600 * saveAttempt));
        }
      }

      // ----------------------------------------------------
      // المرحلة 5: النهائية (نجاح أو فشل)
      // ----------------------------------------------------
      phase = 'FINALIZE';
      _captureCompleted = true;

      if (finalResult != null && _isSuccessResult(finalResult)) {
        FaceApiService.markLastFaceSessionSuccessful(
          employeeNumber: widget.employeeNumber,
          sessionKind: 'enrollment',
        );
        _completedSuccessfully = true;
        final totalMs = DateTime.now().difference(perfTrace).inMilliseconds;
        final bool updatedExisting = finalResult!['UpdatedExisting'] == true ||
            finalResult!['Updated'] == true;
        if (kDebugMode) {
          print('✅ [ENROLL-SAVE-SUCCESS-$tid] ═══════════════');
          print('✅  الإجمالي: ${totalMs}ms | المحاولات: $saveAttempt');
          print('✅  رسالة: ${finalResult!['Message'] ?? "---"}');
          print('✅  UpdatedExisting: $updatedExisting');
          print('✅ [ENROLL-SAVE-SUCCESS-$tid] ═══════════════');
        }
        if (mounted) {
          // #region debug-point D:save-final-success
          unawaited(_reportDebugEvent(
            'D',
            'face_enrollment_screen_mobile.dart:_captureAndSaveEmployeeFace',
            'Enrollment finalized as success on Flutter side',
            data: {
              'employeeNumber': widget.employeeNumber,
              'updatedExisting': updatedExisting,
              'message': finalResult!['Message'],
              'captureCompleted': _captureCompleted,
              'completedSuccessfully': _completedSuccessfully,
            },
          ));
          // #endregion
          setState(() {
            _borderColor = Colors.green;
            _statusMessage = updatedExisting
                ? 'تم تحديث صورة الوجه بنجاح في ملفك الشخصي...'
                : 'تم حفظ صورة الوجه بنجاح! سيتم تحويلك الآن.';
            _poseHintMessage = '';
            _progressValue = 1.0;
            _isProcessing = false;
            _isSavingToServer = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 1200), () {
              if (mounted) _smartClose();
            });
          });
        }
      } else {
        var msg = lastApiErr ?? 'فشل حفظ صورة الوجه.';
        var shouldAutoReset = true;
        // 🛡️ تحويل أخطاء الـ HTTP الخام إلى رسائل مفهومة للمستخدم النهائي:
        final msgLower = msg.toLowerCase();
        if (msgLower.contains('string or binary data would be truncated') ||
            msgLower.contains('binary or string data would be truncated') ||
            msgLower.contains('truncated')) {
          msg =
              'فشل الحفظ لأن الخادم اعتبر البيانات المرسلة أكبر من سعة الحقل في قاعدة البيانات. '
              'غالباً المشكلة من الخادم أو من نسخة API قديمة، وليست من وجهك أو الكاميرا.';
          shouldAutoReset = false;
        } else if (msgLower.contains('multiple_faces_detected') ||
            msgLower.contains('أكثر من وجه') ||
            msgLower.contains('more than one face')) {
          msg =
              'تم اكتشاف أكثر من وجه داخل صورة التسجيل. أبعد أي شاشة أو شخص آخر من الخلفية، واجعل وجه موظف واحد فقط داخل الإطار ثم أعد المحاولة.';
          shouldAutoReset = false;
        } else if (msgLower.contains('database') || msgLower.contains('sql')) {
          msg =
              'فشل الحفظ بسبب مشكلة في قاعدة البيانات على الخادم. الرسالة ستبقى ظاهرة حتى تتمكن من قراءتها ثم اضغط إعادة المحاولة.';
          shouldAutoReset = false;
        }
        if (msg.contains('404') || msgLower.contains('not found')) {
          msg =
              'تعذر الوصول إلى خدمة الحفظ مؤقتاً. يتم الآن استخدام خدمة بديلة... يرجى المحاولة مرة أخرى إذا استمرت المشكلة.';
        } else if (msg.contains('500') ||
            msgLower.contains('server error') ||
            msgLower.contains('internal server')) {
          msg =
              'يوجد خطأ في سيرفر قاعدة البيانات حالياً. يرجى المحاولة بعد بضع دقائق أو التواصل مع الدعم الفني.';
        } else if (msgLower.contains('timeout') ||
            msg.contains('مهلة') ||
            msgLower.contains('timed out')) {
          msg =
              'الاستجابة بطيئة جداً من السيرفر. تأكد من قوة الإنترنت ثم أعد المحاولة.';
        } else if (msgLower.contains('connection') ||
            msgLower.contains('socket') ||
            msgLower.contains('network')) {
          msg =
              'تعذر الاتصال بالسيرفر. تأكد من اتصالك بالإنترنت ثم أعد المحاولة.';
        }
        if (kDebugMode) print('❌❌❌ [ENROLL-SAVE-$tid] فشل نهائي. السبب: $msg');
        if (mounted) {
          // #region debug-point D:save-final-failure
          unawaited(_reportDebugEvent(
            'D',
            'face_enrollment_screen_mobile.dart:_captureAndSaveEmployeeFace',
            'Enrollment finalized as failure on Flutter side',
            data: {
              'employeeNumber': widget.employeeNumber,
              'message': msg,
              'shouldAutoReset': shouldAutoReset,
              'lastApiErr': lastApiErr,
              'captureCompleted': _captureCompleted,
            },
          ));
          // #endregion
          setState(() {
            _statusMessage = msg;
            _isProcessing = false;
            _isSavingToServer = false;
            _poseHintMessage = _lang() == 'ar'
                ? 'يمكنك قراءة الرسالة ثم الضغط على "إعادة المحاولة".'
                : 'Read the message, then tap Retry.';
            _borderColor = Colors.red;
          });
          _showFailureDialog(
            title: _lang() == 'ar'
                ? 'فشل حفظ بصمة الوجه'
                : 'Face Save Failed',
            message: msg,
            rawDetails: lastApiErr,
          );
        }
      }
    } catch (e, stack) {
      if (kDebugMode) {
        final ms = DateTime.now().difference(perfTrace).inMilliseconds;
        print(
            '❌❌❌ [ENROLL-SAVE-$tid] استثناء فادح (${ms}ms) | المرحلة: $phase');
        print('❌❌❌ الخطأ: $e');
        print('❌❌❌ Stack: $stack');
      }
      if (mounted) {
        final rawErr = e.toString();
        final errLower = rawErr.toLowerCase();
        String friendlyMsg;
        var shouldAutoReset = true;
        if (rawErr.contains('404') || errLower.contains('not found')) {
          friendlyMsg =
              'خدمة الحفظ غير متاحة حالياً، تم التبديل إلى الخدمة البديلة. يرجى المحاولة مرة أخرى.';
        } else if (rawErr.contains('500') ||
            errLower.contains('server error')) {
          friendlyMsg = 'خطأ في سيرفر قاعدة البيانات. يرجى المحاولة لاحقاً.';
        } else if (errLower.contains('timeout') ||
            errLower.contains('timed out')) {
          friendlyMsg =
              'الاستجابة بطيئة جداً. تأكد من الإنترنت ثم أعد المحاولة.';
        } else if (errLower.contains('connection') ||
            errLower.contains('socket') ||
            errLower.contains('network')) {
          friendlyMsg = 'تعذر الاتصال بالسيرفر. تحقق من اتصال الإنترنت.';
        } else if (errLower.contains('null check operator used on a null value')) {
          friendlyMsg =
              'تم فقدان مرجع الكاميرا أو صورة الوجه مؤقتاً أثناء التسجيل. أعد المحاولة مع إبقاء الوجه ثابتاً داخل الإطار.';
          shouldAutoReset = false;
        } else if (errLower
                .contains('string or binary data would be truncated') ||
            errLower.contains('binary or string data would be truncated') ||
            errLower.contains('truncated')) {
          friendlyMsg =
              'الخادم رفض الحفظ لأن حجم البيانات النصية المرسلة أكبر من سعة الحقل في قاعدة البيانات. '
              'هذا خطأ من جهة الـ API أو قاعدة البيانات، وليس من طريقة وقوفك أمام الكاميرا.';
          shouldAutoReset = false;
        } else if (errLower.contains('multiple_faces_detected') ||
            errLower.contains('أكثر من وجه') ||
            errLower.contains('more than one face')) {
          friendlyMsg =
              'تم اكتشاف أكثر من وجه داخل صورة التسجيل. أبعد أي شاشة أو شخص آخر من الخلفية، واجعل وجه موظف واحد فقط داخل الإطار ثم أعد المحاولة.';
          shouldAutoReset = false;
        } else {
          friendlyMsg = _tParams('error_with_error', {'error': rawErr});
        }
        setState(() {
          _statusMessage = friendlyMsg;
          _isProcessing = false;
          _isSavingToServer = false;
          _poseHintMessage = _lang() == 'ar'
              ? 'بعد قراءة الرسالة اضغط "إعادة المحاولة".'
              : 'After reading the message, tap Retry.';
          _borderColor = Colors.red;
        });
        _showFailureDialog(
          title:
              _lang() == 'ar' ? 'فشل حفظ بصمة الوجه' : 'Face Save Failed',
          message: friendlyMsg,
          rawDetails: rawErr,
        );
      }
    } finally {
      await _resumeImageStreamIfNeeded();
    }
  }

  // =========================================================
  // 🔁 إعادة البدء (زر Retry)
  // =========================================================
  void _resetAndStartOver() {
    if (!mounted) return;
    _stabilizationTimer?.cancel();
    _stabilizationTimer = null;
    _lastProactiveCapturedJpg = null;
    _lastProactiveCapturedFace = null;
    _lastProactiveCapturedAt = null;
    setState(() {
      _isProcessing = false;
      _isSavingToServer = false;
      _autoCaptureInProgress = false;
      _progressValue = 0.0;
      _goodPoseFramesCount = 0;
      _previousTrackedFace = null;
      _currentDetectedFace = null;
      _isFaceCurrentlyDetected = false;
      _frameCounter = 0;
      _noFaceGraceStreak = 0;
      _lastValidFrameBytes = null;
      _lastValidFrameSize = null;
      _lastValidFrameRotation = null;
      _lastValidFace = null;
      _lastTelemetryFaceCount = -999;
      _streamPausedForStillCapture = false;
      _captureCompleted = false;
      final lang = _lang();
      _statusMessage = Translations.getText('face_point_to_camera', lang);
      _poseHintMessage = '';
      _borderColor = Colors.blue.withOpacity(0.6);
    });

    unawaited(() async {
      if (!mounted) return;
      final controller = _controller;
      if (controller == null || !controller.value.isInitialized) {
        await _initializeCamera();
        return;
      }
      await _startFrameStreaming();
    }());
  }

  // =========================================================
  // 🎨 واجهة المستخدم الجديدة (مبسطة - بدون تحديات!)
  // =========================================================
  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _smartClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_t('face_enrollment')),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _smartClose,
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: ClipRect(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final controller = _controller;
                          if (controller == null ||
                              !controller.value.isInitialized) {
                            return const ColoredBox(color: Colors.black);
                          }
                          final previewSize = controller.value.previewSize;
                          final screenAspect =
                              constraints.maxWidth / constraints.maxHeight;
                          final cameraAspect = previewSize == null
                              ? controller.value.aspectRatio
                              : previewSize.height / previewSize.width;
                          double scale = cameraAspect / screenAspect;
                          if (scale < 1) scale = 1 / scale;
                          return Transform.scale(
                            scale: scale,
                            child: Center(child: CameraPreview(controller)),
                          );
                        },
                      ),
                    ),
                  ),
                  // ✅ البطاقة العلوية (العنوان المبسط):
                  Positioned(
                    top: 16,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _t('face_procedure_enrollment_title'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _t('face_fix_face_now'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _t('face_procedure_enrollment_desc'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (_isProcessing || _isSavingToServer) ...[
                              const SizedBox(height: 10),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _t('face_processing_in_progress'),
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.9),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // ✅ بطاقة ملاحظات الوضع (الموجهة للمستخدم بدلاً من التحديات):
                  if (_poseHintMessage.isNotEmpty)
                    Positioned(
                      top: 132,
                      left: 12,
                      right: 12,
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                _borderColor.withOpacity(0.95),
                                _borderColor.withOpacity(0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: _borderColor.withOpacity(0.35),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 500),
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  _poseHintMessage,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // الإطار الملون + شريط التقدم (الاستقرار):
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 270,
                          height: 360,
                          decoration: BoxDecoration(
                            border: Border.all(color: _borderColor, width: 5),
                            borderRadius: BorderRadius.circular(140),
                            boxShadow: [
                              BoxShadow(
                                color: _borderColor.withOpacity(0.25),
                                blurRadius: 20,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 270,
                          child: Column(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                  value: _progressValue,
                                  minHeight: 8,
                                  backgroundColor: Colors.white24,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _borderColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isFaceCurrentlyDetected
                                    ? 'استقرار الوجه: ${(_progressValue * 100).toInt()}%'
                                    : 'في انتظار اكتشاف الوجه...',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // شاشة الانتظار (الـ Loading):
                  if (_isProcessing || _isSavingToServer)
                    Container(
                      color: Colors.black26,
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                                color: Colors.white),
                            const SizedBox(height: 16),
                            Text(
                              _statusMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // ✅ البطاقة السفلية (الأزرار + التعليمات):
            Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _statusMessage,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _borderColor == Colors.red ||
                              _borderColor == Colors.redAccent
                          ? Colors.red
                          : Colors.blue.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_instructionMessage.isNotEmpty &&
                      !_isProcessing &&
                      !_isSavingToServer)
                    Text(
                      _instructionMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 20),
                  // زر التقاط الصورة يدوياً (في حال عدم رغبة المستخدم بالانتظار التلقائي):
                  SizedBox(
                    width: double.infinity,
                    height: 60,
                    child: ElevatedButton.icon(
                      onPressed: (!_isProcessing &&
                              !_isSavingToServer &&
                              _isFaceCurrentlyDetected)
                          ? _manualOrAutoCapture
                          : null,
                      icon: const Icon(Icons.photo_camera, size: 26),
                      label: const Text(
                        'التقاط الصورة الآن',
                        style: TextStyle(
                            fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // زر إعادة المحاولة:
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: (!_isProcessing && !_isSavingToServer)
                          ? _resetAndStartOver
                          : null,
                      icon: const Icon(Icons.refresh),
                      label: Text(
                        _t('retry'),
                        style: const TextStyle(fontSize: 15),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blue,
                        side:
                            BorderSide(color: Colors.blue.shade200, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
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
