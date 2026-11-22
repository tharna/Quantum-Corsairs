// Balance simulator: plays many raids per lane with scripted players.
//
//   dart run bin/simulate.dart [--raids 1500] [--seed 1]
//
// Each raid fights the trader and, on a win, always stands against the
// protector, with the player at starting ratings and everything unlocked.
import 'package:qc_core/qc_core.dart';

void main(List<String> args) {
  var raids = 1500;
  var seed = 1;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--raids') raids = int.parse(args[i + 1]);
    if (args[i] == '--seed') seed = int.parse(args[i + 1]);
  }
  final policies = <PlayerPolicy>[RandomPolicy(), HabitPolicy()];

  final header = StringBuffer('Lane'.padRight(48));
  for (final p in policies) {
    header.write('${p.name} trader'.padLeft(16));
    header.write('${p.name} both'.padLeft(16));
  }
  header.write('avg rounds'.padLeft(12));
  print(header);

  for (var li = 0; li < lanes.length; li++) {
    final lane = lanes[li];
    final label = lane.guard == null
        ? factions[lane.trade]!.name
        : '${factions[lane.trade]!.name}, then ${factions[lane.guard]!.name}';
    final row = StringBuffer(label.padRight(48));
    var rounds = 0, battles = 0;
    for (final policy in policies) {
      var beatTrader = 0, beatBoth = 0;
      final rng = Rng.seeded(seed * 7919 + li);
      for (var r = 0; r < raids; r++) {
        var g = const GameState(
          profile: Profile(prizesTotal: maxUnlockLevel),
        ).newRaid(rng.nextUint32()).startLane(li);
        var stage = 0;
        while (true) {
          final raid = g.raid!;
          if (raid.phase == RaidPhase.battle) {
            g = g.fire(policy.choose(raid.battle!, rng));
            continue;
          }
          rounds += raid.battle!.round;
          battles++;
          if (raid.phase == RaidPhase.defeat) break;
          if (stage == 0) beatTrader++;
          if (raid.protectorWaiting) {
            g = g.fightProtector();
            stage = 1;
            continue;
          }
          beatBoth++;
          break;
        }
      }
      String pct(int n) => '${(100 * n / raids).round()}%';
      row.write(pct(beatTrader).padLeft(16));
      row.write((lane.guard == null ? '-' : pct(beatBoth)).padLeft(16));
    }
    row.write((rounds / battles).toStringAsFixed(1).padLeft(12));
    print(row);
  }
}
