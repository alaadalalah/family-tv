import 'package:family_tv/models/content.dart';
import 'package:family_tv/models/profile.dart';
import 'package:family_tv/services/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('PIN is hashed, verified and locks out after 5 failures', () async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppState(prefs);
    await s.completeSetup(pin: '2468', parentName: 'أبي');
    expect(prefs.getString('pin_v1'), isNot(contains('2468')));
    expect(s.verifyPin('2468'), isTrue);
    final t = DateTime(2026, 1, 1, 12);
    for (var i = 0; i < 5; i++) {
      expect(s.verifyPin('0000', now: t), isFalse);
    }
    expect(s.pinLockSecondsLeft(t), 30);
    expect(s.verifyPin('2468', now: t), isFalse, reason: 'locked even with right PIN');
    expect(s.verifyPin('2468', now: t.add(const Duration(seconds: 31))), isTrue);
  });

  test('state persists and kid view is filtered', () async {
    final prefs = await SharedPreferences.getInstance();
    final s = AppState(prefs);
    await s.completeSetup(pin: '1234', parentName: 'P');
    final kid = Profile.kidDefaults(id: 'k', name: 'K')
      ..maxAge = null
      ..windowStart = null
      ..windowEnd = null
      ..allowedCategories = {'live|Kids'};
    await s.addProfile(kid);
    await s.setLockedProfile('k');
    s.setCatalogForTest('src', const [
      ContentItem(id: 'src:1', name: 'Toons', type: ContentType.live, category: 'Kids'),
      ContentItem(id: 'src:2', name: 'News', type: ContentType.live, category: 'News'),
    ]);
    expect(s.visibleItems(ContentType.live).map((e) => e.name), ['Toons']);
    s.addWatchSeconds(30);
    await s.flushUsage();

    final s2 = AppState(prefs);
    await s2.load();
    expect(s2.currentProfileId, 'k', reason: 'locked device opens on kid profile');
    expect(s2.usageFor('k').seconds, 30);
    expect(s2.statusFor(s2.currentProfile!).remainingSeconds, 90 * 60 - 30);
    expect(s2.verifyPin('1234'), isTrue);
  });
}
