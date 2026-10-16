import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import '../models/drama_models.dart';

class IqiyiCreatorService {
  static const List<String> creatorIds = [
    '1373641237', // 无穷剧场 (1186 dramas)
    '1790739464', // 887 dramas
    '1109148581', // 245 dramas
    '1264794284', // 791 dramas
  ];

  static const String _deviceId = '98916247d2f8865df8359e9f952ca4fa';
  static const String _appVersion = '17.094.26512';
  static const String _secretKey = 'howcuteitis';

  static List<DramaItem>? _cachedCatalog;
  static bool _isLoadingCatalog = false;

  static String _generateSign(Map<String, dynamic> params) {
    final keys = params.keys.toList()..sort();
    final parts = <String>[];
    for (final k in keys) {
      final v = params[k];
      if (v != null) {
        parts.add('$k=$v');
      }
    }
    parts.add('secret_key=$_secretKey');
    final raw = parts.join('&');
    return md5.convert(utf8.encode(raw)).toString().toUpperCase();
  }

  /// Ensure comprehensive catalog of 3,109 creator dramas is loaded from assets
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
      final jsonStr = await rootBundle.loadString('assets/data/iqiyi_creators_catalog.json');
      final dynamic raw = jsonDecode(jsonStr);
      if (raw is List) {
        _cachedCatalog = raw
            .map((item) => DramaItem.fromJson(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('Error loading cached creator catalog: $e');
    } finally {
      _cachedCatalog ??= [];
      _isLoadingCatalog = false;
    }
  }

  /// Fetch dramas for a specific page across creator accounts
  static Future<List<DramaItem>> fetchCatalog({int page = 1, int pageSize = 18}) async {
    return fetchCatalogByCategory(category: 'all', page: page, pageSize: pageSize);
  }

  /// Fetch dramas filtered by category or sorted by highest episode count
  static Future<List<DramaItem>> fetchCatalogByCategory({
    String category = 'all',
    int page = 1,
    int pageSize = 18,
  }) async {
    await _ensureLoaded();

    if (_cachedCatalog == null || _cachedCatalog!.isEmpty) {
      // Fallback: live fetch first page from all 4 creators
      final futures = creatorIds.map((cid) => _fetchCreatorWorks(cid, page: page, pageSize: 6));
      final res = await Future.wait(futures);
      final List<DramaItem> liveItems = [];
      for (final l in res) {
        liveItems.addAll(l);
      }
      return liveItems;
    }

    // Quick live check on page 1 in background to prepend newly added works
    if (page == 1 && category == 'all') {
      _quickLiveSync();
    }

    List<DramaItem> filteredList;
    if (category == 'all') {
      filteredList = _cachedCatalog!;
    } else if (category == 'most_episodes') {
      // Sort by episodeCount descending (highest episodes first)
      filteredList = List<DramaItem>.from(_cachedCatalog!)
        ..sort((a, b) => b.episodeCount.compareTo(a.episodeCount));
    } else {
      filteredList = _cachedCatalog!
          .where((d) => DramaCategoryHelper.matchesCategory(d, category))
          .toList();
    }

    final total = filteredList.length;
    if (total == 0) return [];

    final start = (page - 1) * pageSize;
    if (start >= total) {
      final wrappedStart = start % total;
      final end = math.min(wrappedStart + pageSize, total);
      return filteredList.sublist(wrappedStart, end);
    }

    final end = math.min(start + pageSize, total);
    return filteredList.sublist(start, end);
  }

  /// Search across all 3,100+ creator dramas
  static Future<List<DramaItem>> search(String query) async {
    await _ensureLoaded();
    if (_cachedCatalog == null || _cachedCatalog!.isEmpty) return [];

    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    return _cachedCatalog!.where((d) {
      return d.title.toLowerCase().contains(q) ||
          d.intro.toLowerCase().contains(q) ||
          d.id.contains(q);
    }).toList();
  }

  /// In background, check if creator has newer items and prepend to _cachedCatalog
  static void _quickLiveSync() async {
    try {
      final futures = creatorIds.map((cid) => _fetchCreatorWorks(cid, page: 1, pageSize: 3));
      final results = await Future.wait(futures);
      final Set<String> existingIds = _cachedCatalog!.map((d) => d.id).toSet();
      final List<DramaItem> newItems = [];
      for (final list in results) {
        for (final item in list) {
          if (!existingIds.contains(item.id)) {
            newItems.add(item);
            existingIds.add(item.id);
          }
        }
      }
      if (newItems.isNotEmpty) {
        _cachedCatalog!.insertAll(0, newItems);
      }
    } catch (_) {}
  }

  static Future<List<DramaItem>> _fetchCreatorWorks(String creatorId, {int page = 1, int pageSize = 12}) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final params = <String, dynamic>{
        'app_version': _appVersion,
        'auth_cookie': '',
        'device_id': _deviceId,
        'is_vip': 0,
        'next_params': '',
        'page': page,
        'page_size': pageSize,
        'src': 'creator',
        'timestamp': ts,
        'uploader_id': creatorId,
        'user_id': '',
      };
      params['sign'] = _generateSign(params);

      final uri = Uri.parse('https://mesh.if.iqiyi.com/tvg/my/home/works').replace(
        queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
      );

      final resp = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': 'https://www.iqiyi.com/creator/$creatorId',
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return [];

      final data = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final albums = data['data']?['albums']?['items'] as List<dynamic>? ?? [];

      return albums.map((item) {
        final title = item['title'] ?? 'រឿងភាគខ្លី';
        final rawImg = item['image_url'] ?? '';
        final cover = rawImg.replaceAll('.avif', '.jpg');
        final entityId = '${item['entity_id']}';
        final videoId = '${item['video_id'] ?? ''}';
        final updateStatus = item['update_status'] ?? '';
        final pageUrl = item['page_url'] ?? '';

        int count = 0;
        final countMatch = RegExp(r'(\d+)').firstMatch(updateStatus);
        if (countMatch != null) {
          count = int.tryParse(countMatch.group(1)!) ?? 0;
        }

        return DramaItem(
          id: 'iqiyi_${entityId}_$videoId',
          title: title,
          coverUrl: cover,
          episodeCount: count,
          intro: item['desc'] ?? '',
          detailUrl: pageUrl.isNotEmpty
              ? pageUrl
              : 'https://www.iqiyi.com/creator/$creatorId?entity_id=$entityId&video_id=$videoId',
          platform: PlatformType.web20,
          heat: '${item['works_num'] ?? ''}',
          tags: ['Full HD', if (count > 0) '$count ភាគចប់'],
        );
      }).toList();
    } catch (e) {
      debugPrint('Error fetching iQIYI creator $creatorId: $e');
      return [];
    }
  }

  /// Resolve drama metadata & all episodes from entity_id or video_id
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    try {
      String? entityId;
      String? videoId;

      // Extract entity_id or video_id from URL or raw query
      if (rawQuery.contains('video_id=')) {
        videoId = RegExp(r'video_id=(\d+)').firstMatch(rawQuery)?.group(1);
      }
      if (rawQuery.contains('entity_id=')) {
        entityId = RegExp(r'entity_id=(\d+)').firstMatch(rawQuery)?.group(1);
      }
      if (rawQuery.startsWith('iqiyi_')) {
        final parts = rawQuery.replaceFirst('iqiyi_', '').split('_');
        if (parts.length >= 2) {
          entityId = parts[0];
          videoId = parts[1];
        } else if (parts.isNotEmpty) {
          entityId = parts[0];
        }
      }

      // If rawQuery is pure numeric ID
      if (entityId == null && videoId == null && RegExp(r'^\d+$').hasMatch(rawQuery.trim())) {
        entityId = rawQuery.trim();
      }

      // If page URL like https://www.iqiyi.com/v_xxxx.html
      // Query accelerator.js if it's an iQIYI web URL
      if (rawQuery.contains('iqiyi.com/v_') || rawQuery.contains('iqiyi.com/')) {
        try {
          final accUri = Uri.parse('https://www.iqiyi.com/prelw/player/lw/lwplay/accelerator.js').replace(
            queryParameters: {'apiVer': '3', 'lwaver': _appVersion, 'appver': _appVersion},
          );
          final accResp = await http.get(accUri, headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': rawQuery.startsWith('http') ? rawQuery : 'https://$rawQuery',
          }).timeout(const Duration(seconds: 10));
          if (accResp.statusCode == 200) {
            final accM = RegExp(r'window\.QiyiPlayerProphetData\s*=\s*(\{.*?\});', dotAll: true).firstMatch(accResp.body);
            if (accM != null) {
              final pdata = json.decode(accM.group(1)!) as Map<String, dynamic>;
              final vid = '${pdata['tvId'] ?? pdata['tvid'] ?? ''}';
              final vinfo = pdata['videoInfo'] as Map<String, dynamic>? ?? {};
              final aid = '${vinfo['albumId'] ?? ''}';
              if (vid.isNotEmpty && vid != '0') videoId = vid;
              if (aid.isNotEmpty && aid != '0') entityId = aid;
            }
          }
        } catch (_) {}
      }

      if (rawQuery.contains('iqiyi.com/v_') || rawQuery.contains('iqiyi.com/')) {
        final pageResp = await http.get(
          Uri.parse(rawQuery),
          headers: {'User-Agent': 'Mozilla/5.0'},
        ).timeout(const Duration(seconds: 10));

        if (pageResp.statusCode == 200) {
          final body = pageResp.body;
          // Look for albumId or tvid in page
          final aidMatch = RegExp(r'"albumId":\s*(\d+)').firstMatch(body) ??
              RegExp(r'"aid":\s*(\d+)').firstMatch(body) ??
              RegExp(r'albumid=(\d+)').firstMatch(body);
          if (aidMatch != null) entityId = aidMatch.group(1);

          final vidMatch = RegExp(r'"tvId":\s*(\d+)').firstMatch(body) ??
              RegExp(r'"tvid":\s*(\d+)').firstMatch(body) ??
              RegExp(r'tvid=(\d+)').firstMatch(body);
          if (vidMatch != null) videoId = vidMatch.group(1);
        }
      }

      if (videoId == null && entityId != null) {
        await _ensureLoaded();
        if (_cachedCatalog != null) {
          for (final d in _cachedCatalog!) {
            if (d.id.contains(entityId) && d.id.contains('_')) {
              videoId = d.id.split('_').lastOrNull;
              break;
            }
          }
        }
      }

      final queryId = videoId ?? entityId ?? rawQuery.replaceAll(RegExp(r'\D'), '');
      if (queryId.isEmpty) return null;

      // Call tvg/v2/lw/base_info
      final ts = DateTime.now().millisecondsSinceEpoch;
      final params = <String, dynamic>{
        'app_mode': 'standard',
        'app_version': _appVersion,
        'auth_cookie': '',
        'device_id': _deviceId,
        'entity_id': queryId,
        'os': '10.0',
        'pcv': _appVersion,
        'player_type': 'mini',
        'scale': 100,
        'src': 'pca_tvg',
        'timestamp': ts,
        'user_id': 0,
        'vip_status': 0,
        'vip_type': -1,
      };
      params['sign'] = _generateSign(params);

      final uri = Uri.parse('https://mesh.if.iqiyi.com/tvg/v2/lw/base_info').replace(
        queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
      );

      final resp = await http.get(
        uri,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': rawQuery.startsWith('http') ? rawQuery : 'https://www.iqiyi.com/',
        },
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) return null;

      final jsonMap = json.decode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      var template = jsonMap['data']?['template'];

      if (template == null && entityId != null && videoId != null && queryId != videoId) {
        params['entity_id'] = videoId;
        params['timestamp'] = DateTime.now().millisecondsSinceEpoch;
        params['sign'] = _generateSign(params);
        final fallbackUri = Uri.parse('https://mesh.if.iqiyi.com/tvg/v2/lw/base_info').replace(
          queryParameters: params.map((k, v) => MapEntry(k, v.toString())),
        );
        final fbResp = await http.get(fallbackUri, headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': rawQuery.startsWith('http') ? rawQuery : 'https://www.iqiyi.com/',
        }).timeout(const Duration(seconds: 15));
        if (fbResp.statusCode == 200) {
          final fbJson = json.decode(utf8.decode(fbResp.bodyBytes)) as Map<String, dynamic>;
          template = fbJson['data']?['template'];
        }
      }

      if (template == null) return null;

      final tabs = template['tabs'] as List<dynamic>? ?? [];
      Map<String, dynamic>? selectorBlock;
      Map<String, dynamic>? metaBlock;

      for (final tab in tabs) {
        final blocks = tab['blocks'] as List<dynamic>? ?? [];
        for (final b in blocks) {
          if (b['bk_id'] == 'immersion_selector_bk') {
            selectorBlock = b;
          } else if (b['bk_id'] == 'meta_info_bk') {
            metaBlock = b;
          }
        }
      }

      final videosBlock = selectorBlock?['data']?['data']?[0]?['videos'];
      final featurePaged = videosBlock?['feature_paged'] as Map<String, dynamic>? ?? {};
      final pageKeys = (videosBlock?['page_keys'] as List<dynamic>?)?.map((e) => '$e').toList() ?? featurePaged.keys.toList();

      final List<EpisodeItem> episodes = [];
      int orderCounter = 1;

      for (final key in pageKeys) {
        final pagedItems = featurePaged[key] as List<dynamic>? ?? [];
        for (final ep in pagedItems) {
          if (ep['is_ad'] == true || ep['play_url'] == null) continue;

          final epOrder = ep['album_order'] is int ? ep['album_order'] as int : orderCounter++;
          final title = ep['short_title'] ?? ep['title'] ?? 'ភាគ $epOrder';
          var pageUrl = ep['page_url'] ?? '';
          if (pageUrl.startsWith('//')) {
            pageUrl = 'https:$pageUrl';
          }

          episodes.add(EpisodeItem(
            index: epOrder,
            title: title,
            streamUrl: pageUrl.isNotEmpty ? pageUrl : null,
            isFree: true,
          ));
        }
      }

      episodes.sort((a, b) => a.index.compareTo(b.index));

      // Extract drama title & cover
      String title = metaBlock?['data']?['title'] ?? '';
      if (title.isEmpty || title == 'រឿងភាគ iQIYI') {
        // 1. Check cached catalog
        if (_cachedCatalog != null) {
          final matched = _cachedCatalog!.where((d) =>
              d.id.contains(queryId) || (entityId != null && d.id.contains(entityId))).firstOrNull;
          if (matched != null && matched.title.isNotEmpty) {
            title = matched.title;
          }
        }
        // 2. Infer from first episode title (e.g. "婚变知真心 第1集" -> "婚变知真心")
        if (title.isEmpty || title == 'រឿងភាគ iQIYI') {
          if (episodes.isNotEmpty) {
            final epTitle = episodes.first.title;
            final cleanTitle = epTitle.replaceAll(RegExp(r'\s*第?\d+.*$'), '').trim();
            if (cleanTitle.isNotEmpty) {
              title = cleanTitle;
            }
          }
        }
      }
      if (title.isEmpty) {
        title = 'រឿងភាគ iQIYI';
      }

      String cover = '';
      if (episodes.isNotEmpty && selectorBlock != null) {
        final firstItem = (featurePaged[pageKeys.first] as List<dynamic>?)?.firstOrNull;
        if (firstItem != null && firstItem['image_url'] != null) {
          cover = '${firstItem['image_url']}'.replaceAll('.avif', '.jpg');
        }
      }

      return DramaItem(
        id: 'iqiyi_${entityId ?? queryId}',
        title: title,
        coverUrl: cover,
        episodeCount: episodes.length,
        intro: metaBlock?['data']?['desc'] ?? '',
        detailUrl: rawQuery.startsWith('http') ? rawQuery : 'https://www.iqiyi.com/creator/1373641237?entity_id=$queryId',
        platform: PlatformType.web20,
        episodes: episodes,
      );
    } catch (e) {
      debugPrint('Error resolving iQIYI drama: $e');
      return null;
    }
  }

  /// Resolve stream .m3u8 from episode page_url
  static Future<String?> resolveEpisodeStream(String episodePageUrl) async {
    try {
      var targetUrl = episodePageUrl;
      if (!targetUrl.startsWith('http')) {
        targetUrl = 'https://$targetUrl';
      }

      final uri = Uri.parse('https://www.iqiyi.com/prelw/player/lw/lwplay/accelerator.js').replace(
        queryParameters: {
          'apiVer': '3',
          'lwaver': _appVersion,
          'appver': _appVersion,
        },
      );

      final resp = await http.get(
        uri,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Referer': targetUrl,
        },
      ).timeout(const Duration(seconds: 12));

      if (resp.statusCode != 200) return null;

      final body = utf8.decode(resp.bodyBytes, allowMalformed: true);
      final m = RegExp(r'window\.QiyiPlayerProphetData\s*=\s*(\{.*?\});', dotAll: true).firstMatch(body);
      if (m == null) return null;

      final prophet = json.decode(m.group(1)!) as Map<String, dynamic>;
      final ev = prophet['ev'] as String?;
      if (ev == null || ev.isEmpty) return null;

      // XOR 90 decoding
      final decodedJson = String.fromCharCodes(ev.codeUnits.map((c) => 90 ^ c));
      final dash = json.decode(decodedJson) as Map<String, dynamic>;

      final videos = dash['data']?['program']?['video'] as List<dynamic>? ?? [];
      if (videos.isEmpty) return null;

      final tvid = '${dash['data']?['tvid'] ?? prophet['tvid'] ?? prophet['tvId'] ?? ''}';
      final vid = videos.isNotEmpty ? '${videos[0]['vid'] ?? ''}' : '';

      // 1. Primary: Use TMTS API (returns verified playable m3utx without HTTP 405 error)
      if (tvid.isNotEmpty && vid.isNotEmpty) {
        try {
          final tm = DateTime.now().millisecondsSinceEpoch;
          const key = 'd5fb4bd9d50c4be6948c97edd7254b0e';
          final sc = md5.convert(utf8.encode('$tm$key$tvid')).toString();
          final tmtsUri = Uri.parse('http://cache.m.iqiyi.com/jp/tmts/$tvid/$vid/').replace(
            queryParameters: {
              'tvid': tvid,
              'vid': vid,
              'src': '76f90cbd92f94a2e925d83e8ccd22cb7',
              'sc': sc,
              't': '$tm',
            },
          );
          final tmtsRes = await http.get(
            tmtsUri,
            headers: {'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15'},
          ).timeout(const Duration(seconds: 10));

          if (tmtsRes.statusCode == 200 && tmtsRes.body.contains('{')) {
            final txt = tmtsRes.body;
            final startIdx = txt.indexOf('{');
            final endIdx = txt.lastIndexOf('}');
            if (startIdx >= 0 && endIdx >= startIdx) {
              final rawJson = txt.substring(startIdx, endIdx + 1);
              final tmtsData = json.decode(rawJson) as Map<String, dynamic>;
              final tData = tmtsData['data'] as Map<String, dynamic>? ?? {};
              if (tData['m3utx'] != null && '${tData['m3utx']}'.isNotEmpty) {
                return '${tData['m3utx']}';
              }
              final vidl = tData['vidl'] as List<dynamic>? ?? [];
              for (final s in vidl) {
                if (s['m3utx'] != null && '${s['m3utx']}'.isNotEmpty) {
                  return '${s['m3utx']}';
                }
              }
            }
          }
        } catch (ex) {
          debugPrint('TMTS stream fetch notice: $ex');
        }
      }

      // 2. Secondary fallback: Prefer highest quality H.264 or H.265 m3u8
      String? bestM3u8;
      int highestBid = 0;

      for (final v in videos) {
        final ml = v['ml'] as String?;
        final bid = v['bid'] is int ? v['bid'] as int : int.tryParse('${v['bid']}') ?? 0;
        if (ml != null && ml.isNotEmpty) {
          if (bid >= highestBid) {
            highestBid = bid;
            bestM3u8 = ml;
          }
        }
      }

      return bestM3u8;
    } catch (e) {
      debugPrint('Error resolving iQIYI episode stream: $e');
      return null;
    }
  }
}
