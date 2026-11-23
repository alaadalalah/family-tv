import 'package:family_tv/models/content.dart';
import 'package:family_tv/models/profile.dart';
import 'package:family_tv/services/parental.dart';
import 'package:flutter_test/flutter_test.dart';

ContentItem item(String name, String cat, {ContentType type = ContentType.live, int? age}) =>
    ContentItem(id: name, name: name, type: type, category: cat, ageRating: age);

void main() {
  final parent = Profile(id: 'p', name: 'Parent');

  group('content filtering', () {
    test('parent sees everything', () {
      expect(ParentalRules.isItemAllowed(parent, item('x', 'XXX Adults')), isTrue);
    });

    test('kid allow-list only shows chosen categories', () {
      final kid = Profile.kidDefaults(id: 'k', name: 'Kid')
        ..maxAge = null
        ..allowedCategories = {Profile.catKey(ContentType.live, 'أطفال')};
      expect(ParentalRules.isItemAllowed(kid, item('Cartoon', 'أطفال')), isTrue);
      expect(ParentalRules.isItemAllowed(kid, item('News', 'News')), isFalse);
      // same category name under another type is a different key
      expect(ParentalRules.isItemAllowed(kid, item('M', 'أطفال', type: ContentType.movie)), isFalse);
    });

    test('blocked keywords always win, even in "all" mode', () {
      final kid = Profile(id: 'k', name: 'Kid', isKid: true, extraBlockedKeywords: ['مصارعة']);
      expect(ParentalRules.isItemAllowed(kid, item('a', 'Adults +18')), isFalse);
      expect(ParentalRules.isItemAllowed(kid, item('a', 'أفلام رعب', type: ContentType.movie)), isFalse);
      expect(ParentalRules.isItemAllowed(kid, item('مصارعة حرة', 'Sports')), isFalse);
      expect(ParentalRules.isItemAllowed(kid, item('Football', 'Sports')), isTrue);
    });

    test('content type switches', () {
      final kid = Profile(id: 'k', name: 'Kid', isKid: true, allowedTypes: {ContentType.movie});
      expect(ParentalRules.isItemAllowed(kid, item('a', 'c')), isFalse);
      expect(ParentalRules.isItemAllowed(kid, item('a', 'c', type: ContentType.movie)), isTrue);
    });

    test('age ratings', () {
      final kid = Profile(id: 'k', name: 'Kid', isKid: true, maxAge: 7);
      expect(ParentalRules.isItemAllowed(kid, item('a', 'c', type: ContentType.movie, age: 7)), isTrue);
      expect(ParentalRules.isItemAllowed(kid, item('a', 'c', type: ContentType.movie, age: 13)), isFalse);
      expect(ParentalRules.isItemAllowed(kid, item('a', 'c', type: ContentType.movie)), isTrue);
      kid.blockUnrated = true;
      expect(ParentalRules.isItemAllowed(kid, item('a', 'c', type: ContentType.movie)), isFalse);
      expect(ParentalRules.isItemAllowed(kid, item('a', 'c')), isTrue, reason: 'live channels never carry ratings');
      final noLimit = Profile(id: 'k', name: 'Kid', isKid: true);
      expect(ParentalRules.isItemAllowed(noLimit, item('a', 'c', age: 18)), isFalse, reason: 'adult flag always blocked');
    });
  });

  group('time limits', () {
    final kid = Profile(id: 'k', name: 'Kid', isKid: true, dailyLimitMinutes: 60, windowStart: 8 * 60, windowEnd: 20 * 60);
    final at10 = DateTime(2026, 11, 23, 10, 0);

    test('remaining time within window', () {
      final u = DailyUsage(dayKey(at10), seconds: 20 * 60);
      final s = ParentalRules.status(kid, u, at10);
      expect(s.canWatch, isTrue);
      expect(s.remainingSeconds, 40 * 60);
    });

    test('limit reached and bonus', () {
      final u = DailyUsage(dayKey(at10), seconds: 60 * 60);
      expect(ParentalRules.status(kid, u, at10).state, TimeState.limitReached);
      u.bonusSeconds = 15 * 60;
      expect(ParentalRules.status(kid, u, at10).remainingSeconds, 15 * 60);
    });

    test('usage from a previous day does not count', () {
      final u = DailyUsage('2026-11-22', seconds: 999999);
      expect(ParentalRules.status(kid, u, at10).canWatch, isTrue);
    });

    test('outside window', () {
      expect(ParentalRules.status(kid, null, DateTime(2026, 11, 23, 7, 59)).state, TimeState.outsideWindow);
      expect(ParentalRules.status(kid, null, DateTime(2026, 11, 23, 20, 0)).state, TimeState.outsideWindow);
    });

    test('remaining is capped by window end', () {
      final s = ParentalRules.status(kid, null, DateTime(2026, 11, 23, 19, 40));
      expect(s.remainingSeconds, 20 * 60);
    });

    test('window across midnight', () {
      final night = Profile(id: 'n', name: 'n', isKid: true, windowStart: 22 * 60, windowEnd: 2 * 60);
      expect(ParentalRules.inWindow(night, DateTime(2026, 1, 1, 23, 0)), isTrue);
      expect(ParentalRules.inWindow(night, DateTime(2026, 1, 1, 1, 0)), isTrue);
      expect(ParentalRules.inWindow(night, DateTime(2026, 1, 1, 12, 0)), isFalse);
    });

    test('parent is never limited', () {
      expect(ParentalRules.status(parent, null, DateTime(2026, 1, 1, 3)).canWatch, isTrue);
    });
  });

  test('profile json round trip', () {
    final p = Profile.kidDefaults(id: 'k', name: 'سارة')
      ..allowedCategories = {'live|أطفال'}
      ..allowedTypes = {ContentType.live};
    final back = Profile.fromJson(p.toJson());
    expect(back.name, 'سارة');
    expect(back.isKid, isTrue);
    expect(back.allowedCategories, {'live|أطفال'});
    expect(back.allowedTypes, {ContentType.live});
    expect(back.dailyLimitMinutes, 90);
    expect(back.windowStart, 480);
  });
}
