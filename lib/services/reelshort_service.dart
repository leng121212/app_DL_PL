import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/drama_models.dart';

class ReelshortService {
  static const String baseUrl = 'https://www.reelshort.com';
  static final Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  /// Categories on ReelShort (Universal Categories)
  static List<Map<String, String>> getCategories() {
    return DramaCategoryHelper.getCategories();
  }

  /// Fetch catalog by universal category
  static Future<List<DramaItem>> fetchCatalogByCategory({
    String category = 'all',
    int page = 1,
    int pageSize = 24,
  }) async {
    if (category == 'most_episodes') {
      final p1 = await fetchCatalog(tagId: '0', page: page, pageSize: pageSize);
      final p2 = await fetchCatalog(tagId: '0', page: page + 1, pageSize: pageSize);
      final combined = [...p1, ...p2];
      combined.sort((a, b) => b.episodeCount.compareTo(a.episodeCount));
      return combined.take(pageSize).toList();
    }

    String tagId = '0';
    if (category == 'romance') tagId = '1'; // Billionaire Romance
    else if (category == 'fantasy' || category == 'supernatural') tagId = '2'; // Werewolf / Fantasy
    else if (category == 'revenge') tagId = '3'; // Revenge
    else if (category == 'suspense') tagId = '4'; // Suspense

    final items = await fetchCatalog(tagId: tagId, page: page, pageSize: pageSize);
    if (category == 'all' || tagId != '0') {
      return items;
    }
    final filtered = items.where((d) => DramaCategoryHelper.matchesCategory(d, category)).toList();
    return filtered.isNotEmpty ? filtered : items;
  }

  /// Popular/featured dramas on ReelShort using official API
  static Future<List<DramaItem>> fetchCatalog({
    String tagId = '0',
    int page = 1,
    int pageSize = 24,
  }) async {
    final apiUrl =
        '$baseUrl/api/video/book/getTagBook?language=en&tag_id=$tagId&page=$page&page_size=$pageSize';
    try {
      final response = await http.get(Uri.parse(apiUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final books = data['data']?['books'] as List? ?? [];

      final List<DramaItem> items = [];
      for (final raw in books) {
        if (raw is! Map<String, dynamic>) continue;
        final bookId = '${raw['book_id'] ?? raw['_id'] ?? ''}';
        if (bookId.isEmpty) continue;

        final title = raw['book_title'] ?? 'ReelShort Drama';
        final cover = raw['book_pic'] ?? '';
        final intro = raw['special_desc'] ?? raw['chapter_desc'] ?? '';
        final count = (raw['chapter_count'] as num?)?.toInt() ?? 0;
        final tagsList = (raw['tag'] as List?)?.map((e) => '$e').toList() ?? [];

        items.add(
          DramaItem(
            id: bookId,
            title: title,
            coverUrl: cover,
            episodeCount: count,
            intro: intro,
            tags: tagsList,
            detailUrl: '$baseUrl/movie/drama-$bookId',
            platform: PlatformType.reelshort,
          ),
        );
      }
      return items;
    } catch (e) {
      return [];
    }
  }

  /// Resolve ReelShort drama URL or Book ID
  static Future<DramaItem?> resolveDrama(String rawQuery) async {
    String cleanUrl = rawQuery.trim();
    String bookId = '';

    if (RegExp(r'^[a-f0-9]{20,32}$', caseSensitive: false).hasMatch(cleanUrl)) {
      bookId = cleanUrl;
      cleanUrl = '$baseUrl/movie/drama-$bookId';
    } else if (cleanUrl.contains('series_id=')) {
      bookId = cleanUrl.split('series_id=').last.split('&').first;
      cleanUrl = '$baseUrl/movie/drama-$bookId';
    } else if (cleanUrl.contains('book_id=')) {
      bookId = cleanUrl.split('book_id=').last.split('&').first;
      cleanUrl = '$baseUrl/movie/drama-$bookId';
    } else if (!cleanUrl.startsWith('http')) {
      cleanUrl = 'https://$cleanUrl';
    }

    try {
      final response = await http.get(Uri.parse(cleanUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return null;

      final html = response.body;

      // Extract book_id from URL or HTML
      if (bookId.isEmpty) {
        final idMatch = RegExp(r'([a-f0-9]{24})', caseSensitive: false).firstMatch(cleanUrl);
        if (idMatch != null) {
          bookId = idMatch.group(1)!;
        }
      }

      String title = 'ReelShort Drama';
      String cover = '';
      int chapterCount = 0;

      // Check NEXT_DATA if available
      final m = RegExp(r'<script id="__NEXT_DATA__" type="application/json">([^<]+)</script>')
          .firstMatch(html);
      if (m != null) {
        try {
          final data = jsonDecode(m.group(1)!);
          final pdata = data['props']?['pageProps']?['data'] ??
              data['props']?['pageProps']?['bookInfo'] ??
              {};
          title = pdata['book_title'] ?? pdata['title'] ?? title;
          cover = pdata['book_pic'] ?? pdata['cover'] ?? cover;
          chapterCount = (pdata['chapter_count'] as num?)?.toInt() ?? 0;
          bookId = '${pdata['book_id'] ?? bookId}';
        } catch (_) {}
      }

      // Title fallback from <title> tag
      if (title == 'ReelShort Drama') {
        final tm = RegExp(r'<title>(.*?)</title>').firstMatch(html);
        if (tm != null) {
          String rawT = tm.group(1)!;
          rawT = rawT.replaceAll(RegExp(r'\s*(Movie Watch Online|Watch Online|Full Movie).*$', caseSensitive: false), '');
          rawT = rawT.split('|').first.split('-').first.trim();
          if (rawT.isNotEmpty) title = rawT;
        }
      }

      // Cover fallback from meta og:image
      if (cover.isEmpty) {
        final cm = RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"').firstMatch(html);
        if (cm != null) cover = cm.group(1)!;
      }

      // Extract all episode links from drama page: href="(/episodes/[^"]+)"
      final epRegex = RegExp(r'href="(/episodes/[^"]+)"');
      final Map<int, String> episodeLinks = {};

      for (final match in epRegex.allMatches(html)) {
        final path = match.group(1)!;
        final numMatch = RegExp(r'episode-(\d+)-', caseSensitive: false).firstMatch(path);
        if (numMatch != null) {
          final epNum = int.parse(numMatch.group(1)!);
          if (!episodeLinks.containsKey(epNum)) {
            final fullEpUrl = path.startsWith('http') ? path : '$baseUrl$path';
            episodeLinks[epNum] = fullEpUrl;
          }
        }
      }

      // If chapter count indicates more episodes, paginate through pages 2..10
      if (chapterCount > episodeLinks.length) {
        for (int p = 2; p <= 10; p++) {
          try {
            final pageUrl = cleanUrl.contains('?') ? '$cleanUrl&page=$p' : '$cleanUrl?page=$p';
            final pRes = await http.get(Uri.parse(pageUrl), headers: _headers).timeout(const Duration(seconds: 10));
            if (pRes.statusCode == 200) {
              int newAdded = 0;
              for (final match in epRegex.allMatches(pRes.body)) {
                final path = match.group(1)!;
                final numMatch = RegExp(r'episode-(\d+)-', caseSensitive: false).firstMatch(path);
                if (numMatch != null) {
                  final epNum = int.parse(numMatch.group(1)!);
                  if (!episodeLinks.containsKey(epNum)) {
                    episodeLinks[epNum] = path.startsWith('http') ? path : '$baseUrl$path';
                    newAdded++;
                  }
                }
              }
              if (newAdded == 0 || episodeLinks.length >= chapterCount) break;
            } else {
              break;
            }
          } catch (_) {
            break;
          }
        }
      }

      final List<EpisodeItem> episodes = [];
      if (episodeLinks.isNotEmpty) {
        for (final entry in (episodeLinks.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))) {
          episodes.add(
            EpisodeItem(
              index: entry.key,
              title: 'EP${entry.key.toString().padLeft(2, '0')}',
              chapterName: 'Episode ${entry.key}',
              streamUrl: entry.value, // Exact episode page URL with slug
            ),
          );
        }
      } else if (chapterCount > 0) {
        for (int i = 1; i <= chapterCount; i++) {
          episodes.add(
            EpisodeItem(
              index: i,
              title: 'EP${i.toString().padLeft(2, '0')}',
            ),
          );
        }
      }

      return DramaItem(
        id: bookId.isNotEmpty ? bookId : 'reelshort_drama',
        title: title,
        coverUrl: cover,
        episodeCount: chapterCount > 0 ? chapterCount : episodes.length,
        detailUrl: cleanUrl,
        platform: PlatformType.reelshort,
        episodes: episodes,
      );
    } catch (e) {
      return null;
    }
  }

  /// Resolve direct HLS m3u8 stream URL from an episode page URL
  static Future<String?> resolveEpisodeStream(String episodeUrlOrId, [String? bookId, int? episodeIndex]) async {
    String targetUrl = episodeUrlOrId.trim();

    // If targetUrl is not a full URL or lacks episode slug, resolve from drama page
    if (!targetUrl.startsWith('http') || !targetUrl.contains('/episodes/')) {
      if (bookId != null && bookId.isNotEmpty) {
        final drama = await resolveDrama(bookId);
        final ep = drama?.episodes?.where((e) => e.index == episodeIndex).firstOrNull;
        if (ep != null && ep.streamUrl != null && ep.streamUrl!.startsWith('http')) {
          targetUrl = ep.streamUrl!;
        } else {
          return null;
        }
      } else {
        return null;
      }
    }

    try {
      final response = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode != 200) return null;

      final html = response.body;
      final m = RegExp(r'<script id="__NEXT_DATA__" type="application/json">([^<]+)</script>')
          .firstMatch(html);
      if (m != null) {
        final data = jsonDecode(m.group(1)!);
        final pageProps = data['props']?['pageProps'] as Map<String, dynamic>? ?? {};
        final pdata = pageProps['data'] as Map<String, dynamic>? ?? {};

        final videoUrl = pdata['video_url'] as String?;
        if (videoUrl != null && videoUrl.isNotEmpty) {
          return videoUrl;
        }

        final hlsUrl = pdata['hls_url'] as String? ?? pdata['play_url'] as String?;
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          return hlsUrl;
        }
      }
    } catch (_) {}
    return null;
  }
}
