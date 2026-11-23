import '../models/content.dart';
import '../models/profile.dart';

/// قواعد حماية الطفل. دوال خالصة سهلة الاختبار.
class ParentalRules {
  static bool _hasBlockedWord(Profile p, String text) {
    if (!p.isKid) return false;
    final t = text.toLowerCase();
    for (final w in [...defaultBlockedKeywords, ...p.extraBlockedKeywords]) {
      final k = w.trim().toLowerCase();
      if (k.isNotEmpty && t.contains(k)) return true;
    }
    return false;
  }

  static bool isTypeAllowed(Profile p, ContentType t) => !p.isKid || p.allowedTypes.contains(t);

  static bool isCategoryAllowed(Profile p, ContentType t, String category) {
    if (!p.isKid) return true;
    if (!isTypeAllowed(p, t)) return false;
    if (_hasBlockedWord(p, category)) return false;
    if (p.categoryMode == CategoryMode.allowList) {
      return p.allowedCategories.contains(Profile.catKey(t, category));
    }
    return true;
  }

  static bool isItemAllowed(Profile p, ContentItem item) {
    if (!p.isKid) return true;
    if (!isCategoryAllowed(p, item.type, item.category)) return false;
    if (_hasBlockedWord(p, item.name)) return false;
    if (item.ageRating != null && item.ageRating! >= 18) return false;
    if (p.maxAge != null) {
      final age = item.ageRating;
      if (age == null) {
        if (p.blockUnrated && item.type != ContentType.live) return false;
      } else if (age > p.maxAge!) {
        return false;
      }
    }
    return true;
  }

  static int _minutesOfDay(DateTime t) => t.hour * 60 + t.minute;

  static bool inWindow(Profile p, DateTime now) {
    final s = p.windowStart, e = p.windowEnd;
    if (s == null || e == null || s == e) return true;
    final m = _minutesOfDay(now);
    return s < e ? (m >= s && m < e) : (m >= s || m < e);
  }

  /// حالة الوقت الحالية للملف الشخصي.
  static TimeStatus status(Profile p, DailyUsage? usage, DateTime now) {
    if (!p.isKid) return const TimeStatus.ok(null);
    if (!inWindow(p, now)) return TimeStatus.outsideWindow(p.windowStart!, p.windowEnd!);
    if (p.dailyLimitMinutes <= 0) return const TimeStatus.ok(null);
    final today = dayKey(now);
    final used = usage != null && usage.day == today ? usage.seconds : 0;
    final bonus = usage != null && usage.day == today ? usage.bonusSeconds : 0;
    final remaining = p.dailyLimitMinutes * 60 + bonus - used;
    if (remaining <= 0) return const TimeStatus.limitReached();
    // إن كانت النافذة ستنتهي قبل نفاد الرصيد، فالمتبقي هو حتى نهاية النافذة
    var r = remaining;
    if (p.windowStart != null && p.windowEnd != null && p.windowStart != p.windowEnd) {
      final m = _minutesOfDay(now);
      var untilEnd = p.windowEnd! - m;
      if (untilEnd <= 0) untilEnd += 24 * 60;
      final secs = untilEnd * 60 - now.second;
      if (secs < r) r = secs;
    }
    return TimeStatus.ok(r);
  }
}

enum TimeState { ok, outsideWindow, limitReached }

class TimeStatus {
  final TimeState state;

  /// الثواني المتبقية (null = بلا حد)
  final int? remainingSeconds;
  final int? windowStart;
  final int? windowEnd;

  const TimeStatus.ok(this.remainingSeconds)
      : state = TimeState.ok,
        windowStart = null,
        windowEnd = null;
  const TimeStatus.outsideWindow(int s, int e)
      : state = TimeState.outsideWindow,
        remainingSeconds = 0,
        windowStart = s,
        windowEnd = e;
  const TimeStatus.limitReached()
      : state = TimeState.limitReached,
        remainingSeconds = 0,
        windowStart = null,
        windowEnd = null;

  bool get canWatch => state == TimeState.ok;
}

String formatMinutesOfDay(int m) {
  final h = (m ~/ 60) % 24, mm = m % 60;
  return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
}

String formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
  if (h > 0) return '$h س $m د';
  return '$m د';
}
