import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drama_models.dart';

class EightMovieService {
  static const String baseUrl = 'https://8movie.com';
  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://8movie.com/',
  };

  /// Categories on 8movie
  static List<Map<String, String>> getCategories() {
    return [
      {'id': 'all', 'name': '🎬 ទាំងអស់ (All)'},
      {'id': 'rank', 'name': '🔥 ពេញនិយម (Rank)'},
      {'id': 'update', 'name': '⚡ ថ្មីៗ (Latest)'},
      {'id': 'bazong', 'name': '👑 មហាសេដ្ឋី (CEO)'},
      {'id': 'nixi', 'name': '⚔️ សងសឹក (Revenge)'},
      {'id': 'nuelian', 'name': '💖 ស្នេហាកម្សត់ (Drama)'},
      {'id': 'shuangju', 'name': '💥 វាយប្រហារ (Action)'},
    ];
  }

  /// Fetch catalog from 8movie.com
  static Future<List<DramaItem>> fetchCatalog({
    String category = 'all',
    int page = 1,
  }) async {
    String path;
    if (category == 'rank') {
      path = page == 1 ? '/movies/rank/' : '/movies/rank/$page/';
    } else if (category == 'update') {
      path = page == 1 ? '/movies/update/' : '/movies/update/$page/';
    } else if (category == 'bazong') {
      path = page == 1 ? '/movies/tags/BaZong/' : '/movies/tags/BaZong/$page/';
    } else if (category == 'nixi') {
      path = page == 1 ? '/movies/tags/NiXi/' : '/movies/tags/NiXi/$page/';
    } else if (category == 'nuelian') {
      path = page == 1 ? '/movies/tags/NueLian/' : '/movies/tags/NueLian/$page/';
    } else if (category == 'shuangju') {
      path = page == 1 ? '/movies/tags/ShuangJu/' : '/movies/tags/ShuangJu/$page/';
    } else {
      // Default to rank & update to ensure high quality real drama posters
      path = page == 1 ? '/movies/rank/' : (page == 2 ? '/movies/update/' : '/movies/$page/');
    }

    final targetUrl = '$baseUrl$path';
    try {
      final response = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return [];

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final List<DramaItem> items = [];
      final Set<String> seenIds = {};

      final cardRegex = RegExp(
        r'''<a[^>]+href=['"]/(?:movies|play)/(\d+)['"][^>]*title=['"]([^'"]+)['"][^>]*>\s*<img[^>]+(?:src|data-src)=['"]([^'"]+)['"][^>]*>([\s\S]*?)</a>''',
        caseSensitive: false,
      );

      for (final match in cardRegex.allMatches(html)) {
        final mid = match.group(1) ?? '';
        if (mid.isEmpty || seenIds.contains(mid)) continue;
        seenIds.add(mid);

        final title = (match.group(2) ?? '8Movie Drama').trim();
        var cover = match.group(3) ?? '';
        if (cover.isNotEmpty && !cover.startsWith('http')) {
          cover = '$baseUrl$cover';
        }
        final inside = match.group(4) ?? '';
        final epsMatch = RegExp(r'<eps>(\d+)').firstMatch(inside);
        final count = epsMatch != null ? int.parse(epsMatch.group(1)!) : 60;

        items.add(
          DramaItem(
            id: mid,
            title: title,
            coverUrl: cover,
            episodeCount: count,
            detailUrl: '$baseUrl/play/$mid',
            platform: PlatformType.eightmovie,
            tags: ['Full HD'],
          ),
        );
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  /// Search dramas on 8movie.com
  static Future<List<DramaItem>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];

    final targetUrl = '$baseUrl/search/?key=${Uri.encodeComponent(query)}';
    try {
      final response = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return [];

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final List<DramaItem> items = [];
      final Set<String> seenIds = {};

      final cardRegex = RegExp(
        r'''<a[^>]+href=['"]/(?:movies|play)/(\d+)['"][^>]*title=['"]([^'"]+)['"][^>]*>[\s\S]*?<img[^>]+(?:src|data-src)=['"]([^'"]+)['"]''',
        caseSensitive: false,
      );

      for (final match in cardRegex.allMatches(html)) {
        final mid = match.group(1) ?? '';
        if (mid.isEmpty || seenIds.contains(mid)) continue;
        seenIds.add(mid);

        final title = (match.group(2) ?? '8Movie Drama').trim();
        var cover = match.group(3) ?? '';
        if (cover.isNotEmpty && !cover.startsWith('http')) {
          cover = '$baseUrl$cover';
        }

        items.add(
          DramaItem(
            id: mid,
            title: title,
            coverUrl: cover,
            episodeCount: 60,
            detailUrl: '$baseUrl/play/$mid',
            platform: PlatformType.eightmovie,
            tags: ['Full HD'],
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Resolve drama episodes and direct streams on 8movie
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    String text = rawQuery.trim();
    String mid = text;

    final idMatch = RegExp(r'/(?:play|movies)/(\d+)').firstMatch(text);
    if (idMatch != null) {
      mid = idMatch.group(1)!;
    } else if (RegExp(r'^\d+$').hasMatch(text)) {
      mid = text;
    }

    if (mid.isEmpty) return null;
    final playUrl = '$baseUrl/play/$mid';

    try {
      final response = await http.get(Uri.parse(playUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return null;

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);

      // Extract title
      final titleMatch = RegExp(r'<title>(.*?)</title>').firstMatch(html);
      String title = titleMatch?.group(1) ?? '8Movie Drama';
      title = title.replaceAll(RegExp(r'\s*-\s*(?:播放頁|八影短劇網).*$'), '').trim();
      title = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), '').trim();
      if (title.isEmpty) title = '8Movie_$mid';

      // Extract cover
      final coverMatch =
          RegExp(r'<meta\s+property=["' + r"']og:image[" + r"']\s+content=[" + r"']([^" + r"']+)[" + r"']").firstMatch(html);
      String cover = coverMatch?.group(1) ?? '';
      if (cover.isEmpty) {
        final pMatch = RegExp('/p/$mid-[^\\s"\'<>]+\\.jpg').firstMatch(html);
        if (pMatch != null) {
          cover = '$baseUrl${pMatch.group(0)}';
        }
      }

      // Extract episodes JSON array: episodes: [{"episode":"1","title":"001","src":"...mp4"}, ...]
      final epsMatch = RegExp(r'episodes:\s*(\[\s*\{.*?\}\s*\])', dotAll: true).firstMatch(html);
      List rawEpisodes = [];
      if (epsMatch != null) {
        try {
          rawEpisodes = jsonDecode(epsMatch.group(1)!) as List;
        } catch (_) {}
      }

      final List<EpisodeItem> episodes = [];
      for (int i = 0; i < rawEpisodes.length; i++) {
        final it = rawEpisodes[i];
        if (it is! Map) continue;
        final epIdx = int.tryParse('${it["episode"]}') ?? (i + 1);
        final src = '${it["src"] ?? ''}';

        episodes.add(
          EpisodeItem(
            index: epIdx,
            title: 'EP${epIdx.toString().padLeft(2, '0')}',
            chapterName: 'Episode $epIdx',
            streamUrl: src.isNotEmpty ? src : null,
          ),
        );
      }

      return DramaItem(
        id: mid,
        title: title,
        coverUrl: cover,
        episodeCount: episodes.length,
        detailUrl: playUrl,
        platform: PlatformType.eightmovie,
        episodes: episodes,
      );
    } catch (e) {
      return null;
    }
  }
}
