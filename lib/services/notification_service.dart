import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class NotificationService {
  static const int walkieNotificationId = 41021;
  static const String _androidNotificationIcon = '@mipmap/launcher_icon';
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  // دالة تسجيل الأحداث للتطوير
  void _log(String message) {
    if (kDebugMode) {
      print('🔔 [NotificationService] $message');
    }
  }

  /// تهيئة خدمة الإشعارات
  Future<void> initialize() async {
    if (kIsWeb) return;
    try {
      _log('🔄 جاري تهيئة خدمة الإشعارات...');

      // إعدادات Android
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings(_androidNotificationIcon);

      // إعدادات iOS
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      // إعدادات التهيئة العامة
      const InitializationSettings initializationSettings =
          InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      // تهيئة الإشعارات
      await _notifications.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _log('✅ تم تهيئة خدمة الإشعارات بنجاح');
    } catch (e) {
      _log('❌ خطأ في تهيئة خدمة الإشعارات: $e');
    }
  }

  /// معالج النقر على الإشعار
  void _onNotificationTapped(NotificationResponse response) {
    _log('👆 تم النقر على الإشعار: ${response.payload}');
    // يمكن إضافة منطق إضافي هنا للتعامل مع النقر على الإشعار
  }

  /// إرسال إشعار نجاح تسجيل الحضور
  Future<void> showCheckInSuccessNotification({
    required String employeeName,
    required String time,
    required String location,
  }) async {
    if (kIsWeb) return;
    try {
      _log('🔔 إرسال إشعار نجاح تسجيل الحضور');

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'attendance_channel',
        'إشعارات الحضور والانصراف',
        channelDescription: 'إشعارات خاصة بتسجيل الحضور والانصراف',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        enableLights: true,
        color: Color(0xFF0EA5E9),
        icon: _androidNotificationIcon,
        largeIcon: DrawableResourceAndroidBitmap(_androidNotificationIcon),
        styleInformation: BigTextStyleInformation(''),
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _notifications.show(
        1, // معرف فريد للإشعار
        '✅ تم تسجيل الحضور بنجاح',
        'تم تسجيل حضور $employeeName في الساعة $time\nالموقع: $location',
        platformChannelSpecifics,
        payload: 'checkin_success',
      );

      _log('✅ تم إرسال إشعار نجاح تسجيل الحضور');
    } catch (e) {
      _log('❌ خطأ في إرسال إشعار نجاح تسجيل الحضور: $e');
    }
  }

  /// إرسال إشعار نجاح تسجيل الإنصراف
  Future<void> showCheckOutSuccessNotification({
    required String employeeName,
    required String time,
    required String location,
  }) async {
    if (kIsWeb) return;
    try {
      _log('🔔 إرسال إشعار نجاح تسجيل الإنصراف');

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'attendance_channel',
        'إشعارات الحضور والانصراف',
        channelDescription: 'إشعارات خاصة بتسجيل الحضور والانصراف',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        enableLights: true,
        color: Color(0xFF0EA5E9),
        icon: _androidNotificationIcon,
        largeIcon: DrawableResourceAndroidBitmap(_androidNotificationIcon),
        styleInformation: BigTextStyleInformation(''),
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _notifications.show(
        2, // معرف فريد للإشعار
        '✅ تم تسجيل الإنصراف بنجاح',
        'تم تسجيل انصراف $employeeName في الساعة $time\nالموقع: $location',
        platformChannelSpecifics,
        payload: 'checkout_success',
      );

      _log('✅ تم إرسال إشعار نجاح تسجيل الإنصراف');
    } catch (e) {
      _log('❌ خطأ في إرسال إشعار نجاح تسجيل الإنصراف: $e');
    }
  }

  /// إرسال إشعار خطأ
  Future<void> showErrorNotification({
    required String title,
    required String message,
  }) async {
    if (kIsWeb) return;
    try {
      _log('🔔 إرسال إشعار خطأ');

      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'attendance_channel',
        'إشعارات الحضور والانصراف',
        channelDescription: 'إشعارات خاصة بتسجيل الحضور والانصراف',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        enableLights: true,
        color: Color(0xFFEF4444),
        icon: _androidNotificationIcon,
        largeIcon: DrawableResourceAndroidBitmap(_androidNotificationIcon),
        styleInformation: BigTextStyleInformation(''),
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _notifications.show(
        3, // معرف فريد للإشعار
        title,
        message,
        platformChannelSpecifics,
        payload: 'error',
      );

      _log('✅ تم إرسال إشعار الخطأ');
    } catch (e) {
      _log('❌ خطأ في إرسال إشعار الخطأ: $e');
    }
  }

  /// إرسال إشعار محلي لرسائل الدردشة أثناء فتح التطبيق
  Future<void> showChatMessageNotification({
    required String title,
    required String message,
  }) async {
    if (kIsWeb) return;
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'chat_channel',
        'إشعارات الدردشة',
        channelDescription: 'إشعارات الرسائل الجديدة داخل النظام',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: true,
        enableLights: true,
        color: Color(0xFF4F46E5),
        icon: _androidNotificationIcon,
        largeIcon: DrawableResourceAndroidBitmap(_androidNotificationIcon),
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'default',
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.remainder(100000),
        title,
        message,
        platformChannelSpecifics,
        payload: 'chat_message',
      );
    } catch (e) {
      _log('❌ خطأ في إرسال إشعار الدردشة: $e');
    }
  }

  /// إرسال إشعار دائم لحالة الووكي-توكي
  Future<void> showWalkiePersistentNotification({
    required String title,
    required String message,
  }) async {
    if (kIsWeb) return;
    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
        'walkie_persistent_channel',
        'إشعارات الووكي-توكي',
        channelDescription: 'إشعار دائم يوضح أن جلسة الووكي-توكي ما زالت متصلة',
        importance: Importance.low,
        priority: Priority.low,
        showWhen: false,
        enableVibration: false,
        playSound: false,
        silent: true,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        category: AndroidNotificationCategory.service,
        visibility: NotificationVisibility.public,
        icon: _androidNotificationIcon,
        largeIcon: DrawableResourceAndroidBitmap(_androidNotificationIcon),
      );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      await _notifications.show(
        walkieNotificationId,
        title,
        message,
        platformChannelSpecifics,
        payload: 'walkie_persistent',
      );
    } catch (e) {
      _log('❌ خطأ في إرسال إشعار الووكي-توكي الدائم: $e');
    }
  }

  Future<void> cancelWalkiePersistentNotification() async {
    if (kIsWeb) return;
    try {
      await _notifications.cancel(walkieNotificationId);
    } catch (e) {
      _log('❌ خطأ في إلغاء إشعار الووكي-توكي الدائم: $e');
    }
  }

  /// إلغاء جميع الإشعارات
  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
    try {
      await _notifications.cancelAll();
      _log('✅ تم إلغاء جميع الإشعارات');
    } catch (e) {
      _log('❌ خطأ في إلغاء الإشعارات: $e');
    }
  }

  /// إلغاء إشعار محدد
  Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      _log('✅ تم إلغاء الإشعار رقم $id');
    } catch (e) {
      _log('❌ خطأ في إلغاء الإشعار: $e');
    }
  }
}
