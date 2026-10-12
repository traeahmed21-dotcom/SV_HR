class AppUpdatePolicy {
  final bool enabled;
  final bool shouldShow;
  final bool isForceUpdate;
  final String mode;
  final String platform;
  final String currentVersion;
  final String latestVersion;
  final String minimumSupportedVersion;
  final String updateUrl;
  final String titleAr;
  final String messageAr;
  final String updateButtonAr;
  final String laterButtonAr;
  final String exitButtonAr;
  final String titleEn;
  final String messageEn;
  final String updateButtonEn;
  final String laterButtonEn;
  final String exitButtonEn;

  const AppUpdatePolicy({
    required this.enabled,
    required this.shouldShow,
    required this.isForceUpdate,
    required this.mode,
    required this.platform,
    required this.currentVersion,
    required this.latestVersion,
    required this.minimumSupportedVersion,
    required this.updateUrl,
    required this.titleAr,
    required this.messageAr,
    required this.updateButtonAr,
    required this.laterButtonAr,
    required this.exitButtonAr,
    required this.titleEn,
    required this.messageEn,
    required this.updateButtonEn,
    required this.laterButtonEn,
    required this.exitButtonEn,
  });

  String titleFor(String lang) => lang == 'ar' ? titleAr : titleEn;
  String messageFor(String lang) => lang == 'ar' ? messageAr : messageEn;
  String updateButtonFor(String lang) =>
      lang == 'ar' ? updateButtonAr : updateButtonEn;
  String laterButtonFor(String lang) =>
      lang == 'ar' ? laterButtonAr : laterButtonEn;
  String exitButtonFor(String lang) =>
      lang == 'ar' ? exitButtonAr : exitButtonEn;

  factory AppUpdatePolicy.fromJson(Map<String, dynamic> json) {
    bool toBool(dynamic value) {
      if (value == null) return false;
      if (value is bool) return value;
      if (value is num) return value != 0;
      final normalized = value.toString().trim().toLowerCase();
      return normalized == 'true' ||
          normalized == '1' ||
          normalized == 'yes' ||
          normalized == 'y';
    }

    String toStringValue(dynamic value, [String fallback = '']) {
      if (value == null) return fallback;
      final result = value.toString().trim();
      return result.isEmpty ? fallback : result;
    }

    return AppUpdatePolicy(
      enabled: toBool(json['Enabled'] ?? json['enabled']),
      shouldShow: toBool(json['ShouldShow'] ?? json['shouldShow']),
      isForceUpdate: toBool(json['IsForceUpdate'] ?? json['isForceUpdate']),
      mode: toStringValue(json['Mode'] ?? json['mode'], 'optional'),
      platform: toStringValue(json['Platform'] ?? json['platform'], 'android'),
      currentVersion:
          toStringValue(json['CurrentVersion'] ?? json['currentVersion']),
      latestVersion:
          toStringValue(json['LatestVersion'] ?? json['latestVersion']),
      minimumSupportedVersion: toStringValue(
          json['MinimumSupportedVersion'] ?? json['minimumSupportedVersion']),
      updateUrl: toStringValue(json['UpdateUrl'] ?? json['updateUrl']),
      titleAr:
          toStringValue(json['TitleAr'] ?? json['titleAr'], 'يوجد تحديث جديد'),
      messageAr: toStringValue(json['MessageAr'] ?? json['messageAr'],
          'تم إصدار نسخة أحدث من التطبيق تحتوي على تحسينات مهمة.'),
      updateButtonAr: toStringValue(
          json['UpdateButtonAr'] ?? json['updateButtonAr'], 'تحديث الآن'),
      laterButtonAr: toStringValue(
          json['LaterButtonAr'] ?? json['laterButtonAr'], 'لاحقاً'),
      exitButtonAr: toStringValue(
          json['ExitButtonAr'] ?? json['exitButtonAr'], 'إغلاق التطبيق'),
      titleEn: toStringValue(
          json['TitleEn'] ?? json['titleEn'], 'A new update is available'),
      messageEn: toStringValue(json['MessageEn'] ?? json['messageEn'],
          'A newer app version is available with important improvements.'),
      updateButtonEn: toStringValue(
          json['UpdateButtonEn'] ?? json['updateButtonEn'], 'Update now'),
      laterButtonEn: toStringValue(
          json['LaterButtonEn'] ?? json['laterButtonEn'], 'Later'),
      exitButtonEn: toStringValue(
          json['ExitButtonEn'] ?? json['exitButtonEn'], 'Exit app'),
    );
  }
}
