import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../widgets/pin_dialog.dart';

/// الإعداد الأول: اسم ولي الأمر ورمز سري يحمي الإعدادات.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _name = TextEditingController(text: 'الوالدين');

  Future<void> _start() async {
    final pin = await askNewPin(context);
    if (pin == null || !mounted) return;
    await context.read<AppState>().completeSetup(
          pin: pin,
          parentName: _name.text.trim().isEmpty ? 'الوالدين' : _name.text.trim(),
          addFree: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(Icons.family_restroom, size: 72, color: Color(0xFF7FA6FF)),
              const SizedBox(height: 12),
              Text('مرحباً بك في تلفاز العائلة', style: t.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              const Text(
                'مشغّل للقنوات والأفلام والمسلسلات من اشتراكك الخاص (رابط M3U أو حساب Xtream)، '
                'مع ملفات للأطفال تحدد وقت المشاهدة والفئات المسموحة.\n\n'
                'سنضيف لك قنوات عامة مجانية (عربية وأطفال) لتبدأ فوراً، ويمكنك إضافة اشتراكك المرخّص من الإعدادات.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.6),
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'اسم ملف ولي الأمر'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                autofocus: true,
                onPressed: _start,
                icon: const Icon(Icons.lock_outline),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('اختر رمز ولي الأمر وابدأ', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'الرمز مطلوب لتغيير الإعدادات، والخروج من ملف الطفل، ومنح وقت إضافي.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
