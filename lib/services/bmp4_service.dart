import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drama_models.dart';

class Bmp4Service {
  static const String baseUrl = 'https://www.bmp4.com';
  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Referer': 'https://www.bmp4.com/',
  };

  /// Fetch catalog from https://www.bmp4.com/page/$page
  static Future<List<DramaItem>> fetchCatalog({int page = 1}) async {
    final targetUrl = page <= 1 ? baseUrl : '$baseUrl/page/$page';
    try {
      final response = await http
          .get(Uri.parse(targetUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final List<DramaItem> items = [];
      final Set<String> seenIds = {};

      final postPattern = RegExp(
        r'<posts[^>]*class="[^"]*posts-item[^"]*"[^>]*>([\s\S]*?)</posts>',
        caseSensitive: false,
      );

      for (final match in postPattern.allMatches(html)) {
        final snippet = match.group(1) ?? '';

        final linkMatch = RegExp(r'href="(https://www\.bmp4\.com/(\d+)\.html)"').firstMatch(snippet);
        if (linkMatch == null) continue;
        final detailUrl = linkMatch.group(1)!;
        final dramaId = linkMatch.group(2)!;
        if (seenIds.contains(dramaId)) continue;
        seenIds.add(dramaId);

        // Extract poster (priority to data-src avoiding placeholder gif)
        final dataSrcMatch = RegExp(r'data-src="([^"]+)"').firstMatch(snippet);
        var cover = dataSrcMatch?.group(1) ?? '';
        if (cover.isEmpty || cover.endsWith('.gif')) {
          final srcMatches = RegExp(r'src="([^"]+)"').allMatches(snippet);
          for (final sm in srcMatches) {
            final s = sm.group(1) ?? '';
            if (!s.endsWith('.gif') && !s.contains('avatar')) {
              cover = s;
              break;
            }
          }
        }
        if (cover.isNotEmpty && !cover.startsWith('http')) {
          cover = '$baseUrl$cover';
        }

        // Extract title
        final titleMatch = RegExp(r'<h2[^>]*class="item-heading"[^>]*>[\s\S]*?<a[^>]*>(.*?)</a>').firstMatch(snippet);
        var rawTitle = titleMatch?.group(1)?.trim() ?? 'BMP4 Drama';
        rawTitle = rawTitle.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final bracketMatch = RegExp(r'《(.*?)》').firstMatch(rawTitle);
        var title = bracketMatch != null ? bracketMatch.group(1)!.trim() : rawTitle;
        title = title
            .replaceAll('短剧', '')
            .replaceAll('已完结在线播放', '')
            .replaceAll('全集在线播放', '')
            .replaceAll('-微短剧网Bmp4', '')
            .trim();
        if (title.isEmpty) title = 'Drama_$dramaId';

        items.add(
          DramaItem(
            id: dramaId,
            title: title,
            coverUrl: cover,
            episodeCount: 50,
            detailUrl: detailUrl,
            platform: PlatformType.bmp4,
            tags: ['Full HD'],
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Search dramas on bmp4.com
  static Future<List<DramaItem>> search(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return [];

    final targetUrl = '$baseUrl/?s=${Uri.encodeComponent(query)}';
    try {
      final response = await http
          .get(Uri.parse(targetUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      final List<DramaItem> items = [];
      final Set<String> seenIds = {};

      final postPattern = RegExp(
        r'<posts[^>]*class="[^"]*posts-item[^"]*"[^>]*>([\s\S]*?)</posts>',
        caseSensitive: false,
      );

      for (final match in postPattern.allMatches(html)) {
        final snippet = match.group(1) ?? '';
        final linkMatch = RegExp(r'href="(https://www\.bmp4\.com/(\d+)\.html)"').firstMatch(snippet);
        if (linkMatch == null) continue;
        final detailUrl = linkMatch.group(1)!;
        final dramaId = linkMatch.group(2)!;
        if (seenIds.contains(dramaId)) continue;
        seenIds.add(dramaId);

        final dataSrcMatch = RegExp(r'data-src="([^"]+)"').firstMatch(snippet);
        var cover = dataSrcMatch?.group(1) ?? '';
        if (cover.isEmpty || cover.endsWith('.gif')) {
          final srcMatches = RegExp(r'src="([^"]+)"').allMatches(snippet);
          for (final sm in srcMatches) {
            final s = sm.group(1) ?? '';
            if (!s.endsWith('.gif') && !s.contains('avatar')) {
              cover = s;
              break;
            }
          }
        }
        if (cover.isNotEmpty && !cover.startsWith('http')) {
          cover = '$baseUrl$cover';
        }

        final titleMatch = RegExp(r'<h2[^>]*class="item-heading"[^>]*>[\s\S]*?<a[^>]*>(.*?)</a>').firstMatch(snippet);
        var rawTitle = titleMatch?.group(1)?.trim() ?? 'BMP4 Drama';
        rawTitle = rawTitle.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final bracketMatch = RegExp(r'《(.*?)》').firstMatch(rawTitle);
        var title = bracketMatch != null ? bracketMatch.group(1)!.trim() : rawTitle;
        title = title
            .replaceAll('短剧', '')
            .replaceAll('已完结在线播放', '')
            .replaceAll('全集在线播放', '')
            .replaceAll('-微短剧网Bmp4', '')
            .trim();
        if (title.isEmpty) title = 'Drama_$dramaId';

        items.add(
          DramaItem(
            id: dramaId,
            title: title,
            coverUrl: cover,
            episodeCount: 50,
            detailUrl: detailUrl,
            platform: PlatformType.bmp4,
            tags: ['Full HD'],
          ),
        );
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Resolve drama episodes from BMP4
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    String text = rawQuery.trim();
    String detailUrl = text;
    String dramaId = '';

    final idMatch = RegExp(r'/(\d+)\.html').firstMatch(text);
    if (idMatch != null) {
      dramaId = idMatch.group(1)!;
      detailUrl = 'https://www.bmp4.com/$dramaId.html';
    } else if (RegExp(r'^\d+$').hasMatch(text)) {
      dramaId = text;
      detailUrl = 'https://www.bmp4.com/$dramaId.html';
    } else if (text.startsWith('http')) {
      detailUrl = text;
      final m = RegExp(r'/(\d+)').firstMatch(text);
      if (m != null) dramaId = m.group(1)!;
    }

    if (detailUrl.isEmpty) return null;

    try {
      final response = await http
          .get(Uri.parse(detailUrl), headers: _headers)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);

      // Extract title
      final titleMatch = RegExp(r'<title>(.*?)</title>').firstMatch(html);
      String rawTitle = titleMatch?.group(1) ?? 'BMP4 Drama';
      final bracketMatch = RegExp(r'《(.*?)》').firstMatch(rawTitle);
      String title = bracketMatch != null ? bracketMatch.group(1)!.trim() : rawTitle;
      title = title
          .replaceAll(RegExp(r'\s*-\s*短剧大全.*$'), '')
          .replaceAll('短剧', '')
          .replaceAll('已完结在线播放', '')
          .replaceAll('全集在线播放', '')
          .replaceAll('-微短剧网Bmp4', '')
          .replaceAll(RegExp(r'[\\/*?:"<>|]'), '')
          .trim();
      if (title.isEmpty) title = 'BMP4_$dramaId';

      // Extract cover
      final ogImg = RegExp(r'''<meta[^>]+property=['"]og:image['"][^>]+content=['"]([^'"]+)['"]''').firstMatch(html);
      String cover = ogImg?.group(1) ?? '';
      if (cover.isEmpty) {
        final imgMatch = RegExp(r'data-src="([^"]+)"').firstMatch(html);
        cover = imgMatch?.group(1) ?? '';
      }

      // Extract episodes
      final List<EpisodeItem> episodes = [];
      final Set<String> seenStreams = {};

      final epRegex = RegExp(
        r'<a[^>]*class="[^"]*switch-video[^"]*"[^>]*video-url="([^"]+)"[^>]*>([\s\S]*?)</a>',
        caseSensitive: false,
      );

      for (final match in epRegex.allMatches(html)) {
        final vUrl = match.group(1)?.trim() ?? '';
        if (vUrl.isEmpty || seenStreams.contains(vUrl)) continue;
        seenStreams.add(vUrl);

        var epText = match.group(2)?.replaceAll(RegExp(r'<[^>]+>'), '').trim() ?? '';
        final epIdx = episodes.length + 1;
        if (epText.isEmpty) {
          epText = 'EP${epIdx.toString().padLeft(2, '0')}';
        }

        episodes.add(
          EpisodeItem(
            index: epIdx,
            title: epText,
            chapterName: epText,
            streamUrl: vUrl,
          ),
        );
      }

      // Fallback if no switch-video anchors: extract video-url="([^"]+)"
      if (episodes.isEmpty) {
        final videoUrlMatches = RegExp(r'video-url="([^"]+)"').allMatches(html);
        for (final vm in videoUrlMatches) {
          final u = vm.group(1)?.trim() ?? '';
          if (u.isNotEmpty && !seenStreams.contains(u)) {
            seenStreams.add(u);
            final epIdx = episodes.length + 1;
            episodes.add(
              EpisodeItem(
                index: epIdx,
                title: 'EP${epIdx.toString().padLeft(2, '0')}',
                chapterName: 'Episode $epIdx',
                streamUrl: u,
              ),
            );
          }
        }
      }

      return DramaItem(
        id: dramaId.isNotEmpty ? dramaId : '${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        coverUrl: cover,
        episodeCount: episodes.length,
        detailUrl: detailUrl,
        platform: PlatformType.bmp4,
        episodes: episodes,
        tags: ['Full HD'],
      );
    } catch (_) {
      return null;
    }
  }
}
