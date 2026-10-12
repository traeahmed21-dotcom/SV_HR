import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_policy.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';

class AppUpdateGate extends StatefulWidget {
  final Widget child;

  const AppUpdateGate({super.key, required this.child});

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _isChecking = false;
  bool _dialogVisible = false;
  String? _lastOptionalPromptVersion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForAppUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkForAppUpdate();
    }
  }

  Future<void> _checkForAppUpdate() async {
    if (!mounted || _isChecking || _dialogVisible) {
      return;
    }

    _isChecking = true;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final buildNumber = packageInfo.buildNumber.trim();
      final currentVersion = buildNumber.isEmpty
          ? packageInfo.version.trim()
          : '${packageInfo.version.trim()}+$buildNumber';

      final policy = await ApiService.getAppUpdatePolicy(
        currentVersion: currentVersion,
        platform: _resolvePlatformName(),
      );

      if (!mounted ||
          policy == null ||
          !policy.enabled ||
          !policy.shouldShow ||
          policy.updateUrl.trim().isEmpty) {
        return;
      }

      if (!policy.isForceUpdate &&
          _lastOptionalPromptVersion == policy.latestVersion) {
        return;
      }

      if (!policy.isForceUpdate) {
        _lastOptionalPromptVersion = policy.latestVersion;
      }

      _dialogVisible = true;
      await _showUpdateDialog(policy);
    } finally {
      _dialogVisible = false;
      _isChecking = false;
    }
  }

  String _resolvePlatformName() {
    if (kIsWeb) return 'android';

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.android:
      default:
        return 'android';
    }
  }

  Future<void> _showUpdateDialog(AppUpdatePolicy policy) async {
    final lang = context.read<LanguageService>().currentLocale.languageCode;

    await showDialog<void>(
      context: context,
      barrierDismissible: !policy.isForceUpdate,
      builder: (dialogContext) {
        return PopScope(
          canPop: !policy.isForceUpdate,
          child: AlertDialog(
            title: Text(policy.titleFor(lang)),
            content: Text(policy.messageFor(lang)),
            actions: [
              if (!policy.isForceUpdate)
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(policy.laterButtonFor(lang)),
                ),
              if (policy.isForceUpdate)
                TextButton(
                  onPressed: () async {
                    Navigator.of(dialogContext).pop();
                    await _closeApplication();
                  },
                  child: Text(policy.exitButtonFor(lang)),
                ),
              ElevatedButton(
                onPressed: () async {
                  final launched = await _launchUpdateUrl(policy.updateUrl);
                  if (launched && dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                  }
                },
                child: Text(policy.updateButtonFor(lang)),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<bool> _launchUpdateUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) {
      return false;
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _closeApplication() async {
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
