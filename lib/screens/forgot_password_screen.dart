import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/language_service.dart';
import '../services/translations.dart';
import 'login_screen.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;

  // Controllers
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _nextPage() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() {
      _currentStep++;
      _errorMessage = null;
    });
  }

  void _previousPage() {
    _pageController.previousPage(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() {
      _currentStep--;
      _errorMessage = null;
    });
  }

  Future<void> _handleSendOTP() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = Translations.getText('error_invalid_email', _getLang()));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.forgotPassword(email);
      if (response['success'] == true) {
        // للتطوير: عرض OTP من الاستجابة
        String otpFromServer = response['otp']?.toString() ?? '';
        String debugMessage = response['debug_message']?.toString() ?? '';
        
        _nextPage();
        
        // عرض OTP في SnackBar للتطوير
        if (otpFromServer.isNotEmpty) {
          _showSnackBar(
            '✅ $debugMessage',
            Colors.green,
          );
          // ملء حقل OTP تلقائياً للتطوير
          _otpController.text = otpFromServer;
        } else {
          _showSnackBar(Translations.getText('otp_sent_success', _getLang()), Colors.green);
        }
      } else {
        setState(() => _errorMessage = response['message']);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleVerifyOTP() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      setState(() => _errorMessage = Translations.getText('enter_verification_code', _getLang()));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.verifyOTP(_emailController.text.trim(), otp);
      if (response['success'] == true) {
        _nextPage();
      } else {
        setState(() => _errorMessage = response['message']);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResetPassword() async {
    final newPass = _newPasswordController.text;
    final confirmPass = _confirmPasswordController.text;

    if (newPass.length < 6) {
      setState(() => _errorMessage = Translations.getText('password_too_short', _getLang()));
      return;
    }
    if (newPass != confirmPass) {
      setState(() => _errorMessage = Translations.getText('password_mismatch', _getLang()));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await ApiService.resetPassword(
        email: _emailController.text.trim(),
        otp: _otpController.text.trim(),
        newPassword: newPass,
        confirmPassword: confirmPass,
      );

      if (response['success'] == true) {
        _showSnackBar(Translations.getText('password_reset_success', _getLang()), Colors.green);
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
      } else {
        setState(() => _errorMessage = response['message']);
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getLang() {
    return Provider.of<LanguageService>(context, listen: false).currentLocale.languageCode;
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = _getLang();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(Translations.getText('forgot_password_title', lang)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _currentStep == 0 ? () => Navigator.pop(context) : _previousPage,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Linear Progress Indicator
            LinearProgressIndicator(
              value: (_currentStep + 1) / 3,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildEmailStep(lang),
                  _buildOTPStep(lang),
                  _buildResetStep(lang),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep(String lang) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            Translations.getText('enter_email_to_reset', lang),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: Translations.getText('email', lang),
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
          if (_errorMessage != null && _currentStep == 0) _buildError(),
          const Spacer(),
          _buildButton(Translations.getText('send_otp', lang), _handleSendOTP),
        ],
      ),
    );
  }

  Widget _buildOTPStep(String lang) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            Translations.getText('enter_verification_code', lang),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '${Translations.getText('otp_sent_success', lang)}: ${_emailController.text}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              labelText: Translations.getText('verification_code', lang),
              hintText: '000000',
              counterText: '',
            ),
          ),
          if (_errorMessage != null && _currentStep == 1) _buildError(),
          const Spacer(),
          _buildButton(Translations.getText('verify_and_continue', lang), _handleVerifyOTP),
        ],
      ),
    );
  }

  Widget _buildResetStep(String lang) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            Translations.getText('reset_password_title', lang),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _newPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: Translations.getText('new_password', lang),
              hintText: Translations.getText('new_password_hint', lang),
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _confirmPasswordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: Translations.getText('confirm_new_password', lang),
              hintText: Translations.getText('confirm_new_password_hint', lang),
              prefixIcon: const Icon(Icons.lock_reset),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            Translations.getText('password_tips', lang),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          if (_errorMessage != null && _currentStep == 2) _buildError(),
          const Spacer(),
          _buildButton(Translations.getText('submit', lang), _handleResetPassword),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButton(String text, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: _isLoading ? null : onPressed,
        child: _isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
