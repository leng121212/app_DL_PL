import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AppUpdateInfo {
  final bool hasUpdate;
  final String currentVersion;
  final String latestVersion;
  final int currentVersionCode;
  final int latestVersionCode;
  final String changelog;
  final String downloadUrl;
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.hasUpdate,
    required this.currentVersion,
    required this.latestVersion,
    required this.currentVersionCode,
    required this.latestVersionCode,
    required this.changelog,
    required this.downloadUrl,
    this.forceUpdate = false,
  });
}

class AppUpdateService {
  static const currentVersion = '1.0.2';
  static const currentVersionCode = 3;

  static const _channel = MethodChannel('com.trabekprey.downloader/storage');

  // GitHub repository endpoints for client updates
  static const _rawVersionJsonUrls = [
    'https://raw.githubusercontent.com/leng121212/app_DL_PL/main/version.json',
    'https://raw.githubusercontent.com/leng121212/app_DL_PV/main/version.json',
  ];

  static const _githubLatestReleaseApiUrls = [
    'https://api.github.com/repos/leng121212/app_DL_PL/releases/latest',
    'https://api.github.com/repos/leng121212/app_DL_PV/releases/latest',
  ];

  Future<AppUpdateInfo> checkForUpdate() async {
    // 1. Try checking version.json first (Fastest, no GitHub API rate limits)
    for (final url in _rawVersionJsonUrls) {
      try {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final latestVer = (data['version'] as String?)?.trim() ?? currentVersion;
          final latestCode = (data['versionCode'] as num?)?.toInt() ?? 1;
          final changelog = (data['changelog'] as String?)?.trim() ?? 'មានកំណែអាប់ដេតថ្មី';
          final downloadUrl = (data['downloadUrl'] as String?)?.trim() ??
              'https://github.com/leng121212/app_DL_PL/releases/latest/download/Trabekprey-DL-Pro-Release.apk';
          final forceUpdate = data['forceUpdate'] == true;

          final hasNewer = latestCode > currentVersionCode || _compareVersions(latestVer, currentVersion) > 0;
          return AppUpdateInfo(
            hasUpdate: hasNewer,
            currentVersion: currentVersion,
            latestVersion: latestVer,
            currentVersionCode: currentVersionCode,
            latestVersionCode: latestCode,
            changelog: changelog,
            downloadUrl: downloadUrl,
            forceUpdate: forceUpdate,
          );
        }
      } catch (e) {
        debugPrint('[AppUpdateService] Error checking $url: $e');
      }
    }

    // 2. Fallback to GitHub Releases API
    for (final apiUrl in _githubLatestReleaseApiUrls) {
      try {
        final response = await http
            .get(
              Uri.parse(apiUrl),
              headers: {'Accept': 'application/vnd.github.v3+json'},
            )
            .timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final tag = (data['tag_name'] as String?)?.trim().replaceFirst(RegExp(r'^[vV]'), '') ?? currentVersion;
          final body = (data['body'] as String?)?.trim() ?? 'កំណែអាប់ដេតថ្មីពី GitHub Release';

          var downloadUrl = '';
          final assets = data['assets'];
          if (assets is List) {
            for (final asset in assets) {
              if (asset is Map<String, dynamic>) {
                final name = (asset['name'] as String?)?.toLowerCase() ?? '';
                if (name.endsWith('.apk')) {
                  downloadUrl = asset['browser_download_url'] as String? ?? '';
                  break;
                }
              }
            }
          }

          if (downloadUrl.isEmpty) {
            downloadUrl =
                'https://github.com/leng121212/app_DL_PL/releases/latest/download/Trabekprey-DL-Pro-Release.apk';
          }

          final hasNewer = _compareVersions(tag, currentVersion) > 0;
          return AppUpdateInfo(
            hasUpdate: hasNewer,
            currentVersion: currentVersion,
            latestVersion: tag,
            currentVersionCode: currentVersionCode,
            latestVersionCode: currentVersionCode + 1,
            changelog: body,
            downloadUrl: downloadUrl,
            forceUpdate: false,
          );
        }
      } catch (e) {
        debugPrint('[AppUpdateService] Error checking $apiUrl: $e');
      }
    }

    return const AppUpdateInfo(
      hasUpdate: false,
      currentVersion: currentVersion,
      latestVersion: currentVersion,
      currentVersionCode: currentVersionCode,
      latestVersionCode: currentVersionCode,
      changelog: '',
      downloadUrl: '',
    );
  }

  static int _compareVersions(String v1, String v2) {
    try {
      final parts1 = v1.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final parts2 = v2.replaceAll(RegExp(r'[^0-9.]'), '').split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final len = parts1.length > parts2.length ? parts1.length : parts2.length;
      for (var i = 0; i < len; i++) {
        final p1 = i < parts1.length ? parts1[i] : 0;
        final p2 = i < parts2.length ? parts2[i] : 0;
        if (p1 > p2) return 1;
        if (p1 < p2) return -1;
      }
    } catch (_) {}
    return 0;
  }

  Future<File> downloadApk({
    required String downloadUrl,
    required void Function(int receivedBytes, int totalBytes, double percent) onProgress,
    void Function(String message)? onStatus,
  }) async {
    final client = http.Client();
    try {
      onStatus?.call('កំពុងភ្ជាប់ទៅកាន់ Server...');
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request).timeout(const Duration(minutes: 5));

      if (response.statusCode != 200) {
        throw Exception('Server returned status ${response.statusCode}');
      }

      final totalBytes = response.contentLength ?? 0;
      final tempDir = await getTemporaryDirectory();
      final targetFile = File('${tempDir.path}/Trabekprey_DL_Update.apk');
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      final sink = targetFile.openWrite();
      var receivedBytes = 0;

      onStatus?.call('កំពុងទាញយកឯកសារ APK...');
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        final percent = totalBytes > 0 ? (receivedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
        onProgress(receivedBytes, totalBytes, percent);
      }

      await sink.flush();
      await sink.close();

      if (!await targetFile.exists() || await targetFile.length() == 0) {
        throw Exception('ឯកសារ APK ទាញយកមកមិនពេញលេញ');
      }

      return targetFile;
    } finally {
      client.close();
    }
  }

  Future<bool> installApk(File apkFile) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {
        'apkPath': apkFile.path,
      });
      return result == true;
    } catch (e) {
      debugPrint('[AppUpdateService] installApk error: $e');
      rethrow;
    }
  }
}
