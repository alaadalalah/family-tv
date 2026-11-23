import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/content.dart';
import '../models/profile.dart';
import 'epg.dart';
import 'm3u_parser.dart';
import 'parental.dart';
import 'xtream_client.dart';

/// حالة التطبيق الكاملة: المصادر، الملفات الشخصية، الرمز السري، الاستهلاك، والمحتوى المحمّل.
class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  final http.Client httpClient;
  AppState(this.prefs, {http.Client? client}) : httpClient = client ?? http.Client();

  static const _kPin = 'pin_v1';
  static const _kSources = 'sources_v1';
  static const _kProfiles = 'profiles_v1';
  static const _kUsage = 'usage_v1';
  static const _kLocked = 'locked_profile_v1';
  static const _kFav = 'favorites_v1';

  // ---------- الرمز السري ----------
  String? _pinHash;
  String? _pinSalt;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  bool get hasPin => _pinHash != null;

  static String _hash(String pin, String salt) => sha256.convert(utf8.encode('$salt:$pin:family_tv')).toString();

  Future<void> setPin(String pin) async {
    final rnd = Random.secure();
    _pinSalt = base64Url.encode(List.generate(16, (_) => rnd.nextInt(256)));
    _pinHash = _hash(pin, _pinSalt!);
    await prefs.setString(_kPin, jsonEncode({'h': _pinHash, 's': _pinSalt}));
    notifyListeners();
  }

  /// يعيد عدد الثواني المتبقية لفك القفل إن كان مقفلاً بسبب المحاولات الخاطئة.
  int pinLockSecondsLeft([DateTime? now]) {
    final until = _lockedUntil;
    if (until == null) return 0;
    final s = until.difference(now ?? DateTime.now()).inSeconds;
    return s > 0 ? s : 0;
  }

  bool verifyPin(String pin, {DateTime? now}) {
    if (!hasPin) return true;
    if (pinLockSecondsLeft(now) > 0) return false;
    final ok = _hash(pin, _pinSalt!) == _pinHash;
    if (ok) {
      _failedAttempts = 0;
      _lockedUntil = null;
    } else {
      _failedAttempts++;
      if (_failedAttempts >= 5) {
        // قفل متصاعد: 30 ثانية ثم يتضاعف
        final secs = 30 * pow(2, _failedAttempts - 5).toInt();
        _lockedUntil = (now ?? DateTime.now()).add(Duration(seconds: min(secs, 900)));
      }
    }
    return ok;
  }

  // ---------- المصادر والملفات الشخصية ----------
  List<Source> sources = [];
  List<Profile> profiles = [];
  String? lockedProfileId;
  String? currentProfileId;
  final Map<String, DailyUsage> _usage = {};
  Map<String, Set<String>> favorites = {};

  Profile? get currentProfile {
    final id = currentProfileId;
    if (id == null) return null;
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Profile? get lockedProfile => profiles.where((p) => p.id == lockedProfileId).firstOrNull;

  bool get isSetUp => hasPin && profiles.isNotEmpty;

  Future<void> load() async {
    final pin = prefs.getString(_kPin);
    if (pin != null) {
      final m = jsonDecode(pin) as Map<String, dynamic>;
      _pinHash = m['h'] as String?;
      _pinSalt = m['s'] as String?;
    }
    sources = _decodeList(_kSources).map(Source.fromJson).toList();
    profiles = _decodeList(_kProfiles).map(Profile.fromJson).toList();
    for (final u in _decodeMap(_kUsage).entries) {
      _usage[u.key] = DailyUsage.fromJson(Map<String, dynamic>.from(u.value as Map));
    }
    favorites = _decodeMap(_kFav).map((k, v) => MapEntry(k, (v as List).map((e) => '$e').toSet()));
    lockedProfileId = prefs.getString(_kLocked);
    if (lockedProfile != null) {
      currentProfileId = lockedProfileId;
    } else if (profiles.length == 1) {
      currentProfileId = profiles.first.id;
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> _decodeList(String key) {
    final s = prefs.getString(key);
    if (s == null) return [];
    try {
      return (jsonDecode(s) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  Map<String, dynamic> _decodeMap(String key) {
    final s = prefs.getString(key);
    if (s == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(s) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveSources() => prefs.setString(_kSources, jsonEncode(sources.map((e) => e.toJson()).toList()));
  Future<void> saveProfiles() async {
    await prefs.setString(_kProfiles, jsonEncode(profiles.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Future<void> _saveUsage() =>
      prefs.setString(_kUsage, jsonEncode(_usage.map((k, v) => MapEntry(k, v.toJson()))));

  String newId() => '${DateTime.now().microsecondsSinceEpoch}${Random().nextInt(9999)}';

  Future<void> completeSetup({required String pin, required String parentName, bool addFree = false}) async {
    await setPin(pin);
    if (profiles.isEmpty) {
      profiles.add(Profile(id: newId(), name: parentName, isKid: false, colorIndex: 0));
      await saveProfiles();
    }
    if (addFree) await addFreeSources();
  }

  bool get missingFreeSources => freePublicSources.any((f) => !sources.any((s) => s.id == f.id));

  /// يضيف القوائم العامة المجانية غير المضافة بعد.
  Future<void> addFreeSources() async {
    for (final f in freePublicSources) {
      if (!sources.any((s) => s.id == f.id)) sources.add(f);
    }
    await _saveSources();
    notifyListeners();
    reloadCatalog();
  }

  /// فئات مناسبة للأطفال تُختار تلقائياً عند إنشاء ملف طفل.
  Set<String> suggestedKidCategories() {
    final re = RegExp(r'kids|children|animation|cartoon|education|أطفال|اطفال|كرتون|رسوم|تعليم', caseSensitive: false);
    final out = <String>{};
    for (final i in allItems) {
      if (re.hasMatch(i.category)) out.add(Profile.catKey(i.type, i.category));
    }
    return out;
  }

  Future<void> addSource(Source s) async {
    sources.removeWhere((e) => e.id == s.id);
    sources.add(s);
    await _saveSources();
    notifyListeners();
    await reloadCatalog();
  }

  Future<void> removeSource(String id) async {
    sources.removeWhere((e) => e.id == id);
    _catalog.removeWhere((k, _) => k == id);
    _epg.remove(id);
    await _saveSources();
    notifyListeners();
  }

  Future<void> addProfile(Profile p) async {
    profiles.add(p);
    await saveProfiles();
  }

  Future<void> deleteProfile(String id) async {
    if (profiles.length <= 1) return;
    final p = profiles.firstWhere((e) => e.id == id);
    // لا يُحذف آخر ملف للوالدين
    if (!p.isKid && profiles.where((e) => !e.isKid).length <= 1) return;
    profiles.removeWhere((e) => e.id == id);
    if (lockedProfileId == id) await setLockedProfile(null);
    if (currentProfileId == id) currentProfileId = null;
    await saveProfiles();
  }

  void switchProfile(String? id) {
    currentProfileId = id;
    notifyListeners();
  }

  /// قفل الجهاز على ملف طفل (مثل تابلت الطفل): يبدأ التطبيق فيه دائماً ويحتاج الرمز للخروج.
  Future<void> setLockedProfile(String? id) async {
    lockedProfileId = id;
    if (id == null) {
      await prefs.remove(_kLocked);
    } else {
      await prefs.setString(_kLocked, id);
      currentProfileId = id;
    }
    notifyListeners();
  }

  // ---------- المفضلة ----------
  bool isFavorite(String itemId) => favorites[currentProfileId]?.contains(itemId) ?? false;

  Future<void> toggleFavorite(String itemId) async {
    final pid = currentProfileId;
    if (pid == null) return;
    final set = favorites.putIfAbsent(pid, () => {});
    if (!set.remove(itemId)) set.add(itemId);
    await prefs.setString(_kFav, jsonEncode(favorites.map((k, v) => MapEntry(k, v.toList()))));
    notifyListeners();
  }

  // ---------- وقت المشاهدة ----------
  DailyUsage usageFor(String profileId, [DateTime? now]) {
    final today = dayKey(now ?? DateTime.now());
    final u = _usage[profileId];
    if (u == null || u.day != today) return _usage[profileId] = DailyUsage(today);
    return u;
  }

  TimeStatus statusFor(Profile p, [DateTime? now]) {
    final t = now ?? DateTime.now();
    return ParentalRules.status(p, usageFor(p.id, t), t);
  }

  TimeStatus get currentStatus {
    final p = currentProfile;
    return p == null ? const TimeStatus.ok(null) : statusFor(p);
  }

  int _unsaved = 0;

  /// يُستدعى كل ثانية أثناء التشغيل الفعلي.
  void addWatchSeconds(int s) {
    final p = currentProfile;
    if (p == null) return;
    usageFor(p.id).seconds += s;
    _unsaved += s;
    if (_unsaved >= 15) flushUsage();
  }

  Future<void> flushUsage() async {
    _unsaved = 0;
    await _saveUsage();
  }

  Future<void> grantBonus(String profileId, int minutes) async {
    usageFor(profileId).bonusSeconds += minutes * 60;
    await _saveUsage();
    notifyListeners();
  }

  Future<void> resetToday(String profileId) async {
    final u = usageFor(profileId);
    u.seconds = 0;
    u.bonusSeconds = 0;
    await _saveUsage();
    notifyListeners();
  }

  // ---------- المحتوى ----------
  final Map<String, List<ContentItem>> _catalog = {};
  final Map<String, EpgGuide> _epg = {};
  final Map<String, String> sourceErrors = {};
  bool loading = false;

  List<ContentItem> get allItems => _catalog.values.expand((e) => e).toList();

  XtreamClient? xtreamFor(ContentItem item) {
    final sid = item.id.split(':').first;
    final s = sources.where((e) => e.id == sid && e.kind == SourceKind.xtream).firstOrNull;
    return s == null ? null : XtreamClient(s, client: httpClient);
  }

  Future<void> reloadCatalog() async {
    if (loading) return;
    loading = true;
    sourceErrors.clear();
    notifyListeners();
    await Future.wait(sources.map(_loadSource));
    loading = false;
    notifyListeners();
    // دليل البرامج يُحمّل في الخلفية بعد ظهور المحتوى
    for (final s in sources) {
      _loadEpg(s);
    }
  }

  Future<void> _loadSource(Source s) async {
    try {
      if (s.kind == SourceKind.xtream) {
        final c = XtreamClient(s, client: httpClient);
        await c.login();
        _catalog[s.id] = await c.fetchAll();
      } else {
        final res = await httpClient.get(Uri.parse(s.url)).timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) throw Exception('رد الخادم برمز ${res.statusCode}');
        final text = utf8.decode(res.bodyBytes, allowMalformed: true);
        if (!text.trimLeft().startsWith('#EXTM3U') && !text.contains('#EXTINF')) {
          throw Exception('الملف ليس قائمة M3U صالحة');
        }
        _catalog[s.id] = M3uParser.parse(text, sourceId: s.id);
      }
    } catch (e) {
      sourceErrors[s.id] = '$e'.replaceFirst('Exception: ', '');
    }
  }

  Future<void> _loadEpg(Source s) async {
    var url = s.epgUrl.trim();
    if (url.isEmpty && s.kind == SourceKind.xtream) url = XtreamClient(s).epgUrl;
    if (url.isEmpty) return;
    try {
      _epg[s.id] = await EpgGuide.fetch(url, client: httpClient);
      notifyListeners();
    } catch (_) {
      // دليل البرامج اختياري؛ نتجاهل الفشل
    }
  }

  (Programme?, Programme?) nowNext(ContentItem item) {
    if (item.epgId.isEmpty) return (null, null);
    final g = _epg[item.id.split(':').first];
    return g?.nowNext(item.epgId) ?? (null, null);
  }

  /// للاختبارات ولصفحة المعاينة.
  @visibleForTesting
  void setCatalogForTest(String sourceId, List<ContentItem> items) {
    _catalog[sourceId] = items;
    notifyListeners();
  }

  // ---------- الترشيح حسب الملف الشخصي ----------
  bool isAllowed(ContentItem item) {
    final p = currentProfile;
    return p == null || ParentalRules.isItemAllowed(p, item);
  }

  List<ContentItem> visibleItems(ContentType type) =>
      allItems.where((i) => i.type == type && isAllowed(i)).toList();

  /// الفئات الظاهرة للملف الحالي مع عدد العناصر.
  List<MapEntry<String, int>> visibleCategories(ContentType type) {
    final counts = <String, int>{};
    for (final i in visibleItems(type)) {
      counts[i.category] = (counts[i.category] ?? 0) + 1;
    }
    return counts.entries.toList();
  }

  /// كل الفئات (دون ترشيح) لشاشة إعدادات ولي الأمر.
  List<String> allCategories(ContentType type) {
    final seen = <String>{};
    for (final i in allItems) {
      if (i.type == type) seen.add(i.category);
    }
    return seen.toList();
  }

  List<ContentItem> favoriteItems() {
    final fav = favorites[currentProfileId] ?? {};
    return allItems.where((i) => fav.contains(i.id) && isAllowed(i)).toList();
  }

  List<ContentItem> search(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) return [];
    return allItems.where((i) => i.name.toLowerCase().contains(s) && isAllowed(i)).take(200).toList();
  }
}
