import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/drama_models.dart';
import 'license_service.dart';
import 'eightmovie_service.dart';
import 'beeplaylet_service.dart';
import 'bmp4_service.dart';

class HongguoService {
  static const String baseUrl = 'https://hongguoduanju.com';
  static const String novelQuickUrl = 'https://novelquickapp.com';
  static const List<String> webDomains = [
    'https://hongguoduanju.com',
    'https://novelquickapp.com',
  ];
  static const String prefBridgeUrlKey = 'hongguo_bridge_url';
  static const String defaultBridgeUrl = '';
  static const String apiKey = 'vidbee-key';

  static String? _cachedBridgeUrl;
  static bool? _isBridgeAvailable;
  static List<DramaItem>? _cachedCatalog;
  static bool _isLoadingCatalog = false;
  static final Map<String, DramaItem?> _mirrorCache = {};

  /// Ensure 10,500+ curated Hongguo catalog is loaded from bundled assets
  static Future<void> _ensureCatalogLoaded() async {
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) return;
    if (_isLoadingCatalog) {
      while (_isLoadingCatalog) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isLoadingCatalog = true;
    try {
      final jsonStr = await rootBundle.loadString('assets/data/hongguo_catalog.json');
      final dynamic raw = jsonDecode(jsonStr);
      if (raw is Map<String, dynamic>) {
        final items = raw['items'] as List? ?? [];
        _cachedCatalog = items.map((it) {
          final m = it as Map<String, dynamic>;
          final sid = '${m['id'] ?? ''}';
          final title = '${m['title'] ?? 'Hongguo Drama'}'.trim();
          final cover = '${m['cover'] ?? ''}'.trim();
          final eps = int.tryParse('${m['episodeCount']}') ?? 50;
          final intro = '${m['intro'] ?? ''}'.trim();
          final tags = (m['tags'] as List?)?.map((e) => '$e').toList() ?? ['Full HD'];

          return DramaItem(
            id: sid,
            title: title,
            coverUrl: cover,
            episodeCount: eps,
            intro: intro,
            tags: tags,
            detailUrl: '$baseUrl/detail?series_id=$sid',
            platform: PlatformType.hongguo,
          );
        }).toList();
      }
    } catch (e) {
      debugPrint('Error loading Hongguo catalog asset: $e');
    } finally {
      _cachedCatalog ??= [];
      _isLoadingCatalog = false;
    }
  }

  static const Map<String, String> _s2tMap = {
    '猎': '獵', '体': '體', '风': '風', '云': '雲', '战': '戰', '后': '後',
    '妈': '媽', '东': '東', '门': '門', '双': '雙', '爱': '愛', '宝': '寶',
    '爷': '爺', '总': '總', '裁': '裁', '妇': '婦', '儿': '兒', '钱': '錢',
    '头': '頭', '换': '換', '发': '發', '这': '這', '点': '點', '国': '國',
    '产': '產', '归': '歸', '来': '來', '龙': '龍', '华': '華', '万': '萬',
    '亿': '億', '时': '時', '长': '長', '开': '開', '关': '關', '见': '見',
    '两': '兩', '进': '進', '远': '遠', '运': '運', '动': '動', '车': '車',
    '机': '機', '电': '電', '权': '權', '师': '師', '医': '醫', '圣': '聖',
    '皇': '皇', '帝': '帝', '妃': '妃', '宠': '寵', '妻': '妻', '财': '財',
    '富': '富', '书': '書', '说': '說', '语': '語', '话': '話', '记': '記',
    '义': '義', '侠': '俠', '传': '傳', '统': '統', '级': '級', '炼': '煉',
    '经': '經', '结': '結', '线': '線', '终': '終', '续': '續', '编': '編',
    '缘': '緣', '红': '紅', '剧': '劇', '岁': '歲', '亲': '親', '娘': '娘',
    '称': '稱', '当': '當', '现': '現', '代': '代', '修': '修', '仙': '仙',
    '逆': '逆', '袭': '襲', '复': '復', '仇': '仇',
  };

  static const Map<String, String> _t2sMap = {
    '獵': '猎', '體': '体', '風': '风', '雲': '云', '戰': '战', '後': '后',
    '媽': '妈', '東': '东', '門': '门', '雙': '双', '愛': '爱', '寶': '宝',
    '爺': '爷', '總': '总', '裁': '裁', '婦': '妇', '兒': '儿', '錢': '钱',
    '頭': '头', '換': '换', '發': '发', '這': '这', '點': '点', '國': '国',
    '產': '产', '歸': '归', '來': '来', '龍': '龙', '華': '华', '萬': '万',
    '億': '亿', '時': '时', '長': '长', '開': '开', '關': '关', '見': '见',
    '兩': '两', '進': '进', '遠': '远', '運': '运', '動': '动', '車': '车',
    '機': '机', '電': '电', '權': '权', '師': '师', '醫': '医', '聖': '圣',
    '皇': '皇', '帝': '帝', '妃': '妃', '寵': '宠', '妻': '妻', '財': '财',
    '富': '富', '書': '书', '說': '说', '語': '语', '話': '话', '記': '记',
    '義': '义', '俠': '侠', '傳': '传', '統': '统', '級': '级', '煉': '炼',
    '經': '经', '結': '结', '線': '线', '終': '终', '續': '续', '編': '编',
    '緣': '缘', '紅': '红', '劇': '剧', '歲': '岁', '親': '亲', '稱': '称',
    '當': '当', '現': '现', '襲': '袭', '復': '复',
  };

  static String simplifiedToTraditional(String text) {
    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      sb.write(_s2tMap[ch] ?? ch);
    }
    return sb.toString();
  }

  static String traditionalToSimplified(String text) {
    final sb = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      final ch = text[i];
      sb.write(_t2sMap[ch] ?? ch);
    }
    return sb.toString();
  }

  static String normalizeChinese(String text) {
    final s = traditionalToSimplified(text);
    return s.replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '').toLowerCase();
  }

  /// Clear any cached most-episodes catalog to force immediate live re-sync
  static void clearCache() {
    _cachedMostEpisodes = null;
    _lastMostEpisodesFetch = null;
  }

  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };

  /// Get current Bridge URL from SharedPreferences
  static Future<String> getBridgeUrl() async {
    if (_cachedBridgeUrl != null && _cachedBridgeUrl!.isNotEmpty) {
      return _cachedBridgeUrl!;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedBridgeUrl = prefs.getString(prefBridgeUrlKey) ?? defaultBridgeUrl;
    } catch (_) {
      _cachedBridgeUrl = defaultBridgeUrl;
    }
    return _cachedBridgeUrl!;
  }

  /// Save new Bridge URL into SharedPreferences
  static Future<void> setBridgeUrl(String url) async {
    String clean = url.trim();
    if (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    _cachedBridgeUrl = clean;
    _isBridgeAvailable = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefBridgeUrlKey, clean);
    } catch (_) {}
  }

  static bool _isSyncingCloud = false;
  static bool? _cloudBridgeOnline;
  static String? _cloudBridgeError;

  static bool? get isCloudBridgeOnline => _cloudBridgeOnline;
  static String? get cloudBridgeError => _cloudBridgeError;

  /// Fetch active Bridge Tunnel URL automatically from GitHub / Cloud Server
  static Future<Map<String, dynamic>> fetchAutoBridgeFromCloud() async {
    if (_isSyncingCloud) {
      return {'online': _cloudBridgeOnline ?? false, 'message': 'Sync in progress'};
    }
    _isSyncingCloud = true;
    try {
      // 1. Primary: Direct high-speed fetch from GitHub raw manifest (zero-config, always awake)
      try {
        final ghUri = Uri.parse('https://raw.githubusercontent.com/leng121212/app_DL_PL/main/bridge_info.json?t=${DateTime.now().millisecondsSinceEpoch}');
        final ghResp = await http.get(ghUri).timeout(const Duration(seconds: 4));
        if (ghResp.statusCode == 200) {
          final ghData = jsonDecode(ghResp.body) as Map<String, dynamic>;
          final isOnline = ghData['is_online'] == true;
          final bridgeUrl = (ghData['bridge_url'] as String?)?.trim();
          if (isOnline && bridgeUrl != null && bridgeUrl.isNotEmpty && !bridgeUrl.contains('192.168.18.5')) {
            // Strictly verify before marking online
            final probeUri = Uri.parse('$bridgeUrl/?api_key=$apiKey');
            final pRes = await http.get(probeUri, headers: {'x-api-key': apiKey}).timeout(const Duration(seconds: 3));
            if (pRes.statusCode == 200) {
              await setBridgeUrl(bridgeUrl);
              _cloudBridgeOnline = true;
              _isBridgeAvailable = true;
              _cloudBridgeError = null;
              return {'online': true, 'url': bridgeUrl};
            }
          }
        }
      } catch (_) {}

      // 2. Secondary: Render License Server
      try {
        final deviceHash = await LicenseService.instance.getDeviceHash();
        final uri = Uri.parse('${LicenseService.serverUrl}/api/v1/bridge/active');
        final resp = await http.get(
          uri,
          headers: {
            'X-Device-Hash': deviceHash,
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));

        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final isOnline = data['is_online'] == true;
          final bridgeUrl = (data['bridge_url'] as String?)?.trim();
          if (isOnline && bridgeUrl != null && bridgeUrl.isNotEmpty && !bridgeUrl.contains('192.168.18.5')) {
            final probeUri = Uri.parse('$bridgeUrl/?api_key=$apiKey');
            final pRes = await http.get(probeUri, headers: {'x-api-key': apiKey}).timeout(const Duration(seconds: 3));
            if (pRes.statusCode == 200) {
              await setBridgeUrl(bridgeUrl);
              _cloudBridgeOnline = true;
              _isBridgeAvailable = true;
              _cloudBridgeError = null;
              return {'online': true, 'url': bridgeUrl};
            }
          }
        }
      } catch (_) {}

      _cloudBridgeOnline = false;
      _isBridgeAvailable = false;
      _cloudBridgeError = 'PC Server មិនទាន់បើកនៅឡើយទេ';
      return {'online': false, 'message': _cloudBridgeError};
    } finally {
      _isSyncingCloud = false;
    }
  }

  /// Check whether the Hongguo Pro Engine Bridge is running and reachable
  static Future<bool> checkBridgeConnection([String? testUrl]) async {
    // 1. If specific URL provided, test it strictly
    if (testUrl != null && testUrl.trim().isNotEmpty) {
      final clean = testUrl.trim().endsWith('/') ? testUrl.trim().substring(0, testUrl.trim().length - 1) : testUrl.trim();
      try {
        final probeUri = Uri.parse('$clean/?api_key=$apiKey');
        final res = await http.get(
          probeUri,
          headers: {'x-api-key': apiKey},
        ).timeout(const Duration(milliseconds: 2500));
        if (res.statusCode == 200) {
          _isBridgeAvailable = true;
          _cloudBridgeOnline = true;
          _cloudBridgeError = null;
          return true;
        }
      } catch (_) {}
      return false;
    }

    // 2. Standalone mode: Default to FALSE immediately without hanging
    final saved = await getBridgeUrl();
    if (saved.isEmpty || saved.contains('192.168.18.5')) {
      _isBridgeAvailable = false;
      _cloudBridgeOnline = false;
      return false;
    }

    final clean = saved.endsWith('/') ? saved.substring(0, saved.length - 1) : saved;
    try {
      final probeUri = Uri.parse('$clean/?api_key=$apiKey');
      final res = await http.get(
        probeUri,
        headers: {'x-api-key': apiKey},
      ).timeout(const Duration(milliseconds: 2000));
      if (res.statusCode == 200) {
        _isBridgeAvailable = true;
        _cloudBridgeOnline = true;
        _cloudBridgeError = null;
        return true;
      }
    } catch (_) {}

    _isBridgeAvailable = false;
    _cloudBridgeOnline = false;
    return false;
  }

  /// Cached status getter
  static bool? get isBridgeAvailable => _isBridgeAvailable;

  /// Fetch categories list for Hongguo
  static List<Map<String, String>> getCategories() {
    return DramaCategoryHelper.getCategories();
  }

  /// Scrapes or queries catalog for a given category and page
  static Future<List<DramaItem>> fetchCatalog({
    String category = 'all',
    int page = 1,
  }) async {
    // 1. Primary: Scrape directly from novelquickapp.com / hongguoduanju.com web catalog
    final webItems = await _fetchCatalogFromWeb(category, page);
    if (webItems.isNotEmpty) {
      return webItems;
    }

    // 2. Fallback to bundled 10,500+ Hongguo catalog
    await _ensureCatalogLoaded();
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      const pageSize = 18;
      final start = (page - 1) * pageSize;
      if (start < _cachedCatalog!.length) {
        final end = math.min(start + pageSize, _cachedCatalog!.length);
        return _cachedCatalog!.sublist(start, end);
      }
    }

    // 3. Fallback to Bridge Engine if available
    final hasBridge = _isBridgeAvailable == true || await checkBridgeConnection();
    if (hasBridge) {
      final bridgeItems = await _fetchCatalogFromBridge(category);
      if (bridgeItems.isNotEmpty) {
        return bridgeItems;
      }
    }

    return [];
  }

  /// Search dramas by keyword across 10,500+ bundled catalog, web, and online mirrors
  static Future<List<DramaItem>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];

    final qLower = query.toLowerCase();
    final normQuery = normalizeChinese(qLower);
    final List<DramaItem> results = [];
    final Set<String> seenIds = {};

    void addUnique(DramaItem d) {
      if (!seenIds.contains(d.id)) {
        seenIds.add(d.id);
        results.add(d);
      }
    }

    // 1. Instant local search in 10,527 bundled Hongguo catalog
    await _ensureCatalogLoaded();
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      for (final d in _cachedCatalog!) {
        final normTitle = normalizeChinese(d.title);
        if (d.title.toLowerCase().contains(qLower) ||
            (normQuery.isNotEmpty && normTitle.contains(normQuery)) ||
            d.id == query ||
            d.tags.any((t) => t.toLowerCase().contains(qLower) || normalizeChinese(t).contains(normQuery)) ||
            (d.intro.isNotEmpty && (d.intro.toLowerCase().contains(qLower) || normalizeChinese(d.intro).contains(normQuery)))) {
          addUnique(d);
        }
      }
    }

    // 2. Query online mirror search (BeePlaylet, 8Movie, BMP4) for Hongguo titles
    try {
      final tradQuery = simplifiedToTraditional(query);
      final beeMatches = await BeeplayletService.search(tradQuery);
      if (beeMatches.isEmpty && tradQuery != query) {
        beeMatches.addAll(await BeeplayletService.search(query));
      }
      for (final it in beeMatches) {
        addUnique(DramaItem(
          id: it.id,
          title: it.title,
          coverUrl: it.coverUrl,
          episodeCount: it.episodeCount,
          detailUrl: it.detailUrl,
          platform: PlatformType.hongguo,
          tags: ['Full HD', '🟢 100% Unlocked'],
        ));
      }
    } catch (_) {}

    try {
      final eightMatches = await EightMovieService.search(query);
      for (final it in eightMatches) {
        addUnique(DramaItem(
          id: it.id,
          title: it.title,
          coverUrl: it.coverUrl,
          episodeCount: it.episodeCount,
          detailUrl: it.detailUrl,
          platform: PlatformType.hongguo,
          tags: ['Full HD', '🟢 100% Unlocked'],
        ));
      }
    } catch (_) {}

    try {
      final bmpMatches = await Bmp4Service.search(query);
      for (final it in bmpMatches) {
        addUnique(DramaItem(
          id: it.id,
          title: it.title,
          coverUrl: it.coverUrl,
          episodeCount: it.episodeCount,
          detailUrl: it.detailUrl,
          platform: PlatformType.hongguo,
          tags: ['Full HD', '🟢 100% Unlocked'],
        ));
      }
    } catch (_) {}

    // 3. Fallback: search in loaded home page
    try {
      final homeItems = await _fetchFromHomePage();
      for (final d in homeItems) {
        if (d.title.toLowerCase().contains(qLower) || normalizeChinese(d.title).contains(normQuery)) {
          addUnique(d);
        }
      }
    } catch (_) {}

    // 4. If Bridge is available, query live bridge search
    if (_isBridgeAvailable == true) {
      try {
        final bridgeUrl = await getBridgeUrl();
        final uri = Uri.parse('$bridgeUrl/search?q=${Uri.encodeComponent(query)}&api_key=$apiKey');
        final res = await http.get(uri, headers: {'x-api-key': apiKey}).timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final data = jsonDecode(utf8.decode(res.bodyBytes));
          for (final it in _parseBridgeItems(data)) {
            addUnique(it);
          }
        }
      } catch (_) {}
    }

    return results;
  }

  /// Queries the Hongguo Pro Bridge Engine for catalog categories
  static Future<List<DramaItem>> _fetchCatalogFromBridge(String category) async {
    try {
      final bridgeUrl = await getBridgeUrl();
      final List<DramaItem> allItems = [];
      final Set<String> seenIds = {};

      Future<List<DramaItem>> fetchEndpoint(String endpoint) async {
        try {
          final sep = endpoint.contains('?') ? '&' : '?';
          final uri = Uri.parse('$bridgeUrl$endpoint${sep}api_key=$apiKey');
          final res = await http.get(uri, headers: {'x-api-key': apiKey}).timeout(const Duration(seconds: 10));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            return _parseBridgeItems(data);
          }
        } catch (_) {}
        return [];
      }

      List<Future<List<DramaItem>>> futures = [];

      switch (category) {
        case 'all':
        case 'most_episodes':
          futures = [
            fetchEndpoint('/dl/rank'),
            fetchEndpoint('/latest'),
            fetchEndpoint('/browse?genre=short_play'),
          ];
          break;
        case 'romance':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('豪门')}'),
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('总裁')}'),
          ];
          break;
        case 'transmigration':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('穿越')}'),
          ];
          break;
        case 'time_travel':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('重生')}'),
          ];
          break;
        case 'costume':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('古代')}'),
          ];
          break;
        case 'farming':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('种田')}'),
          ];
          break;
        case 'supernatural':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('战神')}'),
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('异能')}'),
          ];
          break;
        case 'revenge':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('逆袭')}'),
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('复仇')}'),
          ];
          break;
        case 'fantasy':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('修仙')}'),
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('玄幻')}'),
          ];
          break;
        case 'bl_gl':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('双男')}'),
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('纯爱')}'),
          ];
          break;
        case 'urban':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('都市')}'),
          ];
          break;
        case 'comedy':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('喜剧')}'),
          ];
          break;
        case 'suspense':
          futures = [
            fetchEndpoint('/browse?theme=${Uri.encodeComponent('悬疑')}'),
          ];
          break;
        default:
          futures = [
            fetchEndpoint('/dl/rank'),
            fetchEndpoint('/latest'),
          ];
          break;
      }

      final results = await Future.wait(futures);
      for (final list in results) {
        for (final item in list) {
          if (!seenIds.contains(item.id)) {
            seenIds.add(item.id);
            allItems.add(item);
          }
        }
      }

      if (category == 'most_episodes') {
        allItems.sort((a, b) => b.episodeCount.compareTo(a.episodeCount));
      }
      return allItems;
    } catch (_) {
      return [];
    }
  }

  /// Parses items from Bridge JSON responses
  static List<DramaItem> _parseBridgeItems(dynamic json) {
    if (json == null) return [];
    List rawList = [];
    if (json is List) {
      rawList = json;
    } else if (json is Map) {
      if (json['results'] is List) {
        rawList = json['results'];
      } else if (json['items'] is List) {
        rawList = json['items'];
      } else if (json['list'] is List) {
        rawList = json['list'];
      }
    }

    final List<DramaItem> items = [];
    for (final raw in rawList) {
      if (raw is! Map<String, dynamic>) continue;
      final seriesId = '${raw['series_id'] ?? ''}';
      if (seriesId.isEmpty) continue;

      final title = '${raw['title'] ?? raw['series_name'] ?? 'Hongguo Drama'}';
      final cover = '${raw['cover'] ?? raw['series_cover'] ?? ''}';
      final intro = '${raw['intro'] ?? raw['series_intro'] ?? ''}';
      final count = (raw['episode_cnt'] as num?)?.toInt() ?? 0;
      final category = '${raw['category'] ?? ''}';
      final tagsList = category.isNotEmpty ? [category] : <String>[];

      items.add(
        DramaItem(
          id: seriesId,
          title: title,
          coverUrl: cover,
          episodeCount: count,
          intro: intro,
          tags: tagsList,
          detailUrl: '$baseUrl/detail?series_id=$seriesId',
          platform: PlatformType.hongguo,
        ),
      );
    }
    return items;
  }

  static List<DramaItem>? _cachedMostEpisodes;
  static DateTime? _lastMostEpisodesFetch;

  /// Fetches Hongguo dramas with the highest episode count across all sections (1000+, 999+, 788+, etc.)
  static Future<List<DramaItem>> fetchMostEpisodes({int page = 1, int pageSize = 18}) async {
    final now = DateTime.now();
    if (_cachedMostEpisodes == null ||
        _cachedMostEpisodes!.isEmpty ||
        _lastMostEpisodesFetch == null ||
        now.difference(_lastMostEpisodesFetch!).inMinutes > 30) {
      final Map<String, DramaItem> uniqueMap = {};

      void addIfHigher(DramaItem item) {
        if (!uniqueMap.containsKey(item.id) || item.episodeCount > uniqueMap[item.id]!.episodeCount) {
          uniqueMap[item.id] = item;
        }
      }

      // 1. Fetch from Home Page (Contains 1000-ep dramas like 家有五女 7688646466708966462)
      final homeDramas = await _fetchFromHomePage();
      for (final it in homeDramas) {
        addIfHigher(it);
      }

      // 2. Fetch comic-drama pages 1..5 (Contains 1000, 999, 788, 623, 536 eps)
      final comicFutures = List.generate(5, (i) => _fetchSingleWebPage('comic-drama', i + 1));
      // 3. Fetch ai-drama pages 1..3 (Contains 380, 221, 188 eps)
      final aiFutures = List.generate(3, (i) => _fetchSingleWebPage('ai-drama', i + 1));
      // 4. Fetch real-drama pages 1..3 (Contains 142, 119, 108 eps)
      final realFutures = List.generate(3, (i) => _fetchSingleWebPage('real-drama', i + 1));

      final allResults = await Future.wait([...comicFutures, ...aiFutures, ...realFutures]);
      for (final list in allResults) {
        for (final it in list) {
          addIfHigher(it);
        }
      }

      final sorted = uniqueMap.values.toList()
        ..sort((a, b) => b.episodeCount.compareTo(a.episodeCount));

      _cachedMostEpisodes = sorted;
      _lastMostEpisodesFetch = now;
    }

    final total = _cachedMostEpisodes!.length;
    if (total == 0) return [];

    final start = (page - 1) * pageSize;
    if (start >= total) return [];
    final end = math.min(start + pageSize, total);
    return _cachedMostEpisodes!.sublist(start, end);
  }

  /// Extracts dramas from Hongguo home page (including latest 1000-ep featured dramas from hongguoduanju.com & novelquickapp.com)
  static Future<List<DramaItem>> _fetchFromHomePage() async {
    final List<DramaItem> items = [];
    final Set<String> seen = {};

    for (final domain in webDomains) {
      try {
        final response = await http.get(Uri.parse(domain), headers: _headers).timeout(
              const Duration(seconds: 12),
            );
        if (response.statusCode != 200) continue;

        final html = response.body;

        // 1. Parse from _ROUTER_DATA
        const startMarker = '_ROUTER_DATA = ';
        const endMarker = 'function runWindowFn';
        final startIndex = html.indexOf(startMarker);
        if (startIndex >= 0) {
          final endIndex = html.indexOf(endMarker, startIndex);
          if (endIndex >= 0) {
            final rawJson = html.substring(startIndex + startMarker.length, endIndex).trim();
            final cleanJson = rawJson.endsWith(';') ? rawJson.substring(0, rawJson.length - 1) : rawJson;
            final data = jsonDecode(cleanJson);
            final pageData = data['loaderData']?['page'] ?? {};
            final sections = pageData['homeSections'] as List? ?? [];
            for (final s in sections) {
              if (s is! Map) continue;
              final vlist = s['video_list'] as List? ?? [];
              for (final v in vlist) {
                if (v is! Map) continue;
                final sid = '${v['series_id'] ?? ''}'.trim();
                if (sid.isEmpty || seen.contains(sid)) continue;
                final title = '${v['series_title'] ?? v['series_name'] ?? ''}';
                final cover = '${v['series_cover'] ?? ''}';
                final count = (v['episode_cnt'] as num?)?.toInt() ?? 0;
                final intro = '${v['series_intro'] ?? ''}';
                final catList = (v['category_list'] as List?)?.map((e) => '$e').toList() ?? [];

                seen.add(sid);
                items.add(
                  DramaItem(
                    id: sid,
                    title: title,
                    coverUrl: cover,
                    episodeCount: count,
                    intro: intro,
                    tags: catList,
                    detailUrl: '$domain/detail?series_id=$sid',
                    platform: PlatformType.hongguo,
                  ),
                );
              }
            }
          }
        }

        // 2. Parse HTML cards with regex
        final cardRegex = RegExp(
          r'href=["' + "'" + r']/detail\?series_id=(\d+)["' + "'" + r']' +
          r'[\s\S]*?src=["' + "'" + r']([^"' + "'" + r']+)["' + "'" + r']' +
          r'[\s\S]*?alt=["' + "'" + r']([^"' + "'" + r']+)["' + "'" + r']' +
          r'[\s\S]*?<span class=["' + "'" + r']pc-episode[^>]*>全?(\d+)集</span>',
        );
        for (final match in cardRegex.allMatches(html)) {
          final sid = match.group(1)!;
          final cover = match.group(2)!;
          final title = match.group(3)!;
          final eps = int.tryParse(match.group(4)!) ?? 0;
          if (!seen.contains(sid)) {
            seen.add(sid);
            items.add(
              DramaItem(
                id: sid,
                title: title,
                coverUrl: cover,
                episodeCount: eps,
                intro: '全$eps集',
                tags: ['热门榜单', '全集'],
                detailUrl: '$domain/detail?series_id=$sid',
                platform: PlatformType.hongguo,
              ),
            );
          }
        }
      } catch (_) {}
    }
    return items;
  }

  /// Web catalog scraper supporting multi-page loading and correct route slugs
  static Future<List<DramaItem>> _fetchCatalogFromWeb(String category, int page) async {
    if (category == 'most_episodes') {
      return fetchMostEpisodes(page: page);
    }

    if (category == 'all' && page == 1) {
      // Fetch live featured / updated cards from home page (hongguoduanju.com and novelquickapp.com)
      final homeItems = await _fetchFromHomePage();
      // Fetch page 1 of real-drama
      final webItems = await _fetchSingleWebPage('real-drama', 1);

      final Set<String> seen = {};
      final List<DramaItem> combined = [];

      for (final it in homeItems) {
        if (!seen.contains(it.id)) {
          seen.add(it.id);
          combined.add(it);
        }
      }
      for (final it in webItems) {
        if (!seen.contains(it.id)) {
          seen.add(it.id);
          combined.add(it);
        }
      }
      if (combined.isNotEmpty) return combined;
    }

    // Map categories to valid hongguoduanju.com web routes
    String webPath;
    int targetPage = page;

    switch (category) {
      case 'all':
        // For 'all', smoothly paginate through all available categories:
        // Pages 1..34: real-drama (800+ items)
        // Pages 35..68: real-drama/romance (800+ items)
        // Pages 69..100: real-drama/comeback (700+ items)
        if (page <= 34) {
          webPath = 'real-drama';
          targetPage = page;
        } else if (page <= 68) {
          webPath = 'real-drama/romance';
          targetPage = page - 34;
        } else {
          webPath = 'real-drama/comeback';
          targetPage = page - 68;
        }
        break;
      case 'romance':
        webPath = 'real-drama/romance';
        break;
      case 'transmigration':
        webPath = 'real-drama';
        break;
      case 'time_travel':
        webPath = 'real-drama/comeback';
        break;
      case 'costume':
        webPath = 'real-drama/costume';
        break;
      case 'farming':
        webPath = 'real-drama';
        break;
      case 'supernatural':
      case 'revenge':
        webPath = 'real-drama/comeback';
        break;
      case 'fantasy':
        webPath = 'real-drama/costume';
        break;
      case 'bl_gl':
        webPath = 'real-drama';
        break;
      case 'urban':
        webPath = 'real-drama/urban';
        break;
      case 'comedy':
        webPath = 'real-drama';
        break;
      case 'suspense':
        webPath = 'real-drama/suspense';
        break;
      default:
        webPath = 'real-drama';
        break;
    }

    final list = await _fetchSingleWebPage(webPath, targetPage);
    if (category == 'all' || category == 'romance' || category == 'urban' || category == 'costume' || category == 'suspense') {
      return list;
    }
    final filtered = list.where((d) => DramaCategoryHelper.matchesCategory(d, category)).toList();
    return filtered.isNotEmpty ? filtered : list;
  }

  /// Fetches a single page from Hongguo Web (supporting both hongguoduanju.com and novelquickapp.com)
  static Future<List<DramaItem>> _fetchSingleWebPage(String webPath, int page) async {
    for (final domain in webDomains) {
      final uri = Uri.parse('$domain/category/$webPath?page=$page');
      try {
        final response = await http.get(uri, headers: _headers).timeout(
              const Duration(seconds: 12),
            );
        if (response.statusCode != 200) continue;

        final html = response.body;
        const startMarker = '_ROUTER_DATA = ';
        const endMarker = 'function runWindowFn';

        final startIndex = html.indexOf(startMarker);
        if (startIndex < 0) continue;

        final endIndex = html.indexOf(endMarker, startIndex);
        if (endIndex < 0) continue;

        final rawJson = html.substring(startIndex + startMarker.length, endIndex).trim();
        final cleanJson = rawJson.endsWith(';') ? rawJson.substring(0, rawJson.length - 1) : rawJson;

        final data = jsonDecode(cleanJson);
        final categoryData = data['loaderData']?['category_\$'] ?? {};
        final recommendList = categoryData['recommendList'] as List? ?? [];

        final List<DramaItem> items = [];
        for (final raw in recommendList) {
          if (raw is! Map<String, dynamic>) continue;
          final seriesId = '${raw['series_id'] ?? ''}';
          if (seriesId.isEmpty) continue;

          final title = raw['series_name'] ?? 'Hongguo Drama';
          final cover = raw['series_cover'] ?? '';
          final intro = raw['series_intro'] ?? '';
          final count = (raw['episode_cnt'] as num?)?.toInt() ?? 0;
          final tagsList = (raw['tags'] as List?)?.map((e) => '$e').toList() ?? [];

          items.add(
            DramaItem(
              id: seriesId,
              title: title,
              coverUrl: cover,
              episodeCount: count,
              intro: intro,
              tags: tagsList,
              detailUrl: '$domain/detail?series_id=$seriesId',
              platform: PlatformType.hongguo,
            ),
          );
        }
        if (items.isNotEmpty) return items;
      } catch (_) {}
    }
    return [];
  }

  /// Extracts series ID and metadata from a novelquickapp.com share link or text
  static Future<Map<String, String>?> parseNovelQuickShare(String rawInput) async {
    try {
      // 1. Extract URL from raw text
      final urlMatch = RegExp(r'https?://[^\s\u4e00-\u9fa5]+').firstMatch(rawInput);
      if (urlMatch == null) return null;

      final url = urlMatch.group(0)!;
      final uri = Uri.parse(url);

      // Follow redirects to get final landing URL and HTML
      final client = http.Client();
      try {
        final res = await client.get(
          uri,
          headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
            'Accept-Language': 'zh-CN,zh;q=0.9',
          },
        ).timeout(const Duration(seconds: 15));

        final finalUri = res.request?.url ?? uri;
        final finalUrl = finalUri.toString();
        final html = utf8.decode(res.bodyBytes, allowMalformed: true);

        // 2. Extract series_id / video_id
        String seriesId = '';
        final zlink = finalUri.queryParameters['zlink'];
        if (zlink != null && zlink.isNotEmpty) {
          try {
            final zUri = Uri.parse(zlink);
            final schemeParamsStr = zUri.queryParameters['schemeParams'];
            if (schemeParamsStr != null) {
              final sparams = jsonDecode(schemeParamsStr) as Map<String, dynamic>;
              seriesId = '${sparams['video_series_id'] ?? ''}'.trim();
              if (seriesId.isEmpty) {
                seriesId = '${sparams['video_id'] ?? ''}'.trim();
              }
            }
          } catch (_) {}
        }

        // Fallback regex for video_id or series_id in finalUrl or HTML
        if (seriesId.isEmpty) {
          final mVid = RegExp(r'video_id["%22:\\]+([0-9]{15,22})').firstMatch('$finalUrl $html');
          if (mVid != null) {
            seriesId = mVid.group(1)!;
          }
        }

        if (seriesId.isEmpty) {
          final mSeries = RegExp(r'series_id["%22:\\]+([0-9]{15,22})').firstMatch('$finalUrl $html');
          if (mSeries != null) {
            seriesId = mSeries.group(1)!;
          }
        }

        if (seriesId.isEmpty) return null;

        // 3. Extract Title
        String title = '';
        final titleInText = RegExp(r'《(.*?)》').firstMatch(rawInput);
        if (titleInText != null) {
          title = titleInText.group(1)!.trim();
        }
        if (title.isEmpty) {
          final titleInHtml = RegExp(r'<title[^>]*>.*?《(.*?)》.*?</title>').firstMatch(html);
          if (titleInHtml != null) {
            title = titleInHtml.group(1)!.trim();
          }
        }
        if (title.isEmpty) {
          final tMatch = RegExp(r'"series_data":\{"title":"([^"]+)"').firstMatch(html);
          if (tMatch != null) {
            title = tMatch.group(1)!.trim();
          }
        }

        // 4. Extract Cover
        String cover = '';
        final covMatch =
            RegExp(r'<meta\s+property=["' + r"']og:image[" + r"']\s+content=[" + r"']([^" + r"']+)[" + r"']").firstMatch(html);
        if (covMatch != null) {
          cover = covMatch.group(1)!;
        }

        return {
          'seriesId': seriesId,
          'title': title,
          'cover': cover,
        };
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Resolve drama metadata and episodes (supports Hongguo Pro Engine Bridge for FULL 100% episodes and novelquickapp links)
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    String cleanId = rawQuery.trim();
    String detectedTitle = '';
    String detectedCover = '';
    int detectedEps = 0;

    // Check if query is a novelquickapp.com share link / message
    if (cleanId.contains('novelquickapp.com')) {
      final nq = await parseNovelQuickShare(cleanId);
      if (nq != null && nq['seriesId'] != null) {
        cleanId = nq['seriesId']!;
        detectedTitle = nq['title'] ?? '';
        detectedCover = nq['cover'] ?? '';
      }
    } else if (cleanId.contains('series_id=')) {
      cleanId = cleanId.split('series_id=').last.split('&').first;
    } else if (cleanId.contains('/player/')) {
      cleanId = cleanId.split('/player/').last.split('?').first.split('/').first;
    } else {
      // Find series ID digits
      final idMatch = RegExp(r'(\d{15,22})').firstMatch(cleanId);
      if (idMatch != null) {
        cleanId = idMatch.group(1)!;
      }
    }

    if (cleanId.isEmpty) return null;

    await _ensureCatalogLoaded();

    // Check if cleanId matches ID or Title in local catalog
    DramaItem? localMeta;
    if (_cachedCatalog != null && _cachedCatalog!.isNotEmpty) {
      localMeta = _cachedCatalog!.where((d) => d.id == cleanId || d.title.toLowerCase() == cleanId.toLowerCase()).firstOrNull;
      if (localMeta != null) {
        if (detectedTitle.isEmpty) detectedTitle = localMeta.title;
        if (detectedCover.isEmpty) detectedCover = localMeta.coverUrl;
        if (detectedEps == 0) detectedEps = localMeta.episodeCount;
        cleanId = localMeta.id;
      }
    }

    // 1. Check if Hongguo Pro Bridge is connected (optional PC server)
    final hasBridge = await checkBridgeConnection();
    if (hasBridge) {
      final bridgeDrama = await _resolveFromBridge(cleanId);
      if (bridgeDrama != null && bridgeDrama.episodes != null && bridgeDrama.episodes!.isNotEmpty) {
        if ((bridgeDrama.title.isEmpty || bridgeDrama.title.startsWith('Hongguo Drama')) && detectedTitle.isNotEmpty) {
          return DramaItem(
            id: bridgeDrama.id,
            title: detectedTitle,
            coverUrl: detectedCover.isNotEmpty ? detectedCover : bridgeDrama.coverUrl,
            episodeCount: bridgeDrama.episodeCount,
            intro: bridgeDrama.intro,
            tags: bridgeDrama.tags,
            detailUrl: bridgeDrama.detailUrl,
            platform: bridgeDrama.platform,
            episodes: bridgeDrama.episodes,
          );
        }
        return bridgeDrama;
      }
    }

    // 2. Fallback to Web Scraping (Hongguo Web provides first 3 episodes free)
    final webDrama = await _resolveFromWeb(cleanId);
    DramaItem? finalDrama = webDrama;

    if (finalDrama == null) {
      final titleToUse = detectedTitle.isNotEmpty ? detectedTitle : cleanId;
      final count = detectedEps > 0 ? detectedEps : 60;
      final List<EpisodeItem> episodes = List.generate(
        count,
        (i) => EpisodeItem(
          index: i + 1,
          title: 'EP${(i + 1).toString().padLeft(2, '0')}',
          chapterName: '🟢 Full HD (1080p)',
          isFree: true,
        ),
      );
      finalDrama = DramaItem(
        id: cleanId,
        title: titleToUse,
        coverUrl: detectedCover.isNotEmpty ? detectedCover : (localMeta?.coverUrl ?? ''),
        episodeCount: count,
        intro: localMeta?.intro ?? '',
        tags: localMeta?.tags ?? ['Full HD', 'Hongguo'],
        detailUrl: '$baseUrl/detail?series_id=$cleanId',
        platform: PlatformType.hongguo,
        episodes: episodes,
      );
    } else if (detectedTitle.isNotEmpty && (finalDrama.title.isEmpty || finalDrama.title.startsWith('Hongguo Drama'))) {
      finalDrama = DramaItem(
        id: finalDrama.id,
        title: detectedTitle,
        coverUrl: detectedCover.isNotEmpty ? detectedCover : finalDrama.coverUrl,
        episodeCount: finalDrama.episodeCount,
        intro: finalDrama.intro,
        tags: finalDrama.tags,
        detailUrl: finalDrama.detailUrl,
        platform: finalDrama.platform,
        episodes: finalDrama.episodes,
      );
    }

    // 3. Fallback: Mirror Aggregation to unlock episodes 4+ if bridge is offline
    if (finalDrama != null) {
      finalDrama = await enhanceWithMirror(finalDrama);
    }
    return finalDrama;
  }

  /// Resolves ALL episodes via Hongguo Pro Engine
  static Future<DramaItem?> _resolveFromBridge(String seriesId) async {
    try {
      final bridgeUrl = await getBridgeUrl();
      final uri = Uri.parse('$bridgeUrl/episodes?series_id=$seriesId&api_key=$apiKey');
      final res = await http.get(
        uri,
        headers: {'x-api-key': apiKey},
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) return null;

      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final epList = (data['episodes'] as List? ?? []);
      if (epList.isEmpty) return null;

      final meta = (data['meta'] is Map<String, dynamic>)
          ? data['meta'] as Map<String, dynamic>
          : <String, dynamic>{};

      // Extract metadata (supports both flat and nested meta schemas)
      String title = data['title'] ?? meta['title'] ?? meta['series_name'] ?? '';
      String cover = data['cover'] ?? meta['cover'] ?? meta['series_cover'] ?? '';
      String intro = data['intro'] ?? meta['intro'] ?? meta['series_intro'] ?? '';
      List<String> tags = [];

      // If title or cover missing from bridge, attempt to scrape from web
      if (title.isEmpty || cover.isEmpty) {
        final webMeta = await _scrapeWebMeta(seriesId);
        if (title.isEmpty) title = webMeta['title'] ?? 'Hongguo Drama $seriesId';
        if (cover.isEmpty) cover = webMeta['cover'] ?? '';
        if (intro.isEmpty) intro = webMeta['intro'] ?? '';
        tags = webMeta['tags'] ?? [];
      }

      final List<EpisodeItem> episodes = [];
      for (final raw in epList) {
        if (raw is! Map<String, dynamic>) continue;
        final epIndex = (raw['index'] as num?)?.toInt() ?? 1;
        final vid = '${raw['vid'] ?? ''}';

        episodes.add(
          EpisodeItem(
            index: epIndex,
            title: 'EP${epIndex.toString().padLeft(2, '0')}',
            vid: vid,
            chapterName: '🟢 Full HD (1080p)',
            streamUrl: '$bridgeUrl/stream?vid=$vid&api_key=$apiKey',
          ),
        );

      }

      return DramaItem(
        id: seriesId,
        title: title,
        coverUrl: cover,
        episodeCount: episodes.length,
        intro: intro,
        tags: tags,
        detailUrl: '$baseUrl/detail?series_id=$seriesId',
        platform: PlatformType.hongguo,
        episodes: episodes,
      );
    } catch (_) {
      return null;
    }
  }

  /// Scrapes basic drama metadata from Web without stream links
  static Future<Map<String, dynamic>> _scrapeWebMeta(String seriesId) async {
    final Map<String, dynamic> meta = {};
    for (final domain in webDomains) {
      try {
        final response = await http.get(Uri.parse('$domain/player/$seriesId'), headers: _headers).timeout(
              const Duration(seconds: 10),
            );
        if (response.statusCode == 200) {
          final html = response.body;
          const startMarker = '_ROUTER_DATA = ';
          const endMarker = 'function runWindowFn';

          final startIndex = html.indexOf(startMarker);
          if (startIndex >= 0) {
            final endIndex = html.indexOf(endMarker, startIndex);
            if (endIndex >= 0) {
              final rawJson = html.substring(startIndex + startMarker.length, endIndex).trim();
              final cleanJson = rawJson.endsWith(';') ? rawJson.substring(0, rawJson.length - 1) : rawJson;

              final data = jsonDecode(cleanJson);
              final loaderData = data['loaderData'] ?? {};
              final pageData = loaderData['player_(series_id)/page'] ?? {};
              final detail = pageData['seriesDetail'] ?? {};

              meta['title'] = detail['series_name'];
              meta['cover'] = detail['series_cover'];
              meta['intro'] = detail['series_intro'];
              meta['tags'] = (detail['tags'] as List?)?.map((e) => '$e').toList();
              if (meta['title'] != null && '${meta['title']}'.isNotEmpty) break;
            }
          }
        }
      } catch (_) {}
    }
    return meta;
  }

  /// Resolves drama using Hongguo Web API (3 episodes free)
  static Future<DramaItem?> _resolveFromWeb(String cleanId) async {
    final List<String> targets = [];
    for (final domain in webDomains) {
      targets.add('$domain/player/$cleanId');
      targets.add('$domain/detail?series_id=$cleanId');
    }

    for (final targetUrl in targets) {
      try {
        final response = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(
              const Duration(seconds: 15),
            );
        if (response.statusCode != 200) continue;

        final html = response.body;
        const startMarker = '_ROUTER_DATA = ';
        const endMarker = 'function runWindowFn';

        final startIndex = html.indexOf(startMarker);
        if (startIndex < 0) continue;

        final endIndex = html.indexOf(endMarker, startIndex);
        if (endIndex < 0) continue;

        final rawJson = html.substring(startIndex + startMarker.length, endIndex).trim();
        final cleanJson = rawJson.endsWith(';') ? rawJson.substring(0, rawJson.length - 1) : rawJson;

        final data = jsonDecode(cleanJson);
        final loaderData = data['loaderData'] ?? {};
        final pageData = loaderData['player_(series_id)/page'] ?? loaderData['detail_page'] ?? {};
        final detail = pageData['seriesDetail'] ?? {};
        final vidList = (detail['vid_list'] as List?)?.map((e) => '$e').toList() ?? [];

        final title = detail['series_name'] ?? '';
        final cover = detail['series_cover'] ?? '';
        final intro = detail['series_intro'] ?? '';
        final count = (detail['episode_cnt'] as num?)?.toInt() ?? vidList.length;
        final tagsList = (detail['tags'] as List?)?.map((e) => '$e').toList() ?? [];

        final accessibleCnt = (detail['accessible_episode_cnt'] as num?)?.toInt() ?? 3;

        final List<EpisodeItem> episodes = [];
        for (int i = 0; i < vidList.length; i++) {
          final epIndex = i + 1;
          final isFree = epIndex <= accessibleCnt;
          episodes.add(
            EpisodeItem(
              index: epIndex,
              title: 'EP${epIndex.toString().padLeft(2, '0')}',
              vid: vidList[i],
              chapterName: isFree ? 'ឥតគិតថ្លៃ (Free)' : '🔒 VIP (App)',
            ),
          );
        }

        if (episodes.isEmpty && count > 0) {
          for (int i = 0; i < count; i++) {
            final epIndex = i + 1;
            episodes.add(
              EpisodeItem(
                index: epIndex,
                title: 'EP${epIndex.toString().padLeft(2, '0')}',
                chapterName: epIndex <= accessibleCnt ? 'ឥតគិតថ្លៃ (Free)' : '🔒 VIP (App)',
              ),
            );
          }
        }

        if (title.isNotEmpty && (episodes.isNotEmpty || count > 0)) {
          return DramaItem(
            id: cleanId,
            title: title,
            coverUrl: cover,
            episodeCount: count,
            intro: intro,
            tags: tagsList,
            detailUrl: '$baseUrl/detail?series_id=$cleanId',
            platform: PlatformType.hongguo,
            episodes: episodes,
          );
        }
      } catch (_) {}
    }
    return null;
  }

  /// Directly fetches official clean 720p MP4 stream from Hongguo protected playback API (Standalone - No PC Server needed)
  static Future<String?> fetchHongguoDirectStream(String seriesId, String vid) async {
    if (vid.isEmpty) return null;
    final endpoints = [
      'https://hongguoduanju.com/api/video/protected/fallback-play-info',
      'https://hongguoduanju.com/api/video/protected/play-info',
      'https://novelquickapp.com/api/video/protected/fallback-play-info',
      'https://novelquickapp.com/api/video/protected/play-info',
    ];

    for (final ep in endpoints) {
      try {
        final uri = Uri.parse(ep);
        final isPlayInfo = ep.endsWith('play-info');
        final Map<String, dynamic> body = isPlayInfo
            ? {'series_id': seriesId, 'item_id': vid, 'definition': '720p'}
            : {'item_id': vid};

        final response = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
            'Referer': 'https://hongguoduanju.com/player/$seriesId/$vid',
            'Origin': 'https://hongguoduanju.com',
            'Accept': 'application/json, text/plain, */*',
          },
          body: jsonEncode(body),
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
          final rawData = json['data'] ?? json;
          final playData = (rawData is Map<String, dynamic>)
              ? (rawData['play_info'] is Map<String, dynamic> ? rawData['play_info'] : rawData)
              : <String, dynamic>{};

          final streamUrl = (playData['main_url'] ?? playData['url'] ?? playData['backup_url']) as String?;
          if (streamUrl != null && streamUrl.isNotEmpty) {
            return streamUrl;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Resolve direct MP4 stream URL for a specific episode vid (supports direct Hongguo API & mirror fallback)
  static Future<String?> resolveEpisodeStream(
    String seriesId,
    String vid, {
    String? dramaTitle,
    int? episodeIndex,
  }) async {
    // 1. Direct Hongguo Web Play-Info API (Standalone on phone, 100% clean direct MP4)
    if (vid.isNotEmpty) {
      final direct = await fetchHongguoDirectStream(seriesId, vid);
      if (direct != null && direct.isNotEmpty) {
        return direct;
      }
    }

    // 2. Fallback: Mirror cross-resolution (BMP4, BeePlaylet, etc.) when Web VIP is restricted
    if (dramaTitle != null && dramaTitle.isNotEmpty && episodeIndex != null && episodeIndex > 0) {
      try {
        final mirror = await searchMirrorDrama(dramaTitle);
        if (mirror != null && mirror.episodes != null) {
          final ep = mirror.episodes!.where((e) => e.index == episodeIndex).firstOrNull;
          if (ep?.streamUrl != null && ep!.streamUrl!.isNotEmpty) {
            return ep.streamUrl;
          }
        }
      } catch (_) {}
    }

    // 3. Fallback: Hongguo web routes episode streams via path segment /player/{series_id}/{vid}
    for (final domain in webDomains) {
      final targetUrl = '$domain/player/$seriesId/$vid';
      try {
        final response = await http.get(
          Uri.parse(targetUrl),
          headers: _headers,
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final html = response.body;
          const startMarker = '_ROUTER_DATA = ';
          const endMarker = 'function runWindowFn';

          final startIndex = html.indexOf(startMarker);
          if (startIndex >= 0) {
            final endIndex = html.indexOf(endMarker, startIndex);
            if (endIndex >= 0) {
              final rawJson = html.substring(startIndex + startMarker.length, endIndex).trim();
              final cleanJson = rawJson.endsWith(';') ? rawJson.substring(0, rawJson.length - 1) : rawJson;

              final data = jsonDecode(cleanJson);
              final loaderData = data['loaderData'] as Map<String, dynamic>? ?? {};

              final epData = loaderData['player_(series_id)/(vid)/page'] as Map<String, dynamic>?;
              if (epData != null) {
                final pageVid = '${epData['vid'] ?? ''}';
                if (pageVid == vid || pageVid.isEmpty) {
                  final epPlayerInfo = epData['video_player_info'] as Map<String, dynamic>?;
                  final epUrl = epPlayerInfo?['main_url'] as String?;
                  if (epUrl != null && epUrl.isNotEmpty) {
                    return epUrl;
                  }
                }
              }

              for (final entry in loaderData.values) {
                if (entry is Map<String, dynamic>) {
                  final entryVid = '${entry['vid'] ?? ''}';
                  if (entryVid == vid) {
                    final pInfo = entry['video_player_info'] as Map<String, dynamic>?;
                    final mainUrl = pInfo?['main_url'] as String?;
                    if (mainUrl != null && mainUrl.isNotEmpty) {
                      return mainUrl;
                    }
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    // 4. Fallback: ONLY if Bridge PC Server is explicitly verified active and online
    if (_isBridgeAvailable == true) {
      final bridgeUrl = await getBridgeUrl();
      if (vid.isNotEmpty && bridgeUrl.isNotEmpty && !bridgeUrl.contains('192.168.18.5')) {
        return '$bridgeUrl/stream?vid=$vid&api_key=$apiKey';
      }
    }

    return null;
  }

  /// Searches Chinese drama mirror platforms (BMP4, BeePlaylet, 8Movie) for matching unlocked episodes
  static Future<DramaItem?> searchMirrorDrama(String rawTitle) async {
    String cleanTitle = rawTitle
        .replaceAll(RegExp(r'《|》|\[|\]|\(|\)|（|）|【|】|“|”|\s*-\s*短剧.*$|\s*-\s*.*$'), '')
        .replaceAll('短剧', '')
        .replaceAll('已完结在线播放', '')
        .replaceAll('全集在线播放', '')
        .replaceAll('在线播放', '')
        .replaceAll('Hongguo', '')
        .replaceAll(RegExp(r'[\\/*?:"<>|]'), '')
        .trim();

    if (cleanTitle.isEmpty) return null;

    final cacheKey = normalizeChinese(cleanTitle);
    if (_mirrorCache.containsKey(cacheKey)) {
      return _mirrorCache[cacheKey];
    }

    final List<String> searchKeywords = [];
    searchKeywords.add(cleanTitle);

    // Split on common Chinese punctuation to extract core title
    final parts = cleanTitle.split(RegExp(r'[,，、：:\s]'));
    if (parts.isNotEmpty && parts.first.length >= 2 && parts.first != cleanTitle) {
      searchKeywords.add(parts.first.trim());
    }
    if (parts.length > 1 && parts[1].length >= 2) {
      searchKeywords.add(parts[1].trim());
    }
    if (cleanTitle.length > 6) {
      searchKeywords.add(cleanTitle.substring(0, 6));
    }
    if (cleanTitle.length > 4 && !searchKeywords.contains(cleanTitle.substring(0, 4))) {
      searchKeywords.add(cleanTitle.substring(0, 4));
    }

    // Add Traditional Chinese forms of keywords for BeePlaylet
    final tradKeywords = <String>[];
    for (final kw in searchKeywords) {
      final t = simplifiedToTraditional(kw);
      if (t != kw && !tradKeywords.contains(t)) {
        tradKeywords.add(t);
      }
    }

    final allKws = [...searchKeywords, ...tradKeywords];

    for (final kw in allKws) {
      // 1. Search BMP4 (Fastest and highly reliable for full unlocked episodes)
      try {
        final bmpResults = await Bmp4Service.search(kw);
        if (bmpResults.isNotEmpty) {
          DramaItem? best;
          for (final item in bmpResults) {
            if (_isFuzzyTitleMatch(cleanTitle, item.title)) {
              best = item;
              break;
            }
          }
          if (best != null) {
            final resolved = await Bmp4Service.resolveDrama(best.id);
            if (resolved != null && resolved.episodes != null && resolved.episodes!.isNotEmpty) {
              _mirrorCache[cacheKey] = resolved;
              return resolved;
            }
          }
        }
      } catch (_) {}

      // 2. Search BeePlaylet
      try {
        final beeResults = await BeeplayletService.search(kw);
        if (beeResults.isNotEmpty) {
          DramaItem? best;
          for (final item in beeResults) {
            if (_isFuzzyTitleMatch(cleanTitle, item.title)) {
              best = item;
              break;
            }
          }
          if (best != null) {
            final resolved = await BeeplayletService.resolveDrama(best.id);
            if (resolved != null && resolved.episodes != null && resolved.episodes!.isNotEmpty) {
              _mirrorCache[cacheKey] = resolved;
              return resolved;
            }
          }
        }
      } catch (_) {}

      // 3. Search 8Movie
      try {
        final results = await EightMovieService.search(kw);
        if (results.isNotEmpty) {
          DramaItem? best;
          for (final item in results) {
            if (_isFuzzyTitleMatch(cleanTitle, item.title)) {
              best = item;
              break;
            }
          }
          if (best != null) {
            final resolved = await EightMovieService.resolveDrama(best.id);
            if (resolved != null && resolved.episodes != null && resolved.episodes!.isNotEmpty) {
              _mirrorCache[cacheKey] = resolved;
              return resolved;
            }
          }
        }
      } catch (_) {}
    }

    _mirrorCache[cacheKey] = null;
    return null;
  }

  /// Checks if two titles are actually the same drama using normalized Chinese characters
  static bool _isFuzzyTitleMatch(String cleanTitle, String candidateTitle) {
    final a = normalizeChinese(cleanTitle);
    final b = normalizeChinese(candidateTitle);

    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;

    // Substring containment
    if (a.length >= 3 && b.contains(a)) return true;
    if (b.length >= 3 && a.contains(b)) return true;

    // Sub-token / 4-character overlap match
    if (a.length >= 4 && b.length >= 4) {
      if (b.startsWith(a.substring(0, 4)) || a.startsWith(b.substring(0, 4))) return true;
      for (int i = 0; i <= a.length - 4; i++) {
        final sub = a.substring(i, i + 4);
        if (b.contains(sub)) return true;
      }
    }

    return false;
  }

  /// Unlocks VIP episodes 4+ by cross-referencing mirror platforms if bridge is unavailable
  static Future<DramaItem> enhanceWithMirror(DramaItem webDrama) async {
    try {
      final mirror = await searchMirrorDrama(webDrama.title);
      final currentEpisodes = webDrama.episodes ?? [];

      if (mirror == null || mirror.episodes == null || mirror.episodes!.isEmpty) {
        // Ensure all episodes up to episodeCount are populated and marked isFree
        final totalCount = math.max(webDrama.episodeCount, currentEpisodes.length);
        final List<EpisodeItem> updatedEpisodes = [];

        for (int i = 1; i <= totalCount; i++) {
          final webEp = currentEpisodes.where((e) => e.index == i).firstOrNull;
          if (webEp != null && webEp.streamUrl != null && webEp.streamUrl!.isNotEmpty) {
            updatedEpisodes.add(webEp);
          } else {
            updatedEpisodes.add(EpisodeItem(
              index: i,
              title: webEp?.title ?? 'EP${i.toString().padLeft(2, '0')}',
              vid: webEp?.vid,
              chapterName: '🟢 Full HD (1080p)',
              isFree: true,
            ));
          }
        }

        return DramaItem(
          id: webDrama.id,
          title: webDrama.title,
          coverUrl: webDrama.coverUrl,
          episodeCount: totalCount,
          intro: webDrama.intro,
          tags: webDrama.tags,
          detailUrl: webDrama.detailUrl,
          platform: webDrama.platform,
          episodes: updatedEpisodes,
        );
      }

      final mirrorEpMap = <int, EpisodeItem>{};
      for (final ep in mirror.episodes!) {
        mirrorEpMap[ep.index] = ep;
      }

      final updatedEpisodes = <EpisodeItem>[];
      final totalCount = math.max(webDrama.episodeCount, mirror.episodes!.length);

      for (int i = 1; i <= totalCount; i++) {
        final webEp = currentEpisodes.where((e) => e.index == i).firstOrNull;
        final mirrorEp = mirrorEpMap[i];

        if (webEp != null && webEp.streamUrl != null && webEp.streamUrl!.isNotEmpty) {
          // Free episode 1-3 from Hongguo web
          updatedEpisodes.add(EpisodeItem(
            index: i,
            title: webEp.title,
            vid: webEp.vid,
            chapterName: '🟢 Full HD (Hongguo)',
            streamUrl: webEp.streamUrl,
            isFree: true,
          ));
        } else if (mirrorEp != null && mirrorEp.streamUrl != null && mirrorEp.streamUrl!.isNotEmpty) {
          // Unlocked from mirror in Full HD
          updatedEpisodes.add(EpisodeItem(
            index: i,
            title: webEp?.title ?? mirrorEp.title,
            vid: webEp?.vid ?? mirrorEp.vid,
            chapterName: '🟢 Full HD (1080p)',
            streamUrl: mirrorEp.streamUrl,
            isFree: true,
          ));
        } else if (webEp != null) {
          updatedEpisodes.add(EpisodeItem(
            index: i,
            title: webEp.title,
            vid: webEp.vid,
            chapterName: '🟢 Full HD (1080p)',
            streamUrl: mirrorEp?.streamUrl,
            isFree: true,
          ));
        } else {
          updatedEpisodes.add(EpisodeItem(
            index: i,
            title: 'EP${i.toString().padLeft(2, '0')}',
            chapterName: '🟢 Full HD (1080p)',
            streamUrl: mirrorEp?.streamUrl,
            isFree: true,
          ));
        }
      }

      return DramaItem(
        id: webDrama.id,
        title: webDrama.title,
        coverUrl: webDrama.coverUrl.isNotEmpty ? webDrama.coverUrl : mirror.coverUrl,
        episodeCount: totalCount,
        intro: webDrama.intro.isNotEmpty ? webDrama.intro : mirror.intro,
        tags: webDrama.tags.isNotEmpty ? webDrama.tags : mirror.tags,
        detailUrl: webDrama.detailUrl,
        platform: webDrama.platform,
        episodes: updatedEpisodes,
      );
    } catch (_) {
      return webDrama;
    }
  }
}
