import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/content.dart';

/// عميل لواجهة Xtream Codes (player_api.php) التي تستخدمها أغلب خدمات IPTV.
class XtreamClient {
  final Source source;
  final http.Client _http;

  XtreamClient(this.source, {http.Client? client}) : _http = client ?? http.Client();

  String get base {
    var b = source.url.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    if (!b.startsWith('http://') && !b.startsWith('https://')) b = 'http://$b';
    return b;
  }

  String get _u => Uri.encodeComponent(source.username);
  String get _p => Uri.encodeComponent(source.password);

  Uri apiUri([String? action, Map<String, String> extra = const {}]) {
    final q = {
      'username': source.username,
      'password': source.password,
      'action': ?action,
      ...extra,
    };
    return Uri.parse('$base/player_api.php').replace(queryParameters: q);
  }

  String get epgUrl => '$base/xmltv.php?username=$_u&password=$_p';

  String liveUrl(String streamId) => '$base/live/$_u/$_p/$streamId.m3u8';
  String movieUrl(String streamId, String ext) => '$base/movie/$_u/$_p/$streamId.${ext.isEmpty ? 'mp4' : ext}';
  String episodeUrl(String episodeId, String ext) =>
      '$base/series/$_u/$_p/$episodeId.${ext.isEmpty ? 'mp4' : ext}';

  Future<dynamic> _get(String? action, [Map<String, String> extra = const {}]) async {
    final res = await _http.get(apiUri(action, extra)).timeout(const Duration(seconds: 40));
    if (res.statusCode != 200) {
      throw XtreamException('رد الخادم برمز ${res.statusCode}');
    }
    try {
      return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
    } catch (_) {
      throw XtreamException('رد غير مفهوم من الخادم');
    }
  }

  /// يتحقق من بيانات الدخول.
  Future<void> login() async {
    final data = await _get(null);
    final info = data is Map ? data['user_info'] : null;
    if (info is! Map || '${info['auth']}' != '1') {
      throw XtreamException('اسم المستخدم أو كلمة المرور غير صحيحة');
    }
  }

  Future<Map<String, String>> _categories(String action) async {
    final data = await _get(action);
    final map = <String, String>{};
    if (data is List) {
      for (final c in data) {
        if (c is Map) map['${c['category_id']}'] = '${c['category_name'] ?? ''}'.trim();
      }
    }
    return map;
  }

  Future<List<ContentItem>> fetchAll() async {
    final results = await Future.wait([
      _fetchType(ContentType.live, 'get_live_categories', 'get_live_streams'),
      _fetchType(ContentType.movie, 'get_vod_categories', 'get_vod_streams'),
      _fetchType(ContentType.series, 'get_series_categories', 'get_series'),
    ]);
    return results.expand((e) => e).toList();
  }

  Future<List<ContentItem>> _fetchType(ContentType type, String catAction, String listAction) async {
    final cats = await _categories(catAction);
    final data = await _get(listAction);
    if (data is! List) return [];
    final out = <ContentItem>[];
    for (final s in data) {
      if (s is! Map) continue;
      final isAdult = '${s['is_adult'] ?? '0'}' == '1';
      final age = isAdult ? 18 : parseAgeRating(s['age']?.toString() ?? s['mpaa_rating']?.toString());
      final cat = cats['${s['category_id']}'] ?? 'بدون فئة';
      switch (type) {
        case ContentType.live:
          final id = '${s['stream_id']}';
          out.add(ContentItem(
            id: '${source.id}:live:$id',
            name: '${s['name'] ?? ''}',
            type: type,
            category: cat.isEmpty ? 'بدون فئة' : cat,
            logo: '${s['stream_icon'] ?? ''}',
            streamUrl: liveUrl(id),
            epgId: '${s['epg_channel_id'] ?? ''}',
            ageRating: age,
          ));
        case ContentType.movie:
          final id = '${s['stream_id']}';
          out.add(ContentItem(
            id: '${source.id}:movie:$id',
            name: '${s['name'] ?? ''}',
            type: type,
            category: cat.isEmpty ? 'بدون فئة' : cat,
            logo: '${s['stream_icon'] ?? ''}',
            streamUrl: movieUrl(id, '${s['container_extension'] ?? 'mp4'}'),
            ageRating: age,
          ));
        case ContentType.series:
          final id = '${s['series_id']}';
          out.add(ContentItem(
            id: '${source.id}:series:$id',
            name: '${s['name'] ?? ''}',
            type: type,
            category: cat.isEmpty ? 'بدون فئة' : cat,
            logo: '${s['cover'] ?? ''}',
            seriesId: id,
            ageRating: age,
          ));
      }
    }
    return out;
  }

  Future<List<Episode>> fetchEpisodes(String seriesId) async {
    final data = await _get('get_series_info', {'series_id': seriesId});
    final eps = <Episode>[];
    final raw = data is Map ? data['episodes'] : null;
    void addList(dynamic seasonKey, dynamic list) {
      if (list is! List) return;
      for (final e in list) {
        if (e is! Map) continue;
        final id = '${e['id']}';
        eps.add(Episode(
          id: id,
          title: '${e['title'] ?? 'حلقة ${e['episode_num']}'}',
          season: int.tryParse('${e['season'] ?? seasonKey}') ?? 1,
          number: int.tryParse('${e['episode_num']}') ?? 0,
          streamUrl: episodeUrl(id, '${e['container_extension'] ?? 'mp4'}'),
        ));
      }
    }

    if (raw is Map) {
      raw.forEach(addList);
    } else if (raw is List) {
      // بعض الخوادم تعيد قائمة مواسم بدل خريطة
      for (var i = 0; i < raw.length; i++) {
        addList(i + 1, raw[i]);
      }
    }
    eps.sort((a, b) => a.season != b.season ? a.season.compareTo(b.season) : a.number.compareTo(b.number));
    return eps;
  }
}

class XtreamException implements Exception {
  final String message;
  XtreamException(this.message);
  @override
  String toString() => message;
}
