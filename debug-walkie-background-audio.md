# Debug Session: walkie-background-audio
- **Status**: [OPEN]
- **Issue**: عند بدء اتصال الووكي-توكي ثم خروج المستخدم من التطبيق، لا يصل الصوت أحيانًا في الخلفية، كما لا يظهر إشعار دائم يثبت أن الخدمة ما زالت فعالة.
- **Debug Server**: http://192.168.1.168:7777/event
- **Log File**: .dbg/trae-debug-log-walkie-background-audio.ndjson

## Reproduction Steps
1. فتح شاشة الووكي-توكي.
2. اختيار مجموعة والضغط على `بدء الاتصال`.
3. التأكد أن الحالة أصبحت `متصل`.
4. الخروج من التطبيق إلى الخلفية.
5. جعل مستخدم آخر يتحدث من نفس المجموعة.
6. التحقق من ظهور إشعار دائم ومن استمرار وصول الصوت.

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | خدمة الخلفية لا تبدأ أصلًا أو تفشل مباشرة بعد طلب التشغيل من Flutter. | High | Low | Confirmed: Flutter logs show repeated `started: false` on every start attempt. |
| B | خدمة الخلفية تبدأ لكن الإشعار لا يُعرض بسبب القناة أو الصلاحيات أو خصائص الإشعار. | Medium | Low | Rejected: no native service start evidence was recorded. |
| C | اتصال LiveKit يبقى متصلًا ظاهريًا لكن تشغيل الصوت في الخلفية يتوقف بعد انتقال التطبيق للخلفية. | High | Medium | Confirmed: participant speaking updates continue in background while user hears no audio. |
| D | الـ MethodChannel/Plugin يعمل أثناء الواجهة لكن يفشل في دورة حياة الخلفية، فلا تصل أوامر التحديث/الإيقاف بشكل ثابت. | Medium | Medium | Likely confirmed: no native plugin/service logs arrived, while Flutter fallback logs did. |
| E | النظام يطبق Battery Optimization / App standby ويوقف مسار الصوت أو الخدمة بعد الخلفية. | Medium | Medium | Not primary with current evidence. |

## Log Evidence
Instrumentation added to:
- `lib/screens/walkie_talkie_screen.dart`
- `android/app/src/main/kotlin/com/example/smart_vision/WalkieForegroundPlugin.kt`
- `android/app/src/main/kotlin/com/example/smart_vision/WalkieTalkieForegroundService.kt`

## Verification Conclusion
- Root cause 1: native foreground-service bridge is not succeeding at runtime on the tested build, so no ongoing notification appears.
- Root cause 2: room connectivity survives in background, but audio playback is not being actively re-armed after lifecycle/playback transitions.
- Root cause 3: `_ensureRoomAudioPlayback('connect')` was being called before `_room` was assigned, so the initial audio-stabilization path was effectively skipped.
- Root cause 4: LiveKit/WebRTC was being initialized lazily with default Android audio routing, instead of an app-wide communication session configured up front with forced routing.

## Applied Fix
- Added persistent Walkie notification through `flutter_local_notifications` as a reliable fallback independent of the broken native bridge.
- Added `_ensureRoomAudioPlayback(...)` and invoked it on connect, lifecycle changes, and `AudioPlaybackStatusChanged`.
- Updated `_ensureRoomAudioPlayback(...)` to accept the just-connected room instance so connect-time playback setup actually runs.
- Initialized `LiveKitClient` at app startup with Android communication audio session options and `forceAudioRouting: true`, then forced speaker output via `AudioManager`.
- Built a fresh debug APK for verification: `build/app/outputs/flutter-apk/app-debug.apk`.
