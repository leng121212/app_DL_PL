import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/drama_models.dart';
import 'hongguo_service.dart';
import 'reelsdizim_service.dart';
import 'reelshort_service.dart';
import 'beeplaylet_service.dart';
import 'dramabox_service.dart';
import 'iqiyi_creator_service.dart';
import 'eightmovie_service.dart';
import 'bmp4_service.dart';
import 'mydrama_service.dart';

class DownloadManager with ChangeNotifier {
  static final DownloadManager instance = DownloadManager._internal();
  DownloadManager._internal();

  static const _channel = MethodChannel('com.trabekprey.downloader/storage');

  final List<DownloadTask> _tasks = [];
  final Set<String> _activeRunningTaskIds = {};
  int _concurrency = 2;
  bool _isProcessing = false;
  Directory? _customBaseDir;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get concurrency => _concurrency;
  set concurrency(int value) {
    _concurrency = value.clamp(1, 4);
    notifyListeners();
  }

  int get runningCount => _activeRunningTaskIds.length;
  int get pendingCount => _tasks.where((t) => t.status == TaskStatus.pending).length;
  int get completedCount => _tasks.where((t) => t.status == TaskStatus.completed).length;

  /// Check if Android 11+ MANAGE_EXTERNAL_STORAGE is granted
  Future<bool> isManageStorageGranted() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel.invokeMethod<bool>('isManageStorageGranted');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Open Android settings for storage access
  Future<void> openStorageSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('openStorageSettings');
    } catch (_) {}
  }

  /// Inform Android MediaScanner so downloaded videos appear in Gallery/Photos
  Future<void> scanMediaFile(String filePath) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('scanMediaFile', {'path': filePath});
    } catch (_) {}
  }

  /// Test if a directory path is writable
  Future<bool> testDirectoryWritable(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final testFile = File(p.join(dir.path, '.probe_${DateTime.now().millisecondsSinceEpoch}'));
      await testFile.writeAsString('ok');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Set and persist custom storage base directory
  Future<bool> setCustomBaseDir(String path) async {
    final ok = await testDirectoryWritable(path);
    if (!ok) return false;

    _customBaseDir = Directory(path);
    try {
      final appDoc = await getApplicationDocumentsDirectory();
      final configFile = File(p.join(appDoc.path, 'storage_base_dir.txt'));
      await configFile.writeAsString(path);
    } catch (_) {}

    notifyListeners();
    return true;
  }

  /// Get or create base storage directory for downloads
  Future<Directory> getBaseStorageDir() async {
    if (_customBaseDir != null && await _customBaseDir!.exists()) {
      return _customBaseDir!;
    }

    // 1. Check saved directory from local config
    try {
      final appDoc = await getApplicationDocumentsDirectory();
      final configFile = File(p.join(appDoc.path, 'storage_base_dir.txt'));
      if (await configFile.exists()) {
        final savedPath = (await configFile.readAsString()).trim();
        if (savedPath.isNotEmpty && await testDirectoryWritable(savedPath)) {
          _customBaseDir = Directory(savedPath);
          return _customBaseDir!;
        }
      }
    } catch (_) {}

    // 2. Try public Movies folder on Android
    try {
      const moviesPath = '/storage/emulated/0/Movies/Trabekprey_DL';
      if (await testDirectoryWritable(moviesPath)) {
        final dir = Directory(moviesPath);
        _customBaseDir = dir;
        return dir;
      }
    } catch (_) {}

    // 3. Try public Download folder on Android
    try {
      const downloadPath = '/storage/emulated/0/Download/Trabekprey_DL';
      if (await testDirectoryWritable(downloadPath)) {
        final dir = Directory(downloadPath);
        _customBaseDir = dir;
        return dir;
      }
    } catch (_) {}

    // 4. Try external storage directory (App external files)
    try {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final target = Directory(p.join(extDir.path, 'Trabekprey_DL'));
        if (await testDirectoryWritable(target.path)) {
          _customBaseDir = target;
          return target;
        }
      }
    } catch (_) {}

    // 5. Fallback to app documents directory
    final appDoc = await getApplicationDocumentsDirectory();
    final fallback = Directory(p.join(appDoc.path, 'Trabekprey_DL'));
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    _customBaseDir = fallback;
    return fallback;
  }

  /// Sanitize folder/file names
  String _sanitize(String name) {
    return name.replaceAll(RegExp(r'[\\/*?:"<>|]'), '').trim();
  }

  /// Submit a batch of episodes for download
  Future<int> submitDownload({
    required DramaItem drama,
    required List<EpisodeItem> episodes,
    int? customConcurrency,
  }) async {
    if (customConcurrency != null) {
      _concurrency = customConcurrency.clamp(1, 4);
    }

    final baseDir = await getBaseStorageDir();
    final cleanDramaTitle = _sanitize(drama.title).isEmpty ? 'Drama_${drama.id}' : _sanitize(drama.title);
    final dramaDir = Directory(p.join(baseDir.path, cleanDramaTitle));
    if (!await dramaDir.exists()) {
      await dramaDir.create(recursive: true);
    }

    // Save cover thumbnail if available
    _saveCoverImage(dramaDir, drama.coverUrl);

    int queuedCount = 0;
    for (final ep in episodes) {
      final taskId = '${drama.platform.id}_${drama.id}_ep${ep.index}';

      // Avoid duplicate tasks if already queued or downloading
      final existing = _tasks.where((t) => t.taskId == taskId).firstOrNull;
      if (existing != null &&
          (existing.status == TaskStatus.downloading ||
              existing.status == TaskStatus.pending ||
              existing.status == TaskStatus.resolving ||
              existing.status == TaskStatus.completed)) {
        continue;
      }

      final fileName = 'EP${ep.index.toString().padLeft(2, '0')}.mp4';
      final outputPath = p.join(dramaDir.path, fileName);

      final task = DownloadTask(
        taskId: taskId,
        dramaTitle: drama.title,
        dramaCover: drama.coverUrl,
        platform: drama.platform,
        episodeIndex: ep.index,
        episodeTitle: ep.title,
        streamUrl: ep.streamUrl,
        vid: ep.vid,
        seriesId: drama.id,
        outputPath: outputPath,
      );

      _tasks.add(task);
      queuedCount++;
    }

    notifyListeners();
    _processQueue();
    return queuedCount;
  }

  /// Downloads and saves the drama's poster/thumbnail image and registers it with Android Gallery
  Future<void> _saveCoverImage(Directory dramaDir, String coverUrl) async {
    if (coverUrl.isEmpty) return;
    try {
      final coverFile = File(p.join(dramaDir.path, 'cover.jpg'));
      final posterFile = File(p.join(dramaDir.path, 'poster.jpg'));

      if (await coverFile.exists() && await posterFile.exists()) {
        return;
      }

      final client = http.Client();
      try {
        String referer = 'https://hongguoduanju.com/';
        if (coverUrl.contains('reelshort')) {
          referer = 'https://www.reelshort.com/';
        } else if (coverUrl.contains('8movie')) {
          referer = 'https://8movie.com/';
        } else if (coverUrl.contains('reelsdizim')) {
          referer = 'https://reelsdizim.com/';
        } else if (coverUrl.contains('my-drama')) {
          referer = 'https://my-drama.com/';
        } else if (coverUrl.contains('bmp4')) {
          referer = 'https://www.bmp4.com/';
        } else if (coverUrl.contains('17video') || coverUrl.contains('beeplaylet')) {
          referer = 'https://beeplaylet.com/';
        }

        final res = await client.get(
          Uri.parse(coverUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
            'Referer': referer,
          },
        ).timeout(const Duration(seconds: 15));

        if (res.statusCode == 200 && res.bodyBytes.length > 500) {
          if (!await coverFile.exists()) {
            await coverFile.writeAsBytes(res.bodyBytes, flush: true);
            await scanMediaFile(coverFile.path);
          }
          if (!await posterFile.exists()) {
            await posterFile.writeAsBytes(res.bodyBytes, flush: true);
            await scanMediaFile(posterFile.path);
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  /// Worker loop to pick up and process tasks
  void _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      while (true) {
        // Auto-recover any ghost/orphaned tasks marked downloading/resolving but not in active pool
        for (final t in _tasks) {
          if ((t.status == TaskStatus.downloading || t.status == TaskStatus.resolving) &&
              !_activeRunningTaskIds.contains(t.taskId)) {
            t.setStatus(TaskStatus.pending);
          }
        }

        if (_activeRunningTaskIds.length >= _concurrency) {
          break;
        }

        final nextTask = _tasks.where((t) => t.status == TaskStatus.pending).firstOrNull;
        if (nextTask == null) {
          break;
        }

        // Reserve active slot
        _activeRunningTaskIds.add(nextTask.taskId);

        // Run download asynchronously
        _executeTask(nextTask);
        await Future.delayed(const Duration(milliseconds: 50));
      }
    } finally {
      _isProcessing = false;
    }
  }

  /// Resilient Resumable Downloader with Range headers, Auto-Retry, and MediaScanner indexing
  Future<void> _executeTask(DownloadTask task) async {
    task.setStatus(TaskStatus.downloading);
    notifyListeners();

    final outputFile = File(task.outputPath);
    final tempPath = '${task.outputPath}.tmp';
    final tempFile = File(tempPath);

    try {
      // 1. If final output file already exists with valid video size (>500KB), mark complete
      if (await outputFile.exists()) {
        final len = await outputFile.length();
        if (len > 500 * 1024) {
          task.updateProgress(
            progress: 100.0,
            downloadedBytes: len,
            totalBytes: len,
            speedBytesPerSec: 0,
            speedStr: '0.0 MB/s',
            etaStr: '00:00',
          );
          task.setStatus(TaskStatus.completed);
          notifyListeners();
          return;
        }
      }

      // 2. Resolve stream URL if missing or if it's an episode page link or bridge endpoint
      String? streamUrl = task.streamUrl;
      if ((streamUrl == null || streamUrl.isEmpty) &&
          task.platform == PlatformType.hongguo &&
          task.vid != null &&
          task.vid!.isNotEmpty) {
        final bridgeUrl = await HongguoService.getBridgeUrl();
        streamUrl = '$bridgeUrl/stream?vid=${task.vid}&api_key=${HongguoService.apiKey}';
        task.streamUrl = streamUrl;
      }

      final needsResolution = streamUrl == null ||
          streamUrl.isEmpty ||
          streamUrl.contains('/video_url') ||
          streamUrl.contains('/play?') ||
          streamUrl.contains('reelshort.com/episodes') ||
          streamUrl.contains('/episodes/') ||
          streamUrl.contains('iqiyi.com') ||
          streamUrl.endsWith('.html');

      if (needsResolution) {
        task.setStatus(TaskStatus.resolving);
        notifyListeners();

        if (task.platform == PlatformType.hongguo && task.seriesId != null) {
          streamUrl = await HongguoService.resolveEpisodeStream(
            task.seriesId!,
            task.vid ?? '',
            dramaTitle: task.dramaTitle,
            episodeIndex: task.episodeIndex,
          );
        } else if (task.platform == PlatformType.reelshort) {
          streamUrl = await ReelshortService.resolveEpisodeStream(
            streamUrl ?? '',
            task.seriesId,
            task.episodeIndex,
          );
          if (streamUrl == null || streamUrl.isEmpty) {
            // Automatic fallback to ReelsDizim which has 1450+ full unlocked ReelShort dramas!
            try {
              final rMatches = await ReelsDizimService.search(task.dramaTitle);
              if (rMatches.isNotEmpty) {
                final rFull = await ReelsDizimService.resolveDrama(rMatches.first.id);
                final rEp = rFull?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
                if (rEp?.streamUrl != null && rEp!.streamUrl!.isNotEmpty) {
                  streamUrl = rEp.streamUrl;
                }
              }
            } catch (_) {}
          }
        } else if (task.platform == PlatformType.eightmovie || (streamUrl != null && streamUrl.contains('8movie'))) {
          final res = await EightMovieService.resolveDrama(task.seriesId ?? streamUrl ?? '');
          final ep = res?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
          streamUrl = ep?.streamUrl ?? streamUrl;
        } else if (task.platform == PlatformType.bmp4 || (streamUrl != null && streamUrl.contains('bmp4'))) {
          final res = await Bmp4Service.resolveDrama(task.seriesId ?? streamUrl ?? '');
          final ep = res?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
          streamUrl = ep?.streamUrl ?? streamUrl;
        } else if (task.platform == PlatformType.mydrama || (streamUrl != null && streamUrl.contains('my-drama'))) {
          final res = await MyDramaService.resolveDrama(task.seriesId ?? streamUrl ?? '');
          final ep = res?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
          streamUrl = ep?.streamUrl ?? streamUrl;
        } else if (task.platform == PlatformType.reelsdizim || (streamUrl != null && streamUrl.contains('reelsdizim'))) {
          final res = await ReelsDizimService.resolveDrama(task.seriesId ?? streamUrl ?? '');
          final ep = res?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
          streamUrl = ep?.streamUrl ?? streamUrl;
        } else if (task.platform == PlatformType.dramabox && task.seriesId != null) {
          // If streamUrl is null or is an intermediate bridge stream URL, resolve direct signed CloudFront URL
          if (streamUrl == null || streamUrl.isEmpty || streamUrl.contains('/dramabox/stream')) {
            final direct = await DramaboxService.resolveEpisodeStream(task.seriesId!, task.episodeIndex);
            if (direct != null && direct.isNotEmpty) {
              streamUrl = direct;
            }
          }
          if (streamUrl == null || streamUrl.isEmpty) {
            final res = await DramaboxService.resolveDrama(task.seriesId!);
            final ep = res?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
            streamUrl = ep?.streamUrl ?? streamUrl;
          }
        } else if (task.platform == PlatformType.beeplaylet && task.seriesId != null) {
          final res = await BeeplayletService.resolveDrama(task.seriesId!);
          final ep = res?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
          streamUrl = ep?.streamUrl ?? streamUrl;
        } else if (task.seriesId != null && task.seriesId!.startsWith('iqiyi_')) {
          if (streamUrl != null && streamUrl.isNotEmpty) {
            streamUrl = await IqiyiCreatorService.resolveEpisodeStream(streamUrl);
          } else {
            final fullDrama = await IqiyiCreatorService.resolveDrama(task.seriesId!);
            final ep = fullDrama?.episodes?.where((e) => e.index == task.episodeIndex).firstOrNull;
            if (ep?.streamUrl != null) {
              streamUrl = await IqiyiCreatorService.resolveEpisodeStream(ep!.streamUrl!);
            }
          }
        } else if (streamUrl != null && streamUrl.contains('iqiyi.com')) {
          streamUrl = await IqiyiCreatorService.resolveEpisodeStream(streamUrl);
        }

        // Automatic mirror cross-resolution fallback ONLY for Hongguo when bridge is offline
        if (task.platform == PlatformType.hongguo && (streamUrl == null || streamUrl.isEmpty)) {
          streamUrl = await _crossResolveStream(task.dramaTitle, task.episodeIndex);
        }
        task.streamUrl = streamUrl;
      }

      // Final fallback check ONLY for Hongguo
      if (task.platform == PlatformType.hongguo && (streamUrl == null || streamUrl.isEmpty)) {
        streamUrl = await _crossResolveStream(task.dramaTitle, task.episodeIndex);
        task.streamUrl = streamUrl;
      }

      if (streamUrl == null || streamUrl.isEmpty) {
        final isHongguoVip = task.platform == PlatformType.hongguo && task.episodeIndex > 3;
        final isDramaboxVip = task.platform == PlatformType.dramabox;
        final errMsg = isHongguoVip
            ? 'ភាគទី ${task.episodeIndex} ជាប់សោ VIP នៅលើ Hongguo Web (អាចដោនឡូតបានតែ 3 ភាគដំបូង)'
            : (isDramaboxVip
                ? 'ភាគទី ${task.episodeIndex} ជាប់សោ VIP នៅលើ DramaBox Web'
                : 'មិនអាចស្វែងរក Link វីដេអូបានទេ (Stream not found)');
        task.setStatus(TaskStatus.failed, err: errMsg);
        notifyListeners();
        return;
      }

      task.setStatus(TaskStatus.downloading);
      notifyListeners();

      // Ensure target directory exists
      final parentDir = outputFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Guarantee drama thumbnail is downloaded and indexed in phone gallery
      if (task.dramaCover.isNotEmpty) {
        _saveCoverImage(parentDir, task.dramaCover);
      }

      // 3. Dispatch to HLS Downloader or Progressive MP4 Downloader
      if (streamUrl.contains('.m3u8')) {
        await _downloadHlsStream(streamUrl, outputFile, tempFile, task);
      } else {
        await _downloadProgressiveMp4(streamUrl, outputFile, tempFile, task);
      }
    } catch (e) {
      task.setStatus(TaskStatus.failed, err: '$e');
      notifyListeners();
    } finally {
      _activeRunningTaskIds.remove(task.taskId);
      _processQueue();
    }
  }

  /// Downloads HLS (.m3u8) streams by resolving segments and concatenating TS chunks
  Future<void> _downloadHlsStream(
    String m3u8Url,
    File outputFile,
    File tempFile,
    DownloadTask task,
  ) async {
    const maxEpisodeRetries = 3;
    int episodeAttempt = 0;

    while (episodeAttempt < maxEpisodeRetries) {
      episodeAttempt++;
      if (task.status == TaskStatus.cancelled || task.status == TaskStatus.paused) {
        return;
      }

      try {
        await _executeHlsStream(m3u8Url, outputFile, tempFile, task);
        return;
      } catch (e) {
        if (task.status == TaskStatus.cancelled || task.status == TaskStatus.paused) {
          return;
        }
        if (episodeAttempt >= maxEpisodeRetries) {
          rethrow;
        }
        // Transient network failure: wait with backoff and retry episode
        await Future.delayed(Duration(seconds: 2 * episodeAttempt));
      }
    }
  }

  Future<void> _executeHlsStream(
    String m3u8Url,
    File outputFile,
    File tempFile,
    DownloadTask task,
  ) async {
    final masterUri = Uri.parse(m3u8Url);
    final client = http.Client();
    final hlsReferer = _getRefererForTask(task, m3u8Url);

    try {
      final res = await client.get(
        masterUri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': hlsReferer,
        },
      ).timeout(const Duration(seconds: 45));

      if (res.statusCode != 200) {
        if (res.statusCode == 403) {
          throw HttpException('Line នេះជាប់កំហិតតំបន់ (Geo-restricted 403) សូមសាកល្បង BeePlaylet ឬបើក VPN');
        } else if (res.statusCode == 404) {
          throw HttpException('Link វីដេអូរឿងនេះផុតកំណត់ ឬលុបចេញពី Server ដើម (404 Not Found)');
        }
        throw HttpException('HTTP Status ${res.statusCode} loading playlist');
      }

      String playlistTxt = res.body;
      Uri variantUri = masterUri;

      // Handle Master Playlist with variants (#EXT-X-STREAM-INF): Prefer 720p HD for fast downloads
      if (playlistTxt.contains('#EXT-X-STREAM-INF')) {
        final lines = playlistTxt.split('\n');
        String? bestVariantPath;
        String? fallbackVariantPath;
        int highestBandwidth = 0;

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.startsWith('#EXT-X-STREAM-INF')) {
            final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
            final bw = bwMatch != null ? int.tryParse(bwMatch.group(1)!) ?? 0 : 0;
            final is720p = line.contains('720') || (bw >= 1000000 && bw <= 3200000);

            for (int j = i + 1; j < lines.length; j++) {
              final nextL = lines[j].trim();
              if (nextL.isNotEmpty && !nextL.startsWith('#')) {
                if (is720p && bestVariantPath == null) {
                  bestVariantPath = nextL;
                }
                if (bw >= highestBandwidth || fallbackVariantPath == null) {
                  highestBandwidth = bw;
                  fallbackVariantPath = nextL;
                }
                break;
              }
            }
          }
        }

        final chosenVariant = bestVariantPath ?? fallbackVariantPath;
        if (chosenVariant != null) {
          variantUri = masterUri.resolve(chosenVariant);
          final vRes = await client.get(
            variantUri,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': hlsReferer,
            },
          ).timeout(const Duration(seconds: 45));
          if (vRes.statusCode == 200) {
            playlistTxt = vRes.body;
          }
        }
      }

      // Collect all segment URLs and inherit security tokens / signature parameters
      final List<Uri> segmentUris = [];
      final Map<String, String> inheritedParams = {
        ...masterUri.queryParameters,
        ...variantUri.queryParameters,
      };

      for (final rawLine in playlistTxt.split('\n')) {
        final line = rawLine.trim();
        if (line.isNotEmpty && !line.startsWith('#')) {
          Uri segUri = variantUri.resolve(line);
          if (inheritedParams.isNotEmpty && segUri.queryParameters.isEmpty) {
            segUri = segUri.replace(queryParameters: inheritedParams);
          }
          segmentUris.add(segUri);
        }
      }

      if (segmentUris.isEmpty) {
        throw Exception('រកមិនឃើញ Segment វីដេអូក្នុង Playlist ឡើយ (No HLS segments)');
      }

      final sink = tempFile.openWrite(mode: FileMode.write);
      int downloadedBytes = 0;
      final stopwatch = Stopwatch()..start();
      int lastReportedTime = 0;
      int lastReportedBytes = 0;

      // Stable Parallel HLS segment downloader (2 concurrent workers to prevent network choke)
      const segmentConcurrency = 2;
      final Map<int, Uint8List> completedSegments = {};
      int nextDownloadIndex = 0;
      int nextWriteIndex = 0;
      bool hasError = false;
      Object? downloadError;

      Future<void> worker() async {
        while (!hasError) {
          if (task.status == TaskStatus.cancelled || task.status == TaskStatus.paused) {
            return;
          }

          int idx;
          if (nextDownloadIndex >= segmentUris.length) {
            return;
          }
          idx = nextDownloadIndex++;

          final segUri = segmentUris[idx];
          Uint8List? segBytes;

          final segHeaders = <String, String>{
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Connection': 'keep-alive',
            'Referer': _getRefererForTask(task, segUri.toString()),
          };

          for (int attempt = 1; attempt <= 5; attempt++) {
            if (task.status == TaskStatus.cancelled || task.status == TaskStatus.paused) {
              return;
            }
            try {
              final sRes = await client.get(
                segUri,
                headers: segHeaders,
              ).timeout(const Duration(seconds: 60));

              if (sRes.statusCode == 200 && sRes.bodyBytes.isNotEmpty) {
                segBytes = sRes.bodyBytes;
                break;
              } else {
                throw HttpException('HTTP Status ${sRes.statusCode} on segment $idx');
              }
            } catch (err) {
              if (attempt == 5) {
                hasError = true;
                downloadError = err;
                return;
              }
              await Future.delayed(Duration(milliseconds: 1000 * attempt));
            }
          }

          if (segBytes != null) {
            completedSegments[idx] = segBytes;
          } else {
            hasError = true;
            downloadError = Exception('Failed to download segment $idx');
            return;
          }
        }
      }

      // Launch worker pool
      final workerFutures = List.generate(segmentConcurrency, (_) => worker());

      // Sequentially write completed segments as they arrive
      while (nextWriteIndex < segmentUris.length) {
        if (task.status == TaskStatus.cancelled || task.status == TaskStatus.paused) {
          await sink.flush();
          await sink.close();
          if (task.status == TaskStatus.cancelled && await tempFile.exists()) {
            await tempFile.delete();
          }
          return;
        }

        if (hasError) {
          await sink.flush();
          await sink.close();
          throw downloadError ?? Exception('Segment download failed');
        }

        if (completedSegments.containsKey(nextWriteIndex)) {
          final bytes = completedSegments.remove(nextWriteIndex)!;
          sink.add(bytes);
          downloadedBytes += bytes.length;
          nextWriteIndex++;

          final elapsedMs = stopwatch.elapsedMilliseconds;
          if (elapsedMs - lastReportedTime > 250 || nextWriteIndex == segmentUris.length) {
            final diffBytes = downloadedBytes - lastReportedBytes;
            final diffSec = (elapsedMs - lastReportedTime) / 1000.0;
            final speedBytesPerSec = diffSec > 0 ? (diffBytes / diffSec) : 0.0;
            final speedMB = speedBytesPerSec / (1024 * 1024);

            final progress = (nextWriteIndex / segmentUris.length) * 100.0;
            String etaStr = '--:--';
            int estimatedTotalBytes = downloadedBytes;
            if (progress > 0 && speedBytesPerSec > 0) {
              estimatedTotalBytes = (downloadedBytes / (progress / 100.0)).round();
              final remainingBytes = estimatedTotalBytes - downloadedBytes;
              final remainingSec = remainingBytes / speedBytesPerSec;
              final mins = (remainingSec ~/ 60).toString().padLeft(2, '0');
              final secs = (remainingSec.toInt() % 60).toString().padLeft(2, '0');
              etaStr = '$mins:$secs';
            }

            task.updateProgress(
              progress: progress.clamp(0.0, 100.0),
              downloadedBytes: downloadedBytes,
              totalBytes: estimatedTotalBytes,
              speedBytesPerSec: speedBytesPerSec,
              speedStr: '${speedMB.toStringAsFixed(1)} MB/s',
              etaStr: etaStr,
            );

            lastReportedBytes = downloadedBytes;
            lastReportedTime = elapsedMs;
          }
        } else {
          await Future.delayed(const Duration(milliseconds: 15));
        }
      }

      await Future.wait(workerFutures);

      await sink.flush();
      await sink.close();

      final finalLen = await tempFile.length();
      if (finalLen > 50 * 1024) {
        if (await outputFile.exists()) {
          await outputFile.delete();
        }
        await tempFile.rename(outputFile.path);

        task.updateProgress(
          progress: 100.0,
          downloadedBytes: finalLen,
          totalBytes: finalLen,
          speedBytesPerSec: 0,
          speedStr: '0.0 MB/s',
          etaStr: '00:00',
        );
        task.setStatus(TaskStatus.completed);
        scanMediaFile(outputFile.path);
        notifyListeners();
      } else {
        throw Exception('File incomplete: only $finalLen bytes downloaded');
      }
    } finally {
      client.close();
    }
  }

  /// Downloads progressive MP4 streams with Range resume and auto-retry
  Future<void> _downloadProgressiveMp4(
    String streamUrl,
    File outputFile,
    File tempFile,
    DownloadTask task,
  ) async {
    const maxAttempts = 5;
    int attempt = 0;
    bool isCompleted = false;

    while (attempt < maxAttempts && !isCompleted) {
      attempt++;
      if (task.status == TaskStatus.cancelled || task.status == TaskStatus.paused) {
        return;
      }

      http.Client? client;
      IOSink? sink;

      try {
        int existingBytes = 0;
        if (await tempFile.exists()) {
          existingBytes = await tempFile.length();
        }

        client = http.Client();
        final request = http.Request('GET', Uri.parse(streamUrl));
        request.headers['User-Agent'] =
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
        request.headers['Accept-Encoding'] = 'identity';
        request.headers['Connection'] = 'keep-alive';

        final referer = _getRefererForTask(task, streamUrl);
        if (referer.isNotEmpty) {
          request.headers['Referer'] = referer;
        }

        if (existingBytes > 0) {
          request.headers['Range'] = 'bytes=$existingBytes-';
        }

        final response = await client.send(request).timeout(const Duration(seconds: 60));

        // Re-resolve expired CDN token on 403 or 404
        if ((response.statusCode == 403 || response.statusCode == 404) && attempt < maxAttempts) {
          String? refreshedUrl;
          if (task.platform == PlatformType.hongguo && task.seriesId != null) {
            refreshedUrl = await HongguoService.resolveEpisodeStream(
              task.seriesId!,
              task.vid ?? '',
              dramaTitle: task.dramaTitle,
              episodeIndex: task.episodeIndex,
            );
          }
          if (refreshedUrl == null || refreshedUrl.isEmpty || refreshedUrl == streamUrl) {
            refreshedUrl = await _crossResolveStream(task.dramaTitle, task.episodeIndex);
          }
          if (refreshedUrl != null && refreshedUrl.isNotEmpty && refreshedUrl != streamUrl) {
            streamUrl = refreshedUrl;
            task.streamUrl = refreshedUrl;
            client.close();
            continue;
          }
        }

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw HttpException('HTTP Status ${response.statusCode}');
        }

        final isPartial = response.statusCode == 206;
        int totalBytes = 0;

        if (isPartial) {
          final remaining = response.contentLength ?? 0;
          totalBytes = existingBytes + remaining;
          sink = tempFile.openWrite(mode: FileMode.append);
        } else {
          totalBytes = response.contentLength ?? 0;
          existingBytes = 0;
          sink = tempFile.openWrite(mode: FileMode.write);
        }

        int downloadedBytes = existingBytes;
        final stopwatch = Stopwatch()..start();
        int lastReportedBytes = downloadedBytes;
        int lastReportedTime = 0;

        await for (final chunk in response.stream.timeout(const Duration(seconds: 25))) {
          if (task.status == TaskStatus.cancelled) {
            await sink.flush();
            await sink.close();
            if (await tempFile.exists()) await tempFile.delete();
            client.close();
            notifyListeners();
            return;
          }

          if (task.status == TaskStatus.paused) {
            await sink.flush();
            await sink.close();
            client.close();
            notifyListeners();
            return;
          }

          sink.add(chunk);
          downloadedBytes += chunk.length;

          final elapsedMs = stopwatch.elapsedMilliseconds;
          if (elapsedMs - lastReportedTime > 400) {
            final diffBytes = downloadedBytes - lastReportedBytes;
            final diffSec = (elapsedMs - lastReportedTime) / 1000.0;
            final speedBytesPerSec = diffSec > 0 ? (diffBytes / diffSec) : 0.0;
            final speedMB = speedBytesPerSec / (1024 * 1024);

            double progress = 0.0;
            String etaStr = '--:--';
            if (totalBytes > 0) {
              progress = (downloadedBytes / totalBytes) * 100.0;
              if (speedBytesPerSec > 0 && downloadedBytes < totalBytes) {
                final remainingSec = (totalBytes - downloadedBytes) / speedBytesPerSec;
                final mins = (remainingSec ~/ 60).toString().padLeft(2, '0');
                final secs = (remainingSec.toInt() % 60).toString().padLeft(2, '0');
                etaStr = '$mins:$secs';
              }
            }

            task.updateProgress(
              progress: progress.clamp(0.0, 100.0),
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
              speedBytesPerSec: speedBytesPerSec,
              speedStr: '${speedMB.toStringAsFixed(1)} MB/s',
              etaStr: etaStr,
            );

            lastReportedBytes = downloadedBytes;
            lastReportedTime = elapsedMs;
          }
        }

        await sink.flush();
        await sink.close();
        sink = null;
        client.close();
        client = null;

        final finalTempLen = await tempFile.length();
        if (finalTempLen > 50 * 1024 && (totalBytes == 0 || finalTempLen >= totalBytes)) {
          if (await outputFile.exists()) {
            await outputFile.delete();
          }
          await tempFile.rename(task.outputPath);

          task.updateProgress(
            progress: 100.0,
            downloadedBytes: finalTempLen,
            totalBytes: finalTempLen,
            speedBytesPerSec: 0,
            speedStr: '0.0 MB/s',
            etaStr: '00:00',
          );
          task.setStatus(TaskStatus.completed);
          scanMediaFile(task.outputPath);

          isCompleted = true;
          notifyListeners();
          break;
        } else {
          throw Exception('File incomplete: only $finalTempLen bytes downloaded');
        }
      } catch (e) {
        if (sink != null) {
          try {
            await sink.flush();
            await sink.close();
          } catch (_) {}
        }
        client?.close();

        if (task.status == TaskStatus.cancelled || task.status == TaskStatus.paused) {
          return;
        }

        if (attempt >= maxAttempts) {
          String errMsg = '$e';
          if (errMsg.contains('Connection closed') ||
              errMsg.contains('SocketException') ||
              errMsg.contains('ClientException')) {
            errMsg = 'សេវាអ៊ីនធឺណិតដាច់ (Dropped). ចុច 🔄 Retry ដើម្បីបន្ត';
          }
          task.setStatus(TaskStatus.failed, err: errMsg);
          notifyListeners();
        } else {
          task.updateProgress(
            progress: task.progress,
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes,
            speedBytesPerSec: 0,
            speedStr: 'ភ្ជាប់ឡើងវិញ $attempt/$maxAttempts...',
            etaStr: '--:--',
          );
          await Future.delayed(Duration(milliseconds: 1000 * attempt));
        }
      }
    }
  }

  void pauseTask(String taskId) {
    final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
    if (task != null && task.status == TaskStatus.downloading) {
      task.setStatus(TaskStatus.paused);
      notifyListeners();
    }
  }

  void resumeTask(String taskId) {
    final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
    if (task != null && task.status == TaskStatus.paused) {
      task.setStatus(TaskStatus.pending);
      notifyListeners();
      _processQueue();
    }
  }

  void cancelTask(String taskId) {
    final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
    if (task != null) {
      task.setStatus(TaskStatus.cancelled);
      notifyListeners();
    }
  }

  void retryTask(String taskId) {
    final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
    if (task != null) {
      task.setStatus(TaskStatus.pending);
      notifyListeners();
      _processQueue();
    }
  }

  void removeTask(String taskId) {
    _tasks.removeWhere((t) => t.taskId == taskId);
    notifyListeners();
  }

  void clearCompleted() {
    _tasks.removeWhere((t) => t.status == TaskStatus.completed || t.status == TaskStatus.cancelled);
    notifyListeners();
  }

  /// Pause all active tasks for a specific drama
  void pauseDrama(String dramaTitle) {
    for (final task in _tasks.where((t) => t.dramaTitle == dramaTitle)) {
      if (task.status == TaskStatus.downloading ||
          task.status == TaskStatus.resolving ||
          task.status == TaskStatus.pending) {
        task.setStatus(TaskStatus.paused);
      }
    }
    notifyListeners();
  }

  /// Resume all paused tasks for a specific drama
  void resumeDrama(String dramaTitle) {
    bool hasResumed = false;
    for (final task in _tasks.where((t) => t.dramaTitle == dramaTitle)) {
      if (task.status == TaskStatus.paused || task.status == TaskStatus.failed) {
        task.setStatus(TaskStatus.pending);
        hasResumed = true;
      }
    }
    if (hasResumed) {
      notifyListeners();
      _processQueue();
    }
  }

  /// Cancel all active tasks for a specific drama
  void cancelDrama(String dramaTitle) {
    for (final task in _tasks.where((t) => t.dramaTitle == dramaTitle)) {
      if (task.status == TaskStatus.downloading ||
          task.status == TaskStatus.pending ||
          task.status == TaskStatus.resolving ||
          task.status == TaskStatus.paused ||
          task.status == TaskStatus.failed) {
        task.setStatus(TaskStatus.cancelled);
      }
    }
    notifyListeners();
  }

  /// Remove all cancelled and failed tasks for a drama from in-memory queue
  void removeCancelledTasksForDrama(String dramaTitle) {
    _tasks.removeWhere((t) =>
        t.dramaTitle == dramaTitle &&
        (t.status == TaskStatus.cancelled || t.status == TaskStatus.failed));
    notifyListeners();
  }

  /// Delete a completed drama and optionally remove its files from disk
  Future<void> deleteCompletedDrama(String dramaTitle, {bool deleteFromDisk = true}) async {
    final tasksToDelete = _tasks
        .where((t) => t.dramaTitle == dramaTitle && (t.status == TaskStatus.completed || t.status == TaskStatus.cancelled))
        .toList();

    for (final t in tasksToDelete) {
      if (deleteFromDisk) {
        try {
          final file = File(t.outputPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      _tasks.remove(t);
    }

    if (deleteFromDisk) {
      try {
        final baseDir = await getBaseStorageDir();
        final dramaDir = Directory(p.join(baseDir.path, _sanitize(dramaTitle)));
        if (await dramaDir.exists()) {
          final remaining = await dramaDir.list().toList();
          final videoFiles = remaining.where((e) => e.path.endsWith('.mp4') || e.path.endsWith('.mkv')).toList();
          if (videoFiles.isEmpty) {
            await dramaDir.delete(recursive: true);
          }
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Delete a single task and optionally delete its file
  Future<void> deleteTaskAndFile(String taskId, {bool deleteFromDisk = true}) async {
    final task = _tasks.where((t) => t.taskId == taskId).firstOrNull;
    if (task != null) {
      if (deleteFromDisk) {
        try {
          final file = File(task.outputPath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
      _tasks.remove(task);
      notifyListeners();
    }
  }

  /// Scan storage folder to recover completed episodes into _tasks
  Future<void> scanStorageForCompletedTasks() async {
    try {
      final baseDir = await getBaseStorageDir();
      if (!await baseDir.exists()) return;

      final entities = await baseDir.list().toList();
      for (final entity in entities) {
        if (entity is Directory) {
          final dramaDir = entity;
          final dramaTitle = p.basename(dramaDir.path);
          if (dramaTitle.isEmpty || dramaTitle.startsWith('.')) continue;

          String coverPath = '';
          final coverFile = File(p.join(dramaDir.path, 'cover.jpg'));
          final posterFile = File(p.join(dramaDir.path, 'poster.jpg'));
          if (await coverFile.exists()) {
            coverPath = coverFile.path;
          } else if (await posterFile.exists()) {
            coverPath = posterFile.path;
          }

          final files = await dramaDir.list().toList();
          for (final f in files) {
            if (f is File) {
              final ext = p.extension(f.path).toLowerCase();
              if (ext == '.mp4' || ext == '.mkv') {
                final baseName = p.basenameWithoutExtension(f.path);
                final match = RegExp(r'\d+').firstMatch(baseName);
                final epIndex = match != null ? (int.tryParse(match.group(0)!) ?? 1) : 1;
                final taskId = 'disk_${_sanitize(dramaTitle)}_ep$epIndex';

                final alreadyExists = _tasks.any((t) => t.outputPath == f.path || t.taskId == taskId);
                if (!alreadyExists) {
                  final stat = await f.stat();
                  final task = DownloadTask(
                    taskId: taskId,
                    dramaTitle: dramaTitle,
                    dramaCover: coverPath,
                    platform: PlatformType.web20,
                    episodeIndex: epIndex,
                    episodeTitle: baseName,
                    outputPath: f.path,
                  );
                  task.setStatus(TaskStatus.completed);
                  task.updateProgress(
                    progress: 100.0,
                    downloadedBytes: stat.size,
                    totalBytes: stat.size,
                    speedBytesPerSec: 0,
                    speedStr: '',
                    etaStr: '',
                  );
                  _tasks.add(task);
                }
              }
            }
          }
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Cross-resolves an episode stream from mirror providers (8Movie, BeePlaylet)
  Future<String?> _crossResolveStream(String dramaTitle, int episodeIndex) async {
    if (dramaTitle.isEmpty || episodeIndex <= 0) return null;
    try {
      final mirror = await HongguoService.searchMirrorDrama(dramaTitle);
      if (mirror != null && mirror.episodes != null) {
        final ep = mirror.episodes!.where((e) => e.index == episodeIndex).firstOrNull;
        if (ep?.streamUrl != null && ep!.streamUrl!.isNotEmpty) {
          return ep.streamUrl;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Derives correct HTTP Referer based on task platform and stream destination
  String _getRefererForTask(DownloadTask task, [String? url]) {
    final target = (url ?? task.streamUrl ?? '').toLowerCase();

    // ByteDance / Hongguo CDN hosts reject third-party referers (returns 403 Forbidden)
    if (target.contains('qznovelvod.com') ||
        target.contains('ixigua.com') ||
        target.contains('bytevcloud.com') ||
        target.contains('ibytedtos.com') ||
        target.contains('douyin.com') ||
        target.contains('snssdk.com') ||
        target.contains('toutiao.com') ||
        target.contains('volces.com') ||
        target.contains('bytedance') ||
        target.contains('tos-cn') ||
        target.contains('fqnovelpic.com') ||
        target.contains('byteimg.com') ||
        target.contains('pstatp.com')) {
      return '';
    }

    if (task.platform == PlatformType.eightmovie || target.contains('8movie') || target.contains('dramasimida')) {
      return 'https://8movie.com/';
    } else if (task.platform == PlatformType.reelsdizim || target.contains('reelsdizim') || target.contains('dramaflix')) {
      return 'https://reelsdizim.com/';
    } else if (task.platform == PlatformType.beeplaylet || target.contains('beeplaylet') || target.contains('17video')) {
      return 'https://beeplaylet.com/';
    } else if (task.platform == PlatformType.bmp4 || target.contains('bmp4')) {
      return 'https://www.bmp4.com/';
    } else if (task.platform == PlatformType.mydrama || target.contains('my-drama')) {
      return 'https://my-drama.com/';
    } else if (task.platform == PlatformType.reelshort || target.contains('reelshort')) {
      return 'https://www.reelshort.com/';
    } else if (target.contains('iqiyi')) {
      return 'https://www.iqiyi.com/';
    }
    return 'https://hongguoduanju.com/';
  }
}
