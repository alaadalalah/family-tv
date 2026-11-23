import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../models/profile.dart';
import '../services/app_state.dart';
import '../services/parental.dart';
import '../widgets/common.dart';
import 'home_screen.dart' show grantBonusFlow;

/// إعدادات ملف شخصي: وقت المشاهدة، الفئات المسموحة، التصنيف العمري.
class ProfileEditor extends StatefulWidget {
  final String profileId;
  const ProfileEditor({super.key, required this.profileId});

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final AppState _s = context.read<AppState>();
  late final Profile _p = _s.profiles.firstWhere((e) => e.id == widget.profileId);
  late final _name = TextEditingController(text: _p.name);
  late final _words = TextEditingController(text: _p.extraBlockedKeywords.join('، '));

  Future<void> _update(void Function() change) async {
    setState(change);
    await _s.saveProfiles();
  }

  static const _limits = [0, 30, 45, 60, 90, 120, 180, 240];
  static const _ages = <int?>[null, 3, 7, 10, 13, 16];
  static final _times = List.generate(48, (i) => i * 30);

  @override
  void dispose() {
    _commitText();
    super.dispose();
  }

  void _commitText() {
    final n = _name.text.trim();
    if (n.isNotEmpty) _p.name = n;
    _p.extraBlockedKeywords =
        _words.text.split(RegExp(r'[,،\n]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    _s.saveProfiles();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: Text('ملف: ${_p.name}')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'الاسم'),
              onSubmitted: (_) => _commitText(),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 10, children: [
              for (var i = 0; i < profileColors.length; i++)
                ChoiceChip(
                  label: const Text(' '),
                  avatar: CircleAvatar(backgroundColor: profileColors[i]),
                  selected: _p.colorIndex == i,
                  onSelected: (_) => _update(() => _p.colorIndex = i),
                ),
            ]),
            if (!_p.isKid) ...[
              const SizedBox(height: 24),
              const ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('ملف ولي أمر'),
                subtitle: Text('يرى كل المحتوى بلا قيود، ويحتاج الرمز للدخول.'),
              ),
            ] else
              ..._kidSections(context),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.redAccent),
              icon: const Icon(Icons.delete_outline),
              label: const Text('حذف هذا الملف'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text('حذف ملف "${_p.name}"؟'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
                    ],
                  ),
                );
                if (ok != true) return;
                final before = _s.profiles.length;
                await _s.deleteProfile(_p.id);
                if (!context.mounted) return;
                if (_s.profiles.length == before) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('لا يمكن حذف آخر ملف لولي الأمر')));
                } else {
                  Navigator.pop(context);
                }
              },
            ),
          ]),
        ),
      ),
    );
  }

  Widget _header(String t, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 8),
        child: Row(children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(t, style: Theme.of(context).textTheme.titleMedium),
        ]),
      );

  List<Widget> _kidSections(BuildContext context) {
    final usage = _s.usageFor(_p.id);
    final status = _s.statusFor(_p);
    return [
      // ---- وقت المشاهدة ----
      _header('وقت المشاهدة', Icons.timer_outlined),
      ListTile(
        title: const Text('الحد اليومي'),
        trailing: DropdownButton<int>(
          value: _limits.contains(_p.dailyLimitMinutes) ? _p.dailyLimitMinutes : null,
          hint: Text('${_p.dailyLimitMinutes} د'),
          items: [
            for (final m in _limits)
              DropdownMenuItem(value: m, child: Text(m == 0 ? 'بلا حد' : formatDuration(m * 60))),
          ],
          onChanged: (v) => _update(() => _p.dailyLimitMinutes = v ?? 0),
        ),
      ),
      SwitchListTile(
        title: const Text('تحديد ساعات المشاهدة'),
        subtitle: const Text('خارج هذه الساعات لا يمكن المشاهدة (مثل وقت النوم والمدرسة)'),
        value: _p.windowStart != null,
        onChanged: (on) => _update(() {
          _p.windowStart = on ? 8 * 60 : null;
          _p.windowEnd = on ? 20 * 60 : null;
        }),
      ),
      if (_p.windowStart != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 16, crossAxisAlignment: WrapCrossAlignment.center, children: [
            const Text('من'),
            _timeDropdown(_p.windowStart!, (v) => _update(() => _p.windowStart = v)),
            const Text('إلى'),
            _timeDropdown(_p.windowEnd ?? 20 * 60, (v) => _update(() => _p.windowEnd = v)),
          ]),
        ),
      Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('اليوم: شاهد ${formatDuration(usage.seconds)}'
                '${usage.bonusSeconds > 0 ? ' · وقت إضافي ${formatDuration(usage.bonusSeconds)}' : ''}'),
            const SizedBox(height: 4),
            Text(
              switch (status.state) {
                TimeState.ok => status.remainingSeconds == null
                    ? 'المشاهدة متاحة الآن'
                    : 'المتبقي الآن: ${formatDuration(status.remainingSeconds!)}',
                TimeState.limitReached => 'انتهى وقت اليوم',
                TimeState.outsideWindow => 'خارج ساعات المشاهدة الآن',
              },
              style: const TextStyle(color: Colors.white60),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.more_time),
                label: const Text('منح وقت إضافي'),
                onPressed: () => grantBonusFlow(context, _p.id),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.restart_alt),
                label: const Text('تصفير عداد اليوم'),
                onPressed: () => _s.resetToday(_p.id),
              ),
            ]),
          ]),
        ),
      ),

      // ---- أنواع المحتوى ----
      _header('أنواع المحتوى المسموحة', Icons.category_outlined),
      for (final t in ContentType.values)
        CheckboxListTile(
          title: Text(t.label),
          value: _p.allowedTypes.contains(t),
          onChanged: (v) => _update(() => v == true ? _p.allowedTypes.add(t) : _p.allowedTypes.remove(t)),
        ),

      // ---- التصنيف العمري ----
      _header('التصنيف العمري', Icons.escalator_warning),
      ListTile(
        title: const Text('أقصى عمر مسموح'),
        subtitle: const Text('يُطبَّق عندما يوفّر المصدر تصنيفاً عمرياً للمحتوى'),
        trailing: DropdownButton<int?>(
          value: _ages.contains(_p.maxAge) ? _p.maxAge : null,
          items: [for (final a in _ages) DropdownMenuItem(value: a, child: Text(a == null ? 'بلا حد' : '$a+ سنوات'))],
          onChanged: (v) => _update(() => _p.maxAge = v),
        ),
      ),
      SwitchListTile(
        title: const Text('حجب الأفلام والمسلسلات غير المصنّفة'),
        subtitle: const Text('أغلب مصادر IPTV لا تذكر العمر؛ فعّلها لحماية أشد واعتمد على الفئات المسموحة'),
        value: _p.blockUnrated,
        onChanged: _p.maxAge == null ? null : (v) => _update(() => _p.blockUnrated = v),
      ),

      // ---- الفئات ----
      _header('الفئات المسموحة', Icons.checklist),
      RadioGroup<CategoryMode>(
        groupValue: _p.categoryMode,
        onChanged: (v) => _update(() => _p.categoryMode = v ?? CategoryMode.allowList),
        child: const Column(children: [
          RadioListTile(
            value: CategoryMode.allowList,
            title: Text('فقط الفئات التي أختارها (موصى به للأطفال)'),
          ),
          RadioListTile(
            value: CategoryMode.all,
            title: Text('كل الفئات ما عدا المحجوبة تلقائياً'),
            subtitle: Text('تُحجب دائماً فئات الكبار والرعب والكلمات أدناه'),
          ),
        ]),
      ),
      if (_p.categoryMode == CategoryMode.allowList)
        for (final t in ContentType.values)
          if (_p.allowedTypes.contains(t)) _categoryPicker(t),

      // ---- كلمات محجوبة ----
      _header('كلمات محجوبة إضافية', Icons.block),
      TextField(
        controller: _words,
        minLines: 1,
        maxLines: 3,
        decoration: const InputDecoration(
          hintText: 'مثال: أكشن، مصارعة، news',
          helperText: 'افصل بفاصلة. أي فئة أو عنوان يحتوي إحدى الكلمات يُحجب عن هذا الطفل.',
        ),
        onSubmitted: (_) => _commitText(),
        onTapOutside: (_) => _commitText(),
      ),
    ];
  }

  Widget _timeDropdown(int value, ValueChanged<int> onChanged) => DropdownButton<int>(
        value: _times.contains(value) ? value : null,
        items: [for (final t in _times) DropdownMenuItem(value: t, child: Text(formatMinutesOfDay(t)))],
        onChanged: (v) => v == null ? null : onChanged(v),
      );

  Widget _categoryPicker(ContentType t) {
    final cats = _s.allCategories(t)..sort();
    final selected = cats.where((c) => _p.allowedCategories.contains(Profile.catKey(t, c))).length;
    return ExpansionTile(
      title: Text(t.label),
      subtitle: Text(cats.isEmpty ? 'لا توجد فئات (أضف مصدراً أولاً)' : 'مسموح $selected من ${cats.length}'),
      children: [
        if (cats.isNotEmpty)
          Row(children: [
            TextButton(
              onPressed: () => _update(() {
                for (final c in cats) {
                  if (ParentalRules.isCategoryAllowed(
                      Profile(id: '', name: '', isKid: true, extraBlockedKeywords: _p.extraBlockedKeywords), t, c)) {
                    _p.allowedCategories.add(Profile.catKey(t, c));
                  }
                }
              }),
              child: const Text('تحديد الكل'),
            ),
            TextButton(
              onPressed: () => _update(() {
                for (final c in cats) {
                  _p.allowedCategories.remove(Profile.catKey(t, c));
                }
              }),
              child: const Text('إلغاء الكل'),
            ),
          ]),
        for (final c in cats) _categoryTile(t, c),
      ],
    );
  }

  Widget _categoryTile(ContentType t, String c) {
    final key = Profile.catKey(t, c);
    // فئة تحتوي كلمة محجوبة لا يمكن السماح بها
    final hardBlocked = !ParentalRules.isCategoryAllowed(
      Profile(id: '', name: '', isKid: true, extraBlockedKeywords: _p.extraBlockedKeywords),
      t,
      c,
    );
    return CheckboxListTile(
      dense: true,
      title: Text(c),
      subtitle: hardBlocked ? const Text('محجوبة تلقائياً', style: TextStyle(color: Colors.redAccent)) : null,
      value: !hardBlocked && _p.allowedCategories.contains(key),
      onChanged: hardBlocked
          ? null
          : (v) => _update(() => v == true ? _p.allowedCategories.add(key) : _p.allowedCategories.remove(key)),
    );
  }
}
