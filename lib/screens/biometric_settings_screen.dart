import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';
import '../services/biometric_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';

class BiometricSettingsScreen extends StatefulWidget {
  const BiometricSettingsScreen({super.key});

  @override
  State<BiometricSettingsScreen> createState() =>
      _BiometricSettingsScreenState();
}

class _BiometricSettingsScreenState extends State<BiometricSettingsScreen> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _isLoading = true;
  bool _canCheckBiometrics = false;
  bool _isDeviceSupported = false;
  List<BiometricType> _availableBiometrics = [];
  String? _errorMessage;

  String _lang() => Provider.of<LanguageService>(context, listen: false)
      .currentLocale
      .languageCode;

  String _t(String key) => Translations.getText(key, _lang());

  String _tParams(String key, Map<String, String> params) =>
      Translations.getTextWithParams(key, _lang(), params);

  // دالة تسجيل الأحداث للتطوير
  void _log(String message) {
    if (kDebugMode) {
      print(message);
    }
  }

  @override
  void initState() {
    super.initState();
    _checkBiometricStatus();
  }

  Future<void> _checkBiometricStatus() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      _log('🔍 فحص حالة البصمة...');

      // التحقق من إمكانية فحص البصمة
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      _log('🔍 canCheckBiometrics: $canCheckBiometrics');

      // التحقق من دعم الجهاز
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      _log('🔍 isDeviceSupported: $isDeviceSupported');

      // جلب أنواع البصمة المتوفرة
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      _log('🔍 availableBiometrics: $availableBiometrics');

      setState(() {
        _canCheckBiometrics = canCheckBiometrics;
        _isDeviceSupported = isDeviceSupported;
        _availableBiometrics = availableBiometrics;
        _isLoading = false;
      });
    } catch (e) {
      _log('💥 خطأ في فحص حالة البصمة: $e');
      setState(() {
        _errorMessage =
            _tParams('error_checking_biometric_with_error', {'error': e.toString()});
        _isLoading = false;
      });
    }
  }

  String _getBiometricTypeName(BiometricType type) {
    switch (type) {
      case BiometricType.fingerprint:
        return _t('biometric_type_fingerprint');
      case BiometricType.face:
        return _t('biometric_type_face');
      case BiometricType.iris:
        return _t('biometric_type_iris');
      default:
        return type.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageService>().currentLocale.languageCode;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('biometric_settings', lang)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkBiometricStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_errorMessage != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: scheme.error.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),

                  // حالة الجهاز
                  _buildStatusCard(),
                  const SizedBox(height: 16),

                  // أنواع البصمة المتوفرة
                  _buildAvailableBiometricsCard(),
                  const SizedBox(height: 16),

                  // تعليمات التفعيل
                  _buildInstructionsCard(),
                  const SizedBox(height: 16),

                  // اختبار البصمة
                  _buildTestCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('device_status'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildStatusRow(
              _t('device_supports_biometrics'),
              _isDeviceSupported,
              Icons.phone_android,
            ),
            _buildStatusRow(
              _t('biometric_available'),
              _canCheckBiometrics,
              Icons.fingerprint,
            ),
            _buildStatusRow(
              _t('overall_status'),
              _canCheckBiometrics && _isDeviceSupported,
              Icons.check_circle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String title, bool status, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            color: status ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: status ? Colors.green.shade100 : Colors.red.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status ? _t('available') : _t('not_available'),
              style: TextStyle(
                color: status ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableBiometricsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('available_biometric_types'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (_availableBiometrics.isEmpty)
              Text(
                _t('no_biometric_types_available'),
                style: const TextStyle(
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ..._availableBiometrics.map((type) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _getBiometricTypeName(type),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('enable_biometric_instructions'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            if (!_isDeviceSupported)
              _buildInstructionItem(
                _t('instruction_device_support_title'),
                _t('instruction_device_support_subtitle'),
                Icons.warning,
                Colors.orange,
              )
            else if (!_canCheckBiometrics)
              _buildInstructionItem(
                _t('instruction_go_to_settings_title'),
                _t('instruction_go_to_settings_subtitle'),
                Icons.settings,
                Colors.blue,
              )
            else if (_availableBiometrics.isEmpty)
              _buildInstructionItem(
                _t('instruction_setup_biometric_title'),
                _t('instruction_setup_biometric_subtitle'),
                Icons.fingerprint,
                Colors.green,
              )
            else
              _buildInstructionItem(
                _t('instruction_biometric_ready_title'),
                _t('instruction_biometric_ready_subtitle'),
                Icons.check_circle,
                Colors.green,
              ),
            const SizedBox(height: 8),
            _buildInstructionItem(
              _t('instruction_add_biometric_title'),
              _t('instruction_add_biometric_subtitle'),
              Icons.add_circle,
              Colors.blue,
            ),
            const SizedBox(height: 8),
            _buildInstructionItem(
              _t('instruction_return_and_try_title'),
              _t('instruction_return_and_try_subtitle'),
              Icons.arrow_back,
              Colors.green,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionItem(
      String title, String subtitle, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('biometric_test'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _t('press_button_to_test_biometric'),
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _canCheckBiometrics ? _testBiometric : null,
                icon: const Icon(Icons.fingerprint),
                label: Text(
                  _t('test_biometric_button'),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testBiometric() async {
    try {
      final result = await BiometricService.authenticateForAttendance(
        isCheckIn: true,
        employeeName: _t('test'),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result
                  ? _t('biometric_test_success')
                  : _t('biometric_test_failed'),
            ),
            backgroundColor: result ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tParams('biometric_test_error_with_error', {'error': e.toString()}),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
