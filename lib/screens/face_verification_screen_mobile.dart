import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../services/face_api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import '../services/liveness_detection_service.dart';

class FaceVerificationScreen extends StatefulWidget {
  final String employeeNumber;
  final int clientId;
  final bool showResetButton;

  const FaceVerificationScreen({
    super.key,
    required this.employeeNumber,
    required this.clientId,
    this.showResetButton = true,
  });

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

enum _GuideVisualState {
  noFace,
  multipleFaces,
  outsideFrame,
  aligning,
  ready,
  scanning,
  success,
  error,
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen>
    with WidgetsBindingObserver {
  static const bool _enableRemoteDebugTelemetry = true;
  static const String _debugEnvPath =
      'd:\\new\\.dbg\\attendance-spoof-location.env';
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

  CameraController? _controller;
  bool _isInitializingCamera = false;
  int _cameraInitToken = 0;
  bool _cameraInitRetryScheduled = false;
  AppLifecycleState? _lastLifecycleState;
  bool _isInitializing = true;
  bool _isProcessing = false;
  bool _isVerifyingOnServer = false;
  String _statusMessage = '';
  String _instructionMessage = '';
  String _challengeMessage = '';
  Color _borderColor = Colors.blue;
  bool _faceMatched = false;
  bool _completedSuccessfully = false;
  bool _closeHandled = false;
  bool _isFailureDialogVisible = false;
  Map<String, dynamic>? _successfulVerificationPayload;
  bool _verificationStartRequested = false;
  bool _streamPausedForStillCapture = false;
  Face? _currentDetectedFace;
  int _currentFaceCount = 0;
  PassiveLivenessSnapshot _analysisSnapshot =
      const PassiveLivenessSnapshot.empty();
  PassiveLivenessSnapshot? _lockedAnalysisSnapshot;

  // ⚡ إصلاح 1: تتبع وقت بدء الجلسة لحساب المدة بشكل صحيح
  final DateTime _sessionStartTime = DateTime.now();

  // ⚡ إصلاح 2: نظام Pre-Capture JPG (نفس الحل في التسجيل):
  Uint8List? _lastProactiveCapturedJpg;
  Face? _lastProactiveCapturedFace;
  DateTime? _lastProactiveCapturedAt;
  Timer? _proactiveCaptureTimer;
  bool _isProactiveCapturing = false;
  bool get _hasReadyIosStillImage =>
      _lastProactiveCapturedJpg != null && _lastProactiveCapturedFace != null;

  final LivenessDetectionService _livenessService = LivenessDetectionService();
  LivenessStatus _livenessStatus = LivenessStatus.initializing;

  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  Face? _previousTrackedFace;
  int _frameCounter = 0;
  static const int _processEveryNthFrame =
      3; // ⚡ من 2 إلى 3 → تقليل استهلاك المعالج 33%
  int _lastTelemetryFaceCount = -999;
  bool _isStartingImageStream = false;

  // ⚡ نفس حماية Race Condition للتسجيل (تطبيقها على التحقق للاتساق):
  // تخزين آخر إطار وجه صالح كـ Fallback عند فشل takePicture بسبب تعليق الكاميرا.
  Uint8List? _lastValidFrameBytes;
  Size? _lastValidFrameSize;
  InputImageRotation? _lastValidFrameRotation;
  Face? _lastValidFace;
  bool _verificationCaptureCompleted = false;
  int _noFaceGraceStreak = 0;
  bool _isFaceWithinGuide = false;
  double _faceGuideFitScore = 0.0;
  bool _showIndicators = true;
  _GuideVisualState _stableGuideState = _GuideVisualState.noFace;
  _GuideVisualState? _pendingGuideState;
  DateTime? _pendingGuideSince;
  DateTime _lastUiRebuildAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _lastUiChallengeMessage = '';

  static const Map<DeviceOrientation, int> _cameraOrientationMap = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lang = Provider.of<LanguageService>(context, listen: false)
        .currentLocale
        .languageCode;
    _statusMessage = Translations.getText('face_point_to_camera', lang);
    _instructionMessage = lang == 'ar'
        ? 'سيطلب منك النظام تحدياً حياً قصيراً: ارمش مرة واحدة. هذا لمنع الاحتيال بالصورة أو الفيديو.'
        : 'The system will ask for a short live challenge: blink once. This blocks photo and replay attacks.';
    _challengeMessage = lang == 'ar'
        ? 'جاري فحص التموضع وحيوية الوجه...'
        : 'Analyzing face position and passive liveness...';
    _livenessService.initialize(requiredChallenges: 1);
    _setupLivenessListeners();
    _initializeCamera();
    // ⚡ إصلاح 2: بدء مؤقت التقاط الاستباقي لصور JPG
    _startProactiveCaptureLoop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _proactiveCaptureTimer?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          unawaited(controller.stopImageStream().catchError((_) {}));
        }
      } catch (_) {}
    }
    unawaited(controller?.dispose());
    _faceDetector.close();
    _livenessService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lastLifecycleState = state;
    // #region debug-point B:lifecycle-state
    unawaited(_reportDebugEvent(
      'B',
      'face_verification_screen_mobile.dart:didChangeAppLifecycleState',
      'App lifecycle state changed',
      data: {
        'state': state.name,
        'controllerExists': _controller != null,
        'controllerInitialized': _controller?.value.isInitialized ?? false,
        'isStreamingImages': _controller?.value.isStreamingImages ?? false,
        'isVerifyingOnServer': _isVerifyingOnServer,
        'verificationCaptureCompleted': _verificationCaptureCompleted,
      },
    ));
    // #endregion
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
        !_isVerifyingOnServer &&
        !_verificationCaptureCompleted &&
        !_closeHandled &&
        !_completedSuccessfully) {
      await _initializeCamera();
    }
  }

  bool get _shouldSuppressCameraFailureUi =>
      !mounted ||
      _completedSuccessfully ||
      _faceMatched ||
      _closeHandled ||
      _isVerifyingOnServer ||
      _verificationCaptureCompleted ||
      (_verificationStartRequested &&
          _lastProactiveCapturedJpg != null &&
          _lastProactiveCapturedFace != null);

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

  PassiveLivenessSnapshot get _displaySnapshot =>
      _lockedAnalysisSnapshot ?? _analysisSnapshot;

  int get _displayCompletedRequiredSignals {
    final snapshot = _displaySnapshot;
    if (snapshot.requiredSignals <= 0) return 0;
    return snapshot.completedSignals.clamp(0, snapshot.requiredSignals);
  }

  double get _displaySignalProgress {
    final snapshot = _displaySnapshot;
    if (snapshot.requiredSignals <= 0) return 0.0;
    return (_displayCompletedRequiredSignals / snapshot.requiredSignals)
        .clamp(0.0, 1.0);
  }

  String _buildSignalSummaryText() {
    final snapshot = _displaySnapshot;
    if (_lang() == 'ar') {
      return 'المؤشرات المجتازة: ${snapshot.completedSignals}/${snapshot.totalSignals} | المطلوب للاعتماد: ${snapshot.requiredSignals}';
    }
    return 'Passed indicators: ${snapshot.completedSignals}/${snapshot.totalSignals} | Required: ${snapshot.requiredSignals}';
  }

  String _buildOverallSnapshotText() {
    final snapshot = _displaySnapshot;
    if (_lang() == 'ar') {
      return 'التقييم العام للّقطة: ${((snapshot.overallScore) * 100).round()}%';
    }
    return 'Overall frame score: ${((snapshot.overallScore) * 100).round()}%';
  }

  String _getFacePresenceGuidance(int faceCount) {
    if (_lang() == 'ar') {
      if (faceCount <= 0) {
        return 'لم يتم اكتشاف وجه، يرجى الوقوف أمام الكاميرا بشكل صحيح داخل الإطار.';
      }
      if (faceCount > 1) {
        return 'تم اكتشاف أكثر من وجه في الإطار. يجب أن يظهر وجه موظف واحد فقط.';
      }
      if (!_isFaceWithinGuide) {
        return 'الوجه خارج الإطار المثالي. حرّك الوجه إلى منتصف العدسة حتى يتغيّر لون الإطار.';
      }
      return _analysisSnapshot.guidanceAr;
    }

    if (faceCount <= 0) {
      return 'No face detected. Please stand clearly in front of the camera.';
    }
    if (faceCount > 1) {
      return 'More than one face detected. Only one employee face is allowed in the frame.';
    }
    if (!_isFaceWithinGuide) {
      return 'Your face is outside the ideal guide. Move it to the center until the frame color changes.';
    }
    return _analysisSnapshot.guidanceEn;
  }

  ({bool inside, double score}) _evaluateGuideFit(Face face, Size imageSize) {
    final width = max(imageSize.width, 1.0);
    final height = max(imageSize.height, 1.0);
    final centerX = (face.boundingBox.center.dx / width).clamp(0.0, 1.0);
    final centerY = (face.boundingBox.center.dy / height).clamp(0.0, 1.0);
    final areaRatio =
        ((face.boundingBox.width * face.boundingBox.height) / (width * height))
            .clamp(0.0, 1.0);

    final centerDx = (centerX - 0.5).abs();
    final centerDy = (centerY - 0.49).abs();
    final centerScore = (1.0 -
            (centerDx / 0.20).clamp(0.0, 1.0) * 0.55 -
            (centerDy / 0.18).clamp(0.0, 1.0) * 0.45)
        .clamp(0.0, 1.0);
    final sizeScore = areaRatio >= 0.09 && areaRatio <= 0.28
        ? 1.0
        : (1.0 - ((areaRatio - 0.18).abs() / 0.14)).clamp(0.0, 1.0);
    final poseScore = (1.0 -
            (((face.headEulerAngleY ?? 0.0).abs() / 22.0) * 0.55) -
            (((face.headEulerAngleX ?? 0.0).abs() / 18.0) * 0.45))
        .clamp(0.0, 1.0);
    final score = ((centerScore * 0.5) + (sizeScore * 0.3) + (poseScore * 0.2))
        .clamp(0.0, 1.0);
    final inside = centerDx <= 0.14 &&
        centerDy <= 0.16 &&
        areaRatio >= 0.08 &&
        areaRatio <= 0.32 &&
        (face.headEulerAngleY ?? 0.0).abs() <= 20 &&
        (face.headEulerAngleX ?? 0.0).abs() <= 16;
    return (inside: inside, score: score);
  }

  _GuideVisualState get _guideVisualState => _stableGuideState;

  _GuideVisualState _computeRawGuideState() {
    if (_faceMatched || _completedSuccessfully) {
      return _GuideVisualState.success;
    }
    if (_livenessStatus == LivenessStatus.spoofDetected ||
        _livenessStatus == LivenessStatus.failed ||
        _livenessStatus == LivenessStatus.timeout) {
      return _GuideVisualState.error;
    }
    if (_currentFaceCount > 1) {
      return _GuideVisualState.multipleFaces;
    }
    if (_currentDetectedFace == null) {
      return _GuideVisualState.noFace;
    }
    if (_isVerifyingOnServer || _livenessStatus == LivenessStatus.analyzing) {
      return _GuideVisualState.scanning;
    }
    if (!_isFaceWithinGuide) {
      return _GuideVisualState.outsideFrame;
    }

    final score = _displaySnapshot.overallScore;
    final isReadyStable = _stableGuideState == _GuideVisualState.ready;
    final readyEnter = 0.62;
    final readyExit = 0.52;
    final ready = _livenessStatus == LivenessStatus.passed ||
        (isReadyStable ? score >= readyExit : score >= readyEnter);
    if (ready) return _GuideVisualState.ready;

    return _GuideVisualState.aligning;
  }

  bool _updateStableGuideState({bool force = false}) {
    final now = DateTime.now();
    final raw = _computeRawGuideState();
    if (raw == _stableGuideState) {
      _pendingGuideState = null;
      _pendingGuideSince = null;
      return false;
    }

    final immediate = force ||
        raw == _GuideVisualState.success ||
        raw == _GuideVisualState.error ||
        raw == _GuideVisualState.scanning ||
        raw == _GuideVisualState.multipleFaces;

    if (immediate) {
      _stableGuideState = raw;
      _pendingGuideState = null;
      _pendingGuideSince = null;
      return true;
    }

    if (_pendingGuideState != raw) {
      _pendingGuideState = raw;
      _pendingGuideSince = now;
      return false;
    }

    final since = _pendingGuideSince;
    if (since == null) return false;
    if (now.difference(since) >= const Duration(milliseconds: 350)) {
      _stableGuideState = raw;
      _pendingGuideState = null;
      _pendingGuideSince = null;
      return true;
    }
    return false;
  }

  void _requestUiRebuild({bool force = false}) {
    if (!mounted) return;
    final now = DateTime.now();
    if (!force &&
        now.difference(_lastUiRebuildAt) < const Duration(milliseconds: 120)) {
      return;
    }
    _lastUiRebuildAt = now;
    setState(() {});
  }

  Color get _guideAccentColor {
    switch (_guideVisualState) {
      case _GuideVisualState.noFace:
        return const Color(0xFF7C3AED);
      case _GuideVisualState.multipleFaces:
        return const Color(0xFFEF4444);
      case _GuideVisualState.outsideFrame:
        return const Color(0xFF7C3AED);
      case _GuideVisualState.aligning:
        return const Color(0xFF7C3AED);
      case _GuideVisualState.ready:
        return const Color(0xFF7C3AED);
      case _GuideVisualState.scanning:
        return const Color(0xFF7C3AED);
      case _GuideVisualState.success:
        return const Color(0xFF22C55E);
      case _GuideVisualState.error:
        return const Color(0xFFEF4444);
    }
  }

  // ⚡ إصلاح 2: نظام التقاط الاستباقي (نفس منطق التسجيل)
  void _startProactiveCaptureLoop() {
    _proactiveCaptureTimer = Timer.periodic(
        Duration(milliseconds: Platform.isIOS ? 900 : 3000), (timer) async {
      if (!mounted ||
          _isInitializing ||
          _isProcessing ||
          _isVerifyingOnServer ||
          _isProactiveCapturing ||
          _verificationCaptureCompleted ||
          _livenessStatus == LivenessStatus.spoofDetected) {
        return;
      }
      if (_livenessStatus != LivenessStatus.waitingForFace &&
          _livenessStatus != LivenessStatus.challengeInProgress) {
        return;
      }
      if (Platform.isIOS &&
          _lastProactiveCapturedJpg != null &&
          _lastProactiveCapturedFace != null &&
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
    if (faces.length == 1) {
      if (kDebugMode) {
        print(
            '📸 [Verify-Proactive] ✅ تم التقاط صورة JPG احتياطية بحجم ${bytes.length ~/ 1024}KB | وجه موجود');
      }
      _lastProactiveCapturedJpg = bytes;
      _lastProactiveCapturedFace = faces.first;
      _lastProactiveCapturedAt = DateTime.now();
    } else if (Platform.isIOS &&
        (_currentDetectedFace != null || _lastValidFace != null)) {
      // على iPhone قد تفشل قراءة الوجه من الصورة الثابتة بسبب EXIF/الاتجاه
      // رغم أن البث المباشر أكد وجود وجه صالح قبل أجزاء من الثانية.
      final fallbackFace = _currentDetectedFace ?? _lastValidFace!;
      _lastProactiveCapturedJpg = bytes;
      _lastProactiveCapturedFace = fallbackFace;
      _lastProactiveCapturedAt = DateTime.now();
    } else {
      _lastProactiveCapturedJpg = null;
      _lastProactiveCapturedFace = null;
      _lastProactiveCapturedAt = null;
    }
  }

  Future<bool> _ensureFreshIosProactiveCapture({int attempts = 2}) async {
    if (!Platform.isIOS) {
      return _lastProactiveCapturedJpg != null &&
          _lastProactiveCapturedFace != null;
    }

    if (_lastProactiveCapturedJpg != null &&
        _lastProactiveCapturedFace != null &&
        _lastProactiveCapturedAt != null &&
        DateTime.now().difference(_lastProactiveCapturedAt!) <
            const Duration(milliseconds: 1800)) {
      return true;
    }

    for (int attempt = 1; attempt <= attempts; attempt++) {
      // #region debug-point A:ios-proactive-capture-attempt
      unawaited(_reportDebugEvent(
        'A',
        'face_verification_screen_mobile.dart:_ensureFreshIosProactiveCapture',
        'Starting iPhone proactive JPG attempt',
        data: {
          'attempt': attempt,
          'attempts': attempts,
          'existingJpg': _lastProactiveCapturedJpg != null,
          'existingFace': _lastProactiveCapturedFace != null,
        },
      ));
      // #endregion
      try {
        await _runProactiveCaptureOnce();
      } catch (_) {}

      if (_lastProactiveCapturedJpg != null &&
          _lastProactiveCapturedFace != null) {
        // #region debug-point A:ios-proactive-capture-success
        unawaited(_reportDebugEvent(
          'A',
          'face_verification_screen_mobile.dart:_ensureFreshIosProactiveCapture',
          'iPhone proactive JPG ready before verification',
          data: {
            'attempt': attempt,
            'attempts': attempts,
            'imageKb': _lastProactiveCapturedJpg!.length ~/ 1024,
            'boundingBoxWidth': _lastProactiveCapturedFace!.boundingBox.width,
            'boundingBoxHeight': _lastProactiveCapturedFace!.boundingBox.height,
          },
        ));
        // #endregion
        if (kDebugMode) {
          print(
              '📸 [Verify-iPhone] تم تجهيز JPG نهائية صالحة قبل الإرسال (attempt=$attempt/$attempts)');
        }
        return true;
      }

      if (attempt < attempts) {
        await Future.delayed(const Duration(milliseconds: 180));
      }
    }

    // #region debug-point A:ios-proactive-capture-failed
    unawaited(_reportDebugEvent(
      'A',
      'face_verification_screen_mobile.dart:_ensureFreshIosProactiveCapture',
      'iPhone proactive JPG unavailable before verification',
      data: {
        'attempts': attempts,
        'existingJpg': _lastProactiveCapturedJpg != null,
        'existingFace': _lastProactiveCapturedFace != null,
      },
    ));
    // #endregion
    return false;
  }

  Future<bool> _prepareIosStillImageBeforeVerify() async {
    if (!Platform.isIOS) return true;
    if (_hasReadyIosStillImage) return true;
    if (_isProactiveCapturing) {
      for (int i = 0; i < 10; i++) {
        await Future.delayed(const Duration(milliseconds: 120));
        if (_hasReadyIosStillImage) return true;
      }
    }

    final previousStatus = _statusMessage;
    if (mounted) {
      setState(() {
        _statusMessage =
            'جاري تجهيز صورة التحقق على iPhone، ابق ثابتاً داخل الإطار للحظة...';
      });
    }

    final ready = await _ensureFreshIosProactiveCapture(attempts: 5);
    if (!ready) {
      await Future.delayed(const Duration(milliseconds: 250));
      try {
        await _runProactiveCaptureOnce();
      } catch (_) {}
    }

    if (mounted && !_isProcessing && !_isVerifyingOnServer) {
      setState(() {
        _statusMessage = _hasReadyIosStillImage
            ? 'تم تجهيز صورة التحقق، جاري المتابعة...'
            : previousStatus;
      });
    }

    return _hasReadyIosStillImage;
  }

  Future<Uint8List> _prepareImageBytesForServerUpload(
    Uint8List originalBytes, {
    required String purpose,
  }) async {
    try {
      final decoded = img.decodeImage(originalBytes);
      if (decoded == null) {
        unawaited(_reportDebugEvent(
          'E',
          'face_verification_screen_mobile.dart:_prepareImageBytesForServerUpload',
          'Failed to decode iPhone image before upload; using original bytes',
          data: {
            'purpose': purpose,
            'originalKb': originalBytes.length ~/ 1024,
          },
        ));
        return originalBytes;
      }

      var normalized = img.bakeOrientation(decoded);
      final isFrontCamera =
          _controller?.description.lensDirection == CameraLensDirection.front;
      if (Platform.isIOS && isFrontCamera) {
        normalized = img.flipHorizontal(normalized);
      }

      final maxDim = max(normalized.width, normalized.height);
      if (maxDim > 960) {
        final scale = 960 / maxDim;
        normalized = img.copyResize(
          normalized,
          width: (normalized.width * scale).round(),
          height: (normalized.height * scale).round(),
          interpolation: img.Interpolation.average,
        );
      }

      final encoded = Uint8List.fromList(
        img.encodeJpg(normalized, quality: 85),
      );
      unawaited(_reportDebugEvent(
        'E',
        'face_verification_screen_mobile.dart:_prepareImageBytesForServerUpload',
        'Normalized iPhone image before upload',
        data: {
          'purpose': purpose,
          'originalKb': originalBytes.length ~/ 1024,
          'normalizedKb': encoded.length ~/ 1024,
          'isFrontCamera': isFrontCamera,
          'width': normalized.width,
          'height': normalized.height,
        },
      ));
      return encoded;
    } catch (e) {
      unawaited(_reportDebugEvent(
        'E',
        'face_verification_screen_mobile.dart:_prepareImageBytesForServerUpload',
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
    if (_verificationCaptureCompleted || _isVerifyingOnServer) return;
    if (_streamPausedForStillCapture && !controller.value.isStreamingImages) {
      try {
        await _startFrameStreaming();
      } catch (_) {
      } finally {
        _streamPausedForStillCapture = false;
      }
    }
  }

  String _lang() => Provider.of<LanguageService>(context, listen: false)
      .currentLocale
      .languageCode;

  String _t(String key) => Translations.getText(key, _lang());

  String _tParams(String key, Map<String, String> params) =>
      Translations.getTextWithParams(key, _lang(), params);

  bool get _isOperationRunning =>
      _isProcessing ||
      _isVerifyingOnServer ||
      _livenessStatus == LivenessStatus.analyzing;

  Map<String, String> _currentProcedureInfo() {
    if (_isInitializing ||
        _controller == null ||
        !(_controller?.value.isInitialized ?? false)) {
      return {
        'title': _t('face_procedure_setup_title'),
        'subtitle': _t('face_procedure_setup_desc'),
      };
    }

    return {
      'title': _t('face_procedure_recognition_title'),
      'subtitle': _isVerifyingOnServer
          ? _t('face_procedure_recognition_desc')
          : _t('face_procedure_scan_desc'),
    };
  }

  IconData _currentProcedureIcon() {
    if (_isInitializing ||
        _controller == null ||
        !(_controller?.value.isInitialized ?? false)) {
      return Icons.camera_alt;
    }
    if (_isVerifyingOnServer) return Icons.verified_user;
    return Icons.face_retouching_natural;
  }

  Map<String, dynamic> _currentChallengeUi() {
    final msg = _challengeMessage.trim();
    final lower = msg.toLowerCase();
    final isChallenge = msg.isNotEmpty &&
        (lower.contains('تحدي') || lower.contains('challenge'));
    return {
      'message': msg.isEmpty ? _t('face_inside_frame') : msg,
      'isChallenge': isChallenge,
    };
  }

  String _formatDialogMessage(String message, {String? rawDetails}) {
    final normalizedMessage = message.trim();
    final normalizedDetails = _sanitizeRawDetails(rawDetails);
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

  String? _sanitizeRawDetails(String? rawDetails) {
    if (rawDetails == null) return null;
    final raw = rawDetails.trim();
    if (raw.isEmpty) return null;
    final lower = raw.toLowerCase();

    if (lower.startsWith('bad state:')) {
      final cleaned = raw.substring('bad state:'.length).trim();
      return cleaned.isEmpty ? null : cleaned;
    }

    if (lower.contains('null check operator used on a null value')) {
      return _lang() == 'ar'
          ? 'تم فقدان مرجع داخلي مؤقتاً أثناء التحقق وتمت حماية الشاشة من الانهيار.'
          : 'A temporary internal camera reference was lost during verification and was handled safely.';
    }

    if (lower.contains('camera') && lower.contains('disposed')) {
      return _lang() == 'ar'
          ? 'تم إغلاق الكاميرا أو إعادة تهيئتها أثناء التحقق.'
          : 'The camera was closed or reinitialized during verification.';
    }

    return raw;
  }

  String _friendlyVerificationFailureMessage(
    String message, {
    String? rawDetails,
    String? phase,
  }) {
    final combined = '$message\n${rawDetails ?? ''}'.trim();
    final lower = combined.toLowerCase();

    if (lower.contains('open_eyes') ||
        lower.contains('فتح عينيك') ||
        lower.contains('افتح عينيك') ||
        lower.contains('eye')) {
      return _lang() == 'ar'
          ? 'لم تكتمل قراءة العينين بوضوح. انظر مباشرة إلى الكاميرا وافتح عينيك بشكل طبيعي ثم أعد المحاولة.'
          : 'The eyes were not captured clearly. Look directly at the camera, keep your eyes naturally open, and try again.';
    }

    if (lower.contains('look straight') ||
        lower.contains('look_straight') ||
        lower.contains('بدون ميل') ||
        lower.contains('انظر مباشرة')) {
      return _lang() == 'ar'
          ? 'وضعية الوجه غير مناسبة للتحقق. اجعل وجهك مستقيماً داخل الإطار بدون ميل ثم أعد المحاولة.'
          : 'Face pose is not suitable for verification. Keep your face straight inside the frame without tilting, then try again.';
    }

    if (lower.contains('no face detected') ||
        lower.contains('لم يتم اكتشاف وجه')) {
      return _lang() == 'ar'
          ? 'لم يتم التقاط وجه واضح في اللحظة النهائية. ابق وجهك داخل الإطار وبإضاءة جيدة ثم أعد المحاولة.'
          : 'No clear face was captured at the final moment. Keep your face inside the frame with good lighting and try again.';
    }

    if (lower.contains('more than one face') || lower.contains('أكثر من وجه')) {
      return _lang() == 'ar'
          ? 'تم اكتشاف أكثر من وجه داخل الإطار. يجب أن يظهر وجه موظف واحد فقط أثناء التحقق.'
          : 'More than one face was detected in the frame. Only one employee face must be visible during verification.';
    }

    if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('استغرق') ||
        lower.contains('مهلة')) {
      return _lang() == 'ar'
          ? 'استغرقت عملية التحقق وقتاً أطول من المتوقع. تحقق من الاتصال والخادم ثم أعد المحاولة.'
          : 'Verification took longer than expected. Check connectivity and the backend service, then try again.';
    }

    if (lower.contains('socket') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('خطأ في الاتصال')) {
      return _lang() == 'ar'
          ? 'تعذر إكمال التحقق بسبب مشكلة اتصال مع الخادم. تأكد من الشبكة ثم أعد المحاولة.'
          : 'Verification could not be completed because of a server connection issue. Check the network and try again.';
    }

    if (lower.contains('غير متزامن مع وقت الخادم')) {
      return _lang() == 'ar'
          ? 'تم التحقق من الوجه، لكن الخادم رفض اعتماد الطابع الزمني للتحقق. تم تحسين هذا المسار، وإذا تكررت الرسالة فتأكد من تحديث نسخة الخادم أيضاً.'
          : 'Face verification succeeded, but the server rejected the verification timestamp. This path has been improved; if it still happens, make sure the backend is updated too.';
    }

    if (lower.contains('تعذر تأكيد التحقق من الوجه من سجلات الخادم')) {
      return _lang() == 'ar'
          ? 'الخادم لم يجد سجلاً حديثاً يؤكد نجاح التحقق. أعد المحاولة فوراً، وإذا تكرر ذلك فراجع خدمة الخادم وسجل FaceLogs.'
          : 'The server could not find a recent record confirming verification success. Retry immediately, and if it repeats, review the backend service and FaceLogs.';
    }

    if (lower.contains('لا تتطابق') ||
        lower.contains('not match') ||
        lower.contains('mismatch')) {
      return _lang() == 'ar'
          ? 'الوجه الحالي لا يطابق السجل المحفوظ بشكل كافٍ. تأكد من الإضاءة والزاوية ثم أعد المحاولة.'
          : 'The current face does not match the stored record closely enough. Check lighting and angle, then try again.';
    }

    if (lower.contains('مقاومة الانتحال') ||
        lower.contains('anti_spoof') ||
        lower.contains('screen') ||
        lower.contains('video') ||
        lower.contains('صورة') ||
        lower.contains('شاشة')) {
      return _lang() == 'ar'
          ? 'تم رفض اللقطة لأن النظام اشتبه بأنها صورة أو فيديو أو عرض من شاشة. استخدم الوجه الحقيقي مباشرة أمام الكاميرا وأبعد أي جهاز آخر عن المشهد.'
          : 'The capture was rejected because it looked like a photo, video, or screen replay. Use a real face directly in front of the camera and keep other devices out of view.';
    }

    if (lower.contains('التحدي العشوائي') ||
        lower.contains('active_challenge') ||
        lower.contains('challenge required')) {
      return _lang() == 'ar'
          ? 'تم رفض التحقق لأن التحدي الحي المباشر لم يكتمل. اتبع التعليمات التي تظهر على الشاشة مثل الرمش أو تحريك الرأس في اللحظة المطلوبة.'
          : 'Verification was rejected because the live challenge did not complete. Follow the on-screen instruction, such as blinking or turning your head at the requested moment.';
    }

    if (lower.contains('نسيج الوجه') ||
        lower.contains('skin texture') ||
        lower.contains('texture')) {
      return _lang() == 'ar'
          ? 'لم يجتز النظام فحص نسيج الوجه ومقاومة السطح المسطح. ابتعد عن أي شاشة أو صورة، واجعل الوجه الحقيقي قريباً وواضحاً داخل الإطار.'
          : 'Face texture validation did not pass. Avoid screens or printed photos and keep a real face close and clear inside the frame.';
    }

    if (lower.contains('زمن الفحص') ||
        lower.contains('session_duration') ||
        lower.contains('session duration')) {
      return _lang() == 'ar'
          ? 'مدة الفحص كانت قصيرة وغير كافية لتأكيد الحيوية. ابق ثابتاً لثوانٍ قليلة إضافية ثم أعد المحاولة.'
          : 'The scan duration was too short to confirm liveness. Stay steady for a few more seconds and try again.';
    }

    if (lower.contains('بيانات الفحص الحيوي') ||
        lower.contains('passive evidence') ||
        lower.contains('evidence_missing')) {
      return _lang() == 'ar'
          ? 'التطبيق أو الخادم لم يتبادلا تفاصيل الفحص الحيوي بشكل كامل. تأكد من تحديث التطبيق والخادم ثم أعد المحاولة.'
          : 'The app or server did not exchange complete passive liveness evidence. Make sure both app and backend are updated, then try again.';
    }

    if (lower.contains('bad state')) {
      return _lang() == 'ar'
          ? 'حدث تعارض داخلي مؤقت أثناء التحقق، وتمت حماية الشاشة من الانهيار. أعد المحاولة مرة أخرى.'
          : 'A temporary internal verification conflict occurred and was handled safely. Please try again.';
    }

    return message.trim().isEmpty
        ? (_lang() == 'ar'
            ? 'تعذر إكمال التحقق من الوجه. أعد المحاولة مرة أخرى.'
            : 'Face verification could not be completed. Please try again.')
        : message.trim();
  }

  String? _detectVerificationResultAnomaly(dynamic result) {
    if (result == null) return null;
    if (result is! Map) {
      return _lang() == 'ar'
          ? 'تم استلام رد غير متوقع من خدمة التحقق. يرجى إعادة المحاولة.'
          : 'An unexpected verification response was received. Please try again.';
    }

    final success = result['Success'] == true ||
        result['success'] == true ||
        result['SUCCESS'] == true;
    final matched = result['IsMatch'] == true || result['Matched'] == true;
    final employee =
        (result['EmployeeNumber'] ?? result['employeeNumber'] ?? '')
            .toString()
            .trim();
    final confidence = (result['ConfidenceScore'] as num?)?.toDouble();

    if (employee.isNotEmpty && employee != widget.employeeNumber) {
      return _lang() == 'ar'
          ? 'رد خدمة التحقق يخص موظفاً مختلفاً عن الموظف الحالي، لذلك تم إيقاف العملية.'
          : 'The verification response belongs to a different employee, so the operation was stopped.';
    }

    if (success && !matched) {
      return _lang() == 'ar'
          ? 'رد الخادم يشير إلى نجاح شكلي بدون تأكيد مطابقة الوجه، لذلك تم رفض النتيجة لحماية العملية.'
          : 'The server response indicated a nominal success without confirming a face match, so the result was rejected for safety.';
    }

    if (matched && confidence != null && confidence < 0.65) {
      return _lang() == 'ar'
          ? 'الخادم أعاد مطابقة بدرجة ثقة منخفضة وغير مقبولة، لذلك تم رفض النتيجة.'
          : 'The server returned a match with an insufficient confidence score, so the result was rejected.';
    }

    return null;
  }

  String _friendlyCameraErrorMessage(Object error) {
    final raw = error.toString().trim();
    final lower = raw.toLowerCase();

    if (lower.contains('null check operator used on a null value')) {
      return _lang() == 'ar'
          ? 'تعذر إكمال تهيئة الكاميرا لأن مرجع الكاميرا أصبح غير جاهز أثناء التشغيل. تم الآن تحسين الحماية داخل الشاشة، وأي فقد مؤقت للكاميرا لن يؤدي إلى انهيار العملية.'
          : 'Camera initialization could not complete because the camera reference became unavailable during execution. The screen now handles temporary camera loss safely.';
    }

    if (lower.contains('camera') && lower.contains('disposed')) {
      return _lang() == 'ar'
          ? 'تم إغلاق الكاميرا أثناء التحقق. يرجى إعادة المحاولة.'
          : 'The camera was closed during verification. Please try again.';
    }

    return _tParams(
      'camera_start_error_with_error',
      {'error': raw},
    );
  }

  void _showFailureDialog({
    required String title,
    required String message,
    String? rawDetails,
  }) {
    if (!mounted ||
        _isFailureDialogVisible ||
        _completedSuccessfully ||
        _closeHandled) {
      return;
    }
    _isFailureDialogVisible = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _isFailureDialogVisible = false;
        return;
      }

      if (_completedSuccessfully || _faceMatched || _closeHandled) {
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

  List<int> _extractFaceTextureSamples(CameraImage image, Face? face) {
    if (image.planes.isEmpty) return const <int>[];

    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return const <int>[];

    final pixelStride = plane.bytesPerPixel ?? (Platform.isIOS ? 4 : 1);
    final bytesPerRow = plane.bytesPerRow;
    final frameWidth = image.width;
    final frameHeight = image.height;

    int left = 0;
    int top = 0;
    int right = frameWidth - 1;
    int bottom = frameHeight - 1;

    if (face != null) {
      final box = face.boundingBox;
      final paddingX = (box.width * 0.12).round();
      final paddingY = (box.height * 0.12).round();
      left = ((box.left.round() - paddingX).clamp(0, frameWidth - 1)) as int;
      top = ((box.top.round() - paddingY).clamp(0, frameHeight - 1)) as int;
      right = ((box.right.round() + paddingX).clamp(0, frameWidth - 1)) as int;
      bottom =
          ((box.bottom.round() + paddingY).clamp(0, frameHeight - 1)) as int;
    }

    if (right <= left || bottom <= top) return const <int>[];

    final samples = <int>[];
    final roiWidth = right - left + 1;
    final roiHeight = bottom - top + 1;
    final stepX = max(1, roiWidth ~/ 28);
    final stepY = max(1, roiHeight ~/ 28);

    for (int y = top; y <= bottom; y += stepY) {
      for (int x = left; x <= right; x += stepX) {
        final offset = (y * bytesPerRow) + (x * pixelStride);
        if (offset < 0 || offset >= bytes.length) continue;

        if (pixelStride >= 4 && offset + 2 < bytes.length) {
          final b = bytes[offset];
          final g = bytes[offset + 1];
          final r = bytes[offset + 2];
          final luminance =
              (0.114 * b + 0.587 * g + 0.299 * r).round().clamp(0, 255);
          samples.add(luminance);
        } else {
          samples.add(bytes[offset]);
        }

        if (samples.length >= 900) {
          return samples;
        }
      }
    }

    return samples;
  }

  Map<String, dynamic>? _extractFaceDepthAnalysisPayload(
    CameraImage image,
    Face? face,
  ) {
    if (image.planes.isEmpty) return null;

    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return null;

    final pixelStride = plane.bytesPerPixel ?? (Platform.isIOS ? 4 : 1);
    final bytesPerRow = plane.bytesPerRow;
    final frameWidth = image.width;
    final frameHeight = image.height;

    int left = 0;
    int top = 0;
    int right = frameWidth - 1;
    int bottom = frameHeight - 1;

    if (face != null) {
      final box = face.boundingBox;
      left = max(0, box.left.floor());
      top = max(0, box.top.floor());
      right = min(frameWidth - 1, box.right.ceil());
      bottom = min(frameHeight - 1, box.bottom.ceil());
    }

    if (right <= left || bottom <= top) return null;

    const targetSize = 36;
    final roiWidth = max(1, right - left + 1);
    final roiHeight = max(1, bottom - top + 1);
    final stepX = max(1, roiWidth ~/ targetSize);
    final stepY = max(1, roiHeight ~/ targetSize);

    final pixels = <int>[];
    int sampleWidth = 0;
    int sampleHeight = 0;

    for (int y = top; y <= bottom; y += stepY) {
      int rowWidth = 0;
      for (int x = left; x <= right; x += stepX) {
        final offset = (y * bytesPerRow) + (x * pixelStride);
        if (offset < 0 || offset >= bytes.length) continue;

        int r;
        int g;
        int b;
        if (pixelStride >= 4 && offset + 2 < bytes.length) {
          b = bytes[offset];
          g = bytes[offset + 1];
          r = bytes[offset + 2];
        } else {
          final yValue = bytes[offset];
          r = yValue;
          g = yValue;
          b = yValue;
        }

        pixels
          ..add(r)
          ..add(g)
          ..add(b);
        rowWidth++;
      }

      if (rowWidth > 0) {
        sampleHeight++;
        if (rowWidth > sampleWidth) {
          sampleWidth = rowWidth;
        }
      }
    }

    if (pixels.isEmpty || sampleWidth < 8 || sampleHeight < 8) {
      return null;
    }

    return {
      'pixels': pixels,
      'width': sampleWidth,
      'height': sampleHeight,
    };
  }

  bool _isVerifiedMatchResult(dynamic result) {
    if (result is! Map) return false;

    final bool explicitMatch =
        result['IsMatch'] == true || result['Matched'] == true;
    if (explicitMatch) return true;

    final bool successFlag = result['Success'] == true ||
        result['success'] == true ||
        result['SUCCESS'] == true;
    final status =
        (result['Status'] ?? result['status'] ?? '').toString().toLowerCase();
    final message =
        (result['Message'] ?? result['message'] ?? '').toString().toLowerCase();
    final confidence = (result['ConfidenceScore'] as num?)?.toDouble() ?? 0.0;

    // توافق احتياطي مع الردود القديمة: لا نعتبر النجاح صحيحاً إلا إذا
    // كان الرد ناجحاً ورسالة الخادم تؤكد التحقق ودرجة التشابه ضمن الحد المقبول.
    return successFlag &&
        (status == 'success' || status == 'ok' || status.isEmpty) &&
        confidence >= 0.65 &&
        (message.contains('تم التحقق من الوجه بنجاح') ||
            message.contains('verification success'));
  }

  void _smartClose({String reason = 'auto', bool forceSuccess = false}) {
    if (_closeHandled) return;
    _closeHandled = true;
    final bool result = forceSuccess || _completedSuccessfully || _faceMatched;
    final payload = <String, dynamic>{
      'Success': result,
      'Matched': _faceMatched,
      'Completed': _completedSuccessfully,
      'EmployeeNumber': widget.employeeNumber,
      'Reason': reason,
    };
    if (_successfulVerificationPayload != null) {
      payload.addAll(_successfulVerificationPayload!);
    }
    if (kDebugMode) {
      print(
          '🚪 [Verification-SmartClose] محاولة إغلاق شاشة التحقق | result=$result | completed=$_completedSuccessfully | matched=$_faceMatched | reason=$reason | canPop=${Navigator.of(context).canPop()}');
    }
    try {
      final localNavigator = Navigator.of(context);
      final rootNavigator = Navigator.of(context, rootNavigator: true);
      if (localNavigator.canPop()) {
        localNavigator.pop(payload);
      } else if (rootNavigator.canPop()) {
        rootNavigator.pop(payload);
      } else {
        if (kDebugMode) {
          print(
              '🚪 [Verification-SmartClose] لا يوجد Navigator يمكنه pop. سنعتمد على Global Flag فقط.');
        }
      }
    } catch (e) {
      if (kDebugMode)
        print(
            '🚪 [Verification-SmartClose] ❌ استثناء أثناء الإغلاق: $e. الاعتماد على Global Flag Failsafe.');
    }
  }

  void _setupLivenessListeners() {
    _livenessService.statusStream.listen((status) {
      if (!mounted) return;
      if (status == _livenessStatus) return;
      _livenessStatus = status;
      _handleLivenessStatusChange(status);
      _updateStableGuideState(force: status == LivenessStatus.analyzing);
      _requestUiRebuild(force: true);
    });
    _livenessService.challengeStream.listen((challenge) {
      if (!mounted) return;
      final msg = _describeLivenessChallenge(challenge);
      if (msg == _challengeMessage) return;
      _challengeMessage = msg;
      _lastUiChallengeMessage = msg;
      _requestUiRebuild(force: true);
      // #region debug-point A:liveness-active-challenge
      unawaited(_reportDebugEvent(
        'A',
        'face_verification_screen_mobile.dart:_setupLivenessListeners:challenge',
        'Issued active liveness challenge',
        data: {
          'challengeType': challenge.type.name,
          'timeLimitSec': challenge.timeLimit.inSeconds,
          'completedCount': _livenessService.completedChallengeCount,
          'requiredCount': _livenessService.requiredChallenges,
        },
      ));
      // #endregion
    });
  }

  String _describeLivenessChallenge(LivenessChallenge challenge) {
    final elapsed = DateTime.now().difference(challenge.startTime);
    final remaining =
        max(0, challenge.timeLimit.inSeconds - elapsed.inSeconds);
    switch (challenge.type) {
      case LivenessChallengeType.blink:
        return _lang() == 'ar'
            ? 'تحدي مباشر: ارمش مرة واحدة الآن خلال $remaining ثوانٍ.'
            : 'Live challenge: blink once now within $remaining seconds.';
      case LivenessChallengeType.headTiltLeft:
        return _lang() == 'ar'
            ? 'تحدي مباشر: حرّك رأسك قليلاً إلى اليسار خلال $remaining ثوانٍ.'
            : 'Live challenge: turn your head slightly to the left within $remaining seconds.';
      case LivenessChallengeType.headTiltRight:
        return _lang() == 'ar'
            ? 'تحدي مباشر: حرّك رأسك قليلاً إلى اليمين خلال $remaining ثوانٍ.'
            : 'Live challenge: turn your head slightly to the right within $remaining seconds.';
      case LivenessChallengeType.smile:
      case LivenessChallengeType.mouthOpen:
      case LivenessChallengeType.headTiltUp:
      case LivenessChallengeType.headTiltDown:
        return _lang() == 'ar'
            ? 'جاري تنفيذ التحدي الحيوي المباشر...'
            : 'Live biometric challenge in progress...';
    }
  }

  void _handleLivenessStatusChange(LivenessStatus status) {
    if (!mounted) return;

    // #region debug-point A:liveness-status
    unawaited(_reportDebugEvent(
      'A',
      'face_verification_screen_mobile.dart:_handleLivenessStatusChange',
      'Liveness status changed',
      data: {
        'status': status.name,
        'isProcessing': _isProcessing,
        'isVerifyingOnServer': _isVerifyingOnServer,
        'controllerExists': _controller != null,
        'controllerInitialized': _controller?.value.isInitialized ?? false,
        'verificationCaptureCompleted': _verificationCaptureCompleted,
      },
    ));
    // #endregion

    switch (status) {
      case LivenessStatus.initializing:
        _borderColor = Colors.blue;
        _statusMessage = _t('liveness_initializing');
        break;
      case LivenessStatus.waitingForFace:
        _borderColor = Colors.blue;
        _statusMessage = _t('liveness_waiting_face');
        _challengeMessage = _getFacePresenceGuidance(_currentFaceCount);
        break;
      case LivenessStatus.challengeInProgress:
        _borderColor = Colors.lightBlueAccent;
        _statusMessage = _lang() == 'ar'
            ? 'جاري فحص الحياة السلبي وتتبع الوجه'
            : 'Passive liveness scan in progress';
        _challengeMessage = _livenessService.currentChallenge != null
            ? _describeLivenessChallenge(_livenessService.currentChallenge!)
            : _getFacePresenceGuidance(_currentFaceCount);
        break;
      case LivenessStatus.analyzing:
        _borderColor = Colors.purple;
        _challengeMessage = _lang() == 'ar'
            ? 'جاري إنهاء تحليل الهوية ومقاومة الانتحال...'
            : 'Finalizing liveness and anti-spoof analysis...';
        _statusMessage = _t('liveness_analyzing');
        _isProcessing = true;
        break;
      case LivenessStatus.passed:
        _borderColor = Colors.green;
        _lockedAnalysisSnapshot = _livenessService.currentSnapshot;
        _challengeMessage = _lang() == 'ar'
            ? 'تم اجتياز جميع مؤشرات الفحص الحيوي المطلوبة، جاري إرسال التحقق للخادم.'
            : 'All required biometric indicators passed, sending verification request.';
        _statusMessage = _t('liveness_passed');
        // ⚡ تم إزالة _isProcessing=true هنا (تعارض قاتل مع Retry Mechanism!)
        if (kDebugMode) {
          print('✅ [VERIFY-LIVENESS-PASSED] ════════════════════════');
          print(
              '✅ [VERIFY-LIVENESS-PASSED] Status=passed | _isProcessing=$_isProcessing | _isVerifyingOnServer=$_isVerifyingOnServer');
          print(
              '✅ [VERIFY-LIVENESS-PASSED] _controller=${_controller != null ? "EXISTS" : "NULL"} | initialized=${_controller?.value.isInitialized ?? false} | mounted=$mounted');
          print(
              '✅ [VERIFY-LIVENESS-PASSED] بدء سلسلة Retry للاستدعاء (3 محاولات كل 300ms)...');
          print('✅ [VERIFY-LIVENESS-PASSED] ════════════════════════');
        }
        if (_verificationStartRequested ||
            _isVerifyingOnServer ||
            _verificationCaptureCompleted) {
          unawaited(_reportDebugEvent(
            'A',
            'face_verification_screen_mobile.dart:LivenessStatus.passed',
            'Ignored duplicate passed event',
            data: {
              'verificationStartRequested': _verificationStartRequested,
              'isVerifyingOnServer': _isVerifyingOnServer,
              'verificationCaptureCompleted': _verificationCaptureCompleted,
            },
          ));
          break;
        }
        _verificationStartRequested = true;
        _lastProactiveCapturedAt = null;
        // #region debug-point A:passed-trigger
        unawaited(_reportDebugEvent(
          'A',
          'face_verification_screen_mobile.dart:LivenessStatus.passed',
          'Scheduling verification start retry',
          data: {
            'isProcessing': _isProcessing,
            'isVerifyingOnServer': _isVerifyingOnServer,
            'controllerInitialized': _controller?.value.isInitialized ?? false,
            'completedChallenges': _livenessService.completedChallengeCount,
          },
        ));
        // #endregion
        unawaited(_tryStartVerificationWithRetry(maxAttempts: 10, delayMs: 200));
        break;
      case LivenessStatus.spoofDetected:
        _borderColor = Colors.red;
        _challengeMessage = '';
        _statusMessage = _t('liveness_failed_spoof');
        _isProcessing = false;
        _logSecurityEvent('SPOOF_DETECTED');
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) _resetAndStartOver();
        });
        break;
      case LivenessStatus.timeout:
        _borderColor = Colors.orange;
        _challengeMessage = '';
        _statusMessage = _t('liveness_failed_timeout');
        _isProcessing = false;
        Future.delayed(const Duration(seconds: 2), () {
          // ⚡ 2s بدلاً من 3s
          if (mounted) _resetAndStartOver();
        });
        break;
      case LivenessStatus.failed:
        _borderColor = Colors.red;
        _challengeMessage = '';
        _statusMessage = _t('liveness_failed_generic');
        _isProcessing = false;
        Future.delayed(const Duration(seconds: 2), () {
          // ⚡ 2s بدلاً من 3s
          if (mounted) _resetAndStartOver();
        });
        break;
    }
    // ⚡ إزالة setState(() {}) المكرر هنا → كان يسبب إعادة بناء مرتين لكل حدث
  }

  void _logSecurityEvent(String eventType) {
    if (kDebugMode) {
      print(
          '🔴 SECURITY EVENT [$eventType]: Employee: ${widget.employeeNumber}, '
          'Client: ${widget.clientId}, Time: ${DateTime.now().toIso8601String()}');
    }
  }

  Future<void> _initializeCamera() async {
    if (_shouldSuppressCameraFailureUi) {
      // #region debug-point B:camera-init-skipped
      unawaited(_reportDebugEvent(
        'B',
        'face_verification_screen_mobile.dart:_initializeCamera',
        'Skipped camera initialization because verification is closing or already completed',
        data: {
          'mounted': mounted,
          'completedSuccessfully': _completedSuccessfully,
          'faceMatched': _faceMatched,
          'closeHandled': _closeHandled,
          'isVerifyingOnServer': _isVerifyingOnServer,
          'verificationCaptureCompleted': _verificationCaptureCompleted,
        },
      ));
      // #endregion
      return;
    }

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

      // #region debug-point B:camera-init-success
      unawaited(_reportDebugEvent(
        'B',
        'face_verification_screen_mobile.dart:_initializeCamera',
        'Camera initialized successfully',
        data: {
          'platform': Platform.operatingSystem,
          'cameraName': _controller?.description.name,
          'sensorOrientation': _controller?.description.sensorOrientation,
          'previewSize': _controller?.value.previewSize?.toString(),
        },
      ));
      // #endregion

      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        await _startFrameStreaming();
      }
    } catch (e) {
      if (token != _cameraInitToken) return;
      // #region debug-point B:camera-init-failed
      unawaited(_reportDebugEvent(
        'B',
        'face_verification_screen_mobile.dart:_initializeCamera',
        'Camera initialization failed',
        data: {
          'platform': Platform.operatingSystem,
          'error': e.toString().split('\n').first,
        },
      ));
      // #endregion

      final lower = e.toString().toLowerCase();
      final isTransient = lower.contains('disposed') ||
          lower.contains('not ready') ||
          lower.contains('bad state') ||
          (lower.contains('camera') && lower.contains('closed'));
      final lifecycleOk = _lastLifecycleState == null ||
          _lastLifecycleState == AppLifecycleState.resumed;
      if (mounted &&
          !_shouldSuppressCameraFailureUi &&
          isTransient &&
          lifecycleOk &&
          !_cameraInitRetryScheduled) {
        _cameraInitRetryScheduled = true;
        final friendlyMessage = _lang() == 'ar'
            ? 'جاري إعادة تشغيل الكاميرا...'
            : 'Restarting camera...';
        setState(() {
          _isInitializing = false;
          _statusMessage = friendlyMessage;
        });
        Future.delayed(const Duration(milliseconds: 450), () {
          if (!mounted) return;
          _cameraInitRetryScheduled = false;
          unawaited(_initializeCamera());
        });
        return;
      }

      if (mounted && !_shouldSuppressCameraFailureUi) {
        final friendlyMessage = _friendlyCameraErrorMessage(e);
        setState(() {
          _isInitializing = false;
          _statusMessage = friendlyMessage;
          _instructionMessage = _lang() == 'ar'
              ? 'تم إيقاف المتابعة حتى تتمكن من قراءة سبب المشكلة.'
              : 'The flow has been paused so you can read the error message.';
        });
        _borderColor = Colors.red;
        _showFailureDialog(
          title: _lang() == 'ar' ? 'خطأ في تشغيل الكاميرا' : 'Camera Error',
          message: friendlyMessage,
          rawDetails: e.toString(),
        );
      }
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
            int planesLength,
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
      planesLength: image.planes.length,
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

  Future<void> _processCameraImage(CameraImage image) async {
    // ⚡ نفس الحماية Race Condition للتسجيل (تجنب تعليق الكاميرا):
    // لا نوقف المعالجة عند Status.passed، بل عند اكتمال التقاط الصورة فور نجاح الـ API.
    if (!mounted ||
        _verificationCaptureCompleted ||
        _livenessStatus == LivenessStatus.spoofDetected) {
      return;
    }

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
            'face_verification_screen_mobile.dart:_processCameraImage',
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

      final camera = controller.description;
      final imageRotation = built.rotation;
      final inputImageFormat = built.format;
      final bytesPerRow = built.bytesPerRow;
      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());
      final Uint8List singlePlaneBytes = image.planes.first.bytes;
      final faces = await _faceDetector.processImage(built.inputImage);

      Face? currentFace;
      var faceCount = faces.length;
      if (faceCount == 1) {
        currentFace = faces.first;
        _noFaceGraceStreak = 0;
        // ⚡ تخزين آخر إطار صالح كـ Fallback (مثل التسجيل)
        _lastValidFrameBytes = singlePlaneBytes;
        _lastValidFrameSize = imageSize;
        _lastValidFrameRotation = imageRotation;
        _lastValidFace = currentFace;
      } else if (faceCount == 0 &&
          _lastValidFace != null &&
          _noFaceGraceStreak < 2) {
        _noFaceGraceStreak++;
        currentFace = _lastValidFace;
        faceCount = 1;
      } else {
        _noFaceGraceStreak = 0;
        _lastValidFrameBytes = null;
        _lastValidFrameSize = null;
        _lastValidFrameRotation = null;
        _lastValidFace = null;
      }

      final motion = LivenessDetectionService.computeFrameMotion(
        currentFace: currentFace,
        previousFace: _previousTrackedFace,
      );

      if (faceCount != _lastTelemetryFaceCount || _frameCounter % 45 == 0) {
        _lastTelemetryFaceCount = faceCount;
        // #region debug-point A:stream-face-detection
        unawaited(_reportDebugEvent(
          'A',
          'face_verification_screen_mobile.dart:_processCameraImage',
          'Processed live camera frame for face detection',
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

      final samplePixels = _extractFaceTextureSamples(image, currentFace);
      final noiseVar =
          LivenessDetectionService.computeNoiseVariance(samplePixels);
      final depthPayload = _extractFaceDepthAnalysisPayload(image, currentFace);
      if (depthPayload != null) {
        _livenessService.recordDepthAnalysisFrame(
          pixels: depthPayload['pixels'] as List<int>,
          width: depthPayload['width'] as int,
          height: depthPayload['height'] as int,
          faceCenterRel: const Point<double>(0.5, 0.5),
          faceBoxRelW: 0.80,
          faceBoxRelH: 0.80,
        );
      }

      _livenessService.processFrame(
        face: currentFace,
        overallMotion: motion,
        noiseVariance: noiseVar,
        imageWidth: imageSize.width,
        imageHeight: imageSize.height,
      );

      final guideFit = currentFace == null
          ? (inside: false, score: 0.0)
          : _evaluateGuideFit(currentFace, imageSize);
      if (mounted) {
        _currentFaceCount = faceCount;
        _currentDetectedFace = currentFace;
        _isFaceWithinGuide = faceCount == 1 && guideFit.inside;
        _faceGuideFitScore = faceCount == 1 ? guideFit.score : 0.0;

        bool stableChanged =
            _updateStableGuideState(force: _isVerifyingOnServer);

        bool challengeChanged = false;
        if (_lockedAnalysisSnapshot == null &&
            !_verificationStartRequested &&
            !_isVerifyingOnServer) {
          _analysisSnapshot = _livenessService.currentSnapshot;
          final activeChallenge = _livenessService.currentChallenge;
          final nextChallengeMessage = activeChallenge != null
              ? _describeLivenessChallenge(activeChallenge)
              : _getFacePresenceGuidance(faceCount);
          if (nextChallengeMessage != _lastUiChallengeMessage) {
            _lastUiChallengeMessage = nextChallengeMessage;
            _challengeMessage = nextChallengeMessage;
            challengeChanged = true;
          }
        }

        if (stableChanged || challengeChanged) {
          _requestUiRebuild(force: true);
        } else {
          _requestUiRebuild();
        }
      }
      /*  if (mounted) {
        setState(() {
          _currentFaceCount = faceCount;
          _currentDetectedFace = currentFace;
          _isFaceWithinGuide = faceCount == 1 && guideFit.inside;
          _faceGuideFitScore = faceCount == 1 ? guideFit.score : 0.0;
          if (_lockedAnalysisSnapshot == null &&
              !_verificationStartRequested &&
              !_isVerifyingOnServer) {
            _analysisSnapshot = _livenessService.currentSnapshot;
            _challengeMessage = _getFacePresenceGuidance(faceCount);
          }
        });
      }*/

      _previousTrackedFace = currentFace;
    } catch (e) {
      // Suppress frame processing errors to avoid spam
    }
  }

  Future<void> _captureAndVerifyWithLiveness() async {
    final controller = _controller;
    final bool hasFallbackCapture =
        _lastProactiveCapturedJpg != null && _lastProactiveCapturedFace != null;
    if (!mounted ||
        _isVerifyingOnServer ||
        ((controller == null || !controller.value.isInitialized) &&
            !hasFallbackCapture)) {
      return;
    }

    // 🔍 Diagnostics Performance لتتبع زمن كل مرحلة
    final perfTrace = DateTime.now();
    String phase = 'START';
    int verifyAttempt = 0;
    if (kDebugMode) {
      print('⚡ [VERIFY-PERF] ════════════════════════════════════════');
      print(
          '⚡ [VERIFY-PERF] بدء عملية التحقق | Trace: T${perfTrace.millisecondsSinceEpoch.toRadixString(36)} | Emp=${widget.employeeNumber}');
      print('⚡ [VERIFY-PERF] ════════════════════════════════════════');
    }

    setState(() {
      _isVerifyingOnServer = true;
      _isProcessing = true;
      _statusMessage = _t('verifying_face_features');
    });
    _updateStableGuideState(force: true);
    _requestUiRebuild(force: true);
    // #region debug-point B:capture-enter
    unawaited(_reportDebugEvent(
      'B',
      'face_verification_screen_mobile.dart:_captureAndVerifyWithLiveness',
      'Entered capture and verify',
      data: {
        'controllerInitialized': _controller?.value.isInitialized ?? false,
        'isStreamingImages': _controller?.value.isStreamingImages ?? false,
        'hasFallbackCapture': hasFallbackCapture,
        'livenessStatus': _livenessStatus.name,
      },
    ));
    // #endregion

    Timer? watchdog;
    Uint8List? finalImageBytes;
    Face? finalFace;
    String? failReason;

    watchdog = Timer(const Duration(seconds: 55), () {
      if (!mounted) return;
      if (_closeHandled || _faceMatched || _completedSuccessfully) return;
      if (_isVerifyingOnServer) {
        _handleFailure(
          _lang() == 'ar'
              ? 'تأخر التحقق من الوجه أكثر من اللازم. تحقق من اتصال الإنترنت والخادم ثم أعد المحاولة.'
              : 'Face verification is taking too long. Check connectivity and the server, then try again.',
        );
      }
    });

    try {
      if (_currentFaceCount <= 0) {
        _handleFailure(
          _lang() == 'ar'
              ? 'لم يتم اكتشاف وجه، يرجى الوقوف أمام الكاميرا بشكل صحيح داخل الإطار.'
              : 'No face detected. Please stand correctly in front of the camera.',
        );
        return;
      }
      if (_currentFaceCount > 1) {
        _handleFailure(
          _lang() == 'ar'
              ? 'تم اكتشاف أكثر من وجه في الإطار. يجب أن يظهر وجه موظف واحد فقط قبل التحقق.'
              : 'More than one face detected. Only one face is allowed before verification.',
        );
        return;
      }

      // 🔍 المرحلة 1: فحص نتيجة Liveness
      phase = 'CHECK_LIVENESS';
      final livenessResult = _livenessService.getFinalResult();
      // #region debug-point A:liveness-final-result
      unawaited(_reportDebugEvent(
        'A',
        'face_verification_screen_mobile.dart:_captureAndVerifyWithLiveness:liveness-result',
        'Client finalized passive liveness result before server verification',
        data: {
          'status': livenessResult.status.name,
          'passed': livenessResult.passed,
          'message': livenessResult.message,
          'livenessScore': livenessResult.livenessScore,
          'spoofRisk': livenessResult.spoofRisk,
          'passedChecks': livenessResult.passedChecks,
          'failedChecks': livenessResult.failedChecks,
          'completedChallengeCount': _livenessService.completedChallengeCount,
          'requiredChallengeCount': _livenessService.requiredChallenges,
          'completedChallengeTypes':
              _livenessService.completedChallenges.map((c) => c.name).toList(),
          'sessionDurationSec':
              DateTime.now().difference(_sessionStartTime).inSeconds,
          'trackingScore': _displaySnapshot.trackingScore,
          'poseScore': _displaySnapshot.poseScore,
          'eyeActivityScore': _displaySnapshot.eyeActivityScore,
          'breathingScore': _displaySnapshot.breathingScore,
          'textureScore': _displaySnapshot.textureScore,
          'landmarkScore': _displaySnapshot.landmarkScore,
          'antiSpoofScore': _displaySnapshot.antiSpoofScore,
          'overallScore': _displaySnapshot.overallScore,
          'completedSignals': _displaySnapshot.completedSignals,
          'requiredSignals': _displaySnapshot.requiredSignals,
        },
      ));
      // #endregion
      if (!livenessResult.passed) {
        if (kDebugMode)
          print(
              '⚡ [VERIFY-PERF] ❌ نتيجة Liveness غير صالحة رغم الحالة passed (تناقض داخلي)');
        // #region debug-point A:liveness-blocked-locally
        unawaited(_reportDebugEvent(
          'A',
          'face_verification_screen_mobile.dart:_captureAndVerifyWithLiveness:liveness-blocked',
          'Client blocked verification because passive liveness failed locally',
          data: {
            'status': livenessResult.status.name,
            'message': livenessResult.message,
            'livenessScore': livenessResult.livenessScore,
            'spoofRisk': livenessResult.spoofRisk,
            'passedChecks': livenessResult.passedChecks,
            'failedChecks': livenessResult.failedChecks,
          },
        ));
        // #endregion
        _handleLivenessResultFailure(livenessResult);
        return;
      }
      final t1 = DateTime.now().difference(perfTrace).inMilliseconds;
      if (kDebugMode)
        print(
            '⚡ [VERIFY-PERF] (${t1}ms) PHASE 1 OK: Liveness ناجحة | score=${livenessResult.livenessScore.toStringAsFixed(2)} | passed=${livenessResult.passedChecks.length}');

      // 🔍 المرحلة 2: التقاط الصورة أو Fallback بشكل متوافق مع iPhone/Android.
      // على iPhone نفضل JPEG الاستباقية أولاً لأنها أكثر استقراراً من إيقاف البث ثم takePicture.
      // ولا نرسل RAW frames إلى الخادم لأنها ليست صورة JPEG/PNG فعلية وقد تفشل المطابقة.
      phase = 'CAPTURE_IMAGE';
      String fallbackUsed = 'NONE';
      try {
        if (Platform.isIOS) {
          await _prepareIosStillImageBeforeVerify();
          await _ensureFreshIosProactiveCapture();
        }
        if (Platform.isIOS &&
            _lastProactiveCapturedJpg != null &&
            _lastProactiveCapturedFace != null) {
          finalImageBytes = _lastProactiveCapturedJpg!;
          finalFace = _lastProactiveCapturedFace!;
          fallbackUsed = 'IOS_PROACTIVE_JPG_PRIMARY';
          if (kDebugMode) {
            print(
                '⚡ [VERIFY-PERF] استخدام JPEG استباقية كأساس على iPhone (${finalImageBytes!.length ~/ 1024}KB)');
          }
        } else if ((controller == null || !controller.value.isInitialized) &&
            hasFallbackCapture) {
          finalImageBytes = _lastProactiveCapturedJpg!;
          finalFace = _lastProactiveCapturedFace!;
          fallbackUsed = 'PROACTIVE_JPG_RECOVERY';
          if (kDebugMode) {
            print(
                '⚡ [VERIFY-PERF] الكاميرا لم تعد جاهزة لكن لدينا JPEG صالحة → متابعة التحقق بدون إعادة تهيئة الكاميرا');
          }
        } else {
          final swCap = Stopwatch()..start();
          final activeController = _controller;
          if (activeController == null ||
              !activeController.value.isInitialized) {
            throw StateError(_lang() == 'ar'
                ? 'تم فقدان اتصال الكاميرا أثناء التحقق. أعد فتح شاشة التحقق.'
                : 'Camera connection was lost during verification. Reopen the verification screen.');
          }
          if (activeController.value.isStreamingImages) {
            await activeController.stopImageStream();
            _streamPausedForStillCapture = true;
          }
          // #region debug-point B:take-picture-before
          unawaited(_reportDebugEvent(
            'B',
            'face_verification_screen_mobile.dart:takePicture-before',
            'Calling takePicture',
            data: {
              'isStreamingImages':
                  _controller?.value.isStreamingImages ?? false,
              'fallbackJpgExists': _lastProactiveCapturedJpg != null,
              'fallbackRawExists': _lastValidFrameBytes != null,
            },
          ));
          // #endregion
          final XFile rawImage = await activeController.takePicture().timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              failReason = 'TIMEOUT_TAKEPICTURE_8S';
              throw TimeoutException(
                  'مهلة التقاط الصورة انتهت (8 ثوانٍ) — سنستخدم آخر صورة JPG محفوظة.');
            },
          );
          final t2a = swCap.elapsedMilliseconds;
          final bytesXFile = await File(rawImage.path)
              .readAsBytes()
              .timeout(const Duration(seconds: 4));
          final t2b = swCap.elapsedMilliseconds;
          final inputImage = InputImage.fromFilePath(rawImage.path);
          final faces = await _faceDetector
              .processImage(inputImage)
              .timeout(const Duration(seconds: 6));
          final t2c = swCap.elapsedMilliseconds;

          if (faces.length == 1) {
            finalImageBytes = bytesXFile;
            finalFace = faces.first;
            fallbackUsed = 'DIRECT';
            if (kDebugMode)
              print(
                  '⚡ [VERIFY-PERF] (${t2c}ms) PHASE 2A OK: takePicture() مباشر + وجه موجود ✅');
            // #region debug-point B:take-picture-success
            unawaited(_reportDebugEvent(
              'B',
              'face_verification_screen_mobile.dart:takePicture-success',
              'Direct takePicture succeeded',
              data: {
                'elapsedMs': t2c,
                'imageKb': finalImageBytes!.length ~/ 1024,
                'faceCount': faces.length,
              },
            ));
            // #endregion
          } else if (faces.length > 1) {
            failReason = 'MULTI_FACE_IN_CAPTURED';
            throw StateError(_lang() == 'ar'
                ? 'تم اكتشاف أكثر من وجه في الصورة. يرجى أن يظهر وجه موظف واحد فقط.'
                : 'More than one face detected in the captured image.');
          } else if (Platform.isIOS &&
              (_currentDetectedFace != null || _lastValidFace != null)) {
            finalImageBytes = bytesXFile;
            finalFace = _currentDetectedFace ?? _lastValidFace!;
            fallbackUsed = 'IOS_LIVE_FACE_FALLBACK';
            if (kDebugMode) {
              print(
                  '⚡ [VERIFY-PERF] (${t2c}ms) PHASE 2A OK: iPhone fallback → استخدام وجه البث المباشر مع الصورة الثابتة ✅');
            }
          } else {
            failReason = 'NO_FACE_IN_CAPTURED';
            throw StateError(_lang() == 'ar'
                ? 'لم يتم اكتشاف وجه في الصورة الملتقطة. يرجى الوقوف أمام الكاميرا بشكل صحيح.'
                : 'No face detected in the captured image.');
          }
        }
      } on StateError {
        rethrow;
      } catch (capErr) {
        if (kDebugMode)
          print(
              '⚡ [VERIFY-PERF] ⚠️ المرحلة 2A فشلت ($failReason): $capErr → البحث عن Fallback...');
        // #region debug-point B:take-picture-failed
        unawaited(_reportDebugEvent(
          'B',
          'face_verification_screen_mobile.dart:takePicture-failed',
          'Direct capture failed, moving to fallback',
          data: {
            'failReason': failReason,
            'error': capErr.toString().split('\n').first,
            'fallbackJpgExists': _lastProactiveCapturedJpg != null,
            'fallbackRawExists': _lastValidFrameBytes != null,
          },
        ));
        // #endregion
        // ⚡ Fallback 1: صورة JPG استباقية (الأفضل أماناً)
        if (_lastProactiveCapturedJpg != null &&
            _lastProactiveCapturedFace != null) {
          final t2fb1 = DateTime.now().difference(perfTrace).inMilliseconds;
          finalImageBytes = _lastProactiveCapturedJpg!;
          finalFace = _lastProactiveCapturedFace!;
          fallbackUsed = 'PROACTIVE_JPG';
          if (kDebugMode)
            print(
                '⚡ [VERIFY-PERF] (${t2fb1}ms) PHASE 2B OK: Fallback 1 → صورة JPG استباقية (حجم=${finalImageBytes!.length ~/ 1024}KB) ✅');
        } else {
          throw StateError(_lang() == 'ar'
              ? 'تعذر الحصول على صورة وجه صالحة من الكاميرا. أعد المحاولة مع إبقاء الوجه ثابتاً داخل الإطار.'
              : 'Unable to obtain a valid face image from the camera. Try again while keeping your face steady inside the frame.');
        }
      }
      if (finalImageBytes == null || finalFace == null)
        throw Exception('فشل الحصول على صورة وجه صالحة.');

      // 🔍 المرحلة 3: فحص زوايا الرأس والعيون
      phase = 'VALIDATE_POSE';
      double headY = finalFace!.headEulerAngleY ?? 0;
      double headX = finalFace!.headEulerAngleX ?? 0;
      if (headY.abs() > 30 || headX.abs() > 30) {
        throw StateError(_t('look_straight_no_tilt'));
      }
      if (finalFace!.leftEyeOpenProbability != null &&
          finalFace!.leftEyeOpenProbability! < 0.12) {
        throw StateError(_t('open_eyes_clearly'));
      }
      final t3 = DateTime.now().difference(perfTrace).inMilliseconds;
      if (kDebugMode)
        print(
            '⚡ [VERIFY-PERF] (${t3}ms) PHASE 3 OK: زوايا الرأس والعيون صالحة | headY=${headY.toStringAsFixed(1)}° headX=${headX.toStringAsFixed(1)}°');

      // 🔍 المرحلة 4: Base64 + Metadata (إصلاح sessionDuration + معلومات Fallback)
      phase = 'BASE64_ENCODE';
      final uploadBytes = await _prepareImageBytesForServerUpload(
        finalImageBytes!,
        purpose: 'verification',
      );
      final base64Image = base64Encode(uploadBytes);
      final snapshotForVerification = _displaySnapshot;
      final livenessMetadata = {
        'livenessScore': livenessResult.livenessScore,
        'spoofRisk': livenessResult.spoofRisk,
        'sessionDurationSec':
            DateTime.now().difference(_sessionStartTime).inSeconds,
        'imageSource': fallbackUsed,
        'activeChallenge': {
          'requiredCount': _livenessService.requiredChallenges,
          'completedCount': _livenessService.completedChallengeCount,
        },
        'passiveAnalysis': {
          'trackingScore': snapshotForVerification.trackingScore,
          'poseScore': snapshotForVerification.poseScore,
          'eyeActivityScore': snapshotForVerification.eyeActivityScore,
          'breathingScore': snapshotForVerification.breathingScore,
          'textureScore': snapshotForVerification.textureScore,
          'landmarkScore': snapshotForVerification.landmarkScore,
          'antiSpoofScore': snapshotForVerification.antiSpoofScore,
          'overallScore': snapshotForVerification.overallScore,
          'completedSignals': snapshotForVerification.completedSignals,
          'requiredSignals': snapshotForVerification.requiredSignals,
        },
      };
      final t4 = DateTime.now().difference(perfTrace).inMilliseconds;
      if (kDebugMode) {
        print(
            '⚡ [VERIFY-PERF] (${t4}ms) PHASE 4 OK: Base64 + Metadata | حجم الصورة المرفوعة=${uploadBytes.length ~/ 1024}KB');
      }
      // #region debug-point A:verification-payload
      unawaited(_reportDebugEvent(
        'A',
        'face_verification_screen_mobile.dart:_captureAndVerifyWithLiveness',
        'Prepared verification payload for server',
        data: {
          'platform': Platform.operatingSystem,
          'imageSource': fallbackUsed,
          'capturedFallbackUsed': fallbackUsed != 'DIRECT',
          'captureImageKb': finalImageBytes!.length ~/ 1024,
          'uploadImageKb': uploadBytes.length ~/ 1024,
          'headY': headY,
          'headX': headX,
          'livenessScore': livenessResult.livenessScore,
          'completedSignals': snapshotForVerification.completedSignals,
          'requiredSignals': snapshotForVerification.requiredSignals,
        },
      ));
      // #endregion

      // 🔍 المرحلة 5: إرسال التحقق للخادم
      phase = 'VERIFY_API_SEND';
      const maxAttempts = 1;
      Map<String, dynamic>? finalResult;
      String? lastApiErr;

      for (verifyAttempt = 1; verifyAttempt <= maxAttempts; verifyAttempt++) {
        try {
          if (kDebugMode)
            print(
                '⚡ [VERIFY-PERF] 🔄 محاولة التحقق $verifyAttempt/$maxAttempts (NEW FLOW: مطابقة مع الصورة المخزنة في Users_Employees)...');
          final swApi = Stopwatch()..start();
          // 🆕 استخدام الـ API الجديد: verifyFaceWithStoredImage → يقوم بالآتي على السيرفر:
          //    1. سحب صورة الوجه المحفوظة من جدول Users_Employees
          //    2. مطابقة الوجه الملتقط حالياً (مع نتيجة Liveness) مع الصورة المحفوظة
          //    3. إرجاع Match/NoMatch + درجة التشابه
          final r = await FaceApiService.verifyFaceWithStoredImage(
            clientId: widget.clientId,
            employeeNumber: widget.employeeNumber,
            imageBase64: base64Image,
            deviceInfo: jsonEncode(livenessMetadata),
            livenessScore: livenessResult.livenessScore,
            challengesCompleted: _livenessService.completedChallengeCount,
            spoofRisk: livenessResult.spoofRisk,
            timeout: const Duration(seconds: 25),
          );
          final t5sub = swApi.elapsedMilliseconds;
          finalResult = r;
          // #region debug-point E:verify-api-result
          unawaited(_reportDebugEvent(
            'E',
            'face_verification_screen_mobile.dart:verify-api-result',
            'Verify API returned response',
            data: {
              'attempt': verifyAttempt,
              'elapsedMs': t5sub,
              'success': _isVerifiedMatchResult(r),
              'message': r['Message']?.toString(),
              'statusCode': r['StatusCode'] ?? r['statusCode'],
              'isMatch': r['IsMatch'] ?? r['Matched'],
              'confidenceScore': r['ConfidenceScore'],
            },
          ));
          // #endregion
          if (_isVerifiedMatchResult(r)) {
            if (kDebugMode)
              print(
                  '⚡ [VERIFY-PERF] (${t5sub}ms) PHASE 5 OK: نجح التحقق في المحاولة $verifyAttempt');
            lastApiErr = null;
            break;
          } else {
            lastApiErr = r['Message'] ?? 'فشل التحقق غير معروف';
            if (kDebugMode)
              print(
                  '⚡ [VERIFY-PERF] ⚠️ رفض السيرفر محاولة $verifyAttempt: $lastApiErr');
            // ⚡ إصلاح منطق التوقف: توسيع القائمة (نفس منطق التسجيل)
            final errLower = lastApiErr!.toLowerCase();
            final logicalStopKeywords = [
              'غير موجود',
              'غير مفعل',
              'الموظف',
              'بصمة',
              'مسجلة',
              'face template',
              'غير واضح',
              'quality',
              'جودة',
              'لا يوجد وجه',
              'no face',
              'detect',
              'لا تتطابق',
              'mismatch',
              'not match',
              'غير مصرح',
              'unauthorized',
              'permission',
              'القاعدة',
              'database',
              'duplicate',
              'invalid',
              'خطأ في',
              'الرجاء',
              'محظور',
              'blocked',
              'suspended',
            ];
            bool shouldStop = logicalStopKeywords.any((k) =>
                lastApiErr!.contains(k) || errLower.contains(k.toLowerCase()));
            if (shouldStop) {
              if (kDebugMode)
                print('⚡ [VERIFY-PERF] 🛑 توقف Retry (خطأ منطقي): $lastApiErr');
              break;
            }
          }
        } catch (apiErr) {
          lastApiErr = apiErr.toString();
          if (kDebugMode)
            print(
                '⚡ [VERIFY-PERF] ❌ استثناء محاولة $verifyAttempt: $lastApiErr');
        }
        if (verifyAttempt < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 600 * verifyAttempt));
        }
      }

      // 🔍 المرحلة 6: الفحص النهائي + إغلاق الشاشة
      phase = 'FINALIZE';
      _verificationCaptureCompleted = true; // ⚡ الآن فقط نوقف معالجة الإطارات

      // Diagnostics كامل للرد (حافظ على التشخيص الأصلي!)
      if (kDebugMode && finalResult != null) {
        print('🔎 DIAGNOSTIC VerifyFace API Response:');
        print(
            '   • Keys = ${finalResult is Map ? finalResult.keys.toList() : "Not a Map: ${finalResult.runtimeType}"}');
        if (finalResult is Map) {
          finalResult.forEach(
              (k, v) => print('   • [$k] => ${v.runtimeType.toString()}: $v'));
        }
        print(
            '   • _isVerifiedMatchResult(result) = ${_isVerifiedMatchResult(finalResult)}');
      }

      if (finalResult != null && _isVerifiedMatchResult(finalResult)) {
        // الفائقة الأهمية: العلم العالمي أولاً!
        FaceApiService.markLastFaceSessionSuccessful(
          employeeNumber: widget.employeeNumber,
          sessionKind: 'verification',
        );
        _completedSuccessfully = true;
        _faceMatched = true;
        final verificationNow = DateTime.now();
        _successfulVerificationPayload = {
          'Verified': true,
          'VerificationAtUtc': verificationNow.toUtc().toIso8601String(),
          'VerificationCapturedAtMs': verificationNow.millisecondsSinceEpoch,
          'ConfidenceScore':
              (finalResult!['ConfidenceScore'] as num?)?.toDouble(),
          'LivenessScore': (finalResult!['LivenessScore'] as num?)?.toDouble(),
          'ServerMessage': finalResult!['Message']?.toString(),
          'VerificationContext': 'ATTENDANCE_CHECKPOINT',
        };
        final totalMs = DateTime.now().difference(perfTrace).inMilliseconds;
        if (kDebugMode) {
          final isMatch = (finalResult!['IsMatch'] == true) ||
              (finalResult!['Matched'] == true) ||
              (finalResult!['Success'] == true);
          print('✅ DIAGNOSTIC [VERIFY-SUCCESS] ═══════════════════');
          print(
              '✅  الإجمالي: ${totalMs}ms | المحاولات: $verifyAttempt/$maxAttempts | Match=$isMatch');
          print('✅  رسالة السيرفر: ${finalResult!['Message'] ?? '---'}');
          print(
              '✅  سيتم الإرجاع الآن فوراً عبر _smartClose + Global Flag مُفعّل.');
          print('✅ DIAGNOSTIC [VERIFY-SUCCESS] ═══════════════════');
        }
        if (mounted) {
          // #region debug-point C:verification-success
          unawaited(_reportDebugEvent(
            'C',
            'face_verification_screen_mobile.dart:_captureAndVerifyWithLiveness',
            'Verification flow finished successfully',
            data: {
              'platform': Platform.operatingSystem,
              'confidenceScore': finalResult!['ConfidenceScore'],
              'livenessScore': finalResult!['LivenessScore'],
              'serverMessage': finalResult!['Message']?.toString(),
              'reason': 'verify-success',
            },
          ));
          // #endregion
          setState(() {
            _borderColor = Colors.green;
            _statusMessage = _t('verification_success');
            _instructionMessage = _t('identity_matched');
            _isProcessing = false;
            _isVerifyingOnServer = false;
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            try {
              if (mounted)
                _smartClose(reason: 'verify-success', forceSuccess: true);
            } catch (e) {
              if (kDebugMode)
                print(
                    '⚠️ فشل _smartClose في التحقق (سنعتمد على Global Flag): $e');
            }
          });
        }
      } else {
        final anomaly = _detectVerificationResultAnomaly(finalResult);
        final msg = anomaly ??
            _friendlyVerificationFailureMessage(
              lastApiErr ?? _t('verification_failed'),
              rawDetails: finalResult?['Message']?.toString(),
              phase: phase,
            );
        // #region debug-point E:verification-failed-final
        unawaited(_reportDebugEvent(
          'E',
          'face_verification_screen_mobile.dart:_captureAndVerifyWithLiveness',
          'Verification flow ended without accepted match',
          data: {
            'platform': Platform.operatingSystem,
            'lastApiError': lastApiErr,
            'finalResultType': finalResult.runtimeType.toString(),
            'finalResultValue': finalResult?.toString(),
            'verifyAttempt': verifyAttempt,
          },
        ));
        // #endregion
        if (kDebugMode) {
          print(
              '❌ [VERIFY-PERF] فشل نهائي بعد $maxAttempts محاولات. السبب الأخير: $msg');
          print('❌ [VERIFY-PERF] آخر مرحلة ناجحة قبل الفشل: $phase');
        }
        _handleFailure(
          msg,
          rawDetails: finalResult?['Message']?.toString(),
        );
      }
    } catch (e, stack) {
      if (kDebugMode) {
        final msTotal = DateTime.now().difference(perfTrace).inMilliseconds;
        print(
            '❌❌❌ [VERIFY-PERF] استثناء فادح (${msTotal}ms) | آخر مرحلة ناجحة: $phase | المحاولة $verifyAttempt');
        print('❌❌❌ [VERIFY-PERF] الخطأ: $e');
        print('❌❌❌ [VERIFY-PERF] Stack: $stack');
      }
      _verificationCaptureCompleted = false;
      _verificationStartRequested = false;
      if (e is TimeoutException) {
        _handleFailure(
          _lang() == 'ar'
              ? 'استغرق الخادم وقتاً أطول من المتوقع أثناء التحقق من الوجه. تأكد أن خدمة التعرف على الوجه وواجهة الـ API تعملان ثم أعد المحاولة.'
              : 'The server took too long while verifying the face. Make sure the face engine and API are running, then try again.',
          rawDetails: e.toString(),
        );
      } else if (e is StateError) {
        _handleFailure(
          _friendlyVerificationFailureMessage(
            e.message,
            rawDetails: e.toString(),
            phase: phase,
          ),
          rawDetails: e.toString(),
        );
      } else {
        _handleFailure(
          _friendlyVerificationFailureMessage(
            _tParams(
              'connection_error_with_error',
              {'error': e.toString().split('\n').first},
            ),
            rawDetails: e.toString(),
            phase: phase,
          ),
          rawDetails: e.toString(),
        );
      }
    } finally {
      watchdog?.cancel();
    }
  }

  /// ⚡ حماية جديدة: Retry Mechanism لبدء عملية التحقق بعد Status.passed.
  /// تحاول استدعاء _captureAndVerifyWithLiveness عدة مرات إذا فشلت الشروط الأولية،
  /// حتى نتجنب تعليق الشاشة في حالة "2 من 2" للأبد بسبب Race Condition نادر.
  Future<void> _tryStartVerificationWithRetry({
    required int maxAttempts,
    required int delayMs,
  }) async {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      if (!mounted) return;
      final controller = _controller;
      final bool hasFallbackCapture = _lastProactiveCapturedJpg != null &&
          _lastProactiveCapturedFace != null;
      final String reason1 =
          _isVerifyingOnServer ? "_isVerifyingOnServer=true" : "✓";
      final String reason2 = controller == null ? "controller=NULL" : "✓";
      final String reason3 =
          (controller != null && !controller.value.isInitialized)
              ? "controller not init"
              : "✓";
      final String reason4 =
          hasFallbackCapture ? "fallback-ready" : "no-fallback";
      final String reasonsFailed = [reason1, reason2, reason3, reason4]
          .where((e) => e != "✓" && e != "fallback-ready")
          .join(", ");
      if (kDebugMode) {
        print(
            '🔄 [VERIFY-START] محاولة $attempt/$maxAttempts: الفشل المحتمل=[$reasonsFailed]');
      }
      // #region debug-point A:start-retry-attempt
      unawaited(_reportDebugEvent(
        'A',
        'face_verification_screen_mobile.dart:_tryStartVerificationWithRetry',
        'Verification start retry tick',
        data: {
          'attempt': attempt,
          'maxAttempts': maxAttempts,
          'reasonsFailed': reasonsFailed,
          'hasFallbackCapture': hasFallbackCapture,
          'isVerifyingOnServer': _isVerifyingOnServer,
          'controllerInitialized': _controller?.value.isInitialized ?? false,
          'isStreamingImages': _controller?.value.isStreamingImages ?? false,
        },
      ));
      // #endregion

      // 🚨 تم إزالة _isProcessing من الشروط (تناقض قاتل مع Status.passed!)
      if (!_isVerifyingOnServer &&
          ((controller != null && controller.value.isInitialized) ||
              hasFallbackCapture)) {
        if (kDebugMode)
          print(
              '🔄 [VERIFY-START-$attempt] ✅ جميع الشروط مستوفاة → بدء التحقق فوراً');
        // #region debug-point A:start-retry-success
        unawaited(_reportDebugEvent(
          'A',
          'face_verification_screen_mobile.dart:_tryStartVerificationWithRetry',
          'Verification start conditions satisfied',
          data: {
            'attempt': attempt,
          },
        ));
        // #endregion
        await _captureAndVerifyWithLiveness();
        return;
      }

      if (kDebugMode) {
        print(
            '🔄 [VERIFY-START-$attempt] ⚠️ فشلت الشروط: [$reasonsFailed] → انتظار ${delayMs}ms ثم إعادة المحاولة');
      }
      await Future.delayed(Duration(milliseconds: delayMs));
    }
    if (kDebugMode) {
      print(
          '❌ [VERIFY-START] ❌ فشلت جميع $maxAttempts محاولات بدء التحقق → إعادة البدء من الصفر مع رسالة خطأ...');
    }
    if (mounted) {
      // #region debug-point A:start-retry-exhausted
      unawaited(_reportDebugEvent(
        'A',
        'face_verification_screen_mobile.dart:_tryStartVerificationWithRetry',
        'Verification start retries exhausted',
        data: {
          'maxAttempts': maxAttempts,
          'isVerifyingOnServer': _isVerifyingOnServer,
          'controllerExists': _controller != null,
          'controllerInitialized': _controller?.value.isInitialized ?? false,
          'fallbackCaptureExists': _lastProactiveCapturedJpg != null &&
              _lastProactiveCapturedFace != null,
        },
      ));
      // #endregion
      setState(() {
        _statusMessage =
            'تعطل بدء عملية التحقق من البصمة. تم إعادة بدء الفحص تلقائياً...';
        _borderColor = Colors.redAccent;
        _isProcessing = false;
        _isVerifyingOnServer = false;
      });
      _verificationStartRequested = false;
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) _resetAndStartOver();
      });
    }
  }

  void _handleLivenessResultFailure(LivenessResult result) {
    setState(() {
      _isProcessing = false;
      _isVerifyingOnServer = false;
      _borderColor = Colors.red;
      _statusMessage = result.message ?? _t('liveness_failed_generic');
      _instructionMessage = _t('try_again');
    });
    _verificationStartRequested = false;
    _logSecurityEvent('LIVENESS_FAIL_${result.status.name}');
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_faceMatched) _resetAndStartOver();
    });
  }

  void _handleFailure(String message, {String? rawDetails}) {
    if (!mounted) return;
    // #region debug-point D:handle-failure
    unawaited(_reportDebugEvent(
      'D',
      'face_verification_screen_mobile.dart:_handleFailure',
      'Verification flow entered failure state',
      data: {
        'message': message,
        'currentFaceCount': _currentFaceCount,
        'livenessStatus': _livenessStatus.name,
        'isVerifyingOnServer': _isVerifyingOnServer,
        'verificationCaptureCompleted': _verificationCaptureCompleted,
      },
    ));
    // #endregion
    setState(() {
      _borderColor = Colors.red;
      _statusMessage = _buildFailureStatusSummary(message);
      _instructionMessage = _t('try_again');
      _isProcessing = false;
      _isVerifyingOnServer = false;
    });
    _verificationStartRequested = false;
    _showFailureDialog(
      title:
          _lang() == 'ar' ? 'فشل التحقق من الوجه' : 'Face Verification Failed',
      message: message,
      rawDetails: rawDetails,
    );
  }

  String _buildFailureStatusSummary(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('فحص الحيوية') ||
        lower.contains('spoof') ||
        lower.contains('screen') ||
        lower.contains('video')) {
      return _lang() == 'ar'
          ? 'فشل فحص الحيوية. استخدم الوجه الحقيقي مباشرة أمام الكاميرا.'
          : 'Liveness failed. Use a real face directly in front of the camera.';
    }
    if (lower.contains('نسيج الوجه') || lower.contains('texture')) {
      return _lang() == 'ar'
          ? 'فشل فحص نسيج الوجه. تجنب الصور والشاشات.'
          : 'Face texture validation failed. Avoid photos and screens.';
    }
    if (lower.contains('زمن الفحص') || lower.contains('session duration')) {
      return _lang() == 'ar'
          ? 'مدة الفحص غير كافية. ابق ثابتاً لثوانٍ إضافية.'
          : 'Scan duration was insufficient. Stay steady a little longer.';
    }
    if (lower.contains('حركة العين') ||
        lower.contains('الرمش') ||
        lower.contains('eye')) {
      return _lang() == 'ar'
          ? 'لم يكتمل فحص العين والرمش بشكل كافٍ.'
          : 'Eye activity validation did not complete sufficiently.';
    }
    return _lang() == 'ar'
        ? 'فشل التحقق من الوجه.'
        : 'Face verification failed.';
  }

  void _resetAndStartOver() {
    if (!mounted) return;
    // #region debug-point C:reset-start-over
    unawaited(_reportDebugEvent(
      'C',
      'face_verification_screen_mobile.dart:_resetAndStartOver',
      'Resetting verification flow to initial state',
      data: {
        'faceMatched': _faceMatched,
        'currentFaceCount': _currentFaceCount,
        'verificationCaptureCompleted': _verificationCaptureCompleted,
        'verificationStartRequested': _verificationStartRequested,
      },
    ));
    // #endregion
    setState(() {
      _isProcessing = false;
      _isVerifyingOnServer = false;
      _lastProactiveCapturedJpg = null;
      _lastProactiveCapturedFace = null;
      _lastProactiveCapturedAt = null;
      _previousTrackedFace = null;
      _frameCounter = 0;
      _verificationCaptureCompleted =
          false; // ⚡ إعادة تفعيل معالجة الإطارات عند إعادة البدء
      _verificationStartRequested = false;
      _closeHandled = false;
      _successfulVerificationPayload = null;
      _lockedAnalysisSnapshot = null;
      _currentDetectedFace = null;
      _currentFaceCount = 0;
      _isFaceWithinGuide = false;
      _faceGuideFitScore = 0.0;
      _analysisSnapshot = const PassiveLivenessSnapshot.empty();
    });
    _livenessService.initialize();
    if (_controller == null && mounted && !_completedSuccessfully) {
      unawaited(_initializeCamera());
    } else {
      unawaited(_resumeImageStreamIfNeeded());
    }
  }

  Future<void> _resetFace() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = _t('resetting_face');
    });

    try {
      final result = await FaceApiService.resetFace(
          widget.clientId, widget.employeeNumber);
      if (result['Success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_t('face_reset_success'))),
          );
          Navigator.pop(context, false);
        }
      } else {
        _handleFailure(result['Message'] ?? _t('face_reset_failed'));
      }
    } catch (e) {
      _handleFailure(_tParams('error_with_error', {'error': e.toString()}));
    }
  }

  Widget _buildMetricChip(String label, double value, {required bool passed}) {
    final normalized = value.clamp(0.0, 1.0);
    final Color chipColor = passed
        ? Colors.greenAccent
        : normalized >= 0.5
            ? Colors.orangeAccent
            : Colors.redAccent;
    final Color chipBackground = passed
        ? const Color(0xFF14532D) // أخضر داكن
        : normalized >= 0.5
            ? const Color(0xFF7C2D12) // برتقالي داكن
            : const Color(0xFF7F1D1D); // أحمر داكن
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: chipColor.withOpacity(0.65)),
        boxShadow: [
          BoxShadow(
            color: chipColor.withOpacity(0.10),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        '${passed ? "✓ " : ""}$label ${(normalized * 100).round()}%',
        style: const TextStyle(
          color: Colors.white, // النص أبيض ثابت بدل chipColor
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

/*
  Widget _buildMetricChip(String label, double value, {required bool passed}) {
    final normalized = value.clamp(0.0, 1.0);
    final Color chipColor = passed
        ? Colors.greenAccent
        : normalized >= 0.5
            ? Colors.orangeAccent
            : Colors.redAccent;
    final Color chipBackground = passed
        ? Colors.greenAccent.withOpacity(0.14)
        : normalized >= 0.5
            ? Colors.orangeAccent.withOpacity(0.16)
            : Colors.redAccent.withOpacity(0.14);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: chipColor.withOpacity(0.65)),
        boxShadow: [
          BoxShadow(
            color: chipColor.withOpacity(0.10),
            blurRadius: 8,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Text(
        '${passed ? "✓ " : ""}$label ${(normalized * 100).round()}%',
        style: TextStyle(
          color: chipColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
*/
  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      final accent = const Color(0xFF7C3AED);
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 6,
                left: 4,
                child: IconButton(
                  onPressed: _smartClose,
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 16),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          color: accent,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _t('preparing'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _lang() == 'ar'
                            ? 'جاري تجهيز الكاميرا للتعرف على الوجه...'
                            : 'Preparing camera for face verification...',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          unawaited(_initializeCamera());
                        },
                        child: Text(
                          _t('retry'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final previewSize = _controller?.value.previewSize;
    final displaySnapshot = _displaySnapshot;
    final guideAccent = _guideAccentColor;
    final effectiveBorderColor = _faceMatched ? Colors.green : guideAccent;
    final safeTop = MediaQuery.of(context).padding.top;
    final procedureInfo = _currentProcedureInfo();
    final challengeUi = _currentChallengeUi();
    final challengeMessage = (challengeUi['message'] as String?) ?? '';
    final isLiveChallenge = challengeUi['isChallenge'] == true;
    final challengesDone = _livenessService.completedChallengeCount;
    final challengesRequired = _livenessService.requiredChallenges;
    final challengeProgress = _tParams(
      'face_challenge_progress',
      {
        'done': challengesDone.toString(),
        'required': challengesRequired.toString(),
      },
    );

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _smartClose();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final controller = _controller;
                    if (controller == null || !controller.value.isInitialized) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          const ColoredBox(color: Colors.black),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _FaceGuidePainter(
                                faceDetected: false,
                                readiness: 0,
                                color: effectiveBorderColor,
                                fitScore: _faceGuideFitScore,
                                state: _guideVisualState,
                              ),
                            ),
                          ),
                          Center(
                            child: CircularProgressIndicator(
                              color: effectiveBorderColor == Colors.red
                                  ? Colors.orange
                                  : effectiveBorderColor,
                            ),
                          ),
                        ],
                      );
                    }
                    final screenAspect =
                        constraints.maxWidth / constraints.maxHeight;
                    final cameraAspect = previewSize == null
                        ? controller.value.aspectRatio
                        : previewSize.height / previewSize.width;

                    double scale = cameraAspect / screenAspect;
                    if (scale < 1) scale = 1 / scale;

                    return Transform.scale(
                      scale: scale,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(child: CameraPreview(controller)),
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _FaceGuidePainter(
                                faceDetected: _currentDetectedFace != null,
                                readiness: displaySnapshot.overallScore,
                                color: effectiveBorderColor,
                                fitScore: _faceGuideFitScore,
                                state: _guideVisualState,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Positioned(
              top: safeTop + 10,
              left: 16,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Colors.white.withOpacity(0.20)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _smartClose,
                ),
              ),
            ),
            Positioned(
              top: safeTop + 10,
              left: 76,
              right: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.52),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: effectiveBorderColor.withOpacity(0.45),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: effectiveBorderColor.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: effectiveBorderColor.withOpacity(0.45),
                            ),
                          ),
                          child: Icon(
                            isLiveChallenge ? Icons.flash_on : Icons.info_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isLiveChallenge
                                    ? _t('face_challenge_title')
                                    : _t('face_guidance_title'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                challengeMessage,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.90),
                                  fontSize: 14,
                                  height: 1.25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    challengeProgress,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.80),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(999),
                                      child: LinearProgressIndicator(
                                        value: challengesRequired <= 0
                                            ? 0.0
                                            : (challengesDone / challengesRequired)
                                                .clamp(0.0, 1.0),
                                        minHeight: 7,
                                        backgroundColor: Colors.white24,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            effectiveBorderColor),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 168,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LinearProgressIndicator(
                            value: _displaySignalProgress,
                            minHeight: 8,
                            backgroundColor: Colors.white24,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                effectiveBorderColor),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _buildSignalSummaryText(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _buildOverallSnapshotText(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () {
                            if (!mounted) return;
                            setState(() {
                              _showIndicators = !_showIndicators;
                            });
                          },
                          icon: Icon(
                            _showIndicators
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.white,
                          ),
                          label: Text(
                            _showIndicators
                                ? _t('face_hide_indicators')
                                : _t('face_show_indicators'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (_showIndicators) ...[
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildMetricChip(
                                _lang() == 'ar' ? 'التموضع' : 'Tracking',
                                displaySnapshot.trackingScore,
                                passed: displaySnapshot.trackingPassed,
                              ),
                              _buildMetricChip(
                                _lang() == 'ar' ? 'الوضعية' : 'Pose',
                                displaySnapshot.poseScore,
                                passed: displaySnapshot.posePassed,
                              ),
                              _buildMetricChip(
                                _lang() == 'ar' ? 'العينان' : 'Eyes',
                                displaySnapshot.eyeActivityScore,
                                passed: displaySnapshot.eyeActivityPassed,
                              ),
                              _buildMetricChip(
                                _lang() == 'ar' ? 'التنفس' : 'Breath',
                                displaySnapshot.breathingScore,
                                passed: displaySnapshot.breathingPassed,
                              ),
                              _buildMetricChip(
                                _lang() == 'ar' ? 'النسيج' : 'Texture',
                                displaySnapshot.textureScore,
                                passed: displaySnapshot.texturePassed,
                              ),
                              _buildMetricChip(
                                _lang() == 'ar' ? 'المعالم' : 'Landmarks',
                                displaySnapshot.landmarkScore,
                                passed: displaySnapshot.landmarkPassed,
                              ),
                              _buildMetricChip(
                                _lang() == 'ar'
                                    ? 'مقاومة الانتحال'
                                    : 'Anti-spoof',
                                displaySnapshot.antiSpoofScore,
                                passed: displaySnapshot.antiSpoofPassed,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 22,
              left: 16,
              right: 16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.18)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isProcessing || _isVerifyingOnServer)
                          Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child:
                                CircularProgressIndicator(color: effectiveBorderColor),
                          ),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _faceMatched ? Colors.green : Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (_instructionMessage.isNotEmpty &&
                            !_isProcessing &&
                            !_isVerifyingOnServer)
                          Text(
                            _instructionMessage,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        if (!_isProcessing &&
                            !_isVerifyingOnServer &&
                            !_faceMatched) ...[
                          const SizedBox(height: 18),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 10,
                            children: [
                              ElevatedButton.icon(
                                onPressed: _resetAndStartOver,
                                icon: const Icon(Icons.refresh),
                                label: Text(_t('retry')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              if (widget.showResetButton)
                                OutlinedButton.icon(
                                  onPressed: _resetFace,
                                  icon: const Icon(Icons.delete_forever),
                                  label: Text(_t('reset')),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Colors.red),
                                    foregroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ]
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_isVerifyingOnServer)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.22),
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.62),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.18),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(
                              color: effectiveBorderColor,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _t('face_processing_in_progress'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _t('face_procedure_recognition_desc'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.86),
                                fontSize: 12,
                                height: 1.3,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  final bool faceDetected;
  final double readiness;
  final Color color;
  final double fitScore;
  final _GuideVisualState state;

  _FaceGuidePainter({
    required this.faceDetected,
    required this.readiness,
    required this.color,
    required this.fitScore,
    required this.state,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final frameWidth = min(size.width * 0.78, 390.0);
    final frameHeight = min(size.height * 0.46, frameWidth * 1.22);
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.50),
      width: frameWidth,
      height: frameHeight,
    );

    final glowStrength = max(readiness, fitScore).clamp(0.18, 1.0);
    final ovalPath = Path()..addOval(rect);

    final overlayPath = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(rect);
    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withOpacity(0.26),
    );

    final framePaint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withOpacity(1.0),
          Colors.white.withOpacity(0.90),
          color.withOpacity(1.0),
        ],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = faceDetected ? 5.2 : 4.2;
    final glowPaint = Paint()
      ..color = color.withOpacity(0.10 + (glowStrength * 0.12))
      ..style = PaintingStyle.stroke
      ..strokeWidth = faceDetected ? 18.0 : 14.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final accentArcPaint = Paint()
      ..color = (state == _GuideVisualState.ready
              ? color.withOpacity(0.95)
              : color.withOpacity(0.70))
          .withOpacity(faceDetected ? 0.95 : 0.80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;
    final innerFillPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withOpacity(state == _GuideVisualState.ready ? 0.10 : 0.06),
          Colors.transparent,
        ],
        radius: 0.95,
      ).createShader(rect);
    final innerRingPaint = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawPath(ovalPath, innerFillPaint);
    canvas.drawPath(Path()..addOval(rect.inflate(4)), glowPaint);
    canvas.drawPath(ovalPath, framePaint);
    canvas.drawPath(Path()..addOval(rect.deflate(10)), innerRingPaint);

    const double arc = 0.52;
    canvas.drawArc(rect, -pi / 2 - arc, arc * 0.85, false, accentArcPaint);
    canvas.drawArc(rect, -pi / 2 + arc * 0.15, arc * 0.85, false, accentArcPaint);
    canvas.drawArc(rect, pi / 2 - arc, arc * 0.85, false, accentArcPaint);
    canvas.drawArc(rect, pi / 2 + arc * 0.15, arc * 0.85, false, accentArcPaint);

    if (faceDetected) {
      final scannerPaint = Paint()
        ..color = color.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;
      final scannerY =
          rect.top + ((rect.height - 8) * readiness.clamp(0.0, 1.0));
      canvas.save();
      canvas.clipPath(ovalPath);
      canvas.drawLine(
        Offset(rect.left + 16, scannerY),
        Offset(rect.right - 16, scannerY),
        scannerPaint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) {
    return oldDelegate.faceDetected != faceDetected ||
        oldDelegate.readiness != readiness ||
        oldDelegate.color != color ||
        oldDelegate.fitScore != fitScore ||
        oldDelegate.state != state;
  }
}
