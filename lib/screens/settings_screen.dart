import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../models/profile.dart';
import '../services/app_state.dart';
import '../services/parental.dart';
import '../widgets/common.dart';
import '../widgets/pin_dialog.dart';
import 'profile_editor.dart';

/// إعدادات ولي الأمر (تُفتح بعد إدخال الرمز).
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final locked = s.lockedProfile;
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات ولي الأمر')),
      body: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
        ListTile(
          autofocus: true,
          leading: const Icon(Icons.playlist_play),
          title: const Text('المصادر (M3U / Xtream)'),
          subtitle: Text('${s.sources.length} مصدر'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: const Text('الملفات الشخصية وحماية الطفل'),
          subtitle: Text('${s.profiles.where((p) => p.isKid).length} ملف طفل'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilesScreen())),
        ),
        ListTile(
          leading: const Icon(Icons.phonelink_lock),
          title: const Text('قفل هذا الجهاز على ملف طفل'),
          subtitle: Text(locked == null
              ? 'غير مفعّل. فعّله على تابلت الطفل ليفتح التطبيق دائماً على ملفه.'
              : 'مقفل على: ${locked.name}'),
          onTap: () => _chooseLock(context, s),
        ),
        ListTile(
          leading: const Icon(Icons.password),
          title: const Text('تغيير رمز ولي الأمر'),
          onTap: () async {
            final pin = await askNewPin(context);
            if (pin == null) return;
            await s.setPin(pin);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تغيير الرمز')));
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text('تحديث المحتوى من المصادر'),
          onTap: s.loading ? null : s.reloadCatalog,
          trailing: s.loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('حول التطبيق'),
          subtitle: Text(
            'تلفاز العائلة 1.0 — مشغّل فقط، بلا أي محتوى مدمج. '
            'لحماية أقوى على تابلت الطفل فعّل "تثبيت الشاشة" في إعدادات أندرويد أو استخدم Google Family Link لمنع الخروج من التطبيق.',
          ),
        ),
      ]),
    );
  }

  Future<void> _chooseLock(BuildContext context, AppState s) async {
    final kids = s.profiles.where((p) => p.isKid).toList();
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('قفل الجهاز على'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ''), child: const Text('بدون قفل')),
          for (final k in kids) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, k.id), child: Text(k.name)),
          if (kids.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('أنشئ ملف طفل أولاً.')),
        ],
      ),
    );
    if (choice == null) return;
    await s.setLockedProfile(choice.isEmpty ? null : choice);
  }
}

// ---------------- المصادر ----------------

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('المصادر')),
      floatingActionButton: FloatingActionButton.extended(
        autofocus: s.sources.isEmpty,
        icon: const Icon(Icons.add),
        label: const Text('إضافة مصدر'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SourceForm())),
      ),
      body: ListView(children: [
              if (s.missingFreeSources)
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('إضافة القنوات العامة المجانية'),
                  subtitle: const Text('قنوات عربية وقنوات أطفال مجانية من مشروع iptv-org'),
                  onTap: s.addFreeSources,
                ),
              if (s.sources.isEmpty)
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('لا توجد مصادر'),
                  subtitle: Text('أضف رابط M3U أو حساب Xtream من مزوّد خدمتك.'),
                ),
              for (final src in s.sources)
                ListTile(
                  leading: Icon(src.kind == SourceKind.m3u ? Icons.list_alt : Icons.dns_outlined),
                  title: Text(src.name),
                  subtitle: Text(
                    s.sourceErrors[src.id] ??
                        '${src.kind == SourceKind.m3u ? 'قائمة M3U' : 'حساب Xtream'} · '
                            '${s.allItems.where((i) => i.id.startsWith('${src.id}:')).length} عنصر',
                    style: TextStyle(color: s.sourceErrors.containsKey(src.id) ? Colors.redAccent : null),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SourceForm(existing: src))),
                  trailing: IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('حذف "${src.name}"؟'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                          ],
                        ),
                      );
                      if (ok == true) await s.removeSource(src.id);
                    },
                  ),
                ),
            ]),
    );
  }
}

class SourceForm extends StatefulWidget {
  final Source? existing;
  const SourceForm({super.key, this.existing});

  @override
  State<SourceForm> createState() => _SourceFormState();
}

class _SourceFormState extends State<SourceForm> {
  late SourceKind _kind = widget.existing?.kind ?? SourceKind.m3u;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _url = TextEditingController(text: widget.existing?.url ?? '');
  late final _user = TextEditingController(text: widget.existing?.username ?? '');
  late final _pass = TextEditingController(text: widget.existing?.password ?? '');
  late final _epg = TextEditingController(text: widget.existing?.epgUrl ?? '');
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final s = context.read<AppState>();
    final url = _url.text.trim();
    if (url.isEmpty || (_kind == SourceKind.xtream && (_user.text.trim().isEmpty || _pass.text.isEmpty))) {
      setState(() => _error = 'أكمل الحقول المطلوبة');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final src = Source(
      id: widget.existing?.id ?? s.newId(),
      name: _name.text.trim().isEmpty ? (_kind == SourceKind.m3u ? 'قائمة M3U' : 'حساب Xtream') : _name.text.trim(),
      kind: _kind,
      url: url,
      username: _user.text.trim(),
      password: _pass.text,
      epgUrl: _epg.text.trim(),
    );
    await s.addSource(src);
    if (!mounted) return;
    final err = s.sourceErrors[src.id];
    if (err != null) {
      setState(() {
        _saving = false;
        _error = 'تم الحفظ، لكن تعذّر التحميل: $err';
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final xt = _kind == SourceKind.xtream;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'إضافة مصدر' : 'تعديل المصدر')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            SegmentedButton<SourceKind>(
              segments: const [
                ButtonSegment(value: SourceKind.m3u, label: Text('رابط M3U'), icon: Icon(Icons.list_alt)),
                ButtonSegment(value: SourceKind.xtream, label: Text('حساب Xtream'), icon: Icon(Icons.dns_outlined)),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 20),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'اسم المصدر (اختياري)')),
            const SizedBox(height: 14),
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: xt ? 'عنوان الخادم *' : 'رابط قائمة M3U *',
                hintText: xt ? 'http://example.com:8080' : 'https://example.com/playlist.m3u',
              ),
            ),
            if (xt) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _user,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'اسم المستخدم *'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _pass,
                obscureText: true,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'كلمة المرور *'),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _epg,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: 'رابط دليل البرامج EPG (اختياري)',
                helperText: xt ? 'اتركه فارغاً لاستخدام دليل الخادم تلقائياً' : 'ملف XMLTV بصيغة xml أو xml.gz',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('حفظ وتحميل', style: TextStyle(fontSize: 16)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ---------------- الملفات الشخصية ----------------

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('الملفات الشخصية')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.child_care),
        label: const Text('إضافة ملف طفل'),
        onPressed: () async {
          final p = Profile.kidDefaults(
            id: s.newId(),
            name: 'طفل ${s.profiles.where((e) => e.isKid).length + 1}',
            colorIndex: (s.profiles.length) % profileColors.length,
          )..allowedCategories = s.suggestedKidCategories();
          await s.addProfile(p);
          if (context.mounted) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditor(profileId: p.id)));
          }
        },
      ),
      body: ListView(children: [
        for (final p in s.profiles)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: profileColors[p.colorIndex % profileColors.length],
              child: Icon(p.isKid ? Icons.child_care : Icons.person, color: Colors.white),
            ),
            title: Text(p.name),
            subtitle: Text(_summary(s, p)),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditor(profileId: p.id))),
          ),
      ]),
    );
  }

  String _summary(AppState s, Profile p) {
    if (!p.isKid) return 'ولي أمر · بلا قيود';
    final parts = <String>[];
    parts.add(p.dailyLimitMinutes > 0 ? '${p.dailyLimitMinutes} دقيقة يومياً' : 'بلا حد يومي');
    if (p.windowStart != null && p.windowEnd != null) {
      parts.add('من ${formatMinutesOfDay(p.windowStart!)} إلى ${formatMinutesOfDay(p.windowEnd!)}');
    }
    final used = s.usageFor(p.id).seconds;
    parts.add('شاهد اليوم ${formatDuration(used)}');
    return parts.join(' · ');
  }
}
