import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ---------------------------------------------------------------------------
// SETTINGS (सिर्फ यहीं बदलना है)
// ---------------------------------------------------------------------------

// ऐप के ऊपर बायीं तरफ दिखने वाला नाम
const String kAppTitle = 'AVITY';

// ऊपर दायीं तरफ खोज का आइकन दिखे या नहीं (true = दिखे, false = न दिखे)
const bool kShowSearch = true;

// डेटा फाइलें. बहुत बड़ा डेटा हो तो कई फाइलों में बांट दो.
const List<String> kDataFiles = <String>['assets/data.json'];

// JSON बदलने पर यह नंबर +1 कर दो (1 -> 2 -> 3), तभी नया डेटा लोड होगा.
const int kDataVersion = 1;

// एक बार में कितने विषय लिस्ट में लोड हों
const int kPageSize = 60;

// कार्ड का कोना कितना गोल हो
const double kCardRadius = 16;

// हर कार्ड के बीच की खाली जगह
const double kCardGap = 12;

// कार्ड के अंदर लोगो का आकार
const double kIconSize = 34;

const String kSearchHint = 'खोजें...';
const String kLoadError = 'डेटा लोड नहीं हो सका। data.json फाइल जांचें।';
const String kEmpty = 'अभी कोई विषय नहीं है।';
const String kNoResult = 'कोई परिणाम नहीं मिला।';

// लोगो के नाम: JSON के "ic" में यह नाम लिखो
const Map<String, IconData> kIcons = <String, IconData>{
  'walk': Icons.directions_walk,
  'food': Icons.restaurant,
  'sunrise': Icons.wb_twilight,
  'namaste': Icons.self_improvement,
  'health': Icons.favorite_border,
  'safety': Icons.health_and_safety,
  'book': Icons.menu_book,
  'study': Icons.school,
  'money': Icons.currency_rupee,
  'home': Icons.home_outlined,
  'water': Icons.water_drop_outlined,
  'clean': Icons.cleaning_services,
  'sleep': Icons.bedtime_outlined,
  'exercise': Icons.fitness_center,
  'travel': Icons.flight_takeoff,
  'phone': Icons.phone_android,
  'time': Icons.schedule,
  'shopping': Icons.shopping_cart_outlined,
  'family': Icons.family_restroom,
  'tree': Icons.park_outlined,
};

// ---------------------------------------------------------------------------

List<dynamic> _decodeList(String s) => jsonDecode(s) as List<dynamic>;

String _likePattern(String term) {
  final String e = term
      .replaceAll('!', '!!')
      .replaceAll('%', '!%')
      .replaceAll('_', '!_');
  return '%$e%';
}

class Item {
  Item(this.id, this.q, this.s, this.ic);
  final int id;
  final String q;
  final String s;
  final String ic;
}

class Detail {
  Detail(this.h, this.a);
  final String h;
  final String a;
}

class Store {
  Database? _db;

  Future<void> init() async {
    final String dir = await getDatabasesPath();
    final Database db = await openDatabase(
      p.join(dir, 'avity_guide.db'),
      version: 1,
      onCreate: (Database d, int v) async {
        await d.execute(
            'CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, q TEXT NOT NULL, s TEXT NOT NULL, h TEXT NOT NULL, a TEXT NOT NULL, ic TEXT NOT NULL)');
        await d.execute(
            'CREATE TABLE meta (id INTEGER PRIMARY KEY, v INTEGER NOT NULL)');
      },
    );
    _db = db;

    final List<Map<String, Object?>> rows =
        await db.query('meta', where: 'id = ?', whereArgs: <Object?>[1]);
    final int stored = rows.isEmpty ? 0 : (rows.first['v'] as int);
    if (stored != kDataVersion) {
      await _import(db);
    }
  }

  Future<void> _import(Database db) async {
    await db.transaction((Transaction txn) async {
      await txn.delete('items');
      for (final String file in kDataFiles) {
        final String raw = await rootBundle.loadString(file);
        final List<dynamic> list = await compute(_decodeList, raw);
        Batch batch = txn.batch();
        int count = 0;
        for (final dynamic item in list) {
          if (item is! Map) continue;
          final dynamic q = item['q'];
          final dynamic a = item['a'];
          if (q is! String || a is! String) continue;
          final String title = q.trim();
          if (title.isEmpty) continue;
          final dynamic s = item['s'];
          final dynamic h = item['h'];
          final dynamic ic = item['ic'];
          batch.insert('items', <String, Object?>{
            'q': title,
            's': s is String ? s.trim() : '',
            'h': h is String ? h.trim() : '',
            'a': a,
            'ic': ic is String ? ic.trim() : '',
          });
          count++;
          if (count % 500 == 0) {
            await batch.commit(noResult: true);
            batch = txn.batch();
          }
        }
        await batch.commit(noResult: true);
      }
      await txn.insert(
        'meta',
        <String, Object?>{'id': 1, 'v': kDataVersion},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<List<Item>> page(int afterId, int limit, String term) async {
    final Database? db = _db;
    if (db == null) return <Item>[];
    final bool all = term.isEmpty;
    final String like = _likePattern(term);
    final List<Map<String, Object?>> rows = await db.query(
      'items',
      columns: <String>['id', 'q', 's', 'ic'],
      where: all
          ? 'id > ?'
          : "id > ? AND (q LIKE ? ESCAPE '!' OR s LIKE ? ESCAPE '!')",
      whereArgs: all ? <Object?>[afterId] : <Object?>[afterId, like, like],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows
        .map((Map<String, Object?> r) => Item(
              r['id'] as int,
              (r['q'] as String?) ?? '',
              (r['s'] as String?) ?? '',
              (r['ic'] as String?) ?? '',
            ))
        .toList();
  }

  Future<Detail> detail(int id) async {
    final Database? db = _db;
    if (db == null) return Detail('', '');
    final List<Map<String, Object?>> rows = await db.query(
      'items',
      columns: <String>['h', 'a'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return Detail('', '');
    return Detail(
      (rows.first['h'] as String?) ?? '',
      (rows.first['a'] as String?) ?? '',
    );
  }
}

// रंग: लाइट और डार्क दोनों के लिए
class Pal {
  const Pal({
    required this.bg,
    required this.card,
    required this.text,
    required this.sub,
    required this.line,
    required this.splash,
    required this.highlight,
    required this.elevation,
  });

  final Color bg;
  final Color card;
  final Color text;
  final Color sub;
  final Color line;
  final Color splash;
  final Color highlight;
  final double elevation;

  static const Pal light = Pal(
    bg: Color(0xFFFFFFFF),
    card: Color(0xFFFFFFFF),
    text: Color(0xFF000000),
    sub: Color(0xFF6B6B6B),
    line: Color(0xFFE3E3E3),
    splash: Color(0x1F000000),
    highlight: Color(0x0F000000),
    elevation: 1.5,
  );

  static const Pal dark = Pal(
    bg: Color(0xFF121212),
    card: Color(0xFF1E1E1E),
    text: Color(0xFFECECEC),
    sub: Color(0xFF9A9A9A),
    line: Color(0xFF2E2E2E),
    splash: Color(0x1FFFFFFF),
    highlight: Color(0x0FFFFFFF),
    elevation: 0,
  );

  static Pal of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }
}

SystemUiOverlayStyle overlayFor(bool dark, Color bg) {
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: bg,
    systemNavigationBarDividerColor: bg,
    systemNavigationBarIconBrightness:
        dark ? Brightness.light : Brightness.dark,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}

class ItemIcon extends StatelessWidget {
  const ItemIcon({
    super.key,
    required this.name,
    required this.color,
    this.size = kIconSize,
  });

  final String name;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (name.startsWith('assets/')) {
      return Image.asset(
        name,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (BuildContext c, Object e, StackTrace? s) =>
            Icon(Icons.article_outlined, size: size, color: color),
      );
    }
    return Icon(kIcons[name] ?? Icons.article_outlined, size: size, color: color);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const AvityApp());
}

class AvityApp extends StatelessWidget {
  const AvityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppTitle,
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: Pal.light.bg,
        splashFactory: InkRipple.splashFactory,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          onPrimary: Colors.white,
          secondary: Colors.black,
          onSecondary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.black,
          selectionColor: Color(0x33000000),
          selectionHandleColor: Colors.black,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Pal.dark.bg,
        splashFactory: InkRipple.splashFactory,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          onPrimary: Colors.black,
          secondary: Colors.white,
          onSecondary: Colors.black,
          surface: Color(0xFF121212),
          onSurface: Colors.white,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Colors.white,
          selectionColor: Color(0x33FFFFFF),
          selectionHandleColor: Colors.white,
        ),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final Store _store = Store();
  final ScrollController _scroll = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final List<Item> _items = <Item>[];

  Timer? _debounce;
  String _term = '';
  bool _ready = false;
  bool _error = false;
  bool _loading = false;
  bool _hasMore = true;
  bool _fresh = true;
  bool _searching = false;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _boot();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      await _store.init();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = true;
          _ready = true;
        });
      }
      return;
    }
    await _loadMore();
    if (mounted) setState(() => _ready = true);
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 800) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final int gen = _loadGen;
    _loading = true;
    try {
      final int after = _items.isEmpty ? 0 : _items.last.id;
      final List<Item> next = await _store.page(after, kPageSize, _term);
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _items.addAll(next);
        _hasMore = next.length == kPageSize;
        _fresh = false;
      });
    } catch (_) {
      if (mounted && gen == _loadGen) {
        setState(() {
          _hasMore = false;
          _fresh = false;
        });
      }
    } finally {
      if (gen == _loadGen) _loading = false;
    }
  }

  Future<void> _reload() async {
    _loadGen++;
    _loading = false;
    _hasMore = true;
    setState(() {
      _items.clear();
      _fresh = true;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _loadMore();
  }

  void _openSearch() {
    setState(() => _searching = true);
  }

  void _closeSearch() {
    _debounce?.cancel();
    final bool had = _term.isNotEmpty;
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _term = '';
    });
    if (had) _reload();
  }

  void _onChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final String t = value.trim();
      if (t == _term) return;
      _term = t;
      _reload();
    });
  }

  void _clearText() {
    _searchCtrl.clear();
    _onChanged('');
  }

  void _open(Item item) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => AnswerPage(store: _store, item: item),
      ),
    );
  }

  Widget _card(Pal pal, Item it) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, kCardGap),
      child: Material(
        color: pal.card,
        elevation: pal.elevation,
        shadowColor: const Color(0x40000000),
        surfaceTintColor: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCardRadius),
          side: BorderSide(color: pal.line, width: 1),
        ),
        child: InkWell(
          splashColor: pal.splash,
          highlightColor: pal.highlight,
          onTap: () => _open(it),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        it.q,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.3,
                          fontWeight: FontWeight.w700,
                          color: pal.text,
                        ),
                      ),
                      if (it.s.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            it.s,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13, color: pal.sub),
                          ),
                        ),
                    ],
                  ),
                ),
                if (it.ic.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 12),
                  ItemIcon(name: it.ic, color: pal.text),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(Pal pal, double bottom) {
    if (!_ready) {
      return Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: pal.sub),
      );
    }
    if (_error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            kLoadError,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: pal.sub),
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      if (_fresh) return const SizedBox.shrink();
      return Center(
        child: Text(
          _term.isEmpty ? kEmpty : kNoResult,
          style: TextStyle(fontSize: 16, color: pal.sub),
        ),
      );
    }
    return ListView.builder(
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(top: 8, bottom: bottom + 16),
      itemCount: _items.length,
      itemBuilder: (BuildContext context, int i) => _card(pal, _items[i]),
    );
  }

  PreferredSizeWidget _appBar(Pal pal, SystemUiOverlayStyle overlay) {
    if (_searching) {
      return AppBar(
        backgroundColor: pal.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlay,
        leading: IconButton(
          onPressed: _closeSearch,
          icon: Icon(Icons.arrow_back, color: pal.text),
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          cursorColor: pal.text,
          textInputAction: TextInputAction.search,
          style: TextStyle(fontSize: 17, color: pal.text),
          onChanged: _onChanged,
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: kSearchHint,
            hintStyle: TextStyle(fontSize: 17, color: pal.sub),
          ),
        ),
        actions: <Widget>[
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              onPressed: _clearText,
              icon: Icon(Icons.close, color: pal.text),
            ),
        ],
      );
    }
    return AppBar(
      backgroundColor: pal.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: overlay,
      title: Text(
        kAppTitle,
        style: TextStyle(
          color: pal.text,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: <Widget>[
        if (kShowSearch)
          IconButton(
            onPressed: _openSearch,
            icon: Icon(Icons.search, color: pal.text),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final Pal pal = Pal.of(context);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final SystemUiOverlayStyle overlay = overlayFor(dark, pal.bg);
    final double bottom = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: PopScope(
        canPop: !_searching,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop && _searching) _closeSearch();
        },
        child: Scaffold(
          backgroundColor: pal.bg,
          appBar: _appBar(pal, overlay),
          body: _body(pal, bottom),
        ),
      ),
    );
  }
}

class AnswerPage extends StatefulWidget {
  const AnswerPage({super.key, required this.store, required this.item});

  final Store store;
  final Item item;

  @override
  State<AnswerPage> createState() => _AnswerPageState();
}

class _AnswerPageState extends State<AnswerPage> {
  late final Future<Detail> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.store.detail(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final Pal pal = Pal.of(context);
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final SystemUiOverlayStyle overlay = overlayFor(dark, pal.bg);
    final double bottom = MediaQuery.of(context).padding.bottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: pal.bg,
        appBar: AppBar(
          backgroundColor: pal.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          systemOverlayStyle: overlay,
          iconTheme: IconThemeData(color: pal.text),
        ),
        body: FutureBuilder<Detail>(
          future: _future,
          builder: (BuildContext context, AsyncSnapshot<Detail> snap) {
            if (snap.connectionState != ConnectionState.done) {
              return Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: pal.sub,
                ),
              );
            }
            final Detail d = snap.data ?? Detail('', '');
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 4, 20, bottom + 28),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SelectableText(
                      widget.item.q,
                      style: TextStyle(
                        fontSize: 28,
                        height: 1.3,
                        fontWeight: FontWeight.w800,
                        color: pal.text,
                      ),
                    ),
                    if (d.h.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 20),
                      SelectableText(
                        d.h,
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                          color: pal.text,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SelectableText(
                      d.a,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.75,
                        color: pal.text,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
