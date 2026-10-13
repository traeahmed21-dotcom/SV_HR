import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/walkie_talkie_models.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/notification_service.dart';
import '../services/translations.dart';
import '../services/walkie_background_service.dart';

const String _walkieDebugFallbackUrl = 'http://192.168.1.168:7777/event';
const String _walkieDebugSessionId = 'walkie-background-audio';

// #region debug-point A:walkie-reporting-helper
Future<void> _reportWalkieDebugEvent(
  String hypothesisId,
  String location,
  String msg, {
  Map<String, dynamic>? data,
}) async {
  if (kIsWeb) return;

  try {
    await http.post(
      Uri.parse(_walkieDebugFallbackUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'sessionId': _walkieDebugSessionId,
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

class WalkieTalkieScreen extends StatefulWidget {
  final int clientId;
  final int employeeId;
  final String employeeName;

  const WalkieTalkieScreen({
    super.key,
    required this.clientId,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<WalkieTalkieScreen> createState() => _WalkieTalkieScreenState();
}

class _WalkieTalkieScreenState extends State<WalkieTalkieScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();

  List<WalkieTalkieGroup> _groups = [];
  List<Participant> _participants = [];
  WalkieTalkieGroup? _selectedGroup;
  WalkieTalkieAccessToken? _token;
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;

  bool _isLoading = true;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isTalking = false;
  int _micToggleSequence = 0;
  bool _desiredTalking = false;
  bool _isApplyingTalkingState = false;
  bool _isForegroundServiceActive = false;
  String? _deviceId;
  String? _error;
  String? _lastForegroundNotification;

  String get _lang =>
      context.read<LanguageService>().currentLocale.languageCode;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_ensureDeviceId());
    unawaited(_loadGroups());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    unawaited(_stopForegroundService());
    unawaited(_disposeRoom());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isBackgroundState =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached;

    // #region debug-point C:lifecycle-transition
    unawaited(_reportWalkieDebugEvent(
      'C',
      'walkie_talkie_screen.dart:didChangeAppLifecycleState',
      'Walkie lifecycle state changed',
      data: {
        'state': state.name,
        'isBackgroundState': isBackgroundState,
        'isConnected': _isConnected,
        'isTalking': _isTalking,
        'foregroundServiceActive': _isForegroundServiceActive,
      },
    ));
    // #endregion

    if (isBackgroundState && _isTalking) {
      unawaited(_stopTalking());
    }

    if (_isConnected) {
      unawaited(_ensureRoomAudioPlayback('lifecycle:${state.name}'));
    }

    unawaited(_syncForegroundService());
  }

  Future<void> _disposeRoom() async {
    final listener = _roomListener;
    final room = _room;
    _desiredTalking = false;
    _isApplyingTalkingState = false;
    _roomListener = null;
    _room = null;

    if (room != null) {
      room.removeListener(_onRoomUpdated);
    }

    await listener?.dispose();

    if (room != null) {
      try {
        await room.disconnect();
      } catch (_) {}
      await room.dispose();
    }
  }

  Future<void> _loadGroups() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final groups = await ApiService.getWalkieTalkieGroups(
        widget.clientId,
        widget.employeeId,
      );

      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selectedGroup = groups.isNotEmpty ? groups.first : null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _ensureDeviceId() async {
    if (_deviceId != null && _deviceId!.isNotEmpty) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDeviceId = prefs.getString('device_uuid');

      if (savedDeviceId != null && savedDeviceId.trim().isNotEmpty) {
        _deviceId = savedDeviceId.trim();
        return;
      }

      final generatedDeviceId = _generateDeviceId();
      await prefs.setString('device_uuid', generatedDeviceId);
      _deviceId = generatedDeviceId;
    } catch (_) {
      _deviceId = _generateDeviceId();
    }
  }

  String _generateDeviceId() {
    final random = Random.secure();
    final values = List<int>.generate(16, (_) => random.nextInt(256));

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

  Future<bool> _ensureAudioPermissions() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) {
      return true;
    }

    if (!mounted) return false;

    final title = Translations.getText('walkie_mic_permission_title', _lang);

    Future<void> openSettingsDialog() async {
      final shouldOpenSettings = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(title),
            content: Text(
              Translations.getText('walkie_mic_permission_settings', _lang),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(Translations.getText('cancel', _lang)),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(Translations.getText('app_settings', _lang)),
              ),
            ],
          );
        },
      );

      if (shouldOpenSettings == true) {
        await openAppSettings();
      }
    }

    if (status.isPermanentlyDenied || status.isRestricted) {
      await openSettingsDialog();
      return false;
    }

    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(
            Translations.getText('walkie_mic_permission_request', _lang),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(Translations.getText('cancel', _lang)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(Translations.getText('walkie_grant_permission', _lang)),
            ),
          ],
        );
      },
    );

    if (shouldRequest != true) {
      return false;
    }

    final result = await Permission.microphone.request();
    if (result.isGranted) {
      return true;
    }

    if (!mounted) return false;

    if (result.isPermanentlyDenied || result.isRestricted) {
      await openSettingsDialog();
    }

    return false;
  }

  Future<bool> _ensureNotificationPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final status = await Permission.notification.status;
    if (status.isGranted) {
      return true;
    }

    final result = await Permission.notification.request();
    return result.isGranted;
  }

  String _participantTitle(Participant participant) {
    final name = participant.name.trim();
    if (name.isNotEmpty) {
      return name;
    }

    final identity = participant.identity.trim();
    if (identity.isNotEmpty) {
      return identity;
    }

    return widget.employeeName;
  }

  String _resolveForegroundGroupName() {
    final selectedName = _selectedGroup?.groupName.trim() ?? '';
    if (selectedName.isNotEmpty) {
      return selectedName;
    }

    final roomName = _token?.roomName.trim() ?? '';
    if (roomName.isNotEmpty) {
      return roomName;
    }

    return Translations.getText('walkie_title', _lang);
  }

  Future<void> _ensureRoomAudioPlayback(
    String reason, {
    Room? roomOverride,
  }) async {
    final room = roomOverride ?? _room;
    if (room == null) return;

    try {
      if (!room.canPlaybackAudio) {
        await room.startAudio();
      }
    } catch (e) {
      // #region debug-point C:audio-restart-failed
      unawaited(_reportWalkieDebugEvent(
        'C',
        'walkie_talkie_screen.dart:_ensureRoomAudioPlayback',
        'Walkie audio playback restart failed',
        data: {
          'reason': reason,
          'error': e.toString(),
          'isConnected': _isConnected,
        },
      ));
      // #endregion
    }

    try {
      await AudioManager.instance.setSpeakerOutputPreferred(true, force: true);
    } catch (_) {}

    // #region debug-point C:audio-restart-attempt
    unawaited(_reportWalkieDebugEvent(
      'C',
      'walkie_talkie_screen.dart:_ensureRoomAudioPlayback',
      'Walkie audio playback ensured',
      data: {
        'reason': reason,
        'canPlaybackAudio': room.canPlaybackAudio,
        'isConnected': _isConnected,
      },
    ));
    // #endregion
  }

  ({String title, String message}) _buildForegroundNotification() {
    final title = Translations.getText('walkie_background_service_title', _lang);
    final groupName = _resolveForegroundGroupName();
    final remoteSpeakers = _participants
        .where((participant) => participant is! LocalParticipant)
        .where((participant) => participant.isSpeaking)
        .map(_participantTitle)
        .toList();

    if (_isTalking) {
      return (
        title: title,
        message: Translations.getTextWithParams(
          'walkie_background_you_talking_group',
          _lang,
          {'group': groupName},
        ),
      );
    }

    if (remoteSpeakers.length == 1) {
      return (
        title: title,
        message: Translations.getTextWithParams(
          'walkie_background_remote_speaking',
          _lang,
          {'name': remoteSpeakers.first, 'group': groupName},
        ),
      );
    }

    if (remoteSpeakers.length > 1) {
      return (
        title: title,
        message: Translations.getTextWithParams(
          'walkie_background_multiple_speakers',
          _lang,
          {'count': remoteSpeakers.length.toString(), 'group': groupName},
        ),
      );
    }

    return (
      title: title,
      message: Translations.getTextWithParams(
        'walkie_background_connected_group',
        _lang,
        {'group': groupName},
      ),
    );
  }

  Future<void> _syncForegroundService() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final shouldRun = _isConnected;
    if (!shouldRun) {
      // #region debug-point A:foreground-stop-request
      unawaited(_reportWalkieDebugEvent(
        'A',
        'walkie_talkie_screen.dart:_syncForegroundService',
        'Stopping walkie foreground service because connection is inactive',
        data: {
          'isConnected': _isConnected,
          'foregroundServiceActive': _isForegroundServiceActive,
        },
      ));
      // #endregion
      await _stopForegroundService();
      return;
    }

    final notification = _buildForegroundNotification();
    final signature = '${notification.title}|${notification.message}';

        await NotificationService().showWalkiePersistentNotification(
          title: notification.title,
          message: notification.message,
        );

    if (!_isForegroundServiceActive) {
      final started = await WalkieBackgroundService.start(
        title: notification.title,
        message: notification.message,
      );
      // #region debug-point A:foreground-start-result
      unawaited(_reportWalkieDebugEvent(
        'A',
        'walkie_talkie_screen.dart:_syncForegroundService',
        'Requested walkie foreground service start',
        data: {
          'started': started,
          'title': notification.title,
          'message': notification.message,
          'isConnected': _isConnected,
          'participantCount': _participants.length,
        },
      ));
      // #endregion
          _isForegroundServiceActive = started;
          _lastForegroundNotification = signature;
      return;
    }

    if (_lastForegroundNotification == signature) {
      return;
    }

    final updated = await WalkieBackgroundService.update(
      title: notification.title,
      message: notification.message,
    );
    // #region debug-point B:foreground-update-result
    unawaited(_reportWalkieDebugEvent(
      'B',
      'walkie_talkie_screen.dart:_syncForegroundService',
      'Requested walkie foreground service update',
      data: {
        'updated': updated,
        'title': notification.title,
        'message': notification.message,
        'foregroundServiceActive': _isForegroundServiceActive,
      },
    ));
    // #endregion
        if (!updated) {
          _isForegroundServiceActive = false;
        }
        _lastForegroundNotification = signature;
  }

  Future<void> _stopForegroundService() async {
    await NotificationService().cancelWalkiePersistentNotification();
    if (_isForegroundServiceActive) {
      await WalkieBackgroundService.stop();
    }
    _isForegroundServiceActive = false;
    _lastForegroundNotification = null;
  }

  void _bindRoomListeners(Room room, EventsListener<RoomEvent> listener) {
    room.addListener(_onRoomUpdated);

    listener
          ..on<RoomReconnectingEvent>((_) async {
            // #region debug-point D:room-reconnecting
            unawaited(_reportWalkieDebugEvent(
              'D',
              'walkie_talkie_screen.dart:RoomReconnectingEvent',
              'Walkie room entered reconnecting state',
              data: {
                'participantCount': _participants.length,
                'foregroundServiceActive': _isForegroundServiceActive,
                'isConnected': _isConnected,
              },
            ));
            // #endregion
          })
          ..on<RoomReconnectedEvent>((_) async {
            // #region debug-point D:room-reconnected
            unawaited(_reportWalkieDebugEvent(
              'D',
              'walkie_talkie_screen.dart:RoomReconnectedEvent',
              'Walkie room reconnected successfully',
              data: {
                'participantCount': _participants.length,
                'foregroundServiceActive': _isForegroundServiceActive,
                'isConnected': _isConnected,
              },
            ));
            // #endregion
            await _ensureRoomAudioPlayback('room-reconnected', roomOverride: room);
            _syncParticipants();
          })
      ..on<RoomDisconnectedEvent>((_) async {
        // #region debug-point C:room-disconnected
        unawaited(_reportWalkieDebugEvent(
          'C',
          'walkie_talkie_screen.dart:RoomDisconnectedEvent',
          'Walkie room disconnected',
          data: {
            'participantCount': _participants.length,
            'foregroundServiceActive': _isForegroundServiceActive,
          },
        ));
        // #endregion
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _isTalking = false;
          _participants = [];
        });
            _desiredTalking = false;
        await _stopForegroundService();
      })
          ..on<ParticipantDisconnectedEvent>((event) {
            // #region debug-point D:participant-disconnected
            unawaited(_reportWalkieDebugEvent(
              'D',
              'walkie_talkie_screen.dart:ParticipantDisconnectedEvent',
              'Remote participant disconnected from walkie room',
              data: {
                'identity': event.participant.identity,
                'sid': event.participant.sid,
                'foregroundServiceActive': _isForegroundServiceActive,
                'isConnected': _isConnected,
              },
            ));
            // #endregion
            _syncParticipants();
          })
          ..on<ParticipantConnectedEvent>((event) {
            // #region debug-point D:participant-connected
            unawaited(_reportWalkieDebugEvent(
              'D',
              'walkie_talkie_screen.dart:ParticipantConnectedEvent',
              'Remote participant connected to walkie room',
              data: {
                'identity': event.participant.identity,
                'sid': event.participant.sid,
                'foregroundServiceActive': _isForegroundServiceActive,
                'isConnected': _isConnected,
              },
            ));
            // #endregion
            _syncParticipants();
          })
      ..on<ParticipantEvent>((_) {
        _syncParticipants();
      })
          ..on<TrackSubscribedEvent>((_) async {
        _syncParticipants();
            await _ensureRoomAudioPlayback(
              'track-subscribed',
              roomOverride: room,
            );
      })
      ..on<TrackUnsubscribedEvent>((_) async {
        _syncParticipants();
      })
      ..on<LocalTrackPublishedEvent>((_) async {
        _syncParticipants();
      })
      ..on<LocalTrackUnpublishedEvent>((_) async {
        _syncParticipants();
      })
          ..on<AudioPlaybackStatusChanged>((event) async {
            // #region debug-point C:audio-playback-status
            unawaited(_reportWalkieDebugEvent(
              'C',
              'walkie_talkie_screen.dart:AudioPlaybackStatusChanged',
              'Walkie audio playback status changed',
              data: {
                'canPlaybackAudio': room.canPlaybackAudio,
                'isConnected': _isConnected,
                'event': event.toString(),
              },
            ));
            // #endregion
            await _ensureRoomAudioPlayback('audio-playback-status');
          });
  }

  void _onRoomUpdated() {
    _syncParticipants();
  }

  void _syncParticipants() {
    final room = _room;
    if (!mounted || room == null) return;

    final list = <Participant>[];
    if (room.localParticipant != null) {
      list.add(room.localParticipant!);
    }
    list.addAll(room.remoteParticipants.values);

    setState(() {
      _participants = list;
    });

    unawaited(_syncForegroundService());
  }

  Future<void> _connectToGroup() async {
    final group = _selectedGroup;
    if (group == null || _isConnecting) return;

    await _ensureDeviceId();

    if (!await _ensureAudioPermissions()) {
      return;
    }

    if (!await _ensureNotificationPermissions()) {
      if (!mounted) return;
      _showMessage(
        Translations.getText('walkie_notification_permission_required', _lang),
        isError: true,
      );
      return;
    }

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    await _disposeRoom();

    try {
      final token = await ApiService.issueWalkieTalkieToken(
        widget.clientId,
        widget.employeeId,
        group.groupId,
        deviceId: _deviceId,
      );

      if (!mounted) return;

      if (token == null) {
        setState(() {
          _isConnecting = false;
        });
        _showMessage(
          Translations.getText('walkie_connect_error', _lang),
          isError: true,
        );
        return;
      }

      final room = Room(
        roomOptions: const RoomOptions(
          adaptiveStream: true,
          dynacast: true,
        ),
      );
      final listener = room.createListener();
      _bindRoomListeners(room, listener);

      if (token.serverUrl.trim().isEmpty || token.token.trim().isEmpty) {
        throw StateError('Walkie token response is missing server URL or token.');
      }

      // `prepareConnection` is only an optimization. If it fails due to
      // transient network conditions, continue with the actual connect call.
      try {
        await room.prepareConnection(token.serverUrl, token.token);
      } catch (e, stackTrace) {
        debugPrint('Walkie prepareConnection failed: $e');
        debugPrint('$stackTrace');
      }

      await room.connect(
        token.serverUrl,
        token.token,
        connectOptions: const ConnectOptions(autoSubscribe: true),
      );

          await _ensureRoomAudioPlayback(
            'connect',
            roomOverride: room,
          );

      if (token.canPublish) {
        await room.localParticipant?.setMicrophoneEnabled(false);
      }

      if (!mounted) {
        await listener.dispose();
        await room.disconnect();
        await room.dispose();
        return;
      }

      setState(() {
        _room = room;
        _roomListener = listener;
        _token = token;
        _isConnected = true;
        _isConnecting = false;
        _isTalking = false;
      });
          await AudioManager.instance.setSpeakerOutputPreferred(true, force: true);
      _syncParticipants();
      await _syncForegroundService();

      // #region debug-point C:room-connected
      unawaited(_reportWalkieDebugEvent(
        'C',
        'walkie_talkie_screen.dart:_connectToGroup',
        'Walkie room connected successfully',
        data: {
          'roomName': token.roomName,
          'identity': token.identity,
          'canPublish': token.canPublish,
          'canSubscribe': token.canSubscribe,
          'canPlaybackAudio': room.canPlaybackAudio,
          'foregroundServiceActive': _isForegroundServiceActive,
        },
      ));
      // #endregion

      _showMessage(Translations.getText('walkie_room_ready', _lang));
    } catch (e, stackTrace) {
      debugPrint('Walkie connect failed: $e');
      debugPrint('$stackTrace');
      // #region debug-point D:room-connect-failed
      unawaited(_reportWalkieDebugEvent(
        'D',
        'walkie_talkie_screen.dart:_connectToGroup',
        'Walkie room connection failed',
        data: {
          'error': e.toString(),
          'stackHead': stackTrace.toString().split('\n').take(8).join('\n'),
          'foregroundServiceActive': _isForegroundServiceActive,
        },
      ));
      // #endregion
      if (!mounted) return;
      await _disposeRoom();
      setState(() {
        _isConnecting = false;
        _isConnected = false;
        _isTalking = false;
        _participants = [];
        _error = e.toString();
      });
      _showMessage(
        Translations.getText('walkie_connect_live_error', _lang),
        isError: true,
      );
    }
  }

  Future<void> _disconnect({bool silent = false}) async {
    await _disposeRoom();
    await _stopForegroundService();

    if (!mounted) return;
    setState(() {
      _token = null;
      _isConnected = false;
      _isConnecting = false;
      _isTalking = false;
      _participants = [];
    });

    if (!silent) {
      _showMessage(Translations.getText('walkie_disconnected', _lang));
    }
  }

  Future<void> _setTalkingState(bool shouldTalk) async {
    if (!_isConnected ||
        _room == null ||
        !(_selectedGroup?.canSpeak ?? false) ||
        !(_token?.canPublish ?? false)) {
      return;
    }

    _desiredTalking = shouldTalk;
    if (_isApplyingTalkingState) {
      return;
    }

    _isApplyingTalkingState = true;
    try {
      while (_room != null && _isConnected) {
        final targetTalking = _desiredTalking;
        if (_isTalking == targetTalking) {
          break;
        }

        final sequence = ++_micToggleSequence;
        final actionName = targetTalking ? 'start' : 'stop';

        // #region debug-point E:talk-toggle-request
        unawaited(_reportWalkieDebugEvent(
          'E',
          'walkie_talkie_screen.dart:_setTalkingState',
          'Requested talking state change',
          data: {
            'sequence': sequence,
            'action': actionName,
            'targetTalking': targetTalking,
            'isTalkingBefore': _isTalking,
            'desiredTalking': _desiredTalking,
          },
        ));
        // #endregion

        try {
          await _room!.localParticipant?.setMicrophoneEnabled(targetTalking);
        } catch (e) {
          // #region debug-point E:talk-toggle-failed
          unawaited(_reportWalkieDebugEvent(
            'E',
            'walkie_talkie_screen.dart:_setTalkingState',
            'Talking state change failed',
            data: {
              'sequence': sequence,
              'action': actionName,
              'targetTalking': targetTalking,
              'error': e.toString(),
            },
          ));
          // #endregion
          if (targetTalking && mounted) {
            _showMessage(
              Translations.getText('walkie_microphone_enable_error', _lang),
              isError: true,
            );
          }
          break;
        }

        // #region debug-point E:talk-toggle-completed
        unawaited(_reportWalkieDebugEvent(
          'E',
          'walkie_talkie_screen.dart:_setTalkingState',
          'Talking state change completed',
          data: {
            'sequence': sequence,
            'action': actionName,
            'targetTalking': targetTalking,
            'desiredTalkingAfterAwait': _desiredTalking,
          },
        ));
        // #endregion

        if (!mounted) return;

        if (_desiredTalking != targetTalking) {
          continue;
        }

        setState(() {
          _isTalking = targetTalking;
        });
        unawaited(_syncForegroundService());
      }
    } finally {
      _isApplyingTalkingState = false;
    }
  }

  Future<void> _startTalking() async {
    await _setTalkingState(true);
  }

  Future<void> _stopTalking() async {
    _desiredTalking = false;
    if (!_isConnected || _room == null) {
      if (mounted && _isTalking) {
        setState(() {
          _isTalking = false;
        });
      }
      return;
    }

    await _setTalkingState(false);
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageService = context.watch<LanguageService>();
    final lang = languageService.currentLocale.languageCode;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filteredGroups = _groups.where((group) {
      final term = _searchController.text.trim().toLowerCase();
      if (term.isEmpty) return true;
      return group.groupName.toLowerCase().contains(term) ||
          group.description.toLowerCase().contains(term);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F7FC),
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(Translations.getText('walkie_title', lang)),
        actions: [
          IconButton(
            onPressed: () => unawaited(_loadGroups()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(lang)
              : _groups.isEmpty
                  ? _buildEmptyState(lang)
                  : RefreshIndicator(
                      onRefresh: _loadGroups,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        children: [
                          _buildHeroCard(theme, scheme, lang),
                          const SizedBox(height: 18),
                          _buildSearchField(lang),
                          const SizedBox(height: 18),
                          _buildSectionHeader(
                            context,
                            title: Translations.getText(
                              'walkie_groups_count',
                              lang,
                            ),
                            subtitle: '${filteredGroups.length}',
                          ),
                          const SizedBox(height: 12),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth;
                              const spacing = 14.0;
                              final columns = width >= 980
                                  ? 3
                                  : width >= 640
                                      ? 2
                                      : 1;
                              final itemWidth = columns == 1
                                  ? width
                                  : (width - (spacing * (columns - 1))) /
                                      columns;

                              return Wrap(
                                spacing: spacing,
                                runSpacing: spacing,
                                children: filteredGroups
                                    .map(
                                      (group) => SizedBox(
                                        width: itemWidth,
                                        child: _buildGroupCard(
                                          group,
                                          _selectedGroup?.groupId ==
                                              group.groupId,
                                          theme,
                                          scheme,
                                          lang,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                          if (_selectedGroup != null)
                            _buildRoomPanel(
                              _selectedGroup!,
                              theme,
                              scheme,
                              lang,
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildSearchField(String lang) {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText: Translations.getText('walkie_search_groups', lang),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary,
            width: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF101828),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(
    ThemeData theme,
    ColorScheme scheme,
    String lang,
  ) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: [
            const Color(0xFF155EEF),
            scheme.primary,
            const Color(0xFF0EA5E9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF155EEF).withValues(alpha: 0.22),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Translations.getText('walkie_title', lang),
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Translations.getText('walkie_subtitle', lang),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final cards = [
                _buildHeroMetric(
                  Icons.groups_rounded,
                  '${_groups.length}',
                  Translations.getText('walkie_groups_count', lang),
                ),
                _buildHeroMetric(
                  Icons.wifi_tethering_rounded,
                  _isConnected
                      ? Translations.getText('walkie_status_connected', lang)
                      : Translations.getText('walkie_status_ready', lang),
                  Translations.getText('walkie_connection_status', lang),
                ),
                _buildHeroMetric(
                  Icons.people_alt_rounded,
                  '${_participants.length}',
                  Translations.getText('walkie_participants', lang),
                ),
              ];

              if (constraints.maxWidth >= 620) {
                return Row(
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      Expanded(child: cards[i]),
                      if (i != cards.length - 1) const SizedBox(width: 12),
                    ],
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[1]),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(width: double.infinity, child: cards[2]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetric(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupCard(
    WalkieTalkieGroup group,
    bool selected,
    ThemeData theme,
    ColorScheme scheme,
    String lang,
  ) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedGroup = group;
          _isTalking = false;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.10),
                    scheme.secondary.withValues(alpha: 0.08),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                )
              : null,
          color: selected ? null : Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: selected ? 0.08 : 0.04),
              blurRadius: selected ? 24 : 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: (selected ? scheme.primary : scheme.secondary)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.campaign_rounded,
                    color: selected ? scheme.primary : scheme.secondary,
                  ),
                ),
                const Spacer(),
                if (group.priorityLevel > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${Translations.getText('walkie_priority', lang)} ${group.priorityLevel}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.groupName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF101828),
                    ),
                  ),
                ),
                if (selected)
                  Container(
                    margin: const EdgeInsetsDirectional.only(start: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              group.description.isEmpty
                  ? Translations.getText('walkie_default_group_desc', lang)
                  : group.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _permissionChip(
                  context,
                  label: Translations.getText('walkie_can_listen', lang),
                  active: group.canListen,
                  icon: Icons.hearing_rounded,
                ),
                _permissionChip(
                  context,
                  label: Translations.getText('walkie_can_speak', lang),
                  active: group.canSpeak,
                  icon: Icons.mic_rounded,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionChip(
    BuildContext context, {
    required String label,
    required bool active,
    required IconData icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active
            ? scheme.primary.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: active ? scheme.primary : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: active ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomPanel(
    WalkieTalkieGroup group,
    ThemeData theme,
    ColorScheme scheme,
    String lang,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            context,
            title: group.groupName,
            subtitle: group.description.isEmpty
                ? Translations.getText('walkie_default_group_desc', lang)
                : group.description,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStatusBadge(theme, scheme, lang),
              _buildMiniStat(
                theme,
                scheme,
                Icons.people_alt_rounded,
                '${_participants.length}',
                Translations.getText('walkie_participants', lang),
              ),
              _buildMiniStat(
                theme,
                scheme,
                Icons.wifi_tethering_rounded,
                _token?.provider ?? 'LiveKit',
                Translations.getText('walkie_provider', lang),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _permissionChip(
                context,
                label: Translations.getText('walkie_can_initiate', lang),
                active: group.canInitiate,
                icon: Icons.call_rounded,
              ),
              _permissionChip(
                context,
                label: Translations.getText('walkie_can_speak', lang),
                active: group.canSpeak,
                icon: Icons.mic_rounded,
              ),
              _permissionChip(
                context,
                label: Translations.getText('walkie_can_listen', lang),
                active: group.canListen,
                icon: Icons.hearing_rounded,
              ),
            ],
          ),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 540;
              final connectButton = SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: (_isConnecting || _isConnected || !group.canListen)
                      ? null
                      : () => unawaited(_connectToGroup()),
                  icon: _isConnecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_calling_3_rounded),
                  label: Text(
                    _isConnecting
                        ? Translations.getText('walkie_connecting', lang)
                        : Translations.getText('walkie_connect', lang),
                  ),
                ),
              );

              final disconnectButton = SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: _isConnected
                      ? () => unawaited(_disconnect())
                      : null,
                  icon: const Icon(Icons.call_end_rounded),
                  label: Text(Translations.getText('walkie_disconnect', lang)),
                ),
              );

              if (stacked) {
                return Column(
                  children: [
                    connectButton,
                    const SizedBox(height: 12),
                    disconnectButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: connectButton),
                  const SizedBox(width: 12),
                  Expanded(child: disconnectButton),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: LinearGradient(
                colors: _isTalking
                    ? [
                        Colors.green.shade400.withValues(alpha: 0.16),
                        Colors.teal.shade300.withValues(alpha: 0.12),
                      ]
                    : [
                        const Color(0xFF155EEF).withValues(alpha: 0.08),
                        const Color(0xFF0EA5E9).withValues(alpha: 0.05),
                      ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              border: Border.all(
                color: _isTalking
                    ? Colors.green.withValues(alpha: 0.28)
                    : scheme.primary.withValues(alpha: 0.14),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final talkSize =
                    max(188.0, min(constraints.maxWidth * 0.62, 280.0));
                return Column(
                  children: [
                    Container(
                      width: talkSize,
                      height: talkSize,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: _isTalking
                              ? [Colors.green.shade500, Colors.teal.shade400]
                              : [
                                  const Color(0xFF155EEF),
                                  const Color(0xFF0EA5E9),
                                ],
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: (_isTalking
                                    ? Colors.green
                                    : const Color(0xFF155EEF))
                                .withValues(alpha: 0.26),
                            blurRadius: 36,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: GestureDetector(
                          onLongPressStart:
                              (_isConnected && (_token?.canPublish ?? false))
                                  ? (_) => unawaited(_startTalking())
                                  : null,
                          onLongPressEnd: _isConnected
                              ? (_) => unawaited(_stopTalking())
                              : null,
                              onLongPressCancel: _isConnected
                                  ? () => unawaited(_stopTalking())
                                  : null,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _isTalking
                                      ? Icons.graphic_eq_rounded
                                      : Icons.mic_rounded,
                                  color: Colors.white,
                                  size: talkSize * 0.24,
                                ),
                                const SizedBox(height: 16),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                  ),
                                  child: Text(
                                    _isTalking
                                        ? Translations.getText(
                                            'walkie_talking_now',
                                            lang,
                                          )
                                        : Translations.getText(
                                            'walkie_hold_to_talk',
                                            lang,
                                          ),
                                    textAlign: TextAlign.center,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _isTalking
                            ? Translations.getText('walkie_audio_live', lang)
                            : Translations.getText(
                                'walkie_press_and_hold_help',
                                lang,
                              ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF344054),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Translations.getText('walkie_session_info', lang),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF101828),
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final items = [
                      _buildSessionTile(
                        theme,
                        label: Translations.getText('walkie_provider', lang),
                        value: _token?.provider ?? 'LiveKit',
                        icon: Icons.hub_rounded,
                      ),
                      _buildSessionTile(
                        theme,
                        label: Translations.getText('walkie_room_name', lang),
                        value: _token?.roomName ??
                            Translations.getText(
                              'walkie_not_connected_yet',
                              lang,
                            ),
                        icon: Icons.meeting_room_rounded,
                      ),
                      _buildSessionTile(
                        theme,
                        label: Translations.getText('walkie_identity', lang),
                        value: _token?.identity ?? widget.employeeName,
                        icon: Icons.badge_rounded,
                      ),
                    ];

                    if (constraints.maxWidth >= 640) {
                      return Row(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            Expanded(child: items[i]),
                            if (i != items.length - 1)
                              const SizedBox(width: 12),
                          ],
                        ],
                      );
                    }

                    return Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          items[i],
                          if (i != items.length - 1)
                            const SizedBox(height: 12),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildSectionHeader(
            context,
            title: Translations.getText('walkie_participants', lang),
            subtitle: _participants.isEmpty
                ? Translations.getText('walkie_no_participants', lang)
                : '${_participants.length}',
          ),
          const SizedBox(height: 12),
          if (_participants.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.30),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                Translations.getText('walkie_no_participants', lang),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else
            ..._participants.map((participant) {
              final isLocal = participant is LocalParticipant;
              final hasAudio = participant.hasAudio;
              final speaking = participant.isSpeaking;
                  final title = _participantTitle(participant);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: speaking
                        ? Colors.green.withValues(alpha: 0.55)
                        : scheme.outlineVariant,
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: speaking
                          ? Colors.green.withValues(alpha: 0.16)
                          : scheme.primary.withValues(alpha: 0.12),
                      child: Icon(
                        speaking ? Icons.graphic_eq_rounded : Icons.person,
                        color:
                            speaking ? Colors.green.shade700 : scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isLocal
                                ? Translations.getText('walkie_you', lang)
                                : Translations.getText('walkie_remote', lang),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: speaking
                            ? Colors.green.withValues(alpha: 0.12)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        speaking
                            ? Translations.getText('walkie_audio_live', lang)
                            : hasAudio
                                ? Translations.getText(
                                    'walkie_audio_muted',
                                    lang,
                                  )
                                : Translations.getText(
                                    'walkie_listening_only',
                                    lang,
                                  ),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: speaking
                              ? Colors.green.shade700
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(ThemeData theme, ColorScheme scheme, String lang) {
    final active = _isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: active
            ? Colors.green.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            active ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 18,
            color: active ? Colors.green.shade700 : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(
            active
                ? Translations.getText('walkie_status_connected', lang)
                : Translations.getText('walkie_status_ready', lang),
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: active ? Colors.green.shade700 : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
    ThemeData theme,
    ColorScheme scheme,
    IconData icon,
    String value,
    String label,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF101828),
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSessionTile(
    ThemeData theme, {
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF155EEF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF155EEF), size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: const Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF101828),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String lang) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.portable_wifi_off_rounded,
              size: 64,
              color: scheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              Translations.getText('walkie_empty_title', lang),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF101828),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              Translations.getText('walkie_empty_desc', lang),
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String lang) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_rounded,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              Translations.getText('walkie_load_error', lang),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF101828),
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.6),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => unawaited(_loadGroups()),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(Translations.getText('reload', lang)),
            ),
          ],
        ),
      ),
    );
  }
}
