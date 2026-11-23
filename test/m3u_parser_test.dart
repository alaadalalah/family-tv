import 'package:family_tv/models/content.dart';
import 'package:family_tv/services/m3u_parser.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = '''#EXTM3U url-tvg="http://epg.example/guide.xml"
#EXTINF:-1 tvg-id="kids.one" tvg-logo="http://img/k1.png" group-title="أطفال",Kids One, HD
http://example.com/live/u/p/1.ts
#EXTINF:-1 tvg-id="news" group-title="News",News 24
http://example.com/live/u/p/2.m3u8
#EXTINF:-1 group-title="VOD | Movies" tvg-rating="PG-13",Some Movie (2020)
http://example.com/movie/u/p/3.mp4
#EXTINF:-1 group-title="Series AR",Show S01E01
http://example.com/series/u/p/4.mkv
#EXTINF:-1,No Group
#EXTGRP:Misc
http://example.com/5.ts
''';

void main() {
  test('parses entries, attributes and titles with commas', () {
    final items = M3uParser.parse(sample, sourceId: 's');
    expect(items, hasLength(5));
    expect(items[0].name, 'Kids One, HD');
    expect(items[0].category, 'أطفال');
    expect(items[0].logo, 'http://img/k1.png');
    expect(items[0].epgId, 'kids.one');
    expect(items[0].type, ContentType.live);
    expect(items[0].id, 's:0');
  });

  test('guesses types and age ratings', () {
    final items = M3uParser.parse(sample);
    expect(items[2].type, ContentType.movie);
    expect(items[2].ageRating, 13);
    expect(items[3].type, ContentType.series);
    expect(items[4].category, 'Misc');
  });

  test('parseAgeRating handles common formats', () {
    expect(parseAgeRating('G'), 0);
    expect(parseAgeRating('TV-Y7'), 7);
    expect(parseAgeRating('12+'), 12);
    expect(parseAgeRating('FSK 16'), 16);
    expect(parseAgeRating('R'), 17);
    expect(parseAgeRating(''), isNull);
    expect(parseAgeRating('7.5'), isNull, reason: 'review scores are not ages');
  });
}
