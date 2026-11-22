import 'content.dart';
import 'damage.dart';
import 'quantum.dart';
import 'rng.dart';

/// Everything an enemy captain knows when committing to a tuning.
class EnemyContext {
  const EnemyContext({
    required this.tactic,
    required this.weather,
    required this.playerHistory,
    required this.table,
    required this.allowed,
  });

  /// The captain's style. Corp Police arrive here already resolved to
  /// [Tactic.defence] or [Tactic.mercenary].
  final Tactic tactic;
  final Weather weather;

  /// The player's last tunings, oldest first, at most three.
  final List<Tuning> playerHistory;

  /// Damage table from the player's point of view.
  final List<Damage> table;

  /// Presets the player has unlocked. Enemies never use a phase trick the
  /// player has not yet been taught: conjugate shields fall back to held
  /// harmonics and a phase-shifted lance to a plain one.
  final Set<TuningPreset> allowed;
}

TuningPreset _restrict(TuningPreset p, Set<TuningPreset> allowed) {
  if (allowed.contains(p)) return p;
  return p.isLance ? TuningPreset.lance : TuningPreset.hold;
}

/// Picks the enemy's tuning for the coming round.
Tuning enemyTuning(EnemyContext ctx, Rng rng) =>
    _restrict(_choose(ctx, rng), ctx.allowed).tuning;

TuningPreset _randomPreset(Rng rng) =>
    TuningPreset.values[rng.nextInt(TuningPreset.values.length)];

TuningPreset _choose(EnemyContext ctx, Rng rng) {
  final calm = ctx.weather.lockHolds;
  final r = rng.nextDouble();
  switch (ctx.tactic) {
    case Tactic.guild:
      return calm && r < 0.75 ? TuningPreset.conjugate : TuningPreset.hold;
    case Tactic.federation:
      return calm && r < 0.4 ? TuningPreset.conjugate : TuningPreset.hold;
    case Tactic.corp:
      return calm && r < 0.5 ? TuningPreset.conjugate : TuningPreset.hold;
    case Tactic.defence:
      return calm && r < 0.3 ? TuningPreset.phaseLance : TuningPreset.lance;
    case Tactic.wild:
      return _randomPreset(rng);
    case Tactic.police:
      // Unresolved police behave as mercenaries; battles resolve them first.
      return _mercenary(ctx, rng, r);
    case Tactic.mercenary:
      return _mercenary(ctx, rng, r);
  }
}

TuningPreset _mercenary(EnemyContext ctx, Rng rng, double r) {
  if (r < 0.2) return _randomPreset(rng); // bluff
  final calm = ctx.weather.lockHolds;
  if (ctx.playerHistory.isEmpty) {
    return calm ? TuningPreset.conjugate : TuningPreset.lance;
  }
  return bestCounter(
    ctx.playerHistory,
    ctx.weather.midpoint,
    ctx.table,
    ctx.allowed,
  );
}

/// The allowed preset that scores best for the enemy against [history] at
/// [fidelity]. Score is expected damage dealt minus damage taken.
TuningPreset bestCounter(
  List<Tuning> history,
  double fidelity,
  List<Damage> table,
  Set<TuningPreset> allowed,
) {
  var best = TuningPreset.lance;
  var bestScore = double.negativeInfinity;
  for (final k in TuningPreset.values) {
    if (!allowed.contains(k)) continue;
    var score = 0.0;
    for (final h in history) {
      final p = outcomeProbabilities(h, k.tuning, fidelity);
      for (var j = 0; j < 4; j++) {
        score += p[j] * (table[j].toYou - table[j].toThem);
      }
    }
    if (score > bestScore + 1e-9) {
      bestScore = score;
      best = k;
    }
  }
  return best;
}
