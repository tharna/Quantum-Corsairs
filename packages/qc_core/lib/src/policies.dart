import 'ai.dart';
import 'battle.dart';
import 'quantum.dart';
import 'rng.dart';

/// A scripted player, for the balance simulator and tests.
abstract class PlayerPolicy {
  String get name;
  Tuning choose(BattleState b, Rng rng);
}

/// Picks one of the four presets uniformly.
class RandomPolicy implements PlayerPolicy {
  @override
  String get name => 'random';

  @override
  Tuning choose(BattleState b, Rng rng) =>
      TuningPreset.values[rng.nextInt(4)].tuning;
}

/// Plays the best reply to the enemy's habit at the forecast midpoint.
///
/// It estimates the habit by sampling the enemy AI with its own generator,
/// so it never sees the actual plan. Like the design document's "skilled
/// player" it is told the Corp Police captain's style, so its Corp lane
/// results are an upper bound.
class HabitPolicy implements PlayerPolicy {
  HabitPolicy({this.samples = 64});

  final int samples;

  @override
  String get name => 'skilled';

  @override
  Tuning choose(BattleState b, Rng rng) {
    final sampler = Rng(rng.nextUint32());
    final ctx = EnemyContext(
      tactic: b.tactic,
      weather: b.weather,
      playerHistory: b.history,
      table: b.table,
      allowed: b.allowed,
    );
    final counts = <TuningPreset, int>{};
    for (var i = 0; i < samples; i++) {
      final k = enemyTuning(ctx, sampler).preset!;
      counts[k] = (counts[k] ?? 0) + 1;
    }
    final t = b.table;
    final f = b.weather.midpoint;
    TuningPreset? best;
    var bestScore = double.negativeInfinity;
    for (final mine in b.allowed) {
      var score = 0.0;
      counts.forEach((theirs, n) {
        final p = outcomeProbabilities(mine.tuning, theirs.tuning, f);
        for (var j = 0; j < 4; j++) {
          // Systems are worth more than hull: they end a fight for full loot.
          score +=
              n *
              p[j] *
              (t[j].toThem +
                  4 * t[j].systemsThem -
                  t[j].toYou -
                  4 * t[j].systemsYou);
        }
      });
      if (score > bestScore) {
        bestScore = score;
        best = mine;
      }
    }
    return best!.tuning;
  }
}
