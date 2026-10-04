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

  /// Fetch catalog from BeePlaylet API
  static Future<List<DramaItem>> fetchCatalog({
    int page = 1,
    String category = 'latest',
  }) async {
    final offset = (page - 1) * 24;
    String endpoint;
    if (category == 'hot') {
      endpoint = '/api/Playlet/HotList?offset=$offset&count=24';
    } else if (category == 'rank') {
      endpoint = '/api/Playlet/RankingList?offset=$offset&count=24';
    } else if (category == 'free') {
      endpoint = '/api/Playlet/FreeList?offset=$offset&count=24';
    } else {
      endpoint = '/api/Playlet/Latest?offset=$offset&count=24';
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

        final title = '${it['name'] ?? it['title'] ?? 'BeePlaylet Drama'}'.trim();
        var cover = '${it['verticalCover'] ?? it['cover'] ?? it['targetCover'] ?? ''}'.trim();
        if (cover.isNotEmpty && !cover.startsWith('http')) {
          cover = '$cdnBaseUrl$cover';
        }

        final epsCount = int.tryParse('${it['seriesCount']}') ?? 50;

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

        final title = '${it['name'] ?? it['title'] ?? 'BeePlaylet Drama'}'.trim();
        var cover = '${it['verticalCover'] ?? it['cover'] ?? it['targetCover'] ?? ''}'.trim();
        if (cover.isNotEmpty && !cover.startsWith('http')) {
          cover = '$cdnBaseUrl$cover';
        }

        final epsCount = int.tryParse('${it['seriesCount']}') ?? 50;

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

  /// Resolve drama episodes from BeePlaylet
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
      var cover = '${currentPlaylet?['verticalCover'] ?? currentPlaylet?['targetCover'] ?? ''}'.trim();
      if (cover.isNotEmpty && !cover.startsWith('http')) {
        cover = '$cdnBaseUrl$cover';
      }

      final rawVideos = data['videos'] as List? ?? [];
      final List<EpisodeItem> episodes = [];

      for (int i = 0; i < rawVideos.length; i++) {
        final it = rawVideos[i];
        if (it is! Map) continue;

        final epNum = int.tryParse('${it['seriesNumber']}') ?? (i + 1);
        final epTitle = '${it['seriesName'] ?? 'EP${epNum.toString().padLeft(2, '0')}'}';
        var videoUrl = '${it['url'] ?? ''}'.trim();
        if (videoUrl.isNotEmpty && !videoUrl.startsWith('http')) {
          videoUrl = '$cdnBaseUrl$videoUrl';
        }

        episodes.add(
          EpisodeItem(
            index: epNum,
            title: epTitle,
            chapterName: epTitle,
            streamUrl: videoUrl.isNotEmpty ? videoUrl : null,
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
        tags: ['Full HD'],
      );
    } catch (_) {
      return null;
    }
  }
}
