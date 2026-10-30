import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../models/drama_models.dart';
import 'hongguo_service.dart';

class DramaboxService {
  static const String baseUrl = 'https://www.dramaboxdb.com';
  static List<DramaItem>? _cachedCatalog;
  static Map<String, dynamic>? _rawCatalogJson;
  static bool _isLoadingCatalog = false;

  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.dramaboxdb.com/',
  };

  /// Ensure curated catalog is loaded from assets
  static Future<void> _ensureLoaded() async {
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) return;
    if (_isLoadingCatalog) {
      while (_isLoadingCatalog) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isLoadingCatalog = true;
    try {
      final jsonStr = await rootBundle.loadString('assets/data/dramabox_catalog.json');
      final dynamic raw = jsonDecode(jsonStr);
      if (raw is Map<String, dynamic>) {
        _rawCatalogJson = raw;
        final items = raw['items'] as List? ?? [];
        _cachedCatalog = items.map((it) {
          final m = it as Map<String, dynamic>;
          final sid = '${m['series_id'] ?? m['id'] ?? ''}';
          final title = '${m['title'] ?? 'DramaBox Drama'}'.trim();
          final cover = '${m['cover'] ?? ''}'.trim();
          final eps = int.tryParse('${m['episode_count']}') ?? 50;
          final tags = (m['tags'] as List?)?.map((e) => '$e').toList() ?? ['Full HD'];

          return DramaItem(
            id: sid,
            title: title,
            coverUrl: cover,
            episodeCount: eps,
            detailUrl: '$baseUrl/movie/$sid/drama',
            platform: PlatformType.dramabox,
            tags: tags,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error loading DramaBox catalog: $e');
    } finally {
      _cachedCatalog ??= [];
      _isLoadingCatalog = false;
    }
  }

  /// Categories available for DramaBox
  static const List<Map<String, String>> categories = [
    {'id': 'all', 'name': 'ទាំងអស់'},
    {'id': 'trending', 'name': 'កំពុងពេញនិយម'},
    {'id': 'must-sees', 'name': 'រឿងត្រូវតែមើល'},
    {'id': 'hidden-gems', 'name': 'រឿងល្អកម្រ'},
    {'id': 'romance', 'name': 'ស្នេហាផ្អែមល្ហែម'},
    {'id': 'werewolf', 'name': 'ចចកព្រៃ'},
    {'id': 'billionaire', 'name': 'មហាសេដ្ឋី'},
    {'id': 'revenge', 'name': 'សងសឹក'},
  ];

  /// Fetch catalog by category with pagination
  static Future<List<DramaItem>> fetchCatalog({
    String category = 'all',
    int page = 1,
    int pageSize = 18,
  }) async {
    await _ensureLoaded();
    if (_cachedCatalog == null || _cachedCatalog!.isEmpty) return [];

    List<DramaItem> filtered = _cachedCatalog!;
    if (category != 'all' && _rawCatalogJson != null) {
      final items = _rawCatalogJson!['items'] as List? ?? [];
      final matchingIds = <String>{};
      for (final it in items) {
        if (it is! Map) continue;
        final catList = (it['categories'] as List?)?.map((c) => '$c').toList() ?? [];
        final tagsList = (it['tags'] as List?)?.map((c) => '$c'.toLowerCase()).toList() ?? [];
        if (catList.contains(category) || tagsList.any((t) => t.contains(category))) {
          matchingIds.add('${it['series_id']}');
        }
      }
      if (matchingIds.isNotEmpty) {
        filtered = _cachedCatalog!.where((d) => matchingIds.contains(d.id)).toList();
      }
    }

    final startIndex = (page - 1) * pageSize;
    if (startIndex >= filtered.length) return [];
    final endIndex = (startIndex + pageSize).clamp(0, filtered.length);
    return filtered.sublist(startIndex, endIndex);
  }

  /// Search dramas locally & online
  static Future<List<DramaItem>> search(String keyword) async {
    final q = keyword.trim().toLowerCase();
    if (q.isEmpty) return [];

    await _ensureLoaded();
    final localMatches = _cachedCatalog?.where((d) {
          return d.title.toLowerCase().contains(q) || d.id == q;
        }).toList() ??
        [];

    if (localMatches.isNotEmpty) {
      return localMatches;
    }

    // If query looks like a numeric ID (e.g. 42000015757), try direct resolve
    final idMatch = RegExp(r'(\d{9,12})').firstMatch(q);
    if (idMatch != null) {
      final resolved = await resolveDrama(idMatch.group(1)!);
      if (resolved != null) {
        return [resolved];
      }
    }

    return localMatches;
  }

  /// Extract Book ID from any DramaBox link or numeric ID
  static String? extractBookId(String input) {
    final text = input.trim();
    if (RegExp(r'^\d{9,12}$').hasMatch(text)) {
      return text;
    }
    final mEp = RegExp(r'/(?:ep|movie|drama|video)[/_](\d{9,12})').firstMatch(text);
    if (mEp != null) return mEp.group(1);

    final mAny = RegExp(r'(42\d{9})').firstMatch(text);
    if (mAny != null) return mAny.group(1);

    final mNum = RegExp(r'(\d{10,12})').firstMatch(text);
    if (mNum != null) return mNum.group(1);

    return null;
  }

  /// Resolve full drama and all episodes (supports Dual-Engine Bridge for 100% full unlocked VIP episodes)
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    final bookId = extractBookId(rawQuery);
    if (bookId == null) return null;

    final targetUrl = '$baseUrl/movie/$bookId/drama';

    // 1. Try Dual-Engine Bridge (unlocks 100% of all episodes via NunoDrama & Signed CDN)
    final hasBridge = HongguoService.isBridgeAvailable == true || await HongguoService.checkBridgeConnection();
    if (hasBridge) {
      try {
        final bridgeUrl = await HongguoService.getBridgeUrl();
        final uri = Uri.parse('$bridgeUrl/dramabox/resolve?book_id=$bookId&api_key=${HongguoService.apiKey}');
        final res = await http.get(uri, headers: {'x-api-key': HongguoService.apiKey}).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data['success'] == true && data['episodes'] is List && (data['episodes'] as List).isNotEmpty) {
            final title = '${data['title'] ?? 'DramaBox_$bookId'}'.trim();
            final cover = '${data['cover'] ?? ''}'.trim();
            final total = int.tryParse('${data['total_chapters']}') ?? (data['episodes'] as List).length;
            final List<EpisodeItem> episodes = [];
            for (final ep in data['episodes']) {
              final idx = int.tryParse('${ep['index']}') ?? 1;
              final t = '${ep['title'] ?? 'EP${idx.toString().padLeft(2, '0')}'}'.trim();
              final chId = '${ep['chapter_id'] ?? idx}';
              var sUrl = '${ep['stream_url'] ?? ''}'.trim();
              if (sUrl.startsWith('/')) {
                sUrl = '$bridgeUrl$sUrl&api_key=${HongguoService.apiKey}';
              }
              episodes.add(
                EpisodeItem(
                  index: idx,
                  title: t,
                  chapterName: t,
                  chapterId: chId,
                  streamUrl: sUrl.isNotEmpty ? sUrl : null,
                  isFree: true,
                ),
              );
            }
            return DramaItem(
              id: bookId,
              title: title,
              coverUrl: cover,
              episodeCount: total > 0 ? total : episodes.length,
              detailUrl: targetUrl,
              platform: PlatformType.dramabox,
              episodes: episodes,
              tags: ['Full HD', 'Dual-Engine VIP Unlocked'],
            );
          }
        }
      } catch (e) {
        debugPrint('[DramaBox Bridge Resolve Notice] $e');
      }
    }

    // 2. Fallback to Next.js SSR Web scraper (episodes 1-7/1-13 free)
    try {
      final response = await http
          .get(Uri.parse(targetUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final m = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true).firstMatch(body);
      if (m == null) return null;

      final json = jsonDecode(m.group(1)!);
      final pageProps = json['props']?['pageProps'] as Map<String, dynamic>?;
      if (pageProps == null) return null;

      final bookInfo = pageProps['bookInfo'] as Map<String, dynamic>? ?? {};
      final title = '${bookInfo['bookName'] ?? 'DramaBox_$bookId'}'.trim();
      var cover = '${bookInfo['cover'] ?? ''}'.trim();
      final totalCh = int.tryParse('${bookInfo['chapterCount']}') ?? 0;

      final chList = pageProps['chapterList'] as List? ?? [];
      final List<EpisodeItem> episodes = [];
      final bridgeUrl = await HongguoService.getBridgeUrl();

      for (int i = 0; i < chList.length; i++) {
        final ch = chList[i];
        if (ch is! Map) continue;

        final chId = '${ch['id'] ?? (i + 1)}';
        final chIndex = (ch['index'] is int ? ch['index'] as int : int.tryParse('${ch['index']}') ?? i) + 1;
        final chName = '${ch['name'] ?? 'EP${chIndex.toString().padLeft(2, '0')}'}'.trim();

        // Check for direct MP4 or M3U8 video stream URL
        var stream = ch['mp4'] ?? ch['m3u8Url'];
        if (stream == null || (stream is String && stream.isEmpty)) {
          final urls = ch['videoUrls'] ?? ch['resources'];
          if (urls is List && urls.isNotEmpty) {
            stream = urls.first['url'] ?? urls.first['videoUrl'];
          }
        }

        var streamUrl = (stream != null && '$stream'.startsWith('http')) ? '$stream' : null;

        // For VIP episodes without SSR stream (e.g. ep 14+), assign bridge resolver URL
        if (streamUrl == null || streamUrl.isEmpty) {
          streamUrl = '$bridgeUrl/dramabox/stream?book_id=$bookId&ep=$chIndex&api_key=${HongguoService.apiKey}';
        }

        episodes.add(
          EpisodeItem(
            index: chIndex,
            title: chName,
            chapterName: chName,
            chapterId: chId,
            streamUrl: streamUrl,
            isFree: true, // 100% unlocked via Dual-Engine Bridge
          ),
        );
      }

      return DramaItem(
        id: bookId,
        title: title,
        coverUrl: cover,
        episodeCount: totalCh > 0 ? totalCh : episodes.length,
        detailUrl: targetUrl,
        platform: PlatformType.dramabox,
        episodes: episodes,
        tags: ['Full HD', 'DramaBox VIP Unlocked'],
      );
    } catch (e) {
      debugPrint('[DramaBox Resolve Error] $e');
      return null;
    }
  }

  /// Resolve direct stream URL for a specific episode using Dual-Engine Bridge
  static Future<String?> resolveEpisodeStream(String bookId, int episodeIndex) async {
    final hasBridge = HongguoService.isBridgeAvailable == true || await HongguoService.checkBridgeConnection();
    if (hasBridge) {
      final bridgeUrl = await HongguoService.getBridgeUrl();
      try {
        final uri = Uri.parse('$bridgeUrl/dramabox/stream?book_id=$bookId&ep=$episodeIndex&redirect=0&api_key=${HongguoService.apiKey}');
        final res = await http.get(uri, headers: {'x-api-key': HongguoService.apiKey}).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          if (data['success'] == true && data['stream_url'] != null && '${data['stream_url']}'.isNotEmpty) {
            return '${data['stream_url']}';
          }
        }
      } catch (_) {}
      return '$bridgeUrl/dramabox/stream?book_id=$bookId&ep=$episodeIndex&api_key=${HongguoService.apiKey}';
    }
    final drama = await resolveDrama(bookId);
    if (drama != null && drama.episodes != null) {
      final ep = drama.episodes!.where((e) => e.index == episodeIndex).firstOrNull;
      return ep?.streamUrl;
    }
    return null;
  }
}
