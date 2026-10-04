import 'package:flutter/material.dart';
import '../services/app_update_service.dart';
import '../theme/app_theme.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  static Future<void> show(BuildContext context, AppUpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: !info.forceUpdate,
      builder: (ctx) => AppUpdateDialog(updateInfo: info),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final _updateService = AppUpdateService();

  bool _isDownloading = false;
  double _progress = 0.0;
  String _statusMessage = 'កំពុងរៀបចំ...';
  String _downloadDetails = '';
  String? _errorMessage;

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _statusMessage = 'កំពុងភ្ជាប់ទៅកាន់ Server...';
      _downloadDetails = '';
    });

    try {
      final apkFile = await _updateService.downloadApk(
        downloadUrl: widget.updateInfo.downloadUrl,
        onProgress: (received, total, percent) {
          if (!mounted) return;
          final recMb = (received / (1024 * 1024)).toStringAsFixed(1);
          final totMb = total > 0 ? (total / (1024 * 1024)).toStringAsFixed(1) : '?';
          final pct = (percent * 100).toInt();
          setState(() {
            _progress = percent;
            _downloadDetails = '$recMb MB / $totMb MB ($pct%)';
          });
        },
        onStatus: (status) {
          if (!mounted) return;
          setState(() {
            _statusMessage = status;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _statusMessage = 'ទាញយករួចរាល់! កំពុងបើកផ្ទាំងដំឡើង...';
      });

      await _updateService.installApk(apkFile);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDownloading = false;
        _errorMessage = 'ការទាញយកមិនជោគជ័យ: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF131D2E),
      elevation: 16,
      child: Container(
        width: 380,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF131D2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.cyanAccent.withOpacity(0.3),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header: App Icon & Title
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.cyanAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.cyanAccent.withOpacity(0.35),
                    ),
                  ),
                  child: const Icon(
                    Icons.system_update_rounded,
                    color: AppTheme.cyanAccent,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'មានកំណែអាប់ដេតថ្មី!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.cyanAccent.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'v${widget.updateInfo.currentVersion} → v${widget.updateInfo.latestVersion}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.cyanAccent,
                              ),
                            ),
                          ),
                          if (widget.updateInfo.forceUpdate) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.redDanger.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'ចាំបាច់ (Required)',
                                style: TextStyle(
                                  color: AppTheme.redDanger,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Changelog / Release notes
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0C1320),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.cardBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.new_releases_outlined,
                        size: 16,
                        color: AppTheme.cyanAccent,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'អ្វីដែលថ្មីក្នុង Version នេះ៖',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.updateInfo.changelog.isNotEmpty
                        ? widget.updateInfo.changelog
                        : '- កែសម្រួលប្រព័ន្ធទាញយកជា Folder រឿង (Drama Folders)\n- បង្ហាញរបារ Progress និងចំនួនភាគច្បាស់លាស់ (ឧ. 1/200)\n- ដោនឡូត Hongguo Full Episodes លើទូរស័ព្ទដោយមិនបាច់បើក PC\n- បន្ថែមមុខងារ Auto Update ផ្ទាល់ក្នុង Setting',
                    style: const TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.redDanger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.redDanger.withOpacity(0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: AppTheme.redDanger, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          color: AppTheme.redDanger,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 18),

            // Download progress or action buttons
            if (_isDownloading) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.cyanAccent,
                        ),
                      ),
                      Text(
                        '${(_progress * 100).toInt()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.cyanAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      minHeight: 8,
                      backgroundColor: const Color(0xFF1E2838),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.cyanAccent,
                      ),
                    ),
                  ),
                  if (_downloadDetails.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _downloadDetails,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textMuted,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!widget.updateInfo.forceUpdate)
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'ពេលក្រោយ',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.cyanAccent,
                      foregroundColor: Colors.black,
                      elevation: 2,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _startDownload,
                    icon: const Icon(Icons.download_rounded, size: 18, color: Colors.black),
                    label: const Text(
                      'Update ឥឡូវនេះ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
