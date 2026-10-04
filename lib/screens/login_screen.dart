import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/license_service.dart';
import '../theme/app_theme.dart';
import '../utils/url_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final LicenseService _licenseService = LicenseService.instance;
  bool _isLoggingIn = false;
  bool _isCheckingNow = false;
  String? _statusMessage;
  String? _errorMessage;
  AuthSessionInfo? _currentInfo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restorePendingSession();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _restorePendingSession() async {
    final pending = await _licenseService.loadPendingSession();
    if (pending != null && mounted) {
      setState(() {
        _currentInfo = pending;
        _isLoggingIn = true;
        _statusMessage = 'កំពុងពិនិត្យការបញ្ជាក់ពី Google...';
      });
      _checkNow();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_currentInfo != null || _isLoggingIn) {
        _checkNow();
      } else {
        _restorePendingSession();
      }
    }
  }

  Future<void> _checkNow() async {
    if (_isCheckingNow) return;
    if (_currentInfo == null) {
      _currentInfo = await _licenseService.loadPendingSession();
      if (_currentInfo == null) return;
    }

    if (_licenseService.state.isLoggedIn) {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
          _statusMessage = 'ការចូលគណនីជោគជ័យ! កំពុងបើកកម្មវិធី...';
        });
      }
      return;
    }

    _isCheckingNow = true;
    if (mounted) {
      setState(() {
        _statusMessage = 'កំពុងពិនិត្យការបញ្ជាក់ពី Google...';
      });
    }

    try {
      final ok = await _licenseService.pollLogin(_currentInfo!);
      if (ok || _licenseService.state.isLoggedIn) {
        if (mounted) {
          setState(() {
            _isLoggingIn = false;
            _statusMessage = 'ការចូលគណនីជោគជ័យ! កំពុងបើកកម្មវិធី...';
          });
        }
        await _licenseService.clearPendingSession();
        return;
      }
      if (_licenseService.state.denialMessage != null) {
        if (mounted) {
          setState(() {
            _isLoggingIn = false;
            _errorMessage = _licenseService.state.denialMessage;
            _statusMessage = null;
          });
        }
        await _licenseService.clearPendingSession();
        return;
      }
    } catch (_) {
      // Don't kill state on network hiccup during app switch
    } finally {
      if (mounted) {
        _isCheckingNow = false;
      }
    }
  }

  void _cancelLogin() {
    setState(() {
      _isLoggingIn = false;
      _statusMessage = null;
      _currentInfo = null;
    });
    _licenseService.clearPendingSession();
  }

  void _startGoogleLogin() async {
    setState(() {
      _isLoggingIn = true;
      _errorMessage = null;
      _statusMessage = 'កំពុងរៀបចំការចូលគណនី...';
    });

    final info = await _licenseService.startLogin();
    if (info == null) {
      if (mounted) {
        setState(() {
          _isLoggingIn = false;
          _errorMessage = 'មិនអាចភ្ជាប់ទៅកាន់ម៉ាស៊ីនបម្រើ License បានទេ។ សូមពិនិត្យមើលអ៊ីនធឺណិតទូរសព្ទ។';
          _statusMessage = null;
        });
      }
      return;
    }

    _currentInfo = info;
    final launched = await openSafeUrl(info.loginUrl);

    if (mounted) {
      setState(() {
        if (launched) {
          _statusMessage = 'សូមជ្រើសរើស Gmail របស់អ្នកក្នុង Browser...\nពេលរួចរាល់ សូមត្រឡប់មកកម្មវិធីវិញ';
        } else {
          _statusMessage = 'សូមចុចប៊ូតុង "បើក Browser ផ្ទាល់" ឬ "ចម្លង Link" ខាងក្រោម ដើម្បីជ្រើសរើស Gmail៖';
        }
      });
    }

    // Poll for completion (up to 120 attempts = 240 seconds)
    for (int i = 0; i < 120; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      if (_licenseService.state.isLoggedIn) {
        setState(() {
          _isLoggingIn = false;
          _statusMessage = 'ការចូលគណនីជោគជ័យ! កំពុងបើកកម្មវិធី...';
        });
        await _licenseService.clearPendingSession();
        return;
      }

      // Avoid collision if _checkNow is currently running
      if (_isCheckingNow) {
        continue;
      }

      final ok = await _licenseService.pollLogin(info);
      if (ok || _licenseService.state.isLoggedIn) {
        if (mounted) {
          setState(() {
            _isLoggingIn = false;
            _statusMessage = 'ការចូលគណនីជោគជ័យ! កំពុងបើកកម្មវិធី...';
          });
        }
        await _licenseService.clearPendingSession();
        return;
      }

      // If server explicitly denied (e.g. DEVICE_MISMATCH or NO_LICENSE)
      if (_licenseService.state.denialMessage != null) {
        if (mounted) {
          setState(() {
            _isLoggingIn = false;
            _errorMessage = _licenseService.state.denialMessage;
            _statusMessage = null;
          });
        }
        await _licenseService.clearPendingSession();
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLoggingIn = false;
        _errorMessage = 'ផុតកំណត់ពេលរង់ចាំ។ សូមចុចសាកល្បងម្ដងទៀត។';
        _statusMessage = null;
      });
    }
    await _licenseService.clearPendingSession();
  }

  void _contactTelegram() async {
    await openSafeUrl(LicenseService.contactUrl);
  }

  @override
  Widget build(BuildContext context) {
    final state = _licenseService.state;
    final displayError = _errorMessage ?? state.denialMessage;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.2,
            colors: [
              Color(0xFF132342),
              Color(0xFF090D16),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Icon / Logo
                  Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.cyanAccent.withOpacity(0.25),
                          blurRadius: 24,
                          spreadRadius: 2,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Image.asset(
                        'assets/Trabekprey_DL_App.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/Trabekprey.png',
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.download_for_offline_rounded,
                            size: 80,
                            color: AppTheme.cyanAccent,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // App Title
                  const Text(
                    'Trabekprey-DL Pro',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Subtitle
                  const Text(
                    'កម្មវិធីទាញយករឿងខ្លីចិន (Hongguo & 20+ Web)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Single Device Notice Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16233B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.devices_other, size: 16, color: AppTheme.cyanAccent),
                        SizedBox(width: 8),
                        Text(
                          'គណនី ១ ប្រើប្រាស់បានតែលើ ១ Device ប៉ុណ្ណោះ',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.cyanAccent,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Error / Denial Message Box
                  if (displayError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38121A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.redDanger.withOpacity(0.6)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: AppTheme.redDanger, size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              displayError,
                              style: const TextStyle(
                                color: Color(0xFFFECDD3),
                                fontSize: 12.5,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Waiting Status Message Box
                  if (_statusMessage != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F2636),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.cyanAccent.withOpacity(0.5)),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.cyanAccent),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _statusMessage!,
                                  style: const TextStyle(
                                    color: Color(0xFFA5F3FC),
                                    fontSize: 12,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_currentInfo != null) ...[
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: SizedBox(
                                    height: 38,
                                    child: ElevatedButton.icon(
                                      onPressed: () => openSafeUrl(_currentInfo!.loginUrl),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppTheme.cyanAccent,
                                        foregroundColor: const Color(0xFF041019),
                                        elevation: 2,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      icon: const Icon(Icons.open_in_browser, size: 18),
                                      label: const Text(
                                        'បើក Browser ផ្ទាល់',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 2,
                                  child: SizedBox(
                                    height: 38,
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: _currentInfo!.loginUrl));
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('បានចម្លង Link រួចរាល់! លោកអ្នកអាចយកទៅបើកក្នុង Browser ណាដែលអ្នកចង់បាន'),
                                            duration: Duration(seconds: 3),
                                            backgroundColor: Color(0xFF0F2636),
                                          ),
                                        );
                                      },
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppTheme.cyanAccent,
                                        side: BorderSide(color: AppTheme.cyanAccent.withOpacity(0.5)),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                      ),
                                      icon: const Icon(Icons.copy, size: 15),
                                      label: const Text('ចម្លង Link', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: SizedBox(
                                  height: 40,
                                  child: ElevatedButton.icon(
                                    onPressed: _isCheckingNow ? null : _checkNow,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0284C7),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: _isCheckingNow
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                          )
                                        : const Icon(Icons.check_circle_outline, size: 18),
                                    label: const Text(
                                      'ពិនិត្យភ្លាមៗ',
                                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: SizedBox(
                                  height: 40,
                                  child: OutlinedButton(
                                    onPressed: _cancelLogin,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.textSecondary,
                                      side: const BorderSide(color: AppTheme.cardBorder),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: const Text('បោះបង់', style: TextStyle(fontSize: 12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Continue with Google Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isLoggingIn ? null : _startGoogleLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1E293B),
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _isLoggingIn
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Color(0xFF1E293B),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Image.asset(
                                  'assets/google_logo.png',
                                  width: 22,
                                  height: 22,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.g_mobiledata,
                                    size: 26,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Text(
                                  'Continue with Google (ចូលគណនី)',
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Telegram Support Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _contactTelegram,
                      icon: const Icon(Icons.telegram, size: 20, color: Color(0xFF24A1DE)),
                      label: const Text(
                        'ទាក់ទង Admin ដើម្បី Activate License',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF24A1DE),
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF24A1DE), width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Privacy and License instruction text
                  const Text(
                    'សូមផ្តល់ Gmail របស់អ្នកទៅកាន់ Admin ដើម្បី Activate អាជ្ញាប័ណ្ណ។\nរាល់ទិន្នន័យត្រូវបានការពារដោយសុវត្ថិភាពខ្ពស់។',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
