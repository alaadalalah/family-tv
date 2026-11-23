/// نماذج البيانات الأساسية: المصدر، العنصر (قناة/فيلم/حلقة)، الفئة.
library;

enum ContentType { live, movie, series }

extension ContentTypeX on ContentType {
  String get label => switch (this) {
        ContentType.live => 'القنوات المباشرة',
        ContentType.movie => 'الأفلام',
        ContentType.series => 'المسلسلات',
      };
  String get key => name;
  static ContentType fromKey(String k) =>
      ContentType.values.firstWhere((e) => e.name == k, orElse: () => ContentType.live);
}

enum SourceKind { m3u, xtream }

/// مصدر يضيفه المستخدم بنفسه. التطبيق لا يحتوي أي محتوى مدمج.
class Source {
  final String id;
  final String name;
  final SourceKind kind;

  /// رابط ملف M3U، أو عنوان خادم Xtream (مثل http://host:port)
  final String url;
  final String username;
  final String password;

  /// رابط دليل البرامج XMLTV (اختياري)
  final String epgUrl;

  const Source({
    required this.id,
    required this.name,
    required this.kind,
    required this.url,
    this.username = '',
    this.password = '',
    this.epgUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'url': url,
        'username': username,
        'password': password,
        'epgUrl': epgUrl,
      };

  factory Source.fromJson(Map<String, dynamic> j) => Source(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        kind: SourceKind.values.firstWhere((e) => e.name == j['kind'], orElse: () => SourceKind.m3u),
        url: j['url'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        epgUrl: j['epgUrl'] as String? ?? '',
      );
}

/// قوائم عامة مجانية من مشروع iptv-org (روابط بث مجانية متاحة للعامة من القنوات نفسها).
/// تُضاف عند الإعداد الأول ويمكن حذفها من الإعدادات.
const freePublicSources = <Source>[
  Source(
    id: 'free_kids',
    name: 'قنوات أطفال مجانية (iptv-org)',
    kind: SourceKind.m3u,
    url: 'https://iptv-org.github.io/iptv/categories/kids.m3u',
  ),
  Source(
    id: 'free_ar',
    name: 'قنوات عربية مجانية (iptv-org)',
    kind: SourceKind.m3u,
    url: 'https://iptv-org.github.io/iptv/languages/ara.m3u',
  ),
];

/// عنصر قابل للعرض: قناة مباشرة، فيلم، أو مسلسل (المسلسل يُفتح لصفحة الحلقات).
class ContentItem {
  final String id;
  final String name;
  final ContentType type;
  final String category;
  final String logo;

  /// رابط التشغيل المباشر. فارغ للمسلسلات القادمة من Xtream (تُجلب الحلقات لاحقاً).
  final String streamUrl;

  /// معرّف القناة في دليل البرامج (tvg-id / epg_channel_id)
  final String epgId;

  /// التصنيف العمري إن وجد في بيانات المصدر (بالسنوات). null = غير معروف.
  final int? ageRating;

  /// معرّف المسلسل في Xtream لجلب المواسم والحلقات.
  final String seriesId;

  const ContentItem({
    required this.id,
    required this.name,
    required this.type,
    required this.category,
    this.logo = '',
    this.streamUrl = '',
    this.epgId = '',
    this.ageRating,
    this.seriesId = '',
  });
}

class Episode {
  final String id;
  final String title;
  final int season;
  final int number;
  final String streamUrl;
  const Episode({
    required this.id,
    required this.title,
    required this.season,
    required this.number,
    required this.streamUrl,
  });
}

/// يحوّل نصوص التصنيف الشائعة (G, PG-13, TV-Y7, 12+, FSK 16 ...) إلى عمر بالسنوات.
int? parseAgeRating(String? raw) {
  if (raw == null) return null;
  final s = raw.trim().toUpperCase();
  if (s.isEmpty) return null;
  const known = {
    'G': 0, 'TV-Y': 0, 'TV-G': 0, 'U': 0, 'E': 0,
    'TV-Y7': 7, 'TV-Y7-FV': 7, 'PG': 10, 'TV-PG': 10,
    'PG-13': 13, 'TV-14': 14, '12A': 12,
    'R': 17, 'TV-MA': 17, 'NC-17': 18, 'X': 18, 'XXX': 18,
  };
  if (known.containsKey(s)) return known[s];
  // درجات التقييم مثل 7.5 أو 8/10 ليست أعماراً
  if (s.contains('.') || s.contains('/')) return null;
  final m = RegExp(r'(\d{1,2})').firstMatch(s);
  if (m != null) {
    final n = int.parse(m.group(1)!);
    if (n <= 21) return n;
  }
  return null;
}
