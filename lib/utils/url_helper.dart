import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Safely open any URL using available browser mechanisms with multi-level fallbacks.
/// Solves Android 11+ package visibility and intent restrictions.
Future<bool> openSafeUrl(String url) async {
  final clean = url.trim();
  if (clean.isEmpty) return false;

  final uri = Uri.parse(clean);

  // 1. External application (System default browser like Chrome or Samsung Internet)
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return true;
    }
  } catch (e) {
    debugPrint('[openSafeUrl] externalApplication failed: $e');
  }

  // 2. In-App Browser View (Chrome Custom Tabs)
  try {
    if (await launchUrl(uri, mode: LaunchMode.inAppBrowserView)) {
      return true;
    }
  } catch (e) {
    debugPrint('[openSafeUrl] inAppBrowserView failed: $e');
  }

  // 3. Platform Default
  try {
    if (await launchUrl(uri, mode: LaunchMode.platformDefault)) {
      return true;
    }
  } catch (e) {
    debugPrint('[openSafeUrl] platformDefault failed: $e');
  }

  return false;
}
