import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drama_models.dart';

class ReelsDizimService {
  static const String baseUrl = 'https://reelsdizim.com';
  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://reelsdizim.com/',
  };

  /// Categories on ReelsDizim
  static List<Map<String, String>> getCategories() {
    return [
      {'id': 'all', 'name': '🔥 ទាំងអស់ (All)'},
      {'id': 'reelshort', 'name': '⚡ ReelShort (1450+)'},
      {'id': 'shortmax', 'name': '🎬 ShortMax'},
      {'id': 'netshort', 'name': '📱 NetShort'},
    ];
  }

  /// Fetch catalog list from reelsdizim.com
  static Future<List<DramaItem>> fetchCatalog({
    String category = 'all',
    int page = 1,
  }) async {
    String targetUrl;
    if (category == 'reelshort') {
      targetUrl = '$baseUrl/tr/yayinci/reelshort?page=$page';
    } else if (category == 'shortmax') {
      targetUrl = '$baseUrl/tr/yayinci/shortmax?page=$page';
    } else if (category == 'netshort') {
      targetUrl = '$baseUrl/tr/yayinci/netshort?page=$page';
    } else {
      targetUrl = '$baseUrl/tr/diziler?page=$page';
    }

    try {
      final response = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return [];

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final List<DramaItem> items = [];
      final Set<String> seenSlugs = {};

      final cardRegex = RegExp(
        r'<a\s+href="(/tr/dizi/([a-zA-Z0-9\-_]+))"[^>]*>[\s\S]*?<img[^>]+src="([^"]+)"[\s\S]*?<p[^>]*class="[^"]*font-semibold[^"]*"[^>]*>([^<]+)</p>\s*<p[^>]*class="[^"]*text-faint[^"]*"[^>]*>([\s\S]*?)</p>',
      );

      final matches = cardRegex.allMatches(html);
      if (matches.isNotEmpty) {
        for (final m in matches) {
          final slug = m.group(2) ?? '';
          if (slug.isEmpty || seenSlugs.contains(slug)) continue;
          seenSlugs.add(slug);

          var rawImg = m.group(3) ?? '';
          if (rawImg.contains('url=')) {
            final uMatch = RegExp(r'url=([^&]+)').firstMatch(rawImg);
            if (uMatch != null) rawImg = Uri.decodeComponent(uMatch.group(1)!);
          }
          rawImg = rawImg.replaceAll('&amp;', '&');

          final rawTitle = m.group(4) ?? slug;
          final title = rawTitle.replaceAll('&amp;', '&').replaceAll('&#x27;', "'").replaceAll('&quot;', '"').trim();
          final meta = m.group(5) ?? '';
          final epMatch = RegExp(r'(\d+)\s*Bölüm', caseSensitive: false).firstMatch(meta);
          final epCnt = int.tryParse(epMatch?.group(1) ?? '') ?? 60;

          items.add(
            DramaItem(
              id: slug,
              title: title,
              coverUrl: rawImg,
              episodeCount: epCnt,
              detailUrl: '$baseUrl/tr/dizi/$slug',
              platform: PlatformType.reelsdizim,
              tags: ['Full HD'],
            ),
          );
        }
      } else {
        // Fallback card structure
        final fallbackRegex = RegExp(r'href="(/tr/dizi/([a-zA-Z0-9\-_]+))"[^>]*>.*?<img[^>]*src="([^"]+)"', dotAll: true);
        for (final m in fallbackRegex.allMatches(html)) {
          final slug = m.group(2) ?? '';
          if (slug.isEmpty || seenSlugs.contains(slug)) continue;
          seenSlugs.add(slug);

          var rawImg = m.group(3) ?? '';
          if (rawImg.contains('url=')) {
            final uMatch = RegExp(r'url=([^&]+)').firstMatch(rawImg);
            if (uMatch != null) rawImg = Uri.decodeComponent(uMatch.group(1)!);
          }
          rawImg = rawImg.replaceAll('&amp;', '&');

          final title = slug.replaceAll('-', ' ').split(' ').map((w) => w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : '').join(' ');

          items.add(
            DramaItem(
              id: slug,
              title: title,
              coverUrl: rawImg,
              episodeCount: 60,
              detailUrl: '$baseUrl/tr/dizi/$slug',
              platform: PlatformType.reelsdizim,
              tags: ['Full HD'],
            ),
          );
        }
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  /// Resolve drama and all episode M3U8 streams on reelsdizim.com
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    String text = rawQuery.trim();
    String slug = text;

    final slugMatch = RegExp(r'/tr/(?:dizi|izle)/([a-zA-Z0-9\-_]+)').firstMatch(text);
    if (slugMatch != null) {
      slug = slugMatch.group(1)!;
    }
    slug = slug.replaceAll(RegExp(r'/\d+$'), '');

    if (slug.isEmpty) return null;
    final watchUrl = '$baseUrl/tr/izle/$slug/1';

    try {
      final response = await http.get(Uri.parse(watchUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return null;

      final html = response.body;

      // Extract title
      final titleMatch = RegExp(r'<title>(.*?)</title>').firstMatch(html);
      String title = titleMatch?.group(1) ?? slug.replaceAll('-', ' ');
      title = title.replaceAll(RegExp(r'\s*[-|–].*$'), '').trim();
      title = title.replaceAll(RegExp(r'\s*\d+\.\s*Bölüm.*$', caseSensitive: false), '').trim();
      title = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), '').trim();
      if (title.isEmpty) title = slug;

      // Extract cover from meta og:image
      final ogMatch = RegExp(r'<meta\s+property=["' + r"']og:image[" + r"']\s+content=[" + r"']([^" + r"']+)[" + r"']").firstMatch(html);
      String cover = ogMatch?.group(1) ?? '';
      if (cover.endsWith('og-default.png')) cover = '';

      // Extract all episode M3U8 URLs: (https://cdn.dramaflix.co/...eps-(N)...m3u8)
      final streamRegex = RegExp(r'(https://cdn\.dramaflix\.co/[^\s"<>\\]+eps-(\d+)[^\s"<>\\]*\.m3u8)');
      final Map<int, String> epDict = {};

      for (final match in streamRegex.allMatches(html)) {
        final streamUrl = match.group(1)!.replaceAll('\\', '');
        final epNum = int.tryParse(match.group(2) ?? '');
        if (epNum != null && !epDict.containsKey(epNum)) {
          epDict[epNum] = streamUrl;
        }
      }

      final List<EpisodeItem> episodes = [];
      for (final entry in (epDict.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
        episodes.add(
          EpisodeItem(
            index: entry.key,
            title: 'EP${entry.key.toString().padLeft(2, '0')}',
            chapterName: 'Episode ${entry.key}',
            streamUrl: entry.value,
          ),
        );
      }

      return DramaItem(
        id: slug,
        title: title,
        coverUrl: cover,
        episodeCount: episodes.length,
        detailUrl: watchUrl,
        platform: PlatformType.reelsdizim,
        episodes: episodes,
      );
    } catch (e) {
      return null;
    }
  }
}
