// lib/services/instant_sounds.dart — download MP3 clips into the library.
//
// NOTE: myinstants HTML pages (trending/search) sit behind Cloudflare bot
// protection and answer 403 to plain HTTP clients, so in-app browsing is
// impossible. The MP3 files themselves (/media/sounds/*.mp3) download fine,
// so the flow is: open the site in the browser, copy an MP3 link, paste it
// here. Pure-Dart HTTP: no native code, APK still builds fully offline.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'native_audio.dart';

class InstantClip {
  final String title;
  final String mp3Url;

  /// Seconds, when the API measured it. Null for bundled/pasted links.
  final double? duration;

  /// Which site served it: myinstants, memesoundboard, 101soundboards.
  final String source;

  /// Board art (101soundboards items). Null elsewhere.
  final String? thumbnail;
  const InstantClip(
      {required this.title,
      required this.mp3Url,
      this.duration,
      this.source = 'myinstants',
      this.thumbnail});
}

/// One 101soundboards board (a tag page lists boards, not sounds).
class InstantBoard {
  final String title;
  final String slug;
  final String? thumbnail;
  const InstantBoard(
      {required this.title, required this.slug, this.thumbnail});
}

/// One 101soundboards tag (top level of the drill-down).
class InstantTag {
  final String tag;
  final String name;
  const InstantTag({required this.tag, required this.name});
}

/// One page of clips plus the server's word on a next page.
/// [hasNext] is null when the endpoint does not report it (the
/// myinstants trending/search/category lists), so callers then fall
/// back to "empty page means the end".
class InstantPage {
  final List<InstantClip> clips;
  final bool? hasNext;
  const InstantPage(this.clips, {this.hasNext});
  static const empty = InstantPage(<InstantClip>[]);
}

/// One page of 101soundboards boards, same [hasNext] contract.
class InstantBoardPage {
  final List<InstantBoard> boards;
  final bool? hasNext;
  const InstantBoardPage(this.boards, {this.hasNext});
}

class InstantSounds {
  /// The user's own deployment of myinstants-api (JSON, CORS open).
  static const apiBase = 'https://myinstants-five.vercel.app';

  /// Fixed site categories (slug = path segment on myinstants.com).
  /// Needs api/categories.php on the deployment (see tool/categories.php).
  static const Map<String, String> categories = {
    'anime & manga': 'Anime & Manga',
    'games': 'Games',
    'memes': 'Memes',
    'movies': 'Movies',
    'music': 'Music',
    'politics': 'Politics',
    'pranks': 'Pranks',
    'reactions': 'Reactions',
    'sound effects': 'Sound Effects',
    'sports': 'Sports',
    'television': 'Television',
    'tiktok trends': 'Tiktok Trends',
    'viral': 'Viral',
    'whatsapp audios': 'Whatsapp Audios',
  };

  static const _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 16; 24117RN76G) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
  };

  static const trendingUrl = 'https://www.myinstants.com/en/index/sy/';

  /// MemeSoundboard.io site categories (for quick-search chips; the
  /// API exposes no category filter, so taps become name searches).
  static const Map<String, String> memeCategories = {
    'anime': 'Anime',
    'creativity': 'Creativity',
    'discord': 'Discord',
    'fart': 'Fart',
    'games': 'Games',
    'memes': 'Memes',
    'movies': 'Movies',
    'politics': 'Politics',
    'pranks': 'Pranks',
    'reactions': 'Reactions',
    'sound effects': 'Sound Effects',
    'whatsapp audios': 'WhatsApp Audios',
  };

  /// MemeSoundboard.io sorts. `new` is the API default.
  static const Map<String, String> memeSorts = {
    'new': 'الأحدث',
    'trending': 'الرائج',
    'all': 'الأشهر',
  };

  /// 101soundboards tags (static fallback from the docs when offline).
  static const List<InstantTag> tags101Fallback = [
    InstantTag(tag: 'anime-comics-cartoons', name: 'Anime & Comics'),
    InstantTag(tag: 'celebrities', name: 'Celebrities'),
    InstantTag(tag: 'comedy', name: 'Comedy'),
    InstantTag(tag: 'games', name: 'Games'),
    InstantTag(tag: 'memes-funny', name: 'Memes & Funny'),
    InstantTag(tag: 'movies', name: 'Movies'),
    InstantTag(tag: 'music-musicians', name: 'Music'),
    InstantTag(tag: 'nature', name: 'Nature'),
    InstantTag(tag: 'other', name: 'Other'),
    InstantTag(tag: 'politics', name: 'Politics'),
    InstantTag(tag: 'sound-fx', name: 'Sound FX'),
    InstantTag(tag: 'sports', name: 'Sports'),
    InstantTag(tag: 'streamers-twitch-podcasts', name: 'Streamers'),
    InstantTag(tag: 'tv', name: 'TV'),
    InstantTag(tag: 'united-kingdom', name: 'UK'),
    InstantTag(tag: 'united-states', name: 'US'),
  ];

  Future<void> openSite() => NativeAudio().openUrl(trendingUrl);

  /// Trending Syria through the JSON API, server-filtered to game length.
  /// Pages start at 1; an empty list means no more pages.
  Future<InstantPage> apiTrending({int page = 1}) {
    return _getPage(
        '$apiBase/trending?q=sy&page=$page&min_duration=2&max_duration=6',
        'تعذّر جلب القائمة');
  }

  /// Search through the JSON API, server-filtered to game length.
  Future<InstantPage> apiSearch(String query, {int page = 1}) {
    final q = query.trim();
    if (q.isEmpty) return Future.value(InstantPage.empty);
    return _getPage(
        '$apiBase/search?q=${Uri.encodeQueryComponent(q)}'
        '&page=$page&min_duration=2&max_duration=6',
        'تعذّر البحث');
  }

  /// One fixed site category, server-filtered to game length.
  /// Matches the deployment docs: `GET /category?category=<name>&q=sy`.
  Future<InstantPage> apiCategory(String slug, {int page = 1}) {
    return _getPage(
        '$apiBase/category?category=${Uri.encodeQueryComponent(slug)}'
        '&q=sy&page=$page&min_duration=2&max_duration=6',
        'تعذّر جلب التصنيف');
  }

  /// Merged search across all sources (round-robin). Items carry
  /// their own `source`; the screen shows a badge per row.
  Future<InstantPage> apiSearchAll(String query, {int page = 1}) {
    final q = query.trim();
    if (q.isEmpty) return Future.value(InstantPage.empty);
    return _getPage(
        '$apiBase/search_all?q=${Uri.encodeQueryComponent(q)}'
        '&page=$page&min_duration=2&max_duration=6',
        'تعذّر البحث الشامل');
  }

  /// Memesoundboard: pass [query] to search by name, or leave it empty
  /// to browse the whole catalog. [sort] is `new` (default), `trending`,
  /// or `all`. The duration params make the source report real lengths
  /// (and drop anything outside 2–6 s) at the cost of a slower reply.
  Future<InstantPage> apiMeme(
      {String query = '', String sort = 'new', int page = 1}) {
    final q = query.trim();
    final sel =
        q.isEmpty ? 'sort=$sort' : 'q=${Uri.encodeQueryComponent(q)}';
    return _getPage(
        '$apiBase/memesoundboard?$sel&page=$page'
        '&min_duration=2&max_duration=6',
        'تعذّر الجلب');
  }

  /// 101soundboards search. Durations come free with the items.
  Future<InstantPage> api101Search(String query, {int page = 1}) {
    final q = query.trim();
    if (q.isEmpty) return Future.value(InstantPage.empty);
    return _getPage(
        '$apiBase/101soundboards?q=${Uri.encodeQueryComponent(q)}'
        '&page=$page&min_duration=2&max_duration=6',
        'تعذّر البحث');
  }

  /// 101soundboards tags for the drill-down. Falls back to the static
  /// list when the endpoint is unreachable.
  Future<List<InstantTag>> api101Tags() async {
    try {
      final res = await http
          .get(Uri.parse('$apiBase/101categories'),
              headers: _browserHeaders)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return tags101Fallback;
      final decoded = jsonDecode(res.body);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! List) return tags101Fallback;
      final out = <InstantTag>[];
      for (final e in data) {
        if (e is! Map) continue;
        final tag = (e['tag'] ?? '').toString();
        final name = (e['name'] ?? '').toString();
        if (tag.isEmpty) continue;
        out.add(InstantTag(
            tag: tag, name: name.isEmpty ? tag : name));
      }
      return out.isEmpty ? tags101Fallback : out;
    } catch (_) {
      return tags101Fallback;
    }
  }

  /// Boards inside one 101soundboards tag. Pages start at 1.
  Future<InstantBoardPage> api101Boards(String tag, {int page = 1}) async {
    final res = await http
        .get(
            Uri.parse('$apiBase/101category?tag='
                '${Uri.encodeQueryComponent(tag)}&page=$page'),
            headers: _browserHeaders)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw StateError(_serverMessage(res.body) ??
          'تعذّر جلب اللوحات (${res.statusCode})');
    }
    return _parseBoardPage(res.body);
  }

  /// Sounds inside one 101soundboards board.
  Future<InstantPage> api101BoardSounds(String board, {int page = 1}) {
    return _getPage(
        '$apiBase/101board?board=${Uri.encodeQueryComponent(board)}'
        '&page=$page&min_duration=2&max_duration=6',
        'تعذّر جلب الأصوات');
  }

  Future<InstantPage> _getPage(String url, String errLabel) async {
    final res = await http
        .get(Uri.parse(url), headers: _browserHeaders)
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw StateError(
          _serverMessage(res.body) ?? '$errLabel (${res.statusCode})');
    }
    return _parsePage(res.body);
  }

  /// A human message from the API's error JSON, if it has one.
  static String? _serverMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final m = decoded['message']?.toString();
        if (m != null && m.isNotEmpty) return m;
      }
    } catch (_) {}
    return null;
  }

  static InstantPage _parsePage(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final hasNext = decoded['has_next'];
    return InstantPage(_parseClips(decoded['data']),
        hasNext: hasNext is bool ? hasNext : null);
  }

  static InstantBoardPage _parseBoardPage(String body) {
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final data = decoded['data'];
    final out = <InstantBoard>[];
    if (data is List) {
      for (final e in data) {
        if (e is! Map) continue;
        final slug = (e['id'] ?? '').toString();
        final title = _decodeHtml((e['title'] ?? '').toString()).trim();
        if (slug.isEmpty) continue;
        final thumb = (e['thumbnail'] ?? '').toString();
        out.add(InstantBoard(
            title: title.isEmpty ? slug : title,
            slug: slug,
            thumbnail: thumb.isEmpty ? null : thumb));
      }
    }
    final hasNext = decoded['has_next'];
    return InstantBoardPage(out,
        hasNext: hasNext is bool ? hasNext : null);
  }

  static List<InstantClip> _parseClips(Object? data) {
    if (data is! List) return const [];
    final out = <InstantClip>[];
    final seen = <String>{};
    for (final e in data) {
      if (e is! Map) continue;
      final mp3 = (e['mp3'] ?? '').toString();
      final title = _decodeHtml((e['title'] ?? '').toString()).trim();
      if (mp3.isEmpty || !seen.add(mp3)) continue;
      final dur = (e['duration'] as num?)?.toDouble();
      // Game length is 2–6 s. Server filters apply, but a source that
      // ignores the params must not leak odd lengths into the game.
      if (dur != null && (dur < 2 || dur > 6)) continue;
      final source = (e['source'] ?? 'myinstants').toString();
      final thumb = (e['thumbnail'] ?? '').toString();
      out.add(InstantClip(
          title: title.isEmpty ? 'صوت' : title,
          mp3Url: mp3,
          duration: dur,
          source: source.isEmpty ? 'myinstants' : source,
          thumbnail: thumb.isEmpty ? null : thumb));
    }
    return out;
  }

  static String _decodeHtml(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)));

  /// Downloads a direct MP3 link into app cache. Returns the local path.
  /// Throws a human (Arabic) message on failure.
  Future<String> downloadMp3(String rawUrl,
      {void Function(int received, int? total)? onProgress}) async {
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw StateError('الرابط غير صحيح — الصق رابط mp3 مباشر');
    }
    if (!uri.path.toLowerCase().endsWith('.mp3') &&
        // The 101 source serves its files through the API's own
        // /stream?url=... proxy (upstream blocks direct hotlinks).
        !(uri.host == Uri.parse(apiBase).host && uri.path == '/stream')) {
      throw StateError(
          'يجب أن يكون الرابط لملف mp3 مباشر (ينتهي بـ .mp3)، وليس رابط صفحة');
    }
    final req = http.Request('GET', uri);
    req.headers.addAll(_browserHeaders);
    final res = await req.send().timeout(const Duration(seconds: 60));
    if (res.statusCode != 200) {
      throw StateError('فشل التحميل (${res.statusCode})');
    }
    if ((res.contentLength ?? 0) > 10 * 1024 * 1024) {
      throw StateError('الملف كبير جدًا');
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}${Platform.pathSeparator}instant_${DateTime.now().millisecondsSinceEpoch}.mp3');
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in res.stream) {
        received += chunk.length;
        if (received > 10 * 1024 * 1024) {
          throw StateError('الملف كبير جدًا');
        }
        sink.add(chunk);
        onProgress?.call(received, res.contentLength);
      }
    } finally {
      await sink.close();
    }
    return file.path;
  }
}
