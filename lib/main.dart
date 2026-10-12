import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'services/notification_service.dart';
import 'services/language_service.dart';
import 'services/translations.dart';
import 'config/api_config.dart';
import 'theme/app_theme.dart';
import 'models/api_models.dart' as api_models;
import 'screens/app_shell.dart';
import 'package:url_strategy/url_strategy.dart';
import 'widgets/app_update_gate.dart';

const bool _enableRemoteDebugTelemetry = true;
const String _debugServerUrl = 'http://192.168.1.163:7777/event';
const String _debugSessionId = 'camera-login-biometrics';

const AudioSessionOptions _walkieAudioSessionOptions =
    AudioSessionOptions.communication(
  android: AndroidAudioSessionConfiguration(
    audioMode: AndroidAudioMode.inCommunication,
    manageAudioFocus: true,
    focusMode: AndroidAudioFocusMode.gain,
    streamType: AndroidAudioStreamType.voiceCall,
    usageType: AndroidAudioAttributesUsageType.voiceCommunication,
    contentType: AndroidAudioAttributesContentType.speech,
    forceAudioRouting: true,
  ),
);

// #region debug-point A:reporting-helper
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
      }),
    );
  } catch (_) {}
}
// #endregion

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await LiveKitClient.initialize(
    initialAudioSessionOptions: _walkieAudioSessionOptions,
  );
  await AudioManager.instance.setSpeakerOutputPreferred(true, force: true);

  FlutterError.onError = (FlutterErrorDetails details) {
    // #region debug-point A:flutter-error
    _reportDebugEvent(
      'A',
      'main.dart:FlutterError.onError',
      'Flutter framework error captured',
      data: {
        'exception': details.exceptionAsString(),
        'library': details.library,
        'context': details.context?.toDescription(),
      },
    );
    // #endregion
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    // #region debug-point A:platform-error
    _reportDebugEvent(
      'A',
      'main.dart:PlatformDispatcher.onError',
      'Platform dispatcher error captured',
      data: {
        'error': error.toString(),
        'stackHead': stack.toString().split('\n').take(6).join('\n'),
      },
    );
    // #endregion
    return false;
  };

  // تهيئة خدمة الإشعارات
  await NotificationService().initialize();

  // تحسين تجربة الويب: إزالة # من الروابط
  if (kIsWeb) {
    setPathUrlStrategy();
  }

  // تهيئة ApiConfig وجلب الرابط المحول
  await ApiConfig.initialize();

  // التحقق من وجود جلسة مسجلة مسبقاً (Remember Me)
  final prefs = await SharedPreferences.getInstance();
  final bool isLoggedIn = prefs.getBool('is_logged_in') ?? false;
  final String? userDataJson = prefs.getString('user_data');

  api_models.EmployeeData? savedUser;
  if (isLoggedIn && userDataJson != null) {
    try {
      final Map<String, dynamic> userMap = json.decode(userDataJson);
      savedUser = api_models.EmployeeData.fromJson(userMap);
    } catch (e) {
      if (kDebugMode) print('❌ خطأ في تحميل بيانات المستخدم المحفوظة: $e');
    }
  }

  runApp(MyApp(savedUser: savedUser));
}

class MyApp extends StatelessWidget {
  final api_models.EmployeeData? savedUser;

  const MyApp({super.key, this.savedUser});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => LanguageService(),
      child: Consumer<LanguageService>(
        builder: (context, languageService, child) {
          return MaterialApp(
            title: Translations.getText(
              'app_name',
              languageService.currentLocale.languageCode,
            ),
            debugShowCheckedModeBanner: false,

            // دعم اللغات المحلية
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('ar', 'SA'), // العربية - السعودية
              Locale('en', 'US'), // الإنجليزية - الولايات المتحدة
            ],
            locale: languageService.currentLocale,

            // دعم الاتجاه من اليمين إلى اليسار
            builder: (context, child) {
              return Directionality(
                textDirection: languageService.currentDirection,
                child: child!,
              );
            },

            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: ThemeMode.system,

            home: AppUpdateGate(
              child: savedUser != null
                  ? AppShell(
                      employeeNumber: savedUser!.employeeNumber,
                      employeeData: savedUser!,
                    )
                  : const LoginScreen(),
            ),
          );
        },
      ),
    );
  }
}
