import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../theme.dart';
import 'blueprint.dart';
import 'console.dart';

/// A ship's blueprint beside its status. Enemies sit at the top of the
/// screen pointing down; the player sits below pointing up.
class ShipCard extends StatelessWidget {
  const ShipCard({super.key, required this.ship, this.faction, this.subtitle});

  final ShipState ship;

  /// Null for the player's ship.
  final FactionId? faction;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final enemy = faction != null;
    final color = enemy ? QC.them : QC.you;
    final name = enemy ? factions[faction]!.shipName : playerShipName;
    return Panel(
      topAccent: enemy ? null : QC.you,
      bottomAccent: enemy ? QC.them : null,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Row(
        children: [
          ShipBlueprint(faction: faction, width: 46, pointDown: enemy),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(
                      child: Text(
                        name.toUpperCase(),
                        style: QC.displayStyle(17, color: color),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      'B${ship.beam} S${ship.barrier}',
                      semanticsLabel:
                          'Beam ${ship.beam}, barrier ${ship.barrier}',
                      style: QC.monoStyle(11),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Text('HULL', style: QC.monoStyle(11)),
                    const Spacer(),
                    Text(
                      '${ship.hull}/${ship.maxHull}',
                      style: QC.monoStyle(11, color: QC.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                HullMeter(hull: ship.hull, max: ship.maxHull, color: color),
                const SizedBox(height: 7),
                Row(
                  children: [
                    SystemPips(
                      systems: ship.systems,
                      max: ship.maxSystems,
                      color: color,
                    ),
                    const SizedBox(width: 6),
                    if (subtitle != null)
                      Expanded(
                        child: Text(
                          subtitle!,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, color: QC.muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
