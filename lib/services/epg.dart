import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml_events.dart';

class Programme {
  final String channel;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String desc;
  const Programme(this.channel, this.start, this.stop, this.title, this.desc);

  bool isOn(DateTime t) => !t.isBefore(start) && t.isBefore(stop);
}

/// دليل البرامج (XMLTV). يحتفظ فقط بالبرامج القريبة من الوقت الحالي لتوفير الذاكرة.
class EpgGuide {
  final Map<String, List<Programme>> _byChannel = {};

  bool get isEmpty => _byChannel.isEmpty;
  int get channelCount => _byChannel.length;

  static Future<EpgGuide> fetch(String url, {http.Client? client, DateTime? now}) async {
    final c = client ?? http.Client();
    final res = await c.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
    if (res.statusCode != 200) throw Exception('تعذّر تحميل دليل البرامج (${res.statusCode})');
    var bytes = res.bodyBytes;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = const GZipDecoder().decodeBytes(bytes);
    }
    return parse(utf8.decode(bytes, allowMalformed: true), now: now);
  }

  /// [now] للاختبارات. يحتفظ بالبرامج من قبل 3 ساعات حتى بعد 24 ساعة.
  static EpgGuide parse(String xml, {DateTime? now}) {
    final g = EpgGuide();
    final t = now ?? DateTime.now();
    final from = t.subtract(const Duration(hours: 3));
    final to = t.add(const Duration(hours: 24));

    String? ch;
    DateTime? start, stop;
    String title = '', desc = '';
    String? field;

    for (final e in parseEvents(xml)) {
      if (e is XmlStartElementEvent) {
        if (e.name == 'programme') {
          String attr(String n) =>
              e.attributes.firstWhere((a) => a.name == n, orElse: () => XmlEventAttribute(n, '', XmlAttributeType.DOUBLE_QUOTE)).value;
          ch = attr('channel');
          start = parseXmltvTime(attr('start'));
          stop = parseXmltvTime(attr('stop'));
          title = '';
          desc = '';
          if (e.isSelfClosing) ch = null;
        } else if (ch != null && (e.name == 'title' || e.name == 'desc')) {
          field = e.name;
        }
      } else if (e is XmlTextEvent || e is XmlCDATAEvent) {
        final text = e is XmlTextEvent ? e.value : (e as XmlCDATAEvent).value;
        if (field == 'title' && title.isEmpty) title = text.trim();
        if (field == 'desc' && desc.isEmpty) desc = text.trim();
      } else if (e is XmlEndElementEvent) {
        if (e.name == 'title' || e.name == 'desc') {
          field = null;
        } else if (e.name == 'programme') {
          if (ch != null && start != null && stop != null && stop.isAfter(from) && start.isBefore(to)) {
            g._byChannel.putIfAbsent(ch.toLowerCase(), () => []).add(Programme(ch, start, stop, title, desc));
          }
          ch = null;
        }
      }
    }
    for (final l in g._byChannel.values) {
      l.sort((a, b) => a.start.compareTo(b.start));
    }
    return g;
  }

  /// البرنامج الحالي والتالي لقناة.
  (Programme?, Programme?) nowNext(String epgId, {DateTime? at}) {
    final list = _byChannel[epgId.toLowerCase()];
    if (list == null || epgId.isEmpty) return (null, null);
    final t = at ?? DateTime.now();
    for (var i = 0; i < list.length; i++) {
      if (list[i].isOn(t)) return (list[i], i + 1 < list.length ? list[i + 1] : null);
      if (list[i].start.isAfter(t)) return (null, list[i]);
    }
    return (null, null);
  }
}

/// صيغة XMLTV: 20261123060000 +0300
DateTime? parseXmltvTime(String s) {
  final m = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?').firstMatch(s.trim());
  if (m == null) return null;
  int p(int i) => int.parse(m.group(i) ?? '0');
  var dt = DateTime.utc(p(1), p(2), p(3), p(4), p(5), p(6));
  final tz = m.group(7);
  if (tz != null) {
    final sign = tz.startsWith('-') ? -1 : 1;
    final mins = int.parse(tz.substring(1, 3)) * 60 + int.parse(tz.substring(3, 5));
    dt = dt.subtract(Duration(minutes: sign * mins));
  }
  return dt.toLocal();
}
