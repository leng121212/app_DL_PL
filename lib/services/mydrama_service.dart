import 'package:http/http.dart' as http;
import '../models/drama_models.dart';

class MyDramaService {
  static const String baseUrl = 'https://my-drama.com';
  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://my-drama.com/',
  };

  /// Fetch catalog list from my-drama.com
  static Future<List<DramaItem>> fetchCatalog({int page = 1}) async {
    final targetUrl = '$baseUrl/';
    try {
      final response = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return [];

      final html = response.body;
      final List<DramaItem> items = [];
      final Set<String> seenIds = {};

      // Pattern 1: Escaped JSON in Next.js SSR script
      final escapedPattern = RegExp(
        r'\\?"videoId\\?":\\?"([a-f0-9\-]{36})\\?",\\?"name\\?":\\?"([^\\"]+)\\?",\\?"description\\?":\\?"([^\\"]*)\\?",(?:\\?"clearCover\\?":\\?"([^\\"]*)\\?",)?\\?"coverUrl\\?":\\?"([^\\"]+)\\?"',
      );

      for (final m in escapedPattern.allMatches(html)) {
        final vid = m.group(1) ?? '';
        if (vid.isEmpty || seenIds.contains(vid)) continue;
        seenIds.add(vid);

        var name = m.group(2) ?? 'MyDrama Series';
        name = name.replaceAll(r'\"', '"').trim();

        var desc = m.group(3) ?? '';
        desc = desc.replaceAll(r'\"', '"').trim();

        var cover = m.group(5) ?? m.group(4) ?? '';
        cover = cover.replaceAll(r'\"', '').replaceAll(r'\/', '/').trim();

        items.add(
          DramaItem(
            id: vid,
            title: name,
            coverUrl: cover,
            episodeCount: 60,
            intro: desc,
            detailUrl: '$baseUrl/video/$vid',
            platform: PlatformType.mydrama,
            tags: ['Full HD'],
          ),
        );
      }

      // Pattern 2 fallback: standard HTML cards
      if (items.isEmpty) {
        final cardRegex = RegExp(
          r'<a[^>]*href="(/video/[^"]+)"[^>]*>.*?<img[^>]*src="([^"]+)"[^>]*alt="([^"]+)".*?</a>',
          dotAll: true,
        );
        for (final match in cardRegex.allMatches(html)) {
          final href = match.group(1) ?? '';
          final cover = match.group(2) ?? '';
          final title = match.group(3) ?? 'MyDrama Series';
          final id = href.split('/').where((s) => s.isNotEmpty).last;
          if (!seenIds.contains(id)) {
            seenIds.add(id);
            items.add(
              DramaItem(
                id: id,
                title: title.trim(),
                coverUrl: cover.startsWith('http') ? cover : '$baseUrl$cover',
                episodeCount: 60,
                detailUrl: '$baseUrl$href',
                platform: PlatformType.mydrama,
                tags: ['Full HD'],
              ),
            );
          }
        }
      }

      return items;
    } catch (e) {
      return [];
    }
  }

  /// Resolve drama and all episode M3U8 streams on my-drama.com
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    String text = rawQuery.trim();
    String vid = text;

    final uuidMatch = RegExp(r'([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})', caseSensitive: false)
        .firstMatch(text);
    if (uuidMatch != null) {
      vid = uuidMatch.group(1)!;
    }

    if (vid.isEmpty) return null;
    final targetUrl = '$baseUrl/video/$vid';

    try {
      final response = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return null;

      final html = response.body;

      // Extract title
      final titleMatch = RegExp(r'\\?"name\\?":\\?"([^\\"]+)\\?"').firstMatch(html);
      String title = titleMatch?.group(1)?.replaceAll(r'\"', '"').trim() ?? 'MyDrama Series';
      title = title.replaceAll(RegExp(r'\s*[-–—]?\s*(?:Episode|Ep\.?|Chapter)\s*\d+.*$', caseSensitive: false), '').trim();
      title = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), '').trim();
      if (title.isEmpty) title = 'MyDrama_${vid.substring(0, 8)}';

      // Extract cover
      final covMatch = RegExp(r'\\?"coverUrl\\?":\\?"([^\\"]+)\\?"|\\?"clearCover\\?":\\?"([^\\"]+)\\?"').firstMatch(html);
      String cover = (covMatch?.group(1) ?? covMatch?.group(2) ?? '').replaceAll(r'\"', '').replaceAll(r'\/', '/');

      // Extract all M3U8 links
      final m3u8Regex = RegExp(r'https://[^\s"<>\\]+\.m3u8');
      final allUrls = m3u8Regex.allMatches(html).map((m) => m.group(0)!).toSet().toList();

      final enUrls = allUrls.where((u) => u.contains('/en/')).toList();
      final targetUrls = enUrls.isNotEmpty ? enUrls : allUrls;

      final Map<int, String> epDict = {};
      for (final u in targetUrls) {
        final epNumMatch = RegExp(r'/(\d+)_\.m3u8').firstMatch(u);
        if (epNumMatch != null) {
          final num = int.parse(epNumMatch.group(1)!);
          epDict[num] = u;
        }
      }

      // If only episode 1 was embedded in HTML, generate sequential CloudFront links if template matches
      if (epDict.isNotEmpty && epDict.length < 5) {
        final sampleUrl = epDict.values.first;
        final baseMatch = RegExp(r'^(https?://[^/]+/convert/[^/]+/[^/]+/[^/]+/)\d+_\.m3u8').firstMatch(sampleUrl);
        if (baseMatch != null) {
          final prefix = baseMatch.group(1)!;
          // Generate up to 60 episodes
          for (int i = 1; i <= 60; i++) {
            if (!epDict.containsKey(i)) {
              epDict[i] = '$prefix${i}_.m3u8';
            }
          }
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
        id: vid,
        title: title,
        coverUrl: cover,
        episodeCount: episodes.length,
        detailUrl: targetUrl,
        platform: PlatformType.mydrama,
        episodes: episodes,
      );
    } catch (e) {
      return null;
    }
  }
}
