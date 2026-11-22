import 'package:material_ui/material_ui.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/console.dart';
import 'hardware_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _reset(BuildContext context, GameController c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: QC.film,
        shape: const RoundedRectangleBorder(
          borderRadius: QC.radius,
          side: BorderSide(color: QC.grid),
        ),
        title: Text('RESET PROGRESS?', style: QC.displayStyle(20)),
        content: const Text(
          'This deletes your raid, your prizes and your unlocks. It cannot be undone.',
          style: TextStyle(color: QC.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset', style: TextStyle(color: QC.them)),
          ),
        ],
      ),
    );
    if (ok == true) await c.resetProgress();
  }

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final s = c.settings;
    Widget toggle(
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> set,
    ) => SwitchListTile(
      title: Text(title, style: const TextStyle(color: QC.ink)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12.5, color: QC.muted),
      ),
      value: value,
      onChanged: set,
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: QC.field,
        foregroundColor: QC.ink,
        title: Text('SETTINGS', style: QC.displayStyle(20)),
      ),
      body: BlueprintBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 24),
              children: [
                toggle(
                  'Sound',
                  'Collapse, hits and probe pings.',
                  s.sound,
                  (v) => c.updateSettings(s.copyWith(sound: v)),
                ),
                toggle(
                  'Haptics',
                  'A pulse when the state collapses.',
                  s.haptics,
                  (v) => c.updateSettings(s.copyWith(haptics: v)),
                ),
                toggle(
                  'Reduced motion',
                  'Replace the collapse flicker with a plain reveal.',
                  s.reducedMotion,
                  (v) => c.updateSettings(s.copyWith(reducedMotion: v)),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: HardwareSettings(),
                ),
                ListTile(
                  title: const Text(
                    'Show hints again',
                    style: TextStyle(color: QC.ink),
                  ),
                  subtitle: const Text(
                    'Replay the onboarding notes.',
                    style: TextStyle(fontSize: 12.5, color: QC.muted),
                  ),
                  onTap: () {
                    c.updateSettings(s.copyWith(seenHints: {}));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Hints will show again')),
                    );
                  },
                ),
                ListTile(
                  title: const Text(
                    'Licences',
                    style: TextStyle(color: QC.ink),
                  ),
                  subtitle: const Text(
                    'Fonts and open-source packages.',
                    style: TextStyle(fontSize: 12.5, color: QC.muted),
                  ),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Quantum Corsairs',
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: GhostButton(
                    label: 'Reset progress',
                    color: QC.them,
                    display: false,
                    onPressed: () => _reset(context, c),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
