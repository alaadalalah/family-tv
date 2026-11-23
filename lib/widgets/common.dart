import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

const profileColors = <Color>[
  Color(0xFF5B8DEF),
  Color(0xFFF4A340),
  Color(0xFF4CC38A),
  Color(0xFFE5607A),
  Color(0xFFA77BF3),
  Color(0xFF34B9D6),
];

const seedColor = Color(0xFF4C7CF0);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Cairo',
    scaffoldBackgroundColor: const Color(0xFF0E1118),
    visualDensity: VisualDensity.standard,
    // تمييز واضح للعنصر المحدد عند التنقل بالريموت
    focusColor: scheme.primary.withValues(alpha: 0.35),
    cardTheme: const CardThemeData(color: Color(0xFF181C26), margin: EdgeInsets.zero),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

/// هل الجهاز شاشة كبيرة (تلفاز أو تابلت بالعرض)؟
bool isWide(BuildContext context) => MediaQuery.sizeOf(context).width >= 900;

/// بطاقة تتفاعل مع الريموت (D-pad) واللمس: تكبر ويظهر لها إطار عند التحديد.
class FocusCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final BorderRadius radius;
  final FocusNode? focusNode;

  const FocusCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.radius = const BorderRadius.all(Radius.circular(12)),
    this.focusNode,
  });

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: widget.radius,
          border: Border.all(color: _focused ? scheme.primary : Colors.transparent, width: 3),
          boxShadow: _focused ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.4), blurRadius: 16)] : null,
        ),
        child: Material(
          color: const Color(0xFF181C26),
          borderRadius: widget.radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onFocusChange: (f) => setState(() => _focused = f),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// صورة شعار/غلاف مع بديل عند الفشل.
class CoverImage extends StatelessWidget {
  final String url;
  final IconData fallback;
  final BoxFit fit;
  const CoverImage(this.url, {super.key, this.fallback = Icons.live_tv, this.fit = BoxFit.contain});

  @override
  Widget build(BuildContext context) {
    final fb = Center(child: Icon(fallback, size: 40, color: Colors.white38));
    if (url.isEmpty || !url.startsWith('http')) return fb;
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      errorWidget: (_, _, _) => fb,
      placeholder: (_, _) => fb,
      fadeInDuration: const Duration(milliseconds: 150),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.subtitle, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(subtitle!, style: const TextStyle(color: Colors.white60), textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 20), action!],
        ]),
      ),
    );
  }
}

/// اختصارات الريموت: زر الوسط (select) يعمل كضغطة.
const tvShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
};
