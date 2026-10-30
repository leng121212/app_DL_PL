import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/drama_models.dart';
import '../services/download_manager.dart';
import '../services/dramabox_service.dart';
import '../services/hongguo_service.dart';
import '../theme/app_theme.dart';
import '../utils/url_helper.dart';

class DramaDetailSheet extends StatefulWidget {
  final DramaItem drama;
  final VoidCallback onNavigateToDownloads;

  const DramaDetailSheet({
    super.key,
    required this.drama,
    required this.onNavigateToDownloads,
  });

  @override
  State<DramaDetailSheet> createState() => _DramaDetailSheetState();
}

class _DramaDetailSheetState extends State<DramaDetailSheet> {
  late DramaItem _currentDrama;
  final Set<int> _selectedIndices = {};
  final TextEditingController _rangeController = TextEditingController();
  int _concurrency = 3;
  bool _isQueueing = false;
  bool _isBridgeActive = false;
  bool _isCheckingBridge = false;

  @override
  void initState() {
    super.initState();
    _currentDrama = widget.drama;
    _initSelection();
    if (_currentDrama.platform == PlatformType.hongguo || _currentDrama.platform == PlatformType.dramabox) {
      _checkBridgeStatus();
    }
  }

  void _initSelection() {
    final eps = _currentDrama.episodes ?? [];
    _selectedIndices.clear();
    if (eps.isNotEmpty) {
      if (_currentDrama.platform == PlatformType.hongguo && !_isBridgeActive) {
        final count = eps.length >= 3 ? 3 : eps.length;
        for (int i = 0; i < count; i++) {
          _selectedIndices.add(eps[i].index);
        }
        _rangeController.text = '1-$count';
      } else if (_currentDrama.platform == PlatformType.dramabox) {
        // Select all episodes by default for DramaBox (supports 1-58 full download)
        final count = eps.length;
        for (int i = 0; i < count; i++) {
          _selectedIndices.add(eps[i].index);
        }
        _rangeController.text = '1-$count';
      } else {
        final initialCount = eps.length > 10 ? 10 : eps.length;
        for (int i = 0; i < initialCount; i++) {
          _selectedIndices.add(eps[i].index);
        }
        _rangeController.text = eps.length > 10 ? '1-10' : '1-${eps.length}';
      }
    }
  }

  Future<void> _checkBridgeStatus() async {
    setState(() => _isCheckingBridge = true);
    final connected = await HongguoService.checkBridgeConnection();
    if (mounted) {
      setState(() {
        _isBridgeActive = connected;
        _isCheckingBridge = false;
      });
      // If connected and current drama only has limited/free episodes, reload to get full episodes
      final currentCount = _currentDrama.episodes?.length ?? 0;
      final freeCount = _currentDrama.episodes?.where((e) => e.isFree).length ?? 0;
      if (connected && (_currentDrama.platform == PlatformType.dramabox || currentCount <= 3 || freeCount < currentCount)) {
        _reloadDrama();
      }
    }
  }

  Future<void> _reloadDrama() async {
    final DramaItem? full = _currentDrama.platform == PlatformType.hongguo
        ? await HongguoService.resolveDrama(_currentDrama.id)
        : (_currentDrama.platform == PlatformType.dramabox
            ? await DramaboxService.resolveDrama(_currentDrama.id)
            : null);
    if (full != null && full.episodes != null && full.episodes!.isNotEmpty && mounted) {
      setState(() {
        _currentDrama = full!;
        _initSelection();
      });
    }
  }

  @override
  void dispose() {
    _rangeController.dispose();
    super.dispose();
  }

  void _applyRangeString(String text) {
    final eps = _currentDrama.episodes ?? [];
    if (eps.isEmpty) return;

    final trimmed = text.trim().toLowerCase();
    final newSelected = <int>{};

    if (trimmed == 'all' || trimmed == 'ទាំងអស់') {
      for (final e in eps) {
        newSelected.add(e.index);
      }
    } else {
      final parts = trimmed.split(RegExp(r'[, ]+'));
      for (final part in parts) {
        if (part.contains('-')) {
          final rangeParts = part.split('-');
          if (rangeParts.length == 2) {
            final start = int.tryParse(rangeParts[0].trim());
            final end = int.tryParse(rangeParts[1].trim());
            if (start != null && end != null) {
              final minVal = start < end ? start : end;
              final maxVal = start > end ? start : end;
              for (int i = minVal; i <= maxVal; i++) {
                if (eps.any((e) => e.index == i)) {
                  newSelected.add(i);
                }
              }
            }
          }
        } else {
          final numVal = int.tryParse(part.trim());
          if (numVal != null && eps.any((e) => e.index == numVal)) {
            newSelected.add(numVal);
          }
        }
      }
    }

    setState(() {
      _selectedIndices.clear();
      _selectedIndices.addAll(newSelected);
    });
  }

  void _selectRange(int start, int end) {
    final eps = _currentDrama.episodes ?? [];
    _selectedIndices.clear();
    for (int i = start; i <= end; i++) {
      if (eps.any((e) => e.index == i)) {
        _selectedIndices.add(i);
      }
    }
    _rangeController.text = '$start-$end';
    setState(() {});
  }

  void _selectAll() {
    final eps = _currentDrama.episodes ?? [];
    _selectedIndices.clear();
    for (final e in eps) {
      _selectedIndices.add(e.index);
    }
    _rangeController.text = '1-${eps.length}';
    setState(() {});
  }

  void _clearSelection() {
    _selectedIndices.clear();
    _rangeController.text = '';
    setState(() {});
  }

  void _toggleEpisode(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  Future<void> _startDownload() async {
    final eps = _currentDrama.episodes ?? [];
    List<EpisodeItem> selectedEps = eps.where((e) => _selectedIndices.contains(e.index)).toList();
    if (selectedEps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('សូមជ្រើសរើសភាគដែលចង់ទាញយកជាមុនសិន'),
          backgroundColor: AppTheme.amberWarning,
        ),
      );
      return;
    }

    if (_currentDrama.platform == PlatformType.hongguo && !_isBridgeActive) {
      final lockedSelected = selectedEps
          .where((e) => e.index > 3 && (e.streamUrl == null || e.streamUrl!.isEmpty))
          .toList();
      if (lockedSelected.isNotEmpty) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.bolt_rounded, color: AppTheme.amberWarning, size: 22),
                SizedBox(width: 8),
                Text('ត្រូវការ Hongguo VIP Bridge',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
            content: Text(
              'ភាគទី 4 ឡើងទៅ (${lockedSelected.length} ភាគ) ត្រូវការភ្ជាប់ VIP Server ពីកុំព្យូទ័រ (START_HONGGUO_PRO_BRIDGE.bat) ដើម្បីទាញយកបានគ្រប់ភាគ ១០០%។\n\nតើលោកអ្នកចង់ទាញយកតែភាគឥតគិតថ្លៃ (Free EP 1-3) ដែរឬទេ?',
              style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ត្រឡប់ក្រោយ', style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent, foregroundColor: Colors.black),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('ទាញយកតែភាគ 1-3', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );

        if (proceed != true) return;
        selectedEps = selectedEps
            .where((e) => !(e.index > 3 && (e.streamUrl == null || e.streamUrl!.isEmpty)))
            .toList();
        if (selectedEps.isEmpty) return;
      }
    }

    if (_currentDrama.platform == PlatformType.dramabox && !_isBridgeActive) {
      // Opportunistically check bridge connection so download manager can stream all episodes
      HongguoService.checkBridgeConnection().then((connected) {
        if (connected && mounted) {
          setState(() => _isBridgeActive = true);
        }
      });
    }

    setState(() => _isQueueing = true);
    final count = await DownloadManager.instance.submitDownload(
      drama: _currentDrama,
      episodes: selectedEps,
      customConcurrency: _concurrency,
    );
    setState(() => _isQueueing = false);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('បានបន្ថែម $count ភាគទៅកាន់បញ្ជីទាញយកដោយជោគជ័យ!'),
          backgroundColor: AppTheme.greenSuccess,
          action: SnackBarAction(
            label: 'មើល',
            textColor: Colors.white,
            onPressed: widget.onNavigateToDownloads,
          ),
        ),
      );
    }
  }

  void _showHongguoBridgeDialog() async {
    bool testing = false;
    String? statusMessage;
    bool isSuccess = _isBridgeActive;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: AppTheme.cardBorder),
              ),
              title: const Row(
                children: [
                  Icon(Icons.bolt_rounded, color: AppTheme.cyanAccent),
                  SizedBox(width: 8),
                  Text(
                    'Hongguo VIP Cloudflare Auto-Sync',
                    style: TextStyle(fontSize: 15, color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isSuccess
                            ? AppTheme.greenSuccess.withOpacity(0.08)
                            : AppTheme.redDanger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSuccess
                              ? AppTheme.greenSuccess.withOpacity(0.3)
                              : AppTheme.redDanger.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSuccess ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                            color: isSuccess ? AppTheme.greenSuccess : AppTheme.redDanger,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSuccess
                                      ? 'Cloudflare Bridge: Online 🟢'
                                      : 'Cloudflare Bridge: Offline 🔴',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isSuccess ? AppTheme.greenSuccess : AppTheme.redDanger,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isSuccess
                                      ? 'បានភ្ជាប់ Cloudflare ស្វ័យប្រវត្តិរួចរាល់ អាចទាញយក VIP បាន'
                                      : 'សូមបើក START_SERVER_FOR_APP.bat លើ PC ដើម្បី Unlock',
                                  style: const TextStyle(fontSize: 10.5, color: AppTheme.textSecondary, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'ប្រព័ន្ធនឹងភ្ជាប់ Cloudflare ទៅកាន់ PC ដោយស្វ័យប្រវត្តិ 100% មិនបាច់វាយបញ្ចូល IP ឡើយ។',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary, height: 1.4),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withOpacity(0.3)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 14, color: Colors.amber),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '💡 គ្រាន់តែបើក START_SERVER_FOR_APP.bat លើ PC App នឹងភ្ជាប់ Cloudflare ស្វ័យប្រវត្តិភ្លាមៗ!',
                              style: TextStyle(fontSize: 10.5, color: Colors.amber, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (statusMessage != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSuccess ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: isSuccess ? Colors.greenAccent : Colors.redAccent),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSuccess ? Icons.check_circle : Icons.error_outline,
                              color: isSuccess ? Colors.greenAccent : Colors.redAccent,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                statusMessage!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSuccess ? Colors.greenAccent : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('បិទ (Close)', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.cyanAccent,
                    foregroundColor: Colors.black,
                  ),
                  icon: testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.sync_rounded, size: 15),
                  label: Text(testing ? 'កំពុងភ្ជាប់ Cloud...' : 'ភ្ជាប់ស្វ័យប្រវត្តិឡើងវិញ (Sync Cloud)'),
                  onPressed: testing
                      ? null
                      : () async {
                          setDialogState(() {
                            testing = true;
                            statusMessage = 'កំពុង Sync Cloudflare ពី Cloud...';
                          });

                          final ok = await HongguoService.checkBridgeConnection();

                          setDialogState(() {
                            testing = false;
                            isSuccess = ok;
                            statusMessage = ok
                                ? '✅ បានភ្ជាប់ Cloudflare ជោគជ័យ! បើកដំណើរការ Full Episodes រួចរាល់។'
                                : (HongguoService.cloudBridgeError ?? '❌ មិនទាន់អាចភ្ជាប់បានទេ! សូមពិនិត្យ PC Server');
                          });

                          if (ok) {
                            setState(() => _isBridgeActive = true);
                            await _reloadDrama();
                            await Future.delayed(const Duration(milliseconds: 700));
                            if (mounted) Navigator.pop(dialogCtx);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildHongguoBridgeBanner() {
    if (_isBridgeActive) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Colors.greenAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚡ Hongguo Pro Engine: បានភ្ជាប់ Cloudflare (Connected)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                  ),
                  Text(
                    'ដោនឡូតបានគ្រប់ភាគទាំងអស់ 1080p Full Episodes (គ្មានដែនកំណត់)!',
                    style: TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hongguo Web: ឥតគិតថ្លៃ 3 ភាគដំបូង',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                ),
                Text(
                  'ចង់ដោនឡូតគ្រប់ភាគ 65+ ភាគពេញ? សូមបើក START_SERVER_FOR_APP.bat លើ PC!',
                  style: TextStyle(fontSize: 10, color: Colors.amberAccent),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final ok = await HongguoService.checkBridgeConnection();
              if (mounted) {
                setState(() => _isBridgeActive = ok);
                if (ok) {
                  await _reloadDrama();
                } else {
                  _showHongguoBridgeDialog();
                }
              }
            },
            icon: const Icon(Icons.sync_rounded, size: 14),
            label: const Text('ភ្ជាប់ Cloud', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDramaboxBanner() {
    if (_isBridgeActive) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.green.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
        ),
        child: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Colors.greenAccent, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '⚡ DramaBox VIP Engine: បានភ្ជាប់ Cloudflare (Connected)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.greenAccent),
                  ),
                  Text(
                    'ដោនឡូតបានគ្រប់ភាគទាំងអស់ 1080p Full Episodes (គ្មានដែនកំណត់)!',
                    style: TextStyle(fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final eps = _currentDrama.episodes ?? [];
    final freeCount = eps.where((e) => e.isFree || (e.streamUrl != null && e.streamUrl!.isNotEmpty)).length;
    if (freeCount <= 0 || freeCount >= eps.length) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.amberAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DramaBox Web: ឥតគិតថ្លៃ $freeCount ភាគដំបូង',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                ),
                Text(
                  'ភាគ ${freeCount + 1} ដល់ ${eps.length} ជាប់សោ VIP (បើក Run_App_server.bat ដើម្បី Unlock គ្រប់ភាគ)',
                  style: const TextStyle(fontSize: 10, color: Colors.amberAccent),
                ),
              ],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              final ok = await HongguoService.checkBridgeConnection();
              if (mounted) {
                setState(() => _isBridgeActive = ok);
                if (ok) {
                  await _reloadDrama();
                } else {
                  _showHongguoBridgeDialog();
                }
              }
            },
            icon: const Icon(Icons.sync_rounded, size: 14),
            label: const Text('ភ្ជាប់ Cloud', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eps = _currentDrama.episodes ?? [];
    final totalEps = _currentDrama.episodeCount > 0 ? _currentDrama.episodeCount : eps.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),

      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header with Cover & Meta
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drama Cover
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 76,
                    height: 108,
                    color: AppTheme.cardBg,
                    child: _currentDrama.coverUrl.isNotEmpty
                        ? Image.network(
                            _currentDrama.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.movie, color: AppTheme.textMuted),
                            ),
                          )
                        : const Center(
                            child: Icon(Icons.movie, color: AppTheme.textMuted),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Drama Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentDrama.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.cyanAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.cyanAccent.withOpacity(0.4),
                              ),
                            ),
                            child: Text(
                              'សរុប $totalEps ភាគ',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.cyanAccent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentDrama.platform.displayName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_currentDrama.intro.isNotEmpty)
                        Text(
                          _currentDrama.intro,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (_currentDrama.platform == PlatformType.hongguo)
            _buildHongguoBridgeBanner(),
          if (_currentDrama.platform == PlatformType.dramabox)
            _buildDramaboxBanner(),

          const Divider(color: AppTheme.cardBorder, height: 16),

          // Range controls & Quick Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'ជ្រើសរើសភាគ (Episodes):',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'បានជ្រើសរើស: ${_selectedIndices.length} / $totalEps',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.cyanAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Custom Range Text Field & Concurrency
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.cardBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.cardBorder),
                        ),
                        child: TextField(
                          controller: _rangeController,
                          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                          decoration: const InputDecoration(
                            hintText: 'ឧ. 1-10 ឬ 1,3,5',
                            hintStyle: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            isDense: true,
                          ),
                          onSubmitted: _applyRangeString,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () => _applyRangeString(_rangeController.text),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cardBg,
                        foregroundColor: AppTheme.cyanAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: AppTheme.cyanAccent),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: const Text('កំណត់', style: TextStyle(fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    // Concurrency dropdown
                    Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.cardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _concurrency,
                          dropdownColor: AppTheme.cardBg,
                          icon: const Icon(Icons.speed, size: 16, color: AppTheme.cyanAccent),
                          style: const TextStyle(fontSize: 12, color: Colors.white),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('1x ខ្សែ')),
                            DropdownMenuItem(value: 2, child: Text('2x ខ្សែ')),
                            DropdownMenuItem(value: 3, child: Text('3x ខ្សែ')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _concurrency = val);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Quick range buttons
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (_currentDrama.platform == PlatformType.hongguo && !_isBridgeActive) ...[
                        _buildQuickPill('1-3 (Free)', () => _selectRange(1, 3)),
                      ],
                      if (_currentDrama.platform == PlatformType.dramabox) ...[
                        () {
                          final freeCount = eps.where((e) => e.isFree || (e.streamUrl != null && e.streamUrl!.isNotEmpty)).length;
                          if (freeCount > 0 && freeCount < eps.length) {
                            return _buildQuickPill('1-$freeCount (Free)', () => _selectRange(1, freeCount));
                          }
                          return const SizedBox.shrink();
                        }(),
                      ],
                      _buildQuickPill('ទាំងអស់', _selectAll),
                      _buildQuickPill('1-10', () => _selectRange(1, 10)),
                      if (totalEps > 10) _buildQuickPill('11-20', () => _selectRange(11, 20)),
                      if (totalEps > 20) _buildQuickPill('21-30', () => _selectRange(21, 30)),
                      if (totalEps > 30) _buildQuickPill('31-50', () => _selectRange(31, 50)),
                      _buildQuickPill('លុប', _clearSelection, isClear: true),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Episodes Grid
          Expanded(
            child: eps.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppTheme.cyanAccent),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GridView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.4,
                      ),
                      itemCount: eps.length,
                      itemBuilder: (context, index) {
                        final ep = eps[index];
                        final isSelected = _selectedIndices.contains(ep.index);
                        final isLocked = _currentDrama.platform == PlatformType.hongguo
                            ? (!_isBridgeActive && ep.index > 3 && (ep.streamUrl == null || ep.streamUrl!.isEmpty))
                            : (_currentDrama.platform == PlatformType.dramabox
                                ? (!_isBridgeActive && !ep.isFree && (ep.streamUrl == null || ep.streamUrl!.isEmpty))
                                : false);
                        final epLabel = (_currentDrama.platform == PlatformType.web20 ||
                                _currentDrama.platform == PlatformType.hongguo ||
                                ep.title.contains('集') ||
                                ep.title.contains('第') ||
                                ep.title.length > 5 ||
                                RegExp(r'[\u4e00-\u9fa5]').hasMatch(ep.title))
                            ? 'EP${ep.index.toString().padLeft(2, '0')}'
                            : (ep.title.startsWith('EP') ? ep.title : 'EP${ep.index.toString().padLeft(2, '0')}');
                        return InkWell(
                          onTap: () => _toggleEpisode(ep.index),
                          borderRadius: BorderRadius.circular(8),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppTheme.cyanAccent.withOpacity(0.2)
                                  : (isLocked ? Colors.black26 : AppTheme.cardBg),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? AppTheme.cyanAccent
                                    : (isLocked ? Colors.white10 : AppTheme.cardBorder),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  epLabel,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    color: isSelected
                                        ? AppTheme.cyanAccent
                                        : (isLocked ? AppTheme.textMuted : AppTheme.textSecondary),
                                  ),
                                ),
                                if (isLocked) ...[
                                  const SizedBox(width: 2),
                                  const Icon(Icons.lock, size: 10, color: Colors.orangeAccent),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.bgDark,
              border: Border(top: BorderSide(color: AppTheme.cardBorder)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: _isQueueing ? null : _startDownload,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isQueueing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.download_rounded, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'ទាញយក ${_selectedIndices.length} ភាគដែលបានជ្រើសរើស',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickPill(String label, VoidCallback onTap, {bool isClear = false}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isClear ? AppTheme.redDanger.withOpacity(0.12) : AppTheme.cardBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isClear ? AppTheme.redDanger.withOpacity(0.5) : AppTheme.cardBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isClear ? AppTheme.redDanger : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
