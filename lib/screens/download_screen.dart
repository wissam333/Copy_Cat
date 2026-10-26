// lib/screens/download_screen.dart — sounds from myinstants.
// Live lists come from your JSON API deployment (paged, server-filtered
// to 2–6 s with a duration badge). If it is unreachable the bundled
// catalog is used instead. Paste any MP3 link for the rest.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../i18n.dart';
import '../services/instant_catalog.dart';
import '../services/instant_sounds.dart';
import '../state/game_state.dart';
import '../widgets/sprite_button.dart';

class DownloadScreen extends ConsumerStatefulWidget {
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen> {
  final TextEditingController _q = TextEditingController();
  final TextEditingController _link = TextEditingController();
  final TextEditingController _pageCtl = TextEditingController();
  final _api = InstantSounds();
  final Map<String, String> _temps = {};
  final Set<String> _seenUrls = {};
  List<InstantClip> _clips = const [];
  String _query = '';
  String? _category;
  // Sound provider: myinstants | meme | board101 | all.
  String _provider = 'myinstants';
  // Memesoundboard feed: new | trending | all.
  String _memeSort = 'new';
  // Active memesoundboard category chip (drives a name search).
  String _memeCat = '';
  // 101soundboards drill-down: tags -> boards -> sounds.
  List<InstantTag> _tags101 = const [];
  String? _tag101;
  List<InstantBoard> _boards = const [];
  String? _board101;
  String? _boardTitle;
  bool _tagsLoading = false;
  int _page = 1;
  bool _endOfList = false;
  bool _loading = false;
  bool _moreLoading = false;
  bool _busy = false;
  bool _fromCatalog = false;
  String? _busyUrl;
  String? _playingUrl;
  String? _msg;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _fresh('', 1));
  }

  @override
  void dispose() {
    _q.dispose();
    _link.dispose();
    _pageCtl.dispose();
    super.dispose();
  }

  /// 101 drill-down level: tags -> boards list instead of sounds.
  bool get _inBoards =>
      _provider == 'board101' && _query.isEmpty && _board101 == null;

  static const Map<String, String> _providerNames = {
    'all': 'الكل',
    'myinstants': 'إنستنتس',
    'meme': 'ميم',
    'board101': '١٠١',
  };

  static const Map<String, String> _sourceNames = {
    'myinstants': 'إنستنتس',
    'memesoundboard': 'ميم',
    '101soundboards': '١٠١',
  };

  Future<InstantPage> _fetch(String query, int page) {
    switch (_provider) {
      case 'meme':
        return _api.apiMeme(query: query, sort: _memeSort, page: page);
      case 'board101':
        if (query.isNotEmpty) return _api.api101Search(query, page: page);
        if (_board101 != null) {
          return _api.api101BoardSounds(_board101!, page: page);
        }
        return Future.value(InstantPage.empty);
      case 'all':
        return _api.apiSearchAll(query, page: page);
      default:
        if (query.isNotEmpty) return _api.apiSearch(query, page: page);
        if (_category != null) {
          return _api.apiCategory(_category!, page: page);
        }
        return _api.apiTrending(page: page);
    }
  }

  void _pickProvider(String p) {
    setState(() {
      _provider = p;
      _category = null;
      _tag101 = null;
      _board101 = null;
      _boardTitle = null;
      _boards = const [];
    });
    if (p == 'board101') {
      _loadTags();
      return;
    }
    _fresh(_q.text.trim(), 1);
  }

  Future<void> _loadTags() async {
    if (_tags101.isNotEmpty) {
      _tag101 ??= _tags101.first.tag;
      _freshBoards(1);
      return;
    }
    setState(() => _tagsLoading = true);
    try {
      final tags = await _api.api101Tags();
      if (!mounted) return;
      setState(() {
        _tags101 = tags;
        _tag101 ??= tags.first.tag;
      });
      _freshBoards(1);
    } finally {
      if (mounted) setState(() => _tagsLoading = false);
    }
  }

  void _pickTag(String tag) {
    setState(() => _tag101 = tag);
    _freshBoards(1);
  }

  Future<void> _freshBoards(int page) async {
    setState(() {
      _loading = true;
      _msg = null;
      _query = '';
      _page = page;
      _endOfList = false;
      _clips = const [];
    });
    try {
      final res = await _api.api101Boards(_tag101 ?? '', page: page);
      if (!mounted) return;
      setState(() {
        _boards = page == 1 ? res.boards : [..._boards, ...res.boards];
        _endOfList = res.hasNext == false || res.boards.isEmpty;
        if (res.boards.isEmpty && _boards.isEmpty) {
          _msg = t('لا لوحات — جرّب تصنيفًا ثانيًا');
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _boards = const [];
        _endOfList = true;
        _msg = e is StateError ? e.message : t('تعذّر جلب اللوحات');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openBoard(InstantBoard board) {
    setState(() {
      _board101 = board.slug;
      _boardTitle = board.title;
    });
    _fresh('', 1);
  }

  void _backToBoards() {
    setState(() {
      _board101 = null;
      _boardTitle = null;
      _clips = const [];
    });
    _freshBoards(1);
  }

  Future<void> _fresh(String query, int page) async {
    // The merged search needs a typed query; 101 without a board shows
    // the boards drill-down instead of sounds. Meme browses without one.
    if (query.isEmpty && _provider == 'all') {
      setState(() {
        _loading = false;
        _msg = t('اكتب كلمة للبحث');
        _query = query;
        _page = 1;
        _endOfList = true;
        _clips = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _msg = null;
      _query = query;
      _page = page;
      _endOfList = false;
    });
    try {
      final res = await _fetch(query, page);
      if (!mounted) return;
      final clips = res.clips;
      _seenUrls
        ..clear()
        ..addAll(clips.map((c) => c.mp3Url));
      setState(() {
        _clips = clips;
        _fromCatalog = false;
        _endOfList = res.hasNext == false || clips.isEmpty;
        _msg = clips.isEmpty ? t('لا نتائج — جرّب كلمة ثانية') : null;
      });
    } catch (e) {
      if (!mounted) return;
      if (_provider != 'myinstants' || _category != null) {
        // Other providers (and myinstants categories) have no saved
        // fallback: a missing endpoint must not show unrelated sounds.
        setState(() {
          _clips = const [];
          _fromCatalog = false;
          _endOfList = true;
          _msg = e is StateError ? e.message : t('تعذّر الجلب');
        });
        return;
      }
      final fallback = query.isEmpty
          ? instantCatalog
          : instantCatalog
              .where((c) => c.title.contains(query))
              .toList();
      _seenUrls
        ..clear()
        ..addAll(fallback.map((c) => c.mp3Url));
      setState(() {
        _clips = fallback;
        _fromCatalog = true;
        _endOfList = true;
        _msg = t('تعذّر الاتصال — هذه قائمة محفوظة');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _more() async {
    if (_moreLoading || _endOfList || _fromCatalog) return;
    if (_inBoards) {
      setState(() => _moreLoading = true);
      try {
        final res = await _api.api101Boards(_tag101 ?? '', page: _page + 1);
        if (!mounted) return;
        setState(() {
          _page++;
          _boards = [..._boards, ...res.boards];
          if (res.hasNext == false || res.boards.isEmpty) {
            _endOfList = true;
          }
        });
      } catch (_) {
        if (mounted) setState(() => _msg = t('تعذّر جلب المزيد'));
      } finally {
        if (mounted) setState(() => _moreLoading = false);
      }
      return;
    }
    setState(() => _moreLoading = true);
    try {
      final res = await _fetch(_query, _page + 1);
      if (!mounted) return;
      final fresh = [
        for (final c in res.clips)
          if (_seenUrls.add(c.mp3Url)) c,
      ];
      setState(() {
        _page++;
        _clips = [..._clips, ...fresh];
        if (res.hasNext == false || res.clips.isEmpty) _endOfList = true;
      });
    } catch (_) {
      if (mounted) setState(() => _msg = t('تعذّر جلب المزيد'));
    } finally {
      if (mounted) setState(() => _moreLoading = false);
    }
  }

void _search() {
    // Search and category/board exclude each other; the box wins.
    _category = null;
    _board101 = null;
    _boardTitle = null;
    _memeCat = '';
    _fresh(_q.text.trim(), 1);
  }

  void _pickMemeSort(String sort) {
    _q.clear();
    setState(() {
      _memeSort = sort;
      _memeCat = '';
    });
    _fresh('', 1);
  }

  void _pickMemeCat(String slug) {
    _q.text = InstantSounds.memeCategories[slug]!;
    _search();
    setState(() => _memeCat = slug);
  }

  void _pickCategory(String? slug) {
    if (slug != null) _q.clear();
    setState(() => _category = slug);
    _fresh('', 1);
  }

  /// Jump straight to any page (e.g. 400). Replaces the list.
  /// Sounds only; boards page through the المزيد button.
  void _jump() {
    if (_inBoards) return;
    final n = int.tryParse(_pageCtl.text.trim()) ?? 0;
    if (n < 1) {
      setState(() => _msg = t('اكتب رقم صفحة 1 أو أكثر'));
      return;
    }
    _pageCtl.clear();
    _fresh(_query, n);
  }

  String _statusLine() {
    final how = t('▶ معاينة، ⬇ إضافة');
    if (_fromCatalog) {
      return '${t('قائمة محفوظة ({n})', {'n': _clips.length})} — $how';
    }
    if (_inBoards) {
      String? tag;
      for (final t2 in _tags101) {
        if (t2.tag == _tag101) {
          tag = t2.name;
          break;
        }
      }
      return '${tag ?? t('لوحات ١٠١')} (${_boards.length}) — ${t('صفحة {n}', {'n': _page})}';
    }
final prov = t(_providerNames[_provider] ?? '');
    if (_provider == 'myinstants' && _category != null) {
      return '${InstantSounds.categories[_category]} (${_clips.length}) — ${t('صفحة {n}', {'n': _page})} — $how';
    }
    if (_provider == 'meme' && _query.isEmpty) {
      final head = _memeCat.isNotEmpty
          ? '${t('ميم:')} ${InstantSounds.memeCategories[_memeCat]}'
          : '${t('ميم:')} ${t(InstantSounds.memeSorts[_memeSort] ?? '')}';
      return '$head (${_clips.length}) — ${t('صفحة {n}', {'n': _page})} — $how';
    }
    if (_query.isNotEmpty) {
      return '$prov: “$_query” (${_clips.length}) — ${t('صفحة {n}', {'n': _page})} — $how';
    }
    return '$prov: ${t('كلها 2–6 ثوانٍ')} (${_clips.length}) — ${t('صفحة {n}', {'n': _page})} — $how';
  }

  Future<String?> _ensureLocal(String mp3Url) async {
    final cached = _temps[mp3Url];
    if (cached != null) return cached;
    try {
      final path = await _api.downloadMp3(mp3Url);
      _temps[mp3Url] = path;
      return path;
    } catch (e) {
      if (mounted) {
        setState(() => _msg =
            e is StateError ? e.message : t('فشل التحميل: {n}', {'n': e}));
      }
      return null;
    }
  }

  Future<void> _preview(InstantClip clip) async {
    // Tap the playing sound again: stop it.
    if (_playingUrl == clip.mp3Url) {
      try {
        await ref.read(audioIoProvider).stopPlayback();
      } catch (_) {}
      if (mounted) setState(() => _playingUrl = null);
      return;
    }
    setState(() {
      _busyUrl = clip.mp3Url;
      _playingUrl = null;
    });
    try {
      final path = await _ensureLocal(clip.mp3Url);
      if (path == null || !mounted) return;
      await ref.read(audioIoProvider).stopPlayback();
      if (!mounted) return;
      setState(() => _playingUrl = clip.mp3Url);
      await ref.read(audioIoProvider).playOnce(path);
    } catch (e) {
      if (mounted) {
        setState(() => _msg = t('فشل التشغيل: {n}', {'n': e}));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busyUrl = null;
          if (_playingUrl == clip.mp3Url) _playingUrl = null;
        });
      }
    }
  }

  Future<void> _add(InstantClip clip) async {
    final path = await _ensureLocal(clip.mp3Url);
    if (path == null || !mounted) return;
    setState(() => _busyUrl = clip.mp3Url);
    try {
      final res = await ref
          .read(libraryProvider)
          .ingest(path, title: clip.title, sourceUrl: clip.mp3Url);
      if (!mounted) return;
      if (res.sound != null) {
        await ref
            .read(gameProvider.notifier)
            .reloadLibrary(ref.read(libraryProvider));
        setState(
            () => _msg = t('تمت الإضافة للمكتبة: "{n}"',
                {'n': res.sound!.title}));
      } else {
        setState(() => _msg = res.error);
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _msg = t('فشلت الإضافة: {n}', {'n': e}));
      }
    } finally {
      if (mounted) setState(() => _busyUrl = null);
    }
  }

  Future<void> _addLink() async {
    final url = _link.text.trim();
    if (url.isEmpty) {
      setState(() => _msg = t('الصق رابط الـmp3 أولًا'));
      return;
    }
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final path = await _api.downloadMp3(url);
      final fileName = url.split('/').last.split('?').first;
      final title = fileName.toLowerCase().endsWith('.mp3')
          ? fileName
              .substring(0, fileName.length - 4)
              .replaceAll(RegExp(r'[-_]+'), ' ')
          : t('صوت من الإنترنت');
      final res = await ref
          .read(libraryProvider)
          .ingest(path, title: title, sourceUrl: url);
      if (!mounted) return;
      if (res.sound != null) {
        await ref
            .read(gameProvider.notifier)
            .reloadLibrary(ref.read(libraryProvider));
        setState(() {
          _msg = t('تمت الإضافة للمكتبة: "{n}"',
              {'n': res.sound!.title});
          _link.clear();
        });
      } else {
        setState(() => _msg = res.error);
      }
    } catch (e) {
      if (mounted) {
        setState(
            () => _msg = e is StateError ? e.message : t('فشل التحميل: {n}', {'n': e}));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSite() async {    try {
      await _api.openSite();
    } catch (e) {
      if (mounted) {
        setState(() =>
            _msg = t('تعذّر فتح المتصفح: {n}', {'n': e}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('تحميل أصوات')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/library'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: t('ابحث عن صوت…'),
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _loading ? null : _search,
                    child: Text(t('بحث'))),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final e in _providerNames.entries)
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        label: Text(t(e.value)),
                        selected: _provider == e.key,
                        onSelected: (_) => _pickProvider(e.key),
                      ),
                    ),
                ],
              ),
            ),
            if (_provider == 'myinstants') ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.only(end: 6),
                      child: ChoiceChip(
                        label: Text(t('الكل')),
                        selected: _category == null,
                        onSelected: (_) => _pickCategory(null),
                      ),
                    ),
                    for (final e
                        in InstantSounds.categories.entries)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                            end: 6),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _category == e.key,
                          onSelected: (_) => _pickCategory(e.key),
                        ),
                      ),
                  ],
                ),
              ),
            ],
if (_provider == 'meme') ...[
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in InstantSounds.memeSorts.entries)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                            end: 6),
                        child: ChoiceChip(
                          label: Text(t(e.value)),
                          selected: _memeSort == e.key &&
                              _query.isEmpty,
                          onSelected: (_) => _pickMemeSort(e.key),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e
                        in InstantSounds.memeCategories.entries)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                            end: 6),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _memeCat == e.key,
                          onSelected: (_) => _pickMemeCat(e.key),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (_provider == 'board101' && _inBoards) ...[
              const SizedBox(height: 8),
              if (_tagsLoading)
                const LinearProgressIndicator()
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final tg in _tags101)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                              end: 6),
                          child: ChoiceChip(
                            label: Text(tg.name),
                            selected: _tag101 == tg.tag,
                            onSelected: (_) => _pickTag(tg.tag),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            if (_provider == 'board101' && !_inBoards) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(_boardTitle ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold)),
                  ),
                  TextButton.icon(
                    onPressed: _backToBoards,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(t('اللوحات')),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
            Text(_statusLine(),
                style: const TextStyle(fontSize: 12)),
            if (_loading) const LinearProgressIndicator(),
            if (_msg != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child:
                    Text(_msg!, style: const TextStyle(fontSize: 12)),
              ),
            const SizedBox(height: 8),
            if ((_inBoards ? _boards.isEmpty : _clips.isEmpty) &&
                !_loading)
              Center(child: Text(t('فارغ.'))),
            if (_inBoards)
              for (final board in _boards)
                Card(
                  child: ListTile(
                    leading: _Thumb(url: board.thumbnail),
                    title: Text(t(board.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => _openBoard(board),
                  ),
                ),
            if (!_inBoards)
              for (final clip in _clips)
                Builder(builder: (context) {
                  final busy = _busyUrl == clip.mp3Url;
                  final dur = clip.duration;
                  final showSrc = _provider == 'all' ||
                      clip.source != 'myinstants';
                  return Card(
                    child: ListTile(
                      leading: _Thumb(url: clip.thumbnail),
                      title: Text(t(clip.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      subtitle: (dur == null && !showSrc)
                          ? null
                          : Text(
                              [
                                if (dur != null)
                                  t('{n} ث',
                                      {'n': dur.toStringAsFixed(1)}),
                                if (showSrc)
                                  t(_sourceNames[clip.source] ??
                                      clip.source),
                              ].join(' · '),
                              style:
                                  const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SpriteButton(
                            seed: clip.mp3Url,
                            size: 42,
                            playing:
                                _playingUrl == clip.mp3Url,
                            onTap: () => _preview(clip),
                          ),
                          IconButton(
                            icon:
                                const Icon(Icons.download),
                            onPressed:
                                busy ? null : () => _add(clip),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            if (!_fromCatalog &&
                !_endOfList &&
                (_inBoards
                    ? _boards.isNotEmpty
                    : _clips.isNotEmpty))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: OutlinedButton(
                  onPressed: _moreLoading ? null : _more,
                  child: Text(_moreLoading ? '…' : t('المزيد')),
                ),
              ),
            if (!_inBoards &&
                !_fromCatalog &&
                !_loading &&
                _clips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pageCtl,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.go,
                        decoration: InputDecoration(
                          hintText:
                              t('اذهب لصفحة… (مثال 400)'),
                          prefixIcon: const Icon(Icons.last_page),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) {
                          if (!_loading) _jump();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: _loading ? null : _jump,
                      child: Text(t('اذهب')),
                    ),
                  ],
                ),
              ),
            const Divider(height: 32),
            Text(t('صوت من خارج القائمة؟'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              t('افتح الموقع في المتصفح، انسخ رابط ملف الـmp3 مباشرة، والصقه هنا.'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _openSite,
                icon: const Icon(Icons.open_in_browser),
                label: Text(t('افتح myinstants في المتصفح')),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _link,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                hintText: 'https://…mp3',
                labelText: t('رابط الـmp3'),
                prefixIcon: const Icon(Icons.link),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _addLink,
                icon: const Icon(Icons.download),
                label: Text(t('تحميل وإضافة للمكتبة')),
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
/// Board/sound art with an icon fallback when missing or offline.
class _Thumb extends StatelessWidget {
  final String? url;
  const _Thumb({this.url});

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || u.isEmpty) {
      return const Icon(Icons.audio_file_outlined);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        u,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.audio_file_outlined),
      ),
    );
  }
}
