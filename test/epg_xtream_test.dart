import 'dart:convert';

import 'package:family_tv/models/content.dart';
import 'package:family_tv/services/epg.dart';
import 'package:family_tv/services/xtream_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('XMLTV now/next', () {
    final now = DateTime.utc(2026, 11, 23, 10, 30).toLocal();
    const xml = '''<?xml version="1.0"?><tv>
<programme start="20261123100000 +0000" stop="20261123110000 +0000" channel="Kids.One"><title lang="ar">رسوم متحركة</title><desc>وصف</desc></programme>
<programme start="20261123110000 +0000" stop="20261123120000 +0000" channel="Kids.One"><title><![CDATA[Next Show]]></title></programme>
<programme start="20201123110000 +0000" stop="20201123120000 +0000" channel="Kids.One"><title>Old</title></programme>
</tv>''';
    final g = EpgGuide.parse(xml, now: now);
    final (cur, next) = g.nowNext('kids.one', at: now);
    expect(cur?.title, 'رسوم متحركة');
    expect(cur?.desc, 'وصف');
    expect(next?.title, 'Next Show');
  });

  test('parseXmltvTime handles offsets', () {
    expect(parseXmltvTime('20261123060000 +0300')!.toUtc(), DateTime.utc(2026, 11, 23, 3));
    expect(parseXmltvTime('garbage'), isNull);
  });

  test('Xtream client builds catalog and episodes', () async {
    final mock = MockClient((req) async {
      final a = req.url.queryParameters['action'];
      expect(req.url.path, '/player_api.php');
      expect(req.url.queryParameters['username'], 'u@x');
      final body = switch (a) {
        null => {'user_info': {'auth': 1}},
        'get_live_categories' => [{'category_id': '1', 'category_name': 'Kids'}],
        'get_live_streams' => [
            {'stream_id': 10, 'name': 'Cartoons', 'category_id': '1', 'epg_channel_id': 'c.1', 'stream_icon': ''},
            {'stream_id': 11, 'name': 'Late', 'category_id': '1', 'is_adult': '1'},
          ],
        'get_vod_categories' => [{'category_id': '2', 'category_name': 'Family'}],
        'get_vod_streams' => [{'stream_id': 20, 'name': 'Film', 'category_id': '2', 'container_extension': 'mkv'}],
        'get_series_categories' => [],
        'get_series' => [{'series_id': 30, 'name': 'Show', 'category_id': '9', 'cover': ''}],
        'get_series_info' => {
            'episodes': {
              '2': [{'id': '302', 'episode_num': 1, 'title': 'S2E1', 'container_extension': 'mp4', 'season': 2}],
              '1': [{'id': '301', 'episode_num': 1, 'title': 'S1E1', 'container_extension': 'mp4', 'season': 1}],
            }
          },
        _ => [],
      };
      return http.Response(jsonEncode(body), 200);
    });
    const src = Source(id: 'x', name: 'X', kind: SourceKind.xtream, url: 'host.tv:8080/', username: 'u@x', password: 'p');
    final c = XtreamClient(src, client: mock);
    await c.login();
    final items = await c.fetchAll();
    expect(items.map((e) => e.name), containsAll(['Cartoons', 'Late', 'Film', 'Show']));
    final live = items.firstWhere((e) => e.name == 'Cartoons');
    expect(live.streamUrl, 'http://host.tv:8080/live/u%40x/p/10.m3u8');
    expect(live.category, 'Kids');
    expect(items.firstWhere((e) => e.name == 'Late').ageRating, 18);
    expect(items.firstWhere((e) => e.name == 'Film').streamUrl, endsWith('/movie/u%40x/p/20.mkv'));
    expect(items.firstWhere((e) => e.name == 'Show').category, 'بدون فئة');
    final eps = await c.fetchEpisodes('30');
    expect(eps.map((e) => e.title), ['S1E1', 'S2E1']);
  });

  test('Xtream login failure', () async {
    final mock = MockClient((_) async => http.Response(jsonEncode({'user_info': {'auth': 0}}), 200));
    const src = Source(id: 'x', name: 'X', kind: SourceKind.xtream, url: 'http://h', username: 'u', password: 'p');
    expect(XtreamClient(src, client: mock).login(), throwsA(isA<XtreamException>()));
  });
}
