import 'package:family_tv/main.dart';
import 'package:family_tv/models/content.dart';
import 'package:family_tv/models/profile.dart';
import 'package:family_tv/services/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppState> seeded({int watchedSeconds = 0}) async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState(await SharedPreferences.getInstance());
  await s.completeSetup(pin: '1234', parentName: 'الوالدين');
  await s.addProfile(Profile.kidDefaults(id: 'k', name: 'سارة')
    ..windowStart = null
    ..windowEnd = null
    ..maxAge = null
    ..allowedCategories = {'live|أطفال'});
  s.sources.add(const Source(id: 'd', name: 'd', kind: SourceKind.m3u, url: 'http://x'));
  s.setCatalogForTest('d', const [
    ContentItem(id: 'd:1', name: 'كرتون', type: ContentType.live, category: 'أطفال'),
    ContentItem(id: 'd:2', name: 'أخبار', type: ContentType.live, category: 'أخبار'),
  ]);
  s.switchProfile('k');
  s.addWatchSeconds(watchedSeconds);
  return s;
}

void main() {
  testWidgets('first launch shows setup', (t) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppState(await SharedPreferences.getInstance());
    await s.load();
    await t.pumpWidget(ChangeNotifierProvider.value(value: s, child: const FamilyTvApp()));
    await t.pump();
    expect(find.text('مرحباً بك في تلفاز العائلة'), findsOneWidget);
  });

  testWidgets('kid sees only allowed channels', (t) async {
    final s = await seeded();
    await t.pumpWidget(ChangeNotifierProvider.value(value: s, child: const FamilyTvApp()));
    await t.pump();
    expect(find.text('كرتون'), findsOneWidget);
    expect(find.text('أخبار'), findsNothing);
  });

  testWidgets('time up blocks browsing', (t) async {
    final s = await seeded(watchedSeconds: 90 * 60);
    await t.pumpWidget(ChangeNotifierProvider.value(value: s, child: const FamilyTvApp()));
    await t.pump();
    expect(find.text('انتهى وقت المشاهدة لليوم'), findsOneWidget);
    expect(find.text('كرتون'), findsNothing);
  });
}
