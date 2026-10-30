import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drama_models.dart';

class BeeplayletService {
  static const String baseUrl = 'https://beeplaylet.com';
  static const String cdnBaseUrl = 'https://cdn.17video.net';

  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Referer': 'https://beeplaylet.com/',
  };

  /// Fetch catalog from BeePlaylet API with strict validation against broken dramas
  static Future<List<DramaItem>> fetchCatalog({
    int page = 1,
    String category = 'all',
  }) async {
    final offset = (page - 1) * 24;
    String endpoint;
    if (category == 'rank') {
      endpoint = '/api/Playlet/RankingList?offset=$offset&count=24';
    } else if (category == 'latest') {
      endpoint = '/api/Playlet/Latest?offset=$offset&count=24';
    } else if (category == 'free') {
      endpoint = '/api/Playlet/FreeList?offset=$offset&count=24';
    } else {
      // Default to HotList for high-quality, complete 50-150 episode series
      endpoint = '/api/Playlet/HotList?offset=$offset&count=24';
    }

    try {
      final response = await http
          .get(Uri.parse('$baseUrl$endpoint'), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      final dynamic rawData = json['data'];
      List list = [];
      if (rawData is Map && rawData['data'] is List) {
        list = rawData['data'] as List;
      } else if (rawData is List) {
        list = rawData;
      }

      final List<DramaItem> items = [];
      for (final it in list) {
        if (it is! Map) continue;
        final sid = '${it['id'] ?? it['seriesId'] ?? ''}';
        if (sid.isEmpty) continue;

        final title = '${it['name'] ?? it['title'] ?? ''}'.trim();
        if (title.isEmpty) continue;

        // Skip incomplete or empty dramas that have <= 1 episode
        final epsCount = int.tryParse('${it['seriesCount']}') ?? 0;
        if (epsCount <= 1) continue;

        var cover = '${it['verticalCover'] ?? it['targetCover'] ?? it['cover'] ?? ''}'.trim();
        if (cover.isEmpty) continue;
        if (!cover.startsWith('http')) {
          cover = '$cdnBaseUrl$cover';
        }

        items.add(
          DramaItem(
            id: sid,
            title: title,
            coverUrl: cover,
            episodeCount: epsCount,
            detailUrl: '$baseUrl/playlet/detail?id=$sid',
            platform: PlatformType.beeplaylet,
            tags: ['Full HD', 'BeePlaylet'],
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Search dramas on BeePlaylet
  static Future<List<DramaItem>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];

    final targetUrl = '$baseUrl/api/Playlet/Search?keyword=${Uri.encodeComponent(query)}&offset=0&count=30';
    try {
      final response = await http
          .get(Uri.parse(targetUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];

      final json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      final dynamic rawData = json['data'];
      List list = [];
      if (rawData is Map && rawData['data'] is List) {
        list = rawData['data'] as List;
      } else if (rawData is List) {
        list = rawData;
      }

      final List<DramaItem> items = [];
      for (final it in list) {
        if (it is! Map) continue;
        final sid = '${it['id'] ?? it['seriesId'] ?? ''}';
        if (sid.isEmpty) continue;

        final title = '${it['name'] ?? it['title'] ?? ''}'.trim();
        if (title.isEmpty) continue;

        final epsCount = int.tryParse('${it['seriesCount']}') ?? 0;
        if (epsCount <= 1) continue;

        var cover = '${it['verticalCover'] ?? it['targetCover'] ?? it['cover'] ?? ''}'.trim();
        if (cover.isEmpty) continue;
        if (!cover.startsWith('http')) {
          cover = '$cdnBaseUrl$cover';
        }

        items.add(
          DramaItem(
            id: sid,
            title: title,
            coverUrl: cover,
            episodeCount: epsCount,
            detailUrl: '$baseUrl/playlet/detail?id=$sid',
            platform: PlatformType.beeplaylet,
            tags: ['Full HD'],
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Resolve drama episodes from BeePlaylet with all episodes merged & sorted
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    String text = rawQuery.trim();
    String sid = text;

    final idMatch = RegExp(r'(?:id|seriesId)=(\d+)').firstMatch(text);
    if (idMatch != null) {
      sid = idMatch.group(1)!;
    } else {
      final numMatch = RegExp(r'(\d+)').firstMatch(text);
      if (numMatch != null) {
        sid = numMatch.group(1)!;
      }
    }

    if (sid.isEmpty) return null;

    final targetUrl = '$baseUrl/api/Playlet/Series?playletId=$sid';
    try {
      final response = await http
          .get(Uri.parse(targetUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
      final dynamic data = json['data'];
      if (data is! Map) return null;

      final currentPlaylet = data['currentPlaylet'] as Map?;
      final title = '${currentPlaylet?['name'] ?? 'BeePlaylet_$sid'}'.trim();
      var cover = '${currentPlaylet?['verticalCover'] ?? currentPlaylet?['targetCover'] ?? currentPlaylet?['cover'] ?? ''}'.trim();
      if (cover.isNotEmpty && !cover.startsWith('http')) {
        cover = '$cdnBaseUrl$cover';
      }

      // Collect all videos: currentVideo + videos array
      final List<Map<dynamic, dynamic>> allVideoMaps = [];
      final Set<dynamic> seenIds = {};

      final curVideo = data['currentVideo'];
      if (curVideo is Map && curVideo['url'] != null && '${curVideo['url']}'.isNotEmpty) {
        final vId = curVideo['id'] ?? curVideo['seriesNumber'];
        if (vId != null) seenIds.add(vId);
        allVideoMaps.add(curVideo);
      }

      final rawVideos = data['videos'] as List? ?? [];
      for (final v in rawVideos) {
        if (v is! Map) continue;
        final vId = v['id'] ?? v['seriesNumber'];
        if (vId != null && seenIds.contains(vId)) continue;
        if (vId != null) seenIds.add(vId);
        allVideoMaps.add(v);
      }

      if (allVideoMaps.isEmpty) return null;

      // Sort by episode/series number
      allVideoMaps.sort((a, b) {
        final na = int.tryParse('${a['seriesNumber']}') ?? 0;
        final nb = int.tryParse('${b['seriesNumber']}') ?? 0;
        return na.compareTo(nb);
      });

      final List<EpisodeItem> episodes = [];
      for (int i = 0; i < allVideoMaps.length; i++) {
        final it = allVideoMaps[i];
        final epNum = i + 1; // 1-indexed sequential
        final origNum = int.tryParse('${it['seriesNumber']}') ?? epNum;
        final rawTitle = '${it['seriesName'] ?? ''}'.trim();
        final epTitle = rawTitle.isNotEmpty ? rawTitle : 'EP${epNum.toString().padLeft(2, '0')}';

        var videoUrl = '${it['url'] ?? ''}'.trim();
        if (videoUrl.isNotEmpty && !videoUrl.startsWith('http')) {
          videoUrl = '$cdnBaseUrl$videoUrl';
        }

        episodes.add(
          EpisodeItem(
            index: epNum,
            title: 'EP${epNum.toString().padLeft(2, '0')}',
            chapterName: epTitle,
            chapterId: '${it['id'] ?? epNum}',
            streamUrl: videoUrl.isNotEmpty ? videoUrl : null,
            isFree: true,
          ),
        );
      }

      return DramaItem(
        id: sid,
        title: title,
        coverUrl: cover,
        episodeCount: episodes.length,
        detailUrl: '$baseUrl/playlet/detail?id=$sid',
        platform: PlatformType.beeplaylet,
        episodes: episodes,
        tags: ['Full HD', 'BeePlaylet'],
      );
    } catch (_) {
      return null;
    }
  }
}
