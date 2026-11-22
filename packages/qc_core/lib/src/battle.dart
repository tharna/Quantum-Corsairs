import 'ai.dart';
import 'content.dart';
import 'damage.dart';
import 'quantum.dart';
import 'rng.dart';

/// A ship's state during a battle.
class ShipState {
  const ShipState({
    required this.hull,
    required this.maxHull,
    required this.systems,
    required this.maxSystems,
    required this.beam,
    required this.barrier,
  });

  final int hull;
  final int maxHull;
  final int systems;
  final int maxSystems;
  final int beam;
  final int barrier;

  bool get destroyed => hull <= 0;
  bool get disabled => systems <= 0;
  bool get down => destroyed || disabled;

  ShipState damaged(int hullLoss, int systemsLoss) => ShipState(
    hull: (hull - hullLoss).clamp(0, maxHull),
    maxHull: maxHull,
    systems: (systems - systemsLoss).clamp(0, maxSystems),
    maxSystems: maxSystems,
    beam: beam,
    barrier: barrier,
  );

  Map<String, Object?> toJson() => {
    'hull': hull,
    'maxHull': maxHull,
    'sys': systems,
    'maxSys': maxSystems,
    'beam': beam,
    'barrier': barrier,
  };

  static ShipState fromJson(Map<String, Object?> j) => ShipState(
    hull: j['hull'] as int,
    maxHull: j['maxHull'] as int,
    systems: j['sys'] as int,
    maxSystems: j['maxSys'] as int,
    beam: j['beam'] as int,
    barrier: j['barrier'] as int,
  );
}

/// What a probe showed this round.
class ProbeReading {
  const ProbeReading(this.shown, this.kicked);

  /// The enemy tuning as planned, before any back-action.
  final Tuning shown;

  /// Whether the probe's back-action turned the enemy's phases. The player is
  /// only told after the shot.
  final bool kicked;

  Map<String, Object?> toJson() => {'shown': shown.toJson(), 'kicked': kicked};
  static ProbeReading fromJson(Map<String, Object?> j) => ProbeReading(
    Tuning.fromJson(j['shown'] as Map<String, Object?>),
    j['kicked'] as bool,
  );
}

/// A round measured on a real quantum computer instead of the simulator.
class HardwareRun {
  const HardwareRun({
    required this.device,
    required this.jobId,
    required this.qubits,
    required this.shots,
    required this.counts,
  });

  /// Quantum computer alias, such as "garnet".
  final String device;
  final String jobId;

  /// Physical qubits used for your emitter and theirs.
  final List<String> qubits;
  final int shots;

  /// How often each [Outcome] was measured across all shots, indexed by
  /// `outcome.index`. The round itself uses the first shot.
  final List<int> counts;

  Map<String, Object?> toJson() => {
    'device': device,
    'job': jobId,
    'qubits': qubits,
    'shots': shots,
    'counts': counts,
  };

  static HardwareRun fromJson(Map<String, Object?> j) => HardwareRun(
    device: j['device'] as String,
    jobId: j['job'] as String,
    qubits: [for (final q in j['qubits'] as List<Object?>) q as String],
    shots: j['shots'] as int,
    counts: [for (final c in j['counts'] as List<Object?>) c as int],
  );
}

/// One resolved round, for the collapse report and the battle log.
class RoundReport {
  const RoundReport({
    required this.round,
    required this.you,
    required this.them,
    required this.fidelityPercent,
    required this.weather,
    required this.probabilities,
    required this.outcome,
    required this.damage,
    this.probe,
    this.table = const [],
    this.hardware,
  });

  final int round;
  final Tuning you;
  final Tuning them;
  final int fidelityPercent;
  final Weather weather;
  final List<double> probabilities;
  final Outcome outcome;
  final Damage damage;
  final ProbeReading? probe;

  /// The table this round was resolved with, for drawing all four cells.
  final List<Damage> table;

  /// Set when the outcome was measured on quantum hardware.
  final HardwareRun? hardware;

  Map<String, Object?> toJson() => {
    'round': round,
    'you': you.toJson(),
    'them': them.toJson(),
    'f': fidelityPercent,
    'wx': weather.name,
    'p': probabilities,
    'o': outcome.index,
    'd': [damage.toYou, damage.toThem, damage.systemsYou, damage.systemsThem],
    'table': [
      for (final d in table) [d.toYou, d.toThem, d.systemsYou, d.systemsThem],
    ],
    if (probe != null) 'probe': probe!.toJson(),
    if (hardware != null) 'hw': hardware!.toJson(),
  };

  static Damage _dmg(List<Object?> d) => Damage(
    d[0] as int,
    d[1] as int,
    systemsYou: d[2] as int,
    systemsThem: d[3] as int,
  );

  static RoundReport fromJson(Map<String, Object?> j) {
    return RoundReport(
      round: j['round'] as int,
      you: Tuning.fromJson(j['you'] as Map<String, Object?>),
      them: Tuning.fromJson(j['them'] as Map<String, Object?>),
      fidelityPercent: j['f'] as int,
      weather: Weather.values.byName(j['wx'] as String),
      probabilities: [
        for (final x in j['p'] as List<Object?>) (x as num).toDouble(),
      ],
      outcome: Outcome.values[j['o'] as int],
      damage: _dmg(j['d'] as List<Object?>),
      probe: j['probe'] == null
          ? null
          : ProbeReading.fromJson(j['probe'] as Map<String, Object?>),
      table: [
        for (final d in (j['table'] as List<Object?>? ?? const []))
          _dmg(d as List<Object?>),
      ],
      hardware: j['hw'] == null
          ? null
          : HardwareRun.fromJson(j['hw'] as Map<String, Object?>),
    );
  }
}

enum BattleResult {
  ongoing,
  enemyDisabled,
  enemyDestroyed,
  playerDestroyed,
  playerDisabled,
}

extension BattleResultX on BattleResult {
  bool get isOver => this != BattleResult.ongoing;
  bool get playerWon =>
      this == BattleResult.enemyDisabled || this == BattleResult.enemyDestroyed;
}

/// Immutable state of one battle. Every action returns a new state.
class BattleState {
  const BattleState({
    required this.foe,
    required this.stage,
    required this.you,
    required this.them,
    required this.round,
    required this.weather,
    required this.plan,
    required this.pendingFidelity,
    required this.history,
    required this.probesLeft,
    required this.probesMax,
    required this.kickChance,
    required this.scan,
    required this.log,
    required this.tactic,
    required this.allowed,
    required this.result,
    required this.rngState,
  });

  final FactionId foe;

  /// 0 for the trader, 1 for the protector who answered its distress call.
  final int stage;
  final ShipState you;
  final ShipState them;

  /// Rounds resolved so far.
  final int round;
  final Weather weather;

  /// The enemy's committed tuning for the coming round. Hidden from the UI
  /// except through a probe.
  final Tuning plan;

  /// Bell-lock fidelity, in percent, for the coming round. Drawn from the
  /// forecast when the enemy commits, so a quantum computer can be given the
  /// whole circuit before the shot. Hidden from the UI, which shows only the
  /// forecast range.
  final int pendingFidelity;
  final List<Tuning> history;
  final int probesLeft;
  final int probesMax;
  final double kickChance;
  final ProbeReading? scan;
  final List<RoundReport> log;

  /// The enemy's resolved style. For the Corp Police this is the hidden
  /// captain style, never shown to the player.
  final Tactic tactic;
  final Set<TuningPreset> allowed;
  final BattleResult result;
  final int rngState;

  Faction get faction => factions[foe]!;
  RoundReport? get last => log.isEmpty ? null : log.last;
  bool get canProbe => !result.isOver && scan == null && probesLeft > 0;

  List<Damage> get table => damageTable(
    youBeam: you.beam,
    youBarrier: you.barrier,
    themBeam: them.beam,
    themBarrier: them.barrier,
  );

  /// Starts a battle. [carry] keeps hull and systems damage from a previous
  /// fight in the same encounter.
  static BattleState start({
    required FactionId foe,
    required int stage,
    required int beam,
    required int barrier,
    required int probes,
    required double kickChance,
    required Set<TuningPreset> allowed,
    required int seed,
    ShipState? carry,
  }) {
    final f = factions[foe]!;
    final rng = Rng.seeded(seed);
    var tactic = f.tactic;
    if (tactic == Tactic.police) {
      tactic = rng.chance(0.5) ? Tactic.defence : Tactic.mercenary;
    }
    final you = ShipState(
      hull: carry?.hull ?? playerHull,
      maxHull: playerHull,
      systems: carry?.systems ?? playerSystems,
      maxSystems: playerSystems,
      beam: beam,
      barrier: barrier,
    );
    final them = ShipState(
      hull: f.hull,
      maxHull: f.hull,
      systems: f.systems,
      maxSystems: f.systems,
      beam: f.beam,
      barrier: f.barrier,
    );
    final draft = BattleState(
      foe: foe,
      stage: stage,
      you: you,
      them: them,
      round: 0,
      weather: Weather.calm,
      plan: TuningPreset.hold.tuning,
      pendingFidelity: Weather.calm.maxPercent,
      history: const [],
      probesLeft: probes,
      probesMax: probes,
      kickChance: kickChance,
      scan: null,
      log: const [],
      tactic: tactic,
      allowed: allowed,
      result: BattleResult.ongoing,
      rngState: rng.state,
    );
    return draft._withNewPlan(rng);
  }

  BattleState _withNewPlan(Rng rng) {
    final fidelity = weather.drawPercent(rng);
    final plan = enemyTuning(
      EnemyContext(
        tactic: tactic,
        weather: weather,
        playerHistory: history,
        table: table,
        allowed: allowed,
      ),
      rng,
    );
    return _copy(plan: plan, pendingFidelity: fidelity, rngState: rng.state);
  }

  /// Fires a probe at the enemy emitter. With [kickChance] its back-action
  /// turns both enemy phases by 90°, changing the planned tuning.
  BattleState probe() {
    if (!canProbe) throw StateError('No probe available');
    final rng = Rng(rngState);
    final kicked = rng.chance(kickChance);
    final reading = ProbeReading(plan, kicked);
    return _copy(
      probesLeft: probesLeft - 1,
      scan: reading,
      plan: kicked ? plan.kicked() : plan,
      rngState: rng.state,
    );
  }

  /// Resolves a round with the player's [tuning].
  ///
  /// The outcome is sampled from the simulated probabilities, unless
  /// [measured] gives the outcome a quantum computer measured for this exact
  /// round (see [compileRound] with [plan] and [pendingFidelity]).
  BattleState fire(Tuning tuning, {Outcome? measured, HardwareRun? hardware}) {
    if (result.isOver) throw StateError('Battle is over');
    final rng = Rng(rngState);
    final fidelity = pendingFidelity;
    final probs = outcomeProbabilities(tuning, plan, fidelity / 100);
    final sampled = sampleOutcome(probs, rng.nextDouble());
    final outcome = measured ?? sampled;
    final t = table;
    final d = t[outcome.index];
    final you2 = you.damaged(d.toYou, d.systemsYou);
    final them2 = them.damaged(d.toThem, d.systemsThem);
    final report = RoundReport(
      round: round + 1,
      you: tuning,
      them: plan,
      fidelityPercent: fidelity,
      weather: weather,
      probabilities: probs,
      outcome: outcome,
      damage: d,
      probe: scan,
      table: t,
      hardware: measured == null ? null : hardware,
    );

    var res = BattleResult.ongoing;
    if (you2.down) {
      res = you2.destroyed
          ? BattleResult.playerDestroyed
          : BattleResult.playerDisabled;
    } else if (them2.down) {
      res = them2.disabled && !them2.destroyed
          ? BattleResult.enemyDisabled
          : BattleResult.enemyDestroyed;
    }

    final hist = [...history, tuning];
    if (hist.length > 3) hist.removeAt(0);
    var next = _copy(
      you: you2,
      them: them2,
      round: round + 1,
      history: List.unmodifiable(hist),
      log: List.unmodifiable([...log, report]),
      result: res,
      clearScan: true,
      rngState: rng.state,
    );
    if (!res.isOver) {
      next = next._copy(weather: weather.next(rng), rngState: rng.state);
      next = next._withNewPlan(rng);
    }
    return next;
  }

  /// Cargo or bounty earned, once the player has won.
  int get payout {
    if (result == BattleResult.enemyDisabled) return faction.loot;
    if (result == BattleResult.enemyDestroyed) {
      return (faction.loot * salvageShare).round();
    }
    return 0;
  }

  BattleState _copy({
    ShipState? you,
    ShipState? them,
    int? round,
    Weather? weather,
    Tuning? plan,
    int? pendingFidelity,
    List<Tuning>? history,
    int? probesLeft,
    ProbeReading? scan,
    bool clearScan = false,
    List<RoundReport>? log,
    BattleResult? result,
    int? rngState,
  }) => BattleState(
    foe: foe,
    stage: stage,
    you: you ?? this.you,
    them: them ?? this.them,
    round: round ?? this.round,
    weather: weather ?? this.weather,
    plan: plan ?? this.plan,
    pendingFidelity: pendingFidelity ?? this.pendingFidelity,
    history: history ?? this.history,
    probesLeft: probesLeft ?? this.probesLeft,
    probesMax: probesMax,
    kickChance: kickChance,
    scan: clearScan ? null : (scan ?? this.scan),
    log: log ?? this.log,
    tactic: tactic,
    allowed: allowed,
    result: result ?? this.result,
    rngState: rngState ?? this.rngState,
  );

  Map<String, Object?> toJson() => {
    'foe': foe.name,
    'stage': stage,
    'you': you.toJson(),
    'them': them.toJson(),
    'round': round,
    'wx': weather.name,
    'plan': plan.toJson(),
    'pf': pendingFidelity,
    'hist': [for (final h in history) h.toJson()],
    'probes': probesLeft,
    'probesMax': probesMax,
    'kick': kickChance,
    if (scan != null) 'scan': scan!.toJson(),
    'log': [for (final r in log) r.toJson()],
    'tactic': tactic.name,
    'allowed': [for (final a in allowed) a.name],
    'result': result.name,
    'rng': rngState,
  };

  static BattleState fromJson(Map<String, Object?> j) => BattleState(
    foe: FactionId.values.byName(j['foe'] as String),
    stage: j['stage'] as int,
    you: ShipState.fromJson(j['you'] as Map<String, Object?>),
    them: ShipState.fromJson(j['them'] as Map<String, Object?>),
    round: j['round'] as int,
    weather: Weather.values.byName(j['wx'] as String),
    plan: Tuning.fromJson(j['plan'] as Map<String, Object?>),
    pendingFidelity:
        j['pf'] as int? ?? Weather.values.byName(j['wx'] as String).maxPercent,
    history: List.unmodifiable([
      for (final h in j['hist'] as List<Object?>)
        Tuning.fromJson(h as Map<String, Object?>),
    ]),
    probesLeft: j['probes'] as int,
    probesMax: j['probesMax'] as int,
    kickChance: (j['kick'] as num).toDouble(),
    scan: j['scan'] == null
        ? null
        : ProbeReading.fromJson(j['scan'] as Map<String, Object?>),
    log: List.unmodifiable([
      for (final r in j['log'] as List<Object?>)
        RoundReport.fromJson(r as Map<String, Object?>),
    ]),
    tactic: Tactic.values.byName(j['tactic'] as String),
    allowed: {
      for (final a in j['allowed'] as List<Object?>)
        TuningPreset.values.byName(a as String),
    },
    result: BattleResult.values.byName(j['result'] as String),
    rngState: j['rng'] as int,
  );
}
