import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../models/profile.dart';
import '../services/app_state.dart';
import '../widgets/common.dart';
import '../widgets/pin_dialog.dart';

/// "من يشاهد الآن؟" — الطفل يدخل مباشرة، وولي الأمر يحتاج الرمز.
class ProfilePicker extends StatelessWidget {
  const ProfilePicker({super.key});

  Future<void> _pick(BuildContext context, Profile p) async {
    final state = context.read<AppState>();
    if (!p.isKid && !await requirePin(context)) return;
    state.switchProfile(p.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('من يشاهد الآن؟', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 32),
            Wrap(
              spacing: 24,
              runSpacing: 24,
              alignment: WrapAlignment.center,
              children: [
                for (var i = 0; i < state.profiles.length; i++)
                  ProfileTile(
                    profile: state.profiles[i],
                    autofocus: i == 0,
                    onTap: () => _pick(context, state.profiles[i]),
                  ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class ProfileTile extends StatelessWidget {
  final Profile profile;
  final VoidCallback onTap;
  final bool autofocus;
  const ProfileTile({super.key, required this.profile, required this.onTap, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final color = profileColors[profile.colorIndex % profileColors.length];
    return SizedBox(
      width: 150,
      child: FocusCard(
        autofocus: autofocus,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: color,
              child: Icon(profile.isKid ? Icons.child_care : Icons.person, size: 44, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(profile.name, style: const TextStyle(fontSize: 18), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (!profile.isKid) const Icon(Icons.lock, size: 14, color: Colors.white54),
              const SizedBox(width: 4),
              Text(profile.isKid ? 'طفل' : 'ولي أمر', style: const TextStyle(color: Colors.white54)),
            ]),
          ]),
        ),
      ),
    );
  }
}
