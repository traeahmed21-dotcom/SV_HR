import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

Future<void> _reportWalkieBridgeDebugEvent(
  String hypothesisId,
  String location,
  String msg, {
  Map<String, Object?>? data,
}) async {
  if (kIsWeb) return;
  const url = String.fromEnvironment(
    'WALKIE_DEBUG_SERVER_URL',
    defaultValue: 'http://192.168.1.168:7777/event',
  );
  const sessionId = String.fromEnvironment(
    'WALKIE_DEBUG_SESSION_ID',
    defaultValue: 'walkie-background-audio',
  );
  try {
    final client = HttpClient();
    final request = await client.postUrl(Uri.parse(url));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({
      'sessionId': sessionId,
      'runId': 'post-fix',
      'hypothesisId': hypothesisId,
      'location': location,
      'msg': '[DEBUG] $msg',
      'data': data ?? <String, Object?>{},
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
    await request.close();
    client.close(force: true);
  } catch (_) {}
}

class WalkieBackgroundService {
  WalkieBackgroundService._();

  static const MethodChannel _channel = MethodChannel(
    'smart_vision/walkie_foreground',
  );

  static Future<bool> start({
    required String title,
    required String message,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;

    try {
      await _channel.invokeMethod('startForegroundService', {
        'title': title,
        'message': message,
      });
      // #region debug-point A:bridge-start-success
      unawaited(_reportWalkieBridgeDebugEvent(
        'A',
        'walkie_background_service.dart:start',
        'Foreground service bridge start succeeded',
        data: {
          'title': title,
          'message': message,
        },
      ));
      // #endregion
      return true;
    } on MissingPluginException catch (e) {
      // #region debug-point A:bridge-start-missing-plugin
      unawaited(_reportWalkieBridgeDebugEvent(
        'A',
        'walkie_background_service.dart:start',
        'Foreground service bridge missing plugin',
        data: {
          'error': e.toString(),
          'title': title,
          'message': message,
        },
      ));
      // #endregion
      debugPrint('Walkie foreground channel is unavailable: $e');
      return false;
    } on PlatformException catch (e) {
      // #region debug-point A:bridge-start-platform-error
      unawaited(_reportWalkieBridgeDebugEvent(
        'A',
        'walkie_background_service.dart:start',
        'Foreground service bridge platform error on start',
        data: {
          'code': e.code,
          'message': e.message,
          'details': e.details?.toString(),
          'title': title,
          'messageText': message,
        },
      ));
      // #endregion
      debugPrint('Walkie foreground start failed: ${e.message}');
      return false;
    } catch (e) {
      // #region debug-point A:bridge-start-unexpected-error
      unawaited(_reportWalkieBridgeDebugEvent(
        'A',
        'walkie_background_service.dart:start',
        'Foreground service bridge unexpected start error',
        data: {
          'error': e.toString(),
          'title': title,
          'message': message,
        },
      ));
      // #endregion
      debugPrint('Walkie foreground start threw an unexpected error: $e');
      return false;
    }
  }

  static Future<bool> update({
    required String title,
    required String message,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;

    try {
      await _channel.invokeMethod('updateForegroundService', {
        'title': title,
        'message': message,
      });
      // #region debug-point B:bridge-update-success
      unawaited(_reportWalkieBridgeDebugEvent(
        'B',
        'walkie_background_service.dart:update',
        'Foreground service bridge update succeeded',
        data: {
          'title': title,
          'message': message,
        },
      ));
      // #endregion
      return true;
    } on MissingPluginException catch (e) {
      // #region debug-point B:bridge-update-missing-plugin
      unawaited(_reportWalkieBridgeDebugEvent(
        'B',
        'walkie_background_service.dart:update',
        'Foreground service bridge missing plugin on update',
        data: {
          'error': e.toString(),
          'title': title,
          'message': message,
        },
      ));
      // #endregion
      debugPrint('Walkie foreground channel is unavailable: $e');
      return false;
    } on PlatformException catch (e) {
      // #region debug-point B:bridge-update-platform-error
      unawaited(_reportWalkieBridgeDebugEvent(
        'B',
        'walkie_background_service.dart:update',
        'Foreground service bridge platform error on update',
        data: {
          'code': e.code,
          'message': e.message,
          'details': e.details?.toString(),
          'title': title,
          'messageText': message,
        },
      ));
      // #endregion
      debugPrint('Walkie foreground update failed: ${e.message}');
      return false;
    } catch (e) {
      // #region debug-point B:bridge-update-unexpected-error
      unawaited(_reportWalkieBridgeDebugEvent(
        'B',
        'walkie_background_service.dart:update',
        'Foreground service bridge unexpected update error',
        data: {
          'error': e.toString(),
          'title': title,
          'message': message,
        },
      ));
      // #endregion
      debugPrint('Walkie foreground update threw an unexpected error: $e');
      return false;
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      await _channel.invokeMethod('stopForegroundService');
    } on MissingPluginException catch (e) {
      debugPrint('Walkie foreground channel is unavailable: $e');
    } on PlatformException catch (e) {
      debugPrint('Walkie foreground stop failed: ${e.message}');
    } catch (e) {
      debugPrint('Walkie foreground stop threw an unexpected error: $e');
    }
  }
}
