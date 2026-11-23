import '../models/content.dart';

/// محلّل قوائم M3U / M3U8 (صيغة #EXTINF مع خصائص tvg-*).
class M3uParser {
  static final _attr = RegExp(r'([\w-]+)="([^"]*)"');

  static List<ContentItem> parse(String text, {String sourceId = 'm3u'}) {
    final items = <ContentItem>[];
    final lines = text.replaceAll('\r', '').split('\n');
    Map<String, String>? attrs;
    String? title;
    String? groupFromExtGrp;
    var index = 0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF')) {
        attrs = {};
        for (final m in _attr.allMatches(line)) {
          attrs[m.group(1)!.toLowerCase()] = m.group(2)!;
        }
        title = _titleAfterComma(line);
        continue;
      }
      if (line.startsWith('#EXTGRP:')) {
        groupFromExtGrp = line.substring(8).trim();
        continue;
      }
      if (line.startsWith('#')) continue;

      // سطر رابط
      if (attrs == null) {
        // رابط بدون #EXTINF: نتجاهله إلا إن كان رابطاً صالحاً
        attrs = {};
        title = line.split('/').last;
      }
      final url = line;
      final group = (attrs['group-title']?.trim().isNotEmpty ?? false)
          ? attrs['group-title']!.trim()
          : (groupFromExtGrp ?? 'بدون فئة');
      final name = (title?.trim().isNotEmpty ?? false) ? title!.trim() : (attrs['tvg-name'] ?? 'بدون اسم');
      items.add(ContentItem(
        id: '$sourceId:${index++}',
        name: name,
        type: guessType(url, group),
        category: group,
        logo: attrs['tvg-logo'] ?? '',
        streamUrl: url,
        epgId: attrs['tvg-id'] ?? '',
        ageRating: parseAgeRating(attrs['tvg-rating'] ?? attrs['rating'] ?? attrs['age']),
      ));
      attrs = null;
      title = null;
      groupFromExtGrp = null;
    }
    return items;
  }

  static String _titleAfterComma(String line) {
    var inQuote = false;
    // العنوان يبدأ بعد أول فاصلة خارج علامات الاقتباس (بعد المدة والخصائص)
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (c == '"') inQuote = !inQuote;
      if (c == ',' && !inQuote) return line.substring(i + 1);
    }
    return '';
  }

  /// تخمين النوع: روابط Xtream تحتوي /movie/ أو /series/، وأسماء الفئات قد تدل على النوع.
  static ContentType guessType(String url, String group) {
    final u = url.toLowerCase();
    final g = group.toLowerCase();
    if (u.contains('/series/') || g.contains('series') || g.contains('مسلسل')) {
      return ContentType.series;
    }
    if (u.contains('/movie/') ||
        g.contains('movie') ||
        g.contains('vod') ||
        g.contains('فيلم') ||
        g.contains('افلام') ||
        g.contains('أفلام') ||
        RegExp(r'\.(mp4|mkv|avi|mov)(\?|$)').hasMatch(u)) {
      return ContentType.movie;
    }
    return ContentType.live;
  }
}
