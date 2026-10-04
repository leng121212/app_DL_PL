import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/license_service.dart';
import '../theme/app_theme.dart';
import '../utils/url_helper.dart';

class LicenseDialog extends StatefulWidget {
  const LicenseDialog({super.key});

  @override
  State<LicenseDialog> createState() => _LicenseDialogState();
}

class _LicenseDialogState extends State<LicenseDialog> {
  final LicenseService _licenseService = LicenseService.instance;
  bool _isLoggingIn = false;
  String? _statusMessage;

  void _startGoogleLogin() async {
    setState(() {
      _isLoggingIn = true;
      _statusMessage = 'កំពុងរៀបចំការចូលគណនី...';
    });

    final info = await _licenseService.startLogin();
    if (info == null) {
      setState(() {
        _isLoggingIn = false;
        _statusMessage = 'មិនអាចភ្ជាប់ទៅកាន់ម៉ាស៊ីនបម្រើ License បានទេ';
      });
      return;
    }

    final launched = await openSafeUrl(info.loginUrl);

    setState(() {
      if (launched) {
        _statusMessage = 'សូមបំពេញការចូលគណនីក្នុងកម្មវិធីរុករក (Browser)...\nកំពុងរង់ចាំការបញ្ជាក់...';
      } else {
        _statusMessage = 'សូមបើកកម្មវិធីរុករកដើម្បីភ្ជាប់ជាមួយគណនី Gmail...';
      }
    });

    // Poll for completion
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final ok = await _licenseService.pollLogin(info);
      if (ok) {
        setState(() {
          _isLoggingIn = false;
          _statusMessage = 'ការចូលគណនីជោគជ័យ!';
        });
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) Navigator.pop(context);
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLoggingIn = false;
        _statusMessage = 'ផុតកំណត់ពេលរង់ចាំ សូមសាកល្បងម្ដងទៀត';
      });
    }
  }

  void _contactTelegram() async {
    await openSafeUrl(LicenseService.contactUrl);
  }

  @override
  Widget build(BuildContext context) {
    final state = _licenseService.state;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: AppTheme.bgDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.cardBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.cyanAccent.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Trabekprey Branding Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/Trabekprey_DL_App.png',
                width: 68,
                height: 68,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/Trabekprey.png',
                  width: 68,
                  height: 68,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.verified_user,
                    size: 68,
                    color: AppTheme.cyanAccent,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Trabekprey-DL Pro License',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'ប្រព័ន្ធអាជ្ញាប័ណ្ណប្រើប្រាស់ និងសមាជិក',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 18),

            // Status Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: state.isLoggedIn ? AppTheme.greenSuccess : AppTheme.amberWarning,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    state.isLoggedIn ? Icons.check_circle : Icons.warning_amber_rounded,
                    color: state.isLoggedIn ? AppTheme.greenSuccess : AppTheme.amberWarning,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.isLoggedIn ? 'អាជ្ញាប័ណ្ណសកម្ម (Active)' : 'មិនទាន់ចូលគណនី (Inactive)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: state.isLoggedIn ? AppTheme.greenSuccess : AppTheme.amberWarning,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.isLoggedIn
                              ? '${state.email}\nនៅសល់: ${state.remainingDays} ថ្ងៃ'
                              : 'សូមចូលគណនី Google ដើម្បីប្រើប្រាស់មុខងារពេញលេញ',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _statusMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: AppTheme.cyanAccent),
              ),
            ],

            const SizedBox(height: 20),

            // Action Buttons
            if (!state.isLoggedIn) ...[
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: _isLoggingIn ? null : _startGoogleLogin,
                  icon: Image.asset(
                    'assets/google_logo.png',
                    width: 20,
                    height: 20,
                    errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, color: Colors.white),
                  ),
                  label: _isLoggingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Continue with Google',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: Color(0xFF334155)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ] else ...[
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _licenseService.logout();
                    setState(() {});
                  },
                  icon: const Icon(Icons.logout, size: 16, color: AppTheme.redDanger),
                  label: const Text('ចាកចេញពីគណនី (Logout)', style: TextStyle(color: AppTheme.redDanger, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.redDanger.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Telegram Contact Support
            SizedBox(
              width: double.infinity,
              height: 42,
              child: TextButton.icon(
                onPressed: _contactTelegram,
                icon: const Icon(Icons.telegram, size: 18, color: Color(0xFF24A1DE)),
                label: const Text(
                  'ទាក់ទង Admin / ទិញ License (Telegram)',
                  style: TextStyle(fontSize: 12.5, color: Color(0xFF24A1DE)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
