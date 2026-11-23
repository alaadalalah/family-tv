import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'screens/profile_picker.dart';
import 'screens/setup_screen.dart';
import 'services/app_state.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final state = AppState(prefs);
  await state.load();
  if (state.sources.isNotEmpty) state.reloadCatalog();
  runApp(ChangeNotifierProvider.value(value: state, child: const FamilyTvApp()));
}

class FamilyTvApp extends StatelessWidget {
  const FamilyTvApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: tvShortcuts,
      child: MaterialApp(
        title: 'تلفاز العائلة',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const RootGate(),
      ),
    );
  }
}

/// يقرر الشاشة الأولى: الإعداد الأول، اختيار الملف الشخصي، أو الرئيسية.
class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.isSetUp) return const SetupScreen();
    if (state.currentProfile == null) return const ProfilePicker();
    return HomeScreen(key: ValueKey(state.currentProfileId));
  }
}
