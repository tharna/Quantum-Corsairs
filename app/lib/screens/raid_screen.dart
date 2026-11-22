import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../controller.dart';
import '../theme.dart';
import 'battle_view.dart';
import 'port_view.dart';

/// Shows the port or the battle, following the raid's phase. Pops back to
/// the title when the raid ends.
class RaidScreen extends StatelessWidget {
  const RaidScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final raid = c.raid;
    if (raid == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return const Scaffold(backgroundColor: QC.field);
    }
    final inPort = raid.phase == RaidPhase.port;
    return Scaffold(
      body: BlueprintBackground(
        deep: !inPort,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: inPort
                    ? const PortView(key: ValueKey('port'))
                    : BattleView(
                        key: ValueKey(
                          'battle-${raid.lane}-${raid.battle?.stage}',
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar at the top of the port and battle screens.
class RaidTopBar extends StatelessWidget {
  const RaidTopBar({super.key, required this.label, required this.loot});
  final String label;
  final int loot;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        IconButton(
          tooltip: 'Back to title',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.pause, color: QC.muted),
        ),
        Expanded(
          child: Center(child: Text(label, style: QC.label(12))),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            '$loot cr',
            semanticsLabel: 'Loot $loot credits',
            style: QC.monoStyle(13, color: QC.you),
          ),
        ),
      ],
    ),
  );
}
