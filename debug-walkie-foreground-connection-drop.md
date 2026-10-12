# Debug Session: walkie-foreground-connection-drop
- **Status**: [OPEN]
- **Issue**: الإشعار يظهر في الخلفية، لكن الصوت ينفصل أو الاتصال ينقطع بعد دخول التطبيق للخلفية.
- **Debug Server**: http://192.168.1.168:7777/event
- **Log File**: .dbg/trae-debug-log-walkie-background-audio.ndjson

## Reproduction Steps
1. فتح شاشة الووكي-توكي.
2. بدء الاتصال بالمجموعة.
3. التأكد من ظهور الإشعار الدائم.
4. إخراج التطبيق إلى الخلفية.
5. انتظار استقبال/إرسال صوت في الخلفية وملاحظة الانقطاع أو فصل الاتصال.

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | خدمة Foreground الأصلية لا تبدأ فعليًا، والإشعار الظاهر مجرد إشعار Flutter عادي. | High | Low | Confirmed by repeated `started: false` / `updated: false` logs. |
| B | نوع خدمة Android المعلن (`mediaPlayback`) غير مناسب لاتصال ووكي-توكي حي، فيُخفف النظام أولوية التنفيذ ويقطع WebRTC في الخلفية. | High | Low | Confirmed by manifest/service implementation mismatch. |
| C | Flutter يعتبر الخدمة الأصلية فعالة حتى بعد فشل البدء، فيتوقف عن المعالجة التصحيحية المبكرة. | Medium | Low | Confirmed by `foregroundServiceActive: true` while native start/update keep failing. |
| D | الانقطاع ناتج فقط عن WebRTC/audio playback، وليس عن الخلفية أو نوع الخدمة. | Medium | Medium | Rejected by current native service evidence. |

## Log Evidence
- `walkie_talkie_screen.dart:_syncForegroundService` reports repeated `started: false`.
- `walkie_talkie_screen.dart:_syncForegroundService` reports repeated `updated: false`.
- No matching native success evidence was recorded for actual foreground promotion.
- Added post-fix instrumentation in `walkie_background_service.dart` to capture exact `MissingPluginException` / `PlatformException` details from the `MethodChannel`.
- Added post-fix instrumentation in `walkie_talkie_screen.dart` for `RoomReconnectingEvent`, `RoomReconnectedEvent`, `ParticipantConnectedEvent`, and `ParticipantDisconnectedEvent`.

## Verification Conclusion
- Root cause 1 confirmed: native foreground promotion was not succeeding reliably; Flutter fallback notification alone is not enough to protect live walkie connectivity in background.
- Root cause 2 confirmed: Android service was declared as `mediaPlayback` instead of a microphone/voice foreground service, which is not appropriate for walkie-talkie live communication.
- Root cause 3 confirmed: Flutter UI state treated foreground service as active even when native start/update calls returned failure.
- Root cause 4 confirmed: the latest native bridge/service fixes were added under the wrong Kotlin package (`com.example.smart_vision`) while the app actually runs under `com.perfectsolutions.mtzhr`, so the real `MainActivity` never registered the walkie channel and the manifest service name did not point at the implemented class.

## Applied Fix
- Updated `AndroidManifest.xml` to request `FOREGROUND_SERVICE_MICROPHONE` and declare `foregroundServiceType="microphone|mediaPlayback"`.
- Updated `WalkieTalkieForegroundService.kt` to call `startForeground(...)` with `FOREGROUND_SERVICE_TYPE_MICROPHONE | FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK`.
- Updated `walkie_talkie_screen.dart` so `_isForegroundServiceActive` reflects actual native start/update success instead of assuming success.
- Moved the effective walkie native path onto the app's real package by registering the `MethodChannel` in `com.perfectsolutions.mtzhr.MainActivity` and changing `WalkieTalkieForegroundService` to the same package used by `namespace`/`applicationId`.
- Rebuilt APK for verification: `build/app/outputs/flutter-apk/app-debug.apk`.
