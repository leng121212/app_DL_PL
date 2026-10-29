import 'package:flutter/foundation.dart';

enum PlatformType {
  dramabox,
  hongguo,
  reelshort,
  web20,
  reelsdizim,
  eightmovie,
  mydrama,
  bmp4,
  beeplaylet,
}

extension PlatformTypeExtension on PlatformType {
  String get id {
    switch (this) {
      case PlatformType.dramabox:
        return 'dramabox';
      case PlatformType.hongguo:
        return 'hongguo';
      case PlatformType.reelshort:
        return 'reelshort';
      case PlatformType.web20:
        return 'web20';
      case PlatformType.reelsdizim:
        return 'reelsdizim';
      case PlatformType.eightmovie:
        return 'eightmovie';
      case PlatformType.mydrama:
        return 'mydrama';
      case PlatformType.bmp4:
        return 'bmp4';
      case PlatformType.beeplaylet:
        return 'beeplaylet';
    }
  }

  String get displayName {
    switch (this) {
      case PlatformType.dramabox:
        return 'DramaBox';
      case PlatformType.hongguo:
        return 'Hongguo (红果)';
      case PlatformType.reelshort:
        return 'ReelShort';
      case PlatformType.web20:
        return '20+ Web';
      case PlatformType.reelsdizim:
        return 'ReelsDizim';
      case PlatformType.eightmovie:
        return '8Movie';
      case PlatformType.mydrama:
        return 'MyDrama';
      case PlatformType.bmp4:
        return 'BMP4';
      case PlatformType.beeplaylet:
        return 'BeePlaylet';
    }
  }

  String? get assetIcon {
    switch (this) {
      case PlatformType.dramabox:
        return 'assets/dramabox-logo.png';
      case PlatformType.hongguo:
        return 'assets/hongguo-logo.png';
      case PlatformType.reelshort:
        return 'assets/reelshort-logo.png';
      case PlatformType.web20:
      case PlatformType.mydrama:
      case PlatformType.reelsdizim:
      case PlatformType.eightmovie:
      case PlatformType.bmp4:
      case PlatformType.beeplaylet:
        return null;
    }
  }

  String get emojiFallback {
    switch (this) {
      case PlatformType.dramabox:
        return '📦';
      case PlatformType.hongguo:
        return '🍎';
      case PlatformType.reelshort:
        return '⚡';
      case PlatformType.web20:
        return '🌐';
      case PlatformType.reelsdizim:
        return '📺';
      case PlatformType.eightmovie:
        return '🎬';
      case PlatformType.mydrama:
        return '🎭';
      case PlatformType.bmp4:
        return '📼';
      case PlatformType.beeplaylet:
        return '🐝';
    }
  }

  String get hintText {
    switch (this) {
      case PlatformType.dramabox:
        return 'បញ្ចូល DramaBox URL (dramaboxdb.com/movie/...) ឬ Book ID...';
      case PlatformType.hongguo:
        return 'បញ្ចូល Series ID ឬ Link (hongguoduanju.com/detail?series_id=...)';
      case PlatformType.reelshort:
        return 'បញ្ចូល ReelShort movie URL ឬ ID...';
      case PlatformType.web20:
        return 'ស្វែងរក ឬ បញ្ចូល Link រឿង...';
      case PlatformType.reelsdizim:
        return 'បញ្ចូល ReelsDizim URL ឬ ID...';
      case PlatformType.eightmovie:
        return 'ស្វែងរក ឬ បញ្ចូល Link រឿង...';
      case PlatformType.mydrama:
        return 'បញ្ចូល MyDrama URL ឬ ស្វែងរកចំណងជើង...';
      case PlatformType.bmp4:
        return 'ស្វែងរក ឬ បញ្ចូល Link រឿង...';
      case PlatformType.beeplaylet:
        return 'បញ្ចូល beeplaylet.com URL ឬ ស្វែងរក...';
    }
  }
}

class EpisodeItem {
  final int index;
  final String title;
  final String? chapterName;
  final String? chapterId;
  final String? vid;
  String? streamUrl;
  final String? subtitleUrl;
  final bool isFree;

  EpisodeItem({
    required this.index,
    required this.title,
    this.chapterName,
    this.chapterId,
    this.vid,
    this.streamUrl,
    this.subtitleUrl,
    this.isFree = true,
  });

  factory EpisodeItem.fromJson(Map<String, dynamic> json) {
    return EpisodeItem(
      index: json['index'] is int ? json['index'] : int.tryParse('${json['index']}') ?? 1,
      title: json['title'] ?? 'EP${json['index']}',
      chapterName: json['chapter_name'],
      chapterId: json['chapter_id'],
      vid: json['vid'],
      streamUrl: json['stream_url'] ?? json['mp4_url'],
      subtitleUrl: json['subtitle_url'],
      isFree: json['is_free'] ?? true,
    );
  }
}

class DramaItem {
  final String id;
  final String title;
  final String coverUrl;
  final int episodeCount;
  final String intro;
  final List<String> tags;
  final String heat;
  final String score;
  final String detailUrl;
  final PlatformType platform;
  List<EpisodeItem>? episodes;

  DramaItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.episodeCount,
    this.intro = '',
    this.tags = const [],
    this.heat = '',
    this.score = '',
    required this.detailUrl,
    required this.platform,
    this.episodes,
  });

  factory DramaItem.fromJson(Map<String, dynamic> json) {
    return DramaItem(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      episodeCount: json['episodeCount'] is int
          ? json['episodeCount']
          : int.tryParse('${json['episodeCount']}') ?? 0,
      intro: json['intro']?.toString() ?? '',
      tags: (json['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .where((t) => t.isNotEmpty)
              .toList() ??
          const [],
      heat: json['heat']?.toString() ?? '',
      score: json['score']?.toString() ?? '',
      detailUrl: json['detailUrl']?.toString() ?? '',
      platform: PlatformType.web20,
    );
  }

  DramaItem copyWith({
    String? id,
    String? title,
    String? coverUrl,
    int? episodeCount,
    String? intro,
    List<String>? tags,
    String? heat,
    String? score,
    String? detailUrl,
    PlatformType? platform,
    List<EpisodeItem>? episodes,
  }) {
    return DramaItem(
      id: id ?? this.id,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      episodeCount: episodeCount ?? this.episodeCount,
      intro: intro ?? this.intro,
      tags: tags ?? this.tags,
      heat: heat ?? this.heat,
      score: score ?? this.score,
      detailUrl: detailUrl ?? this.detailUrl,
      platform: platform ?? this.platform,
      episodes: episodes ?? this.episodes,
    );
  }
}

enum TaskStatus {
  pending,
  resolving,
  downloading,
  completed,
  failed,
  cancelled,
  paused,
}

class DownloadTask with ChangeNotifier {
  final String taskId;
  final String dramaTitle;
  final String dramaCover;
  final PlatformType platform;
  final int episodeIndex;
  final String episodeTitle;
  String? streamUrl;
  final String? vid;
  final String? seriesId;
  final String outputPath;

  TaskStatus _status;
  double _progress;
  int _downloadedBytes;
  int _totalBytes;
  double _speedBytesPerSec;
  String _speedStr;
  String _etaStr;
  String? _error;

  DownloadTask({
    required this.taskId,
    required this.dramaTitle,
    required this.dramaCover,
    required this.platform,
    required this.episodeIndex,
    required this.episodeTitle,
    this.streamUrl,
    this.vid,
    this.seriesId,
    required this.outputPath,
    TaskStatus status = TaskStatus.pending,
    double progress = 0.0,
    int downloadedBytes = 0,
    int totalBytes = 0,
    double speedBytesPerSec = 0.0,
    String speedStr = '0.0 MB/s',
    String etaStr = '--:--',
    String? error,
  })  : _status = status,
        _progress = progress,
        _downloadedBytes = downloadedBytes,
        _totalBytes = totalBytes,
        _speedBytesPerSec = speedBytesPerSec,
        _speedStr = speedStr,
        _etaStr = etaStr,
        _error = error;

  TaskStatus get status => _status;
  double get progress => _progress;
  int get downloadedBytes => _downloadedBytes;
  int get totalBytes => _totalBytes;
  double get speedBytesPerSec => _speedBytesPerSec;
  String get speedStr => _speedStr;
  String get etaStr => _etaStr;
  String? get error => _error;

  void updateProgress({
    required double progress,
    required int downloadedBytes,
    required int totalBytes,
    required double speedBytesPerSec,
    required String speedStr,
    required String etaStr,
  }) {
    _progress = progress;
    _downloadedBytes = downloadedBytes;
    _totalBytes = totalBytes;
    _speedBytesPerSec = speedBytesPerSec;
    _speedStr = speedStr;
    _etaStr = etaStr;
    _status = TaskStatus.downloading;
    notifyListeners();
  }

  void setStatus(TaskStatus newStatus, {String? err}) {
    _status = newStatus;
    if (err != null) {
      _error = err;
    } else if (newStatus == TaskStatus.pending || newStatus == TaskStatus.downloading) {
      _error = null;
    }
    notifyListeners();
  }
}

class DramaCategoryHelper {
  static List<Map<String, String>> getCategories() {
    return [
      {'id': 'all', 'name': '🎬 រឿងទាំងអស់'},
      {'id': 'most_episodes', 'name': '🔥 រឿងច្រើន EP'},
      {'id': 'romance', 'name': '💖 រឿងស្នេហា'},
      {'id': 'transmigration', 'name': '🌀 រឿងឆ្លងភព'},
      {'id': 'time_travel', 'name': '⏳ រឿងឆ្លងពេលវេលា'},
      {'id': 'costume', 'name': '👘 រឿងត្រលប់ទៅបុរាណ'},
      {'id': 'farming', 'name': '🌾 រឿងកសិកម្ម'},
      {'id': 'supernatural', 'name': '⚡ រឿងអភូតហេតុ'},
      {'id': 'revenge', 'name': '⚔️ រឿងឈ្នានីស'},
      {'id': 'fantasy', 'name': '✨ រឿងអភីនិហារ'},
      {'id': 'bl_gl', 'name': '🌈 រឿង BL-GL'},
      {'id': 'urban', 'name': '🏙️ រឿងទីក្រុង/ទំនើប'},
      {'id': 'comedy', 'name': '🎭 រឿងកំប្លែង'},
      {'id': 'suspense', 'name': '🕵️ រឿងអាថ៌កំបាំង'},
    ];
  }

  static bool matchesCategory(DramaItem item, String categoryId) {
    if (categoryId == 'all' || categoryId == 'most_episodes') return true;

    final text = '${item.title} ${item.intro} ${item.tags.join(' ')}'.toLowerCase();

    switch (categoryId) {
      case 'romance':
        return _containsAny(text, [
          '爱', '婚', '恋', '妻', '夫', '宠', '情', '白月光', '替身', '总裁', '闪婚', '前妻', '娇妻', '少爷', '豪门', '心动', '深爱', '热恋', '甜', '相思',
          'love', 'romance', 'marriage', 'wife', 'husband', 'billionaire', 'alpha', 'luna', 'bride', 'sweet', 'heart'
        ]);
      case 'transmigration':
        return _containsAny(text, [
          '穿', '穿越', '穿书', '异世', '跨界', '穿到', '穿成', '异界',
          'transmigrat', 'isekai', 'another world', 'dimension'
        ]);
      case 'time_travel':
        return _containsAny(text, [
          '重', '重生', '回溯', '重返', '当年', '重回', '回到', '重启', '再来一次', '回到过去',
          'rebirth', 'born again', 'rewind', 'time travel', 'second chance', 'reborn'
        ]);
      case 'costume':
        return _containsAny(text, [
          '古', '古装', '王爷', '皇', '妃', '宫', '朝', '殿下', '将军', '天下', '臣', '相府', '陛下', '侯门', '武林', '江湖', '大宋', '大明', '大唐', '清朝',
          'ancient', 'costume', 'emperor', 'prince', 'princess', 'palace', 'dynasty', 'general', 'imperial'
        ]);
      case 'farming':
        return _containsAny(text, [
          '田', '种田', '农', '农家', '乡村', '乡下', '庄园', '地', '发家', '致富', '渔', '渔村', '村', '农民', '田园',
          'farm', 'farming', 'countryside', 'village', 'rural', 'agriculture'
        ]);
      case 'supernatural':
        return _containsAny(text, [
          '神', '神豪', '神医', '异能', '奇门', '天王', '龙王', '透视', '绝世', '首富', '天降', '签到', '系统', '无敌', '鉴宝',
          'system', 'billionaire', 'miracle', 'superpower', 'god', 'tycoon', 'hidden identity', 'treasure', 'peerless'
        ]);
      case 'revenge':
        return _containsAny(text, [
          '逆', '逆袭', '复仇', '战神', '打脸', '退婚', '断绝', '下山', '弃', '夺回', '血债', '归来', '杀', '报仇', '仇', '背叛', '绝不原谅',
          'revenge', 'comeback', 'payback', 'betrayal', 'retaliat', 'slap', 'ex-wife', 'ex-husband', 'avenge'
        ]);
      case 'fantasy':
        return _containsAny(text, [
          '仙', '修仙', '玄幻', '魔', '妖', '道', '宗', '剑', '法', '三界', '灵', '圣', '苍穹', '九天', '洪荒', '神魔', '修真',
          'fantasy', 'immortal', 'magic', 'cultivat', 'demon', 'dragon', 'witch', 'werewolf', 'vampire'
        ]);
      case 'bl_gl':
        return _containsAny(text, [
          '双男', '耽美', '百合', '双女', 'bl', 'gl', '同志', '兄弟情', '纯爱', '绝色', '耽', '腐',
          'bl', 'gl', 'boy love', 'girl love', 'lgbt', 'gay', 'lesbian'
        ]);
      case 'urban':
        return _containsAny(text, [
          '都市', '现代', '职场', '公司', '商海', '商战', '精英', '助理', '律师', '医生', '医院', '商业', '名门',
          'urban', 'modern', 'city', 'office', 'ceo', 'business'
        ]);
      case 'comedy':
        return _containsAny(text, [
          '喜剧', '搞笑', '爆笑', '萌宝', '团宠', '欢喜', '乌龙', '奶爸', '笑', '逗', '沙雕',
          'comedy', 'funny', 'humor', 'hilarious', 'cute baby'
        ]);
      case 'suspense':
        return _containsAny(text, [
          '悬疑', '侦探', '破案', '凶手', '惊悚', '探案', '迷局', '真相', '密室', '捉迷藏', '诡', '阴谋', '杀手',
          'suspense', 'mystery', 'detective', 'thriller', 'investigat', 'crime'
        ]);
      default:
        return true;
    }
  }

  static bool _containsAny(String source, List<String> keywords) {
    for (final kw in keywords) {
      if (source.contains(kw.toLowerCase())) return true;
    }
    return false;
  }
}

