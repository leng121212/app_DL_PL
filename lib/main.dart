import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'services/download_manager.dart';
import 'services/license_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dark navigation and status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bgDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize background services
  LicenseService.instance.init();
  DownloadManager.instance.getBaseStorageDir();

  runApp(const TrabekpreyDownloaderApp());
}

class TrabekpreyDownloaderApp extends StatelessWidget {
  const TrabekpreyDownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Trabekprey-DL Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LicenseService.instance,
      builder: (context, _) {
        final licenseService = LicenseService.instance;

        // If checking license on cold start
        if (licenseService.isChecking && !licenseService.state.isLoggedIn) {
          return Scaffold(
            backgroundColor: AppTheme.bgDark,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.cyanAccent.withOpacity(0.25),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/Trabekprey_DL_App.png',
                        errorBuilder: (_, __, ___) => Image.asset('assets/Trabekprey.png'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppTheme.cyanAccent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'កំពុងផ្ទៀងផ្ទាត់ License...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        // Mandatory License Gate: If not logged in or license inactive -> Show LoginScreen
        if (!licenseService.state.isLoggedIn) {
          return const LoginScreen();
        }

        // Active and verified user -> Show HomeScreen
        return const HomeScreen();
      },
    );
  }
}
