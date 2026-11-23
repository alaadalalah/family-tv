// معاينة الواجهة ببيانات وهمية (بدون أي بث) لالتقاط لقطات الشاشة أثناء التطوير.
// التشغيل: flutter run -d chrome -t preview/preview_main.dart
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:family_tv/main.dart';
import 'package:family_tv/models/content.dart';
import 'package:family_tv/models/profile.dart';
import 'package:family_tv/screens/profile_editor.dart';
import 'package:family_tv/services/app_state.dart';
import 'package:family_tv/widgets/common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final mode = Uri.base.queryParameters['screen'] ?? 'parent';
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final s = AppState(prefs);
  await s.completeSetup(pin: '1234', parentName: 'الوالدين');
  if (mode == 'setup') {
    await prefs.clear();
    final fresh = AppState(prefs);
    await fresh.load();
    runApp(ChangeNotifierProvider.value(value: fresh, child: const FamilyTvApp()));
    return;
  }
  final now = DateTime.now();
  final kid = Profile.kidDefaults(id: 'kid', name: 'سارة', colorIndex: 1)
    ..windowStart = mode == 'outside' ? (now.hour + 2) % 24 * 60 : 0
    ..windowEnd = mode == 'outside' ? (now.hour + 4) % 24 * 60 : 23 * 60 + 30
    ..allowedCategories = {'live|أطفال', 'live|وثائقي', 'movie|أفلام عائلية', 'movie|رسوم متحركة'};
  await s.addProfile(kid);
  await s.addProfile(Profile.kidDefaults(id: 'kid2', name: 'عمر', colorIndex: 2));
  s.sources.add(const Source(id: 'demo', name: 'مصدر تجريبي', kind: SourceKind.m3u, url: 'http://example.invalid/list.m3u'));
  final items = <ContentItem>[];
  void add(ContentType t, String cat, List<String> names) {
    for (final n in names) {
      items.add(ContentItem(id: 'demo:${items.length}', name: n, type: t, category: cat, streamUrl: 'http://example.invalid/${items.length}'));
    }
  }

  add(ContentType.live, 'أطفال', ['قناة الأطفال 1', 'قناة الأطفال 2', 'رسوم HD', 'براعم', 'كرتون بلس', 'تعليمي للصغار']);
  add(ContentType.live, 'وثائقي', ['وثائقي الطبيعة', 'عالم الحيوان', 'علوم']);
  add(ContentType.live, 'أخبار', ['الأخبار 24', 'أخبار العالم']);
  add(ContentType.live, 'رياضة', ['رياضة 1', 'رياضة 2', 'رياضة 3']);
  add(ContentType.live, 'Adults +18', ['Late Night']);
  add(ContentType.movie, 'أفلام عائلية', ['مغامرة في الغابة', 'رحلة إلى القمر', 'الصديق الوفي']);
  add(ContentType.movie, 'رسوم متحركة', ['الأسد الصغير', 'سمكة ملونة', 'روبوت لطيف', 'القطار السحري']);
  add(ContentType.movie, 'أكشن', ['المطاردة', 'العاصفة']);
  add(ContentType.movie, 'أفلام رعب', ['الليل المظلم']);
  add(ContentType.series, 'مسلسلات أطفال', ['المحقق الصغير', 'مغامرات سامي']);
  add(ContentType.series, 'دراما', ['الحي القديم']);
  s.setCatalogForTest('demo', items);

  if (mode == 'kid' || mode == 'timeup' || mode == 'outside' || mode == 'editor') s.switchProfile('kid');
  if (mode == 'parent') s.switchProfile(s.profiles.first.id);
  if (mode == 'picker') s.switchProfile(null);
  if (mode == 'timeup') s.addWatchSeconds(90 * 60);
  if (mode == 'kid') s.addWatchSeconds(35 * 60);

  if (mode == 'editor') {
    runApp(ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const ProfileEditor(profileId: 'kid'),
      ),
    ));
    return;
  }
  runApp(ChangeNotifierProvider.value(value: s, child: const FamilyTvApp()));
}
