import 'content.dart';

/// كلمات تُحجب دائماً في ملفات الأطفال (تُطابق اسم الفئة أو اسم العنصر).
const defaultBlockedKeywords = <String>[
  'xxx', 'adult', 'adults', '+18', '18+', 'porn', 'erotic', 'sexy', 'for adults',
  'للكبار', 'كبار فقط', 'إباحي', 'اباحي', 'رعب', 'horror',
];

enum CategoryMode {
  /// كل الفئات مسموحة ما عدا المحجوبة بالكلمات أو بالعمر
  all,

  /// فقط الفئات التي يختارها ولي الأمر
  allowList,
}

class Profile {
  final String id;
  String name;
  bool isKid;
  int colorIndex;

  /// أنواع المحتوى المسموحة (مباشر / أفلام / مسلسلات)
  Set<ContentType> allowedTypes;

  CategoryMode categoryMode;

  /// مفاتيح الفئات المسموحة بالصيغة "type|اسم الفئة"
  Set<String> allowedCategories;

  /// كلمات إضافية يحجبها ولي الأمر
  List<String> extraBlockedKeywords;

  /// أقصى تصنيف عمري مسموح (null = بلا حد)
  int? maxAge;

  /// حجب الأفلام والمسلسلات التي لا يُعرف تصنيفها العمري عند تفعيل حد العمر
  bool blockUnrated;

  /// الحد اليومي بالدقائق (0 = بلا حد)
  int dailyLimitMinutes;

  /// نافذة المشاهدة المسموحة بالدقائق منذ منتصف الليل (null = طوال اليوم).
  /// إن كانت النهاية أصغر من البداية فالنافذة تعبر منتصف الليل.
  int? windowStart;
  int? windowEnd;

  Profile({
    required this.id,
    required this.name,
    this.isKid = false,
    this.colorIndex = 0,
    Set<ContentType>? allowedTypes,
    this.categoryMode = CategoryMode.all,
    Set<String>? allowedCategories,
    List<String>? extraBlockedKeywords,
    this.maxAge,
    this.blockUnrated = false,
    this.dailyLimitMinutes = 0,
    this.windowStart,
    this.windowEnd,
  })  : allowedTypes = allowedTypes ?? ContentType.values.toSet(),
        allowedCategories = allowedCategories ?? {},
        extraBlockedKeywords = extraBlockedKeywords ?? [];

  factory Profile.kidDefaults({required String id, required String name, int colorIndex = 1}) => Profile(
        id: id,
        name: name,
        isKid: true,
        colorIndex: colorIndex,
        categoryMode: CategoryMode.allowList,
        maxAge: 7,
        blockUnrated: false,
        dailyLimitMinutes: 90,
        windowStart: 8 * 60,
        windowEnd: 20 * 60,
      );

  static String catKey(ContentType t, String category) => '${t.name}|$category';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isKid': isKid,
        'colorIndex': colorIndex,
        'allowedTypes': allowedTypes.map((e) => e.name).toList(),
        'categoryMode': categoryMode.name,
        'allowedCategories': allowedCategories.toList(),
        'extraBlockedKeywords': extraBlockedKeywords,
        'maxAge': maxAge,
        'blockUnrated': blockUnrated,
        'dailyLimitMinutes': dailyLimitMinutes,
        'windowStart': windowStart,
        'windowEnd': windowEnd,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        isKid: j['isKid'] as bool? ?? false,
        colorIndex: j['colorIndex'] as int? ?? 0,
        allowedTypes: ((j['allowedTypes'] as List?) ?? ContentType.values.map((e) => e.name).toList())
            .map((e) => ContentTypeX.fromKey('$e'))
            .toSet(),
        categoryMode: CategoryMode.values
            .firstWhere((e) => e.name == j['categoryMode'], orElse: () => CategoryMode.all),
        allowedCategories: ((j['allowedCategories'] as List?) ?? []).map((e) => '$e').toSet(),
        extraBlockedKeywords: ((j['extraBlockedKeywords'] as List?) ?? []).map((e) => '$e').toList(),
        maxAge: j['maxAge'] as int?,
        blockUnrated: j['blockUnrated'] as bool? ?? false,
        dailyLimitMinutes: j['dailyLimitMinutes'] as int? ?? 0,
        windowStart: j['windowStart'] as int?,
        windowEnd: j['windowEnd'] as int?,
      );
}

/// استهلاك اليوم لملف شخصي.
class DailyUsage {
  String day; // yyyy-mm-dd
  int seconds;
  int bonusSeconds; // وقت إضافي منحه ولي الأمر لهذا اليوم
  DailyUsage(this.day, {this.seconds = 0, this.bonusSeconds = 0});

  Map<String, dynamic> toJson() => {'day': day, 'seconds': seconds, 'bonus': bonusSeconds};
  factory DailyUsage.fromJson(Map<String, dynamic> j) =>
      DailyUsage(j['day'] as String? ?? '', seconds: j['seconds'] as int? ?? 0, bonusSeconds: j['bonus'] as int? ?? 0);
}

String dayKey(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
