import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/blueprint.dart';
import '../widgets/console.dart';
import 'raid_screen.dart';

class PortView extends StatelessWidget {
  const PortView({super.key});

  Future<void> _retire(BuildContext context, GameController c) async {
    final loot = c.raid!.loot;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: QC.film,
        shape: const RoundedRectangleBorder(
          borderRadius: QC.radius,
          side: BorderSide(color: QC.grid),
        ),
        title: Text('END THE RAID?', style: QC.displayStyle(20)),
        content: Text(
          'Bank $loot cr and retire. Refits do not carry over to the next raid.',
          style: const TextStyle(color: QC.ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep raiding'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bank and retire'),
          ),
        ],
      ),
    );
    if (ok == true) c.retire();
  }

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final raid = c.raid!;
    final profile = c.game.profile;
    final open = c.game.openLanes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
      children: [
        RaidTopBar(label: '[DOCK] PRIZES ${raid.prizes}', loot: raid.loot),
        Semantics(
          header: true,
          child: Text('HILBERT STATION', style: QC.displayStyle(32)),
        ),
        const SizedBox(height: 4),
        Text(
          '$playerShipName is repaired: hull $playerHull, systems $playerSystems, '
          'beam ${raid.beam}, barrier ${raid.barrier}.',
          style: const TextStyle(fontSize: 13.5, color: QC.muted),
        ),
        const SizedBox(height: 14),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('[01] Refit'),
              const SizedBox(height: 8),
              for (var i = 0; i < Upgrade.values.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 8),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _RefitButton(upgrade: Upgrade.values[i])),
                      const SizedBox(width: 8),
                      Expanded(
                        child: i + 1 < Upgrade.values.length
                            ? _RefitButton(upgrade: Upgrade.values[i + 1])
                            : const SizedBox(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionLabel('[02] Sector chart · choose a prize'),
        const SizedBox(height: 8),
        for (var i = 0; i < lanes.length; i++) ...[
          _LaneTile(
            index: i,
            open: open.contains(i),
            unlockLevel: lanes[i].unlockLevel,
            prizes: profile.prizesTotal,
          ),
          const SizedBox(height: 7),
        ],
        const SizedBox(height: 8),
        GhostButton(
          label: raid.loot > 0
              ? 'Bank ${raid.loot} cr and end raid'
              : 'End raid',
          color: QC.grid,
          display: false,
          onPressed: () => _retire(context, c),
        ),
      ],
    );
  }
}

class _RefitButton extends StatelessWidget {
  const _RefitButton({required this.upgrade});
  final Upgrade upgrade;

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final raid = c.raid!;
    final owned = raid.level(upgrade);
    final maxed = owned >= upgrade.maxLevel;
    final needsProbe =
        upgrade == Upgrade.probeRack || upgrade == Upgrade.shieldedProbe;
    final locked = needsProbe && !c.game.profile.has(Unlock.probe);
    final can = c.game.canBuy(upgrade);
    final base = upgrade == Upgrade.beam || upgrade == Upgrade.barrier ? 1 : 0;
    final segments = upgrade.maxLevel + base;
    final status = locked
        ? 'Unlocks with the probe'
        : maxed
        ? 'Fully fitted'
        : '${upgrade.cost(owned)} cr';

    return Semantics(
      button: true,
      enabled: can,
      onTap: can ? () => c.buy(upgrade) : null,
      label:
          '${upgrade.label}. ${upgrade.description} Level ${owned + base} of $segments. $status',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: can ? () => c.buy(upgrade) : null,
            borderRadius: QC.radius,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: QC.radius,
                border: Border.all(color: can ? QC.you : QC.grid),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    upgrade.label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5,
                      color: locked ? QC.muted : QC.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var i = 0; i < segments; i++)
                        Container(
                          margin: const EdgeInsets.only(right: 3),
                          width: 22,
                          height: 6,
                          color: i < owned + base ? QC.you : QC.grid,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    maxed || locked
                        ? status
                        : '${owned + base} → ${owned + base + 1} · $status',
                    style: QC.monoStyle(11.5, color: can ? QC.you : QC.muted),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LaneTile extends StatelessWidget {
  const _LaneTile({
    required this.index,
    required this.open,
    required this.unlockLevel,
    required this.prizes,
  });
  final int index;
  final bool open;
  final int unlockLevel;
  final int prizes;

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final lane = lanes[index];
    final trade = factions[lane.trade]!;
    final guard = lane.guard == null ? null : factions[lane.guard]!;
    final need = unlockLevel - prizes;
    final guardLine = guard == null
        ? 'Nobody answers their call'
        : 'Answered by ${guard.name}';
    return Semantics(
      button: open,
      enabled: open,
      onTap: open ? () => c.startLane(index) : null,
      label: open
          ? '${trade.name}. ${trade.shipClass}, cargo ${trade.loot} credits. $guardLine.'
          : '${trade.name}. Locked: take $need more ${need == 1 ? 'prize' : 'prizes'}.',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: open ? () => c.startLane(index) : null,
            borderRadius: QC.radius,
            child: Opacity(
              opacity: open ? 1 : 0.45,
              child: Panel(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    ShipBlueprint(
                      faction: lane.trade,
                      width: 34,
                      pointDown: true,
                      showCentreline: false,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  trade.name.toUpperCase(),
                                  style: QC.displayStyle(16, color: QC.them),
                                ),
                              ),
                              Text(
                                '${trade.loot} cr',
                                style: QC.monoStyle(12.5, color: QC.you),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${trade.shipClass.toUpperCase()} · H${trade.hull} · S${trade.barrier}',
                            style: QC.monoStyle(11),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            open
                                ? guardLine
                                : 'Locked · take $need more ${need == 1 ? 'prize' : 'prizes'}',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: QC.muted,
                            ),
                          ),
                          if (open && guard != null)
                            Text(
                              'Bounty ${guard.loot} cr · ${guard.shipName}',
                              style: QC.monoStyle(11, color: QC.them),
                            ),
                        ],
                      ),
                    ),
                    if (!open)
                      const Icon(Icons.lock_outline, size: 18, color: QC.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
