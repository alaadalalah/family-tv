import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';

/// يطلب رمز ولي الأمر. يعيد true عند النجاح.
Future<bool> requirePin(BuildContext context, {String title = 'أدخل رمز ولي الأمر'}) async {
  final state = context.read<AppState>();
  if (!state.hasPin) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => PinDialog(title: title, verify: state.verifyPin, lockLeft: state.pinLockSecondsLeft),
  );
  return ok ?? false;
}

/// يطلب رمزاً جديداً مرتين ويعيده، أو null عند الإلغاء.
Future<String?> askNewPin(BuildContext context) async {
  final first = await showDialog<String>(
    context: context,
    builder: (_) => const PinDialog(title: 'اختر رمزاً من 4 إلى 6 أرقام'),
  );
  if (first == null || !context.mounted) return null;
  String? mismatchFor;
  final second = await showDialog<String>(
    context: context,
    builder: (_) => PinDialog(
      title: 'أعد إدخال الرمز للتأكيد',
      verify: (p) {
        final ok = p == first;
        if (!ok) mismatchFor = p;
        return ok;
      },
      returnValue: true,
    ),
  );
  if (mismatchFor != null && second == null) return null;
  return second;
}

/// لوحة أرقام كبيرة تعمل بالريموت واللمس ولوحة المفاتيح.
class PinDialog extends StatefulWidget {
  final String title;

  /// إن وُجدت يتحقق منها؛ وإلا يعيد الرمز المُدخل نفسه.
  final bool Function(String pin)? verify;
  final int Function()? lockLeft;

  /// عند true يعيد الرمز (String) بعد نجاح التحقق بدل true.
  final bool returnValue;

  const PinDialog({super.key, required this.title, this.verify, this.lockLeft, this.returnValue = false});

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  String _pin = '';
  String? _error;

  void _press(String d) {
    if (_pin.length >= 6) return;
    setState(() {
      _pin += d;
      _error = null;
    });
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _submit() {
    if (_pin.length < 4) {
      setState(() => _error = 'الرمز من 4 أرقام على الأقل');
      return;
    }
    final v = widget.verify;
    if (v == null) {
      Navigator.pop(context, _pin);
      return;
    }
    if (v(_pin)) {
      Navigator.pop(context, widget.returnValue ? _pin : true);
    } else {
      final left = widget.lockLeft?.call() ?? 0;
      setState(() {
        _pin = '';
        _error = left > 0 ? 'محاولات كثيرة. انتظر $left ثانية' : 'الرمز غير صحيح';
      });
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final ch = e.character;
    if (ch != null && RegExp(r'^[0-9]$').hasMatch(ch)) {
      _press(ch);
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.backspace) {
      _back();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _key(String label, VoidCallback onTap, {bool autofocus = false, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.all(5),
      child: SizedBox(
        width: 72,
        height: 60,
        child: FilledButton.tonal(
          autofocus: autofocus,
          onPressed: onTap,
          style: FilledButton.styleFrom(padding: EdgeInsets.zero),
          child: icon != null ? Icon(icon) : Text(label, style: const TextStyle(fontSize: 24)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Focus(
      onKeyEvent: _onKey,
      child: AlertDialog(
        title: Text(widget.title, textAlign: TextAlign.center),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                6,
                (i) => Container(
                  margin: const EdgeInsets.all(6),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? Theme.of(context).colorScheme.primary : Colors.white24,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: _error == null
                  ? null
                  : Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            // الأرقام تُعرض من اليسار لليمين دائماً كما في لوحات الأرقام
            Directionality(
              textDirection: TextDirection.ltr,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var r = 0; r < rows.length; r++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final d in rows[r]) _key(d, () => _press(d), autofocus: r == 0 && d == '1'),
                  ]),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  _key('', _back, icon: Icons.backspace_outlined),
                  _key('0', () => _press('0')),
                  _key('', _submit, icon: Icons.check),
                ]),
              ]),
            ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء'))],
      ),
    );
  }
}
