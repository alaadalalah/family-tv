import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/content.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import 'player_screen.dart';

/// مواسم وحلقات مسلسل من حساب Xtream.
class SeriesScreen extends StatefulWidget {
  final ContentItem series;
  const SeriesScreen({super.key, required this.series});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  late Future<List<Episode>> _future;
  int? _season;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final c = context.read<AppState>().xtreamFor(widget.series);
    _future = c == null ? Future.value(<Episode>[]) : c.fetchEpisodes(widget.series.seriesId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.series.name)),
      body: FutureBuilder<List<Episode>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'تعذّر تحميل الحلقات',
              subtitle: '${snap.error}',
              action: FilledButton(onPressed: () => setState(_load), child: const Text('إعادة المحاولة')),
            );
          }
          final eps = snap.data!;
          if (eps.isEmpty) return const EmptyState(icon: Icons.video_library, title: 'لا توجد حلقات');
          final seasons = eps.map((e) => e.season).toSet().toList()..sort();
          final season = _season ?? seasons.first;
          final list = eps.where((e) => e.season == season).toList();
          return Column(children: [
            if (seasons.length > 1)
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(8),
                  children: [
                    for (final s in seasons)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: ChoiceChip(
                          label: Text('الموسم $s'),
                          selected: s == season,
                          onSelected: (_) => setState(() => _season = s),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final e = list[i];
                  return ListTile(
                    autofocus: i == 0,
                    leading: CircleAvatar(child: Text('${e.number}')),
                    title: Text(e.title),
                    trailing: const Icon(Icons.play_arrow),
                    onTap: () {
                      if (!context.read<AppState>().currentStatus.canWatch) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PlayerScreen(title: '${widget.series.name} - ${e.title}', url: e.streamUrl)),
                      );
                    },
                  );
                },
              ),
            ),
          ]);
        },
      ),
    );
  }
}
