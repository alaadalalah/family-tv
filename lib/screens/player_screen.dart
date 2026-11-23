import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/content.dart';
import '../services/app_state.dart';
import '../services/parental.dart';

/// مشغّل الفيديو. يحسب وقت المشاهدة الفعلي ويتوقف عند انتهاء وقت الطفل.
class PlayerScreen extends StatefulWidget {
  final String title;
  final String url;

  /// للقنوات المباشرة: القناة الحالية وقائمة القنوات للتنقل بالأعلى/الأسفل.
  final ContentItem? liveItem;
  final List<ContentItem> channels;

  const PlayerScreen({super.key, required this.title, required this.url, this.liveItem, this.channels = const []});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _c;
  late String _title = widget.title;
  late String _url = widget.url;
  late ContentItem? _live = widget.liveItem;
  String? _error;
  bool _controls = true;
  bool _warned = false;
  TimeStatus? _blocked;
  Timer? _usageTimer;
  Timer? _hideTimer;
  final _focus = FocusNode();
  late final AppState _state;

  bool get _isLive => _live != null;

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable().catchError((_) {});
    _open();
    _usageTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecond());
    _scheduleHide();
  }

  Future<void> _open() async {
    final old = _c;
    setState(() {
      _error = null;
      _c = null;
    });
    await old?.dispose();
    final c = VideoPlayerController.networkUrl(Uri.parse(_url));
    _c = c;
    try {
      await c.initialize();
      if (!mounted || _c != c) return;
      // تحقق قبل البدء أن الوقت مازال مسموحاً
      if (!_checkTime()) return;
      await c.play();
      setState(() {});
    } catch (e) {
      if (!mounted || _c != c) return;
      setState(() => _error = 'تعذّر تشغيل البث. تأكد من الاتصال أو جرّب لاحقاً.');
    }
    c.addListener(() {
      if (mounted && c.value.hasError && _error == null) {
        setState(() => _error = 'انقطع البث: ${c.value.errorDescription ?? ''}');
      }
    });
  }

  bool _checkTime() {
    final st = _state.currentStatus;
    if (!st.canWatch) {
      _c?.pause();
      setState(() => _blocked = st);
      return false;
    }
    final r = st.remainingSeconds;
    if (r != null && r <= 300 && !_warned) {
      _warned = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تبقّى ${(r / 60).ceil()} دقائق من وقت المشاهدة')),
      );
    }
    return true;
  }

  void _onSecond() {
    if (!mounted) return;
    final c = _c;
    if (c != null && c.value.isInitialized && c.value.isPlaying) {
      _state.addWatchSeconds(1);
    }
    if (_blocked == null) _checkTime();
    if (_controls) setState(() {}); // تحديث شريط التقدم
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _showControls() {
    setState(() => _controls = true);
    _scheduleHide();
  }

  void _togglePlay() {
    final c = _c;
    if (c == null || !c.value.isInitialized || _blocked != null) return;
    c.value.isPlaying ? c.pause() : c.play();
    _showControls();
  }

  void _seek(int seconds) {
    final c = _c;
    if (c == null || _isLive || !c.value.isInitialized) return;
    c.seekTo(c.value.position + Duration(seconds: seconds));
    _showControls();
  }

  void _zap(int delta) {
    if (!_isLive || widget.channels.length < 2) return;
    final i = widget.channels.indexWhere((e) => e.id == _live!.id);
    final next = widget.channels[(i + delta) % widget.channels.length];
    setState(() {
      _live = next;
      _title = next.name;
      _url = next.streamUrl;
    });
    _open();
    _showControls();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.select ||
        k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.mediaPlayPause ||
        k == LogicalKeyboardKey.space) {
      _togglePlay();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      _seek(10);
      return _isLive ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      _seek(-10);
      return _isLive ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      if (_isLive) {
        _zap(-1);
        return KeyEventResult.handled;
      }
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      if (_isLive) {
        _zap(1);
        return KeyEventResult.handled;
      }
    }
    _showControls();
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _usageTimer?.cancel();
    _hideTimer?.cancel();
    _c?.dispose();
    _focus.dispose();
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // حفظ الاستهلاك عند الخروج
    _state.flushUsage();
    super.dispose();
  }

  String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    final state = context.watch<AppState>();
    final (now, next) = _isLive ? state.nowNext(_live!) : (null, null);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _controls ? setState(() => _controls = false) : _showControls(),
          child: Stack(fit: StackFit.expand, children: [
            Center(
              child: ready
                  ? AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))
                  : _error == null
                      ? const CircularProgressIndicator()
                      : const SizedBox(),
            ),
            if (_error != null && _blocked == null)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, size: 56, color: Colors.white70),
                  const SizedBox(height: 12),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(autofocus: true, onPressed: _open, child: const Text('إعادة المحاولة')),
                ]),
              ),
            if (_controls && _blocked == null) ..._overlay(ready, c, now?.title, next?.title),
            if (_blocked != null) _blockedView(_blocked!),
          ]),
        ),
      ),
    );
  }

  List<Widget> _overlay(bool ready, VideoPlayerController? c, String? nowTitle, String? nextTitle) {
    final playing = ready && c!.value.isPlaying;
    return [
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Colors.black87, Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Row(children: [
            const BackButton(),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                if (nowTitle != null) Text('الآن: $nowTitle', style: const TextStyle(color: Colors.white70)),
                if (nextTitle != null) Text('التالي: $nextTitle', style: const TextStyle(color: Colors.white54)),
              ]),
            ),
          ]),
        ),
      ),
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 32, 16, 20),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Colors.transparent, Colors.black87], begin: Alignment.topCenter, end: Alignment.bottomCenter),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (ready && !_isLive && c!.value.duration > Duration.zero)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  Text(_fmt(c.value.position)),
                  Expanded(
                    child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 12)),
                  ),
                  Text(_fmt(c.value.duration)),
                ]),
              ),
            const SizedBox(height: 8),
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                if (_isLive)
                  IconButton(iconSize: 36, icon: const Icon(Icons.skip_previous), onPressed: () => _zap(-1))
                else
                  IconButton(iconSize: 36, icon: const Icon(Icons.replay_10), onPressed: () => _seek(-10)),
                const SizedBox(width: 16),
                IconButton.filled(
                  iconSize: 44,
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: _togglePlay,
                ),
                const SizedBox(width: 16),
                if (_isLive)
                  IconButton(iconSize: 36, icon: const Icon(Icons.skip_next), onPressed: () => _zap(1))
                else
                  IconButton(iconSize: 36, icon: const Icon(Icons.forward_10), onPressed: () => _seek(10)),
              ]),
            ),
          ]),
        ),
      ),
    ];
  }

  Widget _blockedView(TimeStatus st) {
    final outside = st.state == TimeState.outsideWindow;
    return Container(
      color: Colors.black.withValues(alpha: 0.92),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(outside ? Icons.bedtime_outlined : Icons.hourglass_bottom, size: 72, color: Colors.white70),
        const SizedBox(height: 16),
        Text(
          outside ? 'انتهت ساعات المشاهدة المسموحة' : 'انتهى وقت المشاهدة لليوم',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(autofocus: true, onPressed: () => Navigator.pop(context), child: const Text('حسناً')),
      ]),
    );
  }
}
