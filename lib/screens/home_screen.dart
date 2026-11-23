import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../services/app_state.dart';
import '../services/parental.dart';
import '../widgets/common.dart';
import '../widgets/pin_dialog.dart';
import 'player_screen.dart';
import 'series_screen.dart';
import 'settings_screen.dart';

enum Section { live, movies, series, favorites, search }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Section _section = Section.live;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // إعادة فحص نافذة الوقت كل 30 ثانية
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _pickFirstAllowedSection());
  }

  void _pickFirstAllowedSection() {
    final p = context.read<AppState>().currentProfile;
    if (p == null || !p.isKid) return;
    const order = [ContentType.live, ContentType.movie, ContentType.series];
    for (final t in order) {
      if (p.allowedTypes.contains(t)) {
        setState(() => _section = _sectionFor(t));
        return;
      }
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static Section _sectionFor(ContentType t) => switch (t) {
        ContentType.live => Section.live,
        ContentType.movie => Section.movies,
        ContentType.series => Section.series,
      };

  List<(Section, IconData, String)> _destinations(AppState s) {
    final p = s.currentProfile!;
    return [
      if (ParentalRules.isTypeAllowed(p, ContentType.live)) (Section.live, Icons.live_tv, 'مباشر'),
      if (ParentalRules.isTypeAllowed(p, ContentType.movie)) (Section.movies, Icons.movie_outlined, 'أفلام'),
      if (ParentalRules.isTypeAllowed(p, ContentType.series)) (Section.series, Icons.video_library_outlined, 'مسلسلات'),
      (Section.favorites, Icons.favorite_border, 'المفضلة'),
      (Section.search, Icons.search, 'بحث'),
    ];
  }

  Future<void> _switchProfile() async {
    final s = context.read<AppState>();
    final p = s.currentProfile!;
    if ((p.isKid || s.lockedProfileId != null) && !await requirePin(context, title: 'رمز ولي الأمر لتبديل الملف')) {
      return;
    }
    await s.flushUsage();
    s.switchProfile(null);
  }

  Future<void> _openSettings() async {
    if (!await requirePin(context)) return;
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.currentProfile!;
    final status = s.currentStatus;
    final dests = _destinations(s);
    if (!dests.any((d) => d.$1 == _section)) _section = dests.first.$1;
    final index = dests.indexWhere((d) => d.$1 == _section);
    final wide = isWide(context);

    final body = !status.canWatch
        ? TimeUpView(status: status, onSwitch: _switchProfile)
        : switch (_section) {
            Section.live => CatalogView(type: ContentType.live, key: const ValueKey('live')),
            Section.movies => CatalogView(type: ContentType.movie, key: const ValueKey('movie')),
            Section.series => CatalogView(type: ContentType.series, key: const ValueKey('series')),
            Section.favorites => const FavoritesView(),
            Section.search => const SearchView(),
          };

    final appBar = AppBar(
      title: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: profileColors[p.colorIndex % profileColors.length],
          child: Icon(p.isKid ? Icons.child_care : Icons.person, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Flexible(child: Text(p.name, overflow: TextOverflow.ellipsis)),
        if (p.isKid && status.canWatch && status.remainingSeconds != null) ...[
          const SizedBox(width: 12),
          Chip(
            avatar: const Icon(Icons.timer_outlined, size: 18),
            label: Text('متبقٍ ${formatDuration(status.remainingSeconds!)}'),
          ),
        ],
      ]),
      actions: [
        if (s.loading)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        IconButton(tooltip: 'تبديل الملف', icon: const Icon(Icons.switch_account), onPressed: _switchProfile),
        IconButton(tooltip: 'الإعدادات', icon: const Icon(Icons.settings), onPressed: _openSettings),
      ],
    );

    if (!status.canWatch) return Scaffold(appBar: appBar, body: body);
    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(children: [
          NavigationRail(
            selectedIndex: index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) => setState(() => _section = dests[i].$1),
            destinations: [
              for (final d in dests) NavigationRailDestination(icon: Icon(d.$2), label: Text(d.$3)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      appBar: appBar,
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _section = dests[i].$1),
        destinations: [for (final d in dests) NavigationDestination(icon: Icon(d.$2), label: d.$3)],
      ),
    );
  }
}

/// تصفح نوع محتوى: قائمة فئات + شبكة عناصر.
class CatalogView extends StatefulWidget {
  final ContentType type;
  const CatalogView({super.key, required this.type});

  @override
  State<CatalogView> createState() => _CatalogViewState();
}

class _CatalogViewState extends State<CatalogView> {
  String? _category; // null = الكل

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    if (s.sources.isEmpty) return const NoSourcesView();
    final cats = s.visibleCategories(widget.type);
    var items = s.visibleItems(widget.type);
    if (items.isEmpty) {
      if (s.loading) return const Center(child: CircularProgressIndicator());
      final kid = s.currentProfile?.isKid ?? false;
      return EmptyState(
        icon: kid ? Icons.child_care : Icons.inbox_outlined,
        title: kid ? 'لا يوجد محتوى مسموح هنا بعد' : 'لا يوجد محتوى من هذا النوع',
        subtitle: kid
            ? 'يمكن لولي الأمر اختيار الفئات المسموحة من الإعدادات ← الملفات الشخصية.'
            : s.sourceErrors.isNotEmpty
                ? 'تعذّر تحميل بعض المصادر: ${s.sourceErrors.values.join('، ')}'
                : null,
      );
    }
    if (_category != null && !cats.any((c) => c.key == _category)) _category = null;
    if (_category != null) items = items.where((i) => i.category == _category).toList();

    final grid = ItemGrid(items: items);
    if (isWide(context)) {
      return Row(children: [
        SizedBox(
          width: 260,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _catTile('الكل', null, s.visibleItems(widget.type).length),
              for (final c in cats) _catTile(c.key, c.key, c.value),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: grid),
      ]);
    }
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            _chip('الكل', null),
            for (final c in cats) _chip(c.key, c.key),
          ],
        ),
      ),
      Expanded(child: grid),
    ]);
  }

  Widget _catTile(String label, String? value, int count) => ListTile(
        selected: _category == value,
        title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Text('$count', style: const TextStyle(color: Colors.white54)),
        onTap: () => setState(() => _category = value),
      );

  Widget _chip(String label, String? value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: ChoiceChip(
          label: Text(label),
          selected: _category == value,
          onSelected: (_) => setState(() => _category = value),
        ),
      );
}

class ItemGrid extends StatelessWidget {
  final List<ContentItem> items;
  const ItemGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    final live = items.isNotEmpty && items.first.type == ContentType.live;
    final w = MediaQuery.sizeOf(context).width;
    final maxExtent = live ? (w > 900 ? 220.0 : 170.0) : (w > 900 ? 180.0 : 130.0);
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: live ? 1.05 : 0.62,
      ),
      itemCount: items.length,
      itemBuilder: (ctx, i) => ItemCard(item: items[i], playlist: items, autofocus: i == 0),
    );
  }
}

class ItemCard extends StatelessWidget {
  final ContentItem item;
  final List<ContentItem> playlist;
  final bool autofocus;
  const ItemCard({super.key, required this.item, required this.playlist, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final fav = s.isFavorite(item.id);
    final live = item.type == ContentType.live;
    final now = live ? s.nowNext(item).$1 : null;
    return FocusCard(
      autofocus: autofocus,
      onTap: () => openItem(context, item, playlist),
      onLongPress: () async {
        await s.toggleFavorite(item.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(fav ? 'أُزيل من المفضلة' : 'أُضيف إلى المفضلة'),
          duration: const Duration(seconds: 1),
        ));
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Stack(fit: StackFit.expand, children: [
            Container(
              color: Colors.black26,
              padding: live ? const EdgeInsets.all(14) : EdgeInsets.zero,
              child: CoverImage(
                item.logo,
                fit: live ? BoxFit.contain : BoxFit.cover,
                fallback: switch (item.type) {
                  ContentType.live => Icons.live_tv,
                  ContentType.movie => Icons.movie,
                  ContentType.series => Icons.video_library,
                },
              ),
            ),
            if (fav)
              const PositionedDirectional(
                top: 6,
                end: 6,
                child: Icon(Icons.favorite, color: Colors.pinkAccent, size: 20),
              ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (now != null)
              Text(now.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }
}

/// فتح عنصر: تشغيل مباشر، أو صفحة الحلقات للمسلسل.
Future<void> openItem(BuildContext context, ContentItem item, List<ContentItem> playlist) async {
  final s = context.read<AppState>();
  if (!s.currentStatus.canWatch) return;
  if (item.type == ContentType.series && item.streamUrl.isEmpty) {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesScreen(series: item)));
    return;
  }
  final list = item.type == ContentType.live ? playlist.where((e) => e.type == ContentType.live).toList() : [item];
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PlayerScreen(
        title: item.name,
        url: item.streamUrl,
        liveItem: item.type == ContentType.live ? item : null,
        channels: list,
      ),
    ),
  );
}

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});
  @override
  Widget build(BuildContext context) {
    final items = context.watch<AppState>().favoriteItems();
    if (items.isEmpty) {
      return const EmptyState(
        icon: Icons.favorite_border,
        title: 'لا توجد عناصر مفضلة',
        subtitle: 'اضغط مطولاً على أي قناة أو فيلم لإضافته هنا.',
      );
    }
    return ItemGrid(items: items);
  }
}

class SearchView extends StatefulWidget {
  const SearchView({super.key});
  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final results = context.watch<AppState>().search(_q);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث عن قناة أو فيلم أو مسلسل'),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      Expanded(
        child: results.isEmpty
            ? EmptyState(icon: Icons.search, title: _q.isEmpty ? 'اكتب للبحث' : 'لا نتائج')
            : ListView.builder(
                itemCount: results.length,
                itemBuilder: (_, i) {
                  final it = results[i];
                  return ListTile(
                    leading: SizedBox(width: 48, height: 48, child: CoverImage(it.logo)),
                    title: Text(it.name),
                    subtitle: Text('${it.type.label} · ${it.category}'),
                    onTap: () => openItem(context, it, results),
                  );
                },
              ),
      ),
    ]);
  }
}

class NoSourcesView extends StatelessWidget {
  const NoSourcesView({super.key});
  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.playlist_add,
      title: 'لم تتم إضافة أي مصدر بعد',
      subtitle: 'أضف رابط قائمة M3U أو بيانات حساب Xtream من اشتراكك.',
      action: FilledButton.icon(
        autofocus: true,
        icon: const Icon(Icons.add),
        label: const Text('إضافة مصدر'),
        onPressed: () async {
          if (!await requirePin(context)) return;
          if (!context.mounted) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SourcesScreen()));
        },
      ),
    );
  }
}

/// تظهر عند انتهاء الوقت أو خارج ساعات المشاهدة.
class TimeUpView extends StatelessWidget {
  final TimeStatus status;
  final VoidCallback onSwitch;
  const TimeUpView({super.key, required this.status, required this.onSwitch});

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final outside = status.state == TimeState.outsideWindow;
    return EmptyState(
      icon: outside ? Icons.bedtime_outlined : Icons.hourglass_bottom,
      title: outside ? 'ليس وقت المشاهدة الآن' : 'انتهى وقت المشاهدة لليوم',
      subtitle: outside
          ? 'المشاهدة مسموحة من ${formatMinutesOfDay(status.windowStart!)} إلى ${formatMinutesOfDay(status.windowEnd!)}'
          : 'أحسنت! حان وقت اللعب أو القراءة. نلتقي غداً.',
      action: Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
        if (!outside)
          OutlinedButton.icon(
            autofocus: true,
            icon: const Icon(Icons.more_time),
            label: const Text('وقت إضافي (ولي الأمر)'),
            onPressed: () => grantBonusFlow(context, s.currentProfileId!),
          ),
        OutlinedButton.icon(
          autofocus: outside,
          icon: const Icon(Icons.switch_account),
          label: const Text('تبديل الملف'),
          onPressed: onSwitch,
        ),
      ]),
    );
  }
}

Future<void> grantBonusFlow(BuildContext context, String profileId) async {
  if (!await requirePin(context, title: 'رمز ولي الأمر لمنح وقت إضافي')) return;
  if (!context.mounted) return;
  final mins = await showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('كم دقيقة إضافية؟'),
      children: [
        for (final m in [15, 30, 60])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, m),
            child: Padding(padding: const EdgeInsets.all(8), child: Text('$m دقيقة')),
          ),
      ],
    ),
  );
  if (mins != null && context.mounted) await context.read<AppState>().grantBonus(profileId, mins);
}
