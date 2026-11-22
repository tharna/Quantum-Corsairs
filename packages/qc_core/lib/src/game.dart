import 'battle.dart';
import 'content.dart';
import 'quantum.dart';
import 'rng.dart';

/// Permanent progress that survives a lost raid.
class Profile {
  const Profile({
    this.prizesTotal = 0,
    this.raidsPlayed = 0,
    this.bestRaid = 0,
    this.bankedTotal = 0,
  });

  final int prizesTotal;
  final int raidsPlayed;

  /// Most loot held at the end of a single raid.
  final int bestRaid;

  /// All loot ever banked, across raids.
  final int bankedTotal;

  /// Teaching progress: one level per prize taken, up to [maxUnlockLevel].
  int get unlockLevel =>
      prizesTotal < maxUnlockLevel ? prizesTotal : maxUnlockLevel;

  bool has(Unlock u) => unlockLevel >= u.level;

  Set<TuningPreset> get allowedPresets => {
    TuningPreset.hold,
    TuningPreset.lance,
    if (has(Unlock.conjugate)) TuningPreset.conjugate,
    if (has(Unlock.phaseLance)) TuningPreset.phaseLance,
  };

  Profile copyWith({
    int? prizesTotal,
    int? raidsPlayed,
    int? bestRaid,
    int? bankedTotal,
  }) => Profile(
    prizesTotal: prizesTotal ?? this.prizesTotal,
    raidsPlayed: raidsPlayed ?? this.raidsPlayed,
    bestRaid: bestRaid ?? this.bestRaid,
    bankedTotal: bankedTotal ?? this.bankedTotal,
  );

  Map<String, Object?> toJson() => {
    'prizes': prizesTotal,
    'raids': raidsPlayed,
    'best': bestRaid,
    'banked': bankedTotal,
  };

  static Profile fromJson(Map<String, Object?> j) => Profile(
    prizesTotal: j['prizes'] as int? ?? 0,
    raidsPlayed: j['raids'] as int? ?? 0,
    bestRaid: j['best'] as int? ?? 0,
    bankedTotal: j['banked'] as int? ?? 0,
  );
}

enum RaidPhase {
  /// Docked: refit and pick the next prize.
  port,

  /// A battle is being fought.
  battle,

  /// The battle was won. The player may face the protector, run, or dock.
  victory,

  /// The player's ship is down. The raid is over.
  defeat,
}

/// One run: ports, battles and the loot they earn.
class RaidState {
  const RaidState({
    required this.phase,
    required this.loot,
    required this.prizes,
    required this.upgrades,
    required this.lane,
    required this.lastGain,
    required this.battle,
    required this.rngState,
    this.unlockedThisBattle,
  });

  final RaidPhase phase;
  final int loot;
  final int prizes;
  final Map<Upgrade, int> upgrades;

  /// Index into [lanes] of the current or most recent target.
  final int lane;

  /// Payout of the most recent win, for the "jettison half" offer.
  final int lastGain;
  final BattleState? battle;
  final int rngState;

  /// Set on the victory that raised the unlock level, for the UI to announce.
  final Unlock? unlockedThisBattle;

  int level(Upgrade u) => upgrades[u] ?? 0;
  int get beam => 1 + level(Upgrade.beam);
  int get barrier => 1 + level(Upgrade.barrier);
  int get probes => baseProbes + level(Upgrade.probeRack);
  double get kickChance =>
      level(Upgrade.shieldedProbe) > 0 ? shieldedKickChance : baseKickChance;

  /// Whether the player may now face the trader's protector.
  bool get protectorWaiting =>
      phase == RaidPhase.victory &&
      battle != null &&
      battle!.stage == 0 &&
      lanes[lane].guard != null;

  int get fleeCost => lastGain ~/ 2;

  RaidState copyWith({
    RaidPhase? phase,
    int? loot,
    int? prizes,
    Map<Upgrade, int>? upgrades,
    int? lane,
    int? lastGain,
    BattleState? battle,
    bool clearBattle = false,
    int? rngState,
    Unlock? unlockedThisBattle,
    bool clearUnlock = false,
  }) => RaidState(
    phase: phase ?? this.phase,
    loot: loot ?? this.loot,
    prizes: prizes ?? this.prizes,
    upgrades: upgrades ?? this.upgrades,
    lane: lane ?? this.lane,
    lastGain: lastGain ?? this.lastGain,
    battle: clearBattle ? null : (battle ?? this.battle),
    rngState: rngState ?? this.rngState,
    unlockedThisBattle: clearUnlock
        ? null
        : (unlockedThisBattle ?? this.unlockedThisBattle),
  );

  Map<String, Object?> toJson() => {
    'phase': phase.name,
    'loot': loot,
    'prizes': prizes,
    'up': {for (final e in upgrades.entries) e.key.name: e.value},
    'lane': lane,
    'gain': lastGain,
    if (battle != null) 'battle': battle!.toJson(),
    'rng': rngState,
    if (unlockedThisBattle != null) 'unlocked': unlockedThisBattle!.name,
  };

  static RaidState fromJson(Map<String, Object?> j) => RaidState(
    phase: RaidPhase.values.byName(j['phase'] as String),
    loot: j['loot'] as int,
    prizes: j['prizes'] as int,
    upgrades: {
      for (final e in (j['up'] as Map<String, Object?>).entries)
        Upgrade.values.byName(e.key): e.value as int,
    },
    lane: j['lane'] as int,
    lastGain: j['gain'] as int,
    battle: j['battle'] == null
        ? null
        : BattleState.fromJson(j['battle'] as Map<String, Object?>),
    rngState: j['rng'] as int,
    unlockedThisBattle: j['unlocked'] == null
        ? null
        : Unlock.values.byName(j['unlocked'] as String),
  );
}

/// The whole game: permanent profile plus the raid in progress, if any.
///
/// Every action validates its phase and returns a new state, so the UI and
/// the balance simulator drive the game the same way.
class GameState {
  const GameState({this.profile = const Profile(), this.raid});

  static const int saveVersion = 1;

  final Profile profile;
  final RaidState? raid;

  RaidState get _raid => raid ?? (throw StateError('No raid in progress'));

  GameState _with({
    Profile? profile,
    RaidState? raid,
    bool clearRaid = false,
  }) => GameState(
    profile: profile ?? this.profile,
    raid: clearRaid ? null : (raid ?? this.raid),
  );

  /// Lanes the player can choose from at the current unlock level.
  List<int> get openLanes => [
    for (var i = 0; i < lanes.length; i++)
      if (profile.unlockLevel >= lanes[i].unlockLevel) i,
  ];

  GameState newRaid(int seed) => _with(
    raid: RaidState(
      phase: RaidPhase.port,
      loot: 0,
      prizes: 0,
      upgrades: const {},
      lane: 0,
      lastGain: 0,
      battle: null,
      rngState: Rng.seeded(seed).state,
    ),
  );

  bool canBuy(Upgrade u) {
    final r = raid;
    if (r == null || r.phase != RaidPhase.port) return false;
    final owned = r.level(u);
    if (owned >= u.maxLevel) return false;
    if ((u == Upgrade.probeRack || u == Upgrade.shieldedProbe) &&
        !profile.has(Unlock.probe)) {
      return false;
    }
    return r.loot >= u.cost(owned);
  }

  GameState buy(Upgrade u) {
    if (!canBuy(u)) throw StateError('Cannot buy ${u.name}');
    final r = _raid;
    final owned = r.level(u);
    return _with(
      raid: r.copyWith(
        loot: r.loot - u.cost(owned),
        upgrades: {...r.upgrades, u: owned + 1},
      ),
    );
  }

  BattleState _startBattle(
    RaidState r,
    Rng rng,
    FactionId foe,
    int stage, {
    ShipState? carry,
  }) => BattleState.start(
    foe: foe,
    stage: stage,
    beam: r.beam,
    barrier: r.barrier,
    probes: profile.has(Unlock.probe) ? r.probes : 0,
    kickChance: r.kickChance,
    allowed: profile.allowedPresets,
    seed: rng.nextUint32(),
    carry: carry,
  );

  GameState startLane(int laneIndex) {
    final r = _raid;
    if (r.phase != RaidPhase.port) throw StateError('Not in port');
    if (!openLanes.contains(laneIndex)) throw StateError('Lane locked');
    final rng = Rng(r.rngState);
    final b = _startBattle(r, rng, lanes[laneIndex].trade, 0);
    return _with(
      raid: r.copyWith(
        phase: RaidPhase.battle,
        lane: laneIndex,
        battle: b,
        rngState: rng.state,
        clearUnlock: true,
      ),
    );
  }

  GameState probe() {
    final r = _raid;
    if (r.phase != RaidPhase.battle) throw StateError('Not in battle');
    return _with(raid: r.copyWith(battle: r.battle!.probe()));
  }

  GameState fire(Tuning tuning) {
    final r = _raid;
    if (r.phase != RaidPhase.battle) throw StateError('Not in battle');
    if (tuning.preset != null &&
        !profile.allowedPresets.contains(tuning.preset)) {
      throw StateError('Tuning ${tuning.preset!.name} is locked');
    }
    if (tuning.preset == null && !profile.has(Unlock.dials)) {
      throw StateError('Manual dials are locked');
    }
    final b = r.battle!.fire(tuning);
    if (!b.result.isOver) return _with(raid: r.copyWith(battle: b));

    if (b.result.playerWon) {
      final pay = b.payout;
      final before = profile.unlockLevel;
      final p2 = profile.copyWith(prizesTotal: profile.prizesTotal + 1);
      final unlocked = p2.unlockLevel > before
          ? Unlock.values.firstWhere((u) => u.level == p2.unlockLevel)
          : null;
      return _with(
        profile: p2,
        raid: r.copyWith(
          phase: RaidPhase.victory,
          battle: b,
          loot: r.loot + pay,
          prizes: r.prizes + 1,
          lastGain: pay,
          unlockedThisBattle: unlocked,
        ),
      );
    }
    return _with(
      profile: _banked(r.loot),
      raid: r.copyWith(phase: RaidPhase.defeat, battle: b),
    );
  }

  Profile _banked(int loot) => profile.copyWith(
    raidsPlayed: profile.raidsPlayed + 1,
    bankedTotal: profile.bankedTotal + loot,
    bestRaid: loot > profile.bestRaid ? loot : profile.bestRaid,
  );

  /// Stand and fight the protector, with damage carried over.
  GameState fightProtector() {
    final r = _raid;
    if (!r.protectorWaiting) throw StateError('No protector waiting');
    final rng = Rng(r.rngState);
    final b = _startBattle(
      r,
      rng,
      lanes[r.lane].guard!,
      1,
      carry: r.battle!.you,
    );
    return _with(
      raid: r.copyWith(
        phase: RaidPhase.battle,
        battle: b,
        rngState: rng.state,
        clearUnlock: true,
      ),
    );
  }

  /// Jettison half of the trader's cargo and run for port.
  GameState flee() {
    final r = _raid;
    if (!r.protectorWaiting) throw StateError('Nothing to flee from');
    return _with(
      raid: r.copyWith(
        phase: RaidPhase.port,
        loot: r.loot - r.fleeCost,
        clearBattle: true,
        clearUnlock: true,
      ),
    );
  }

  /// Dock after a win with no protector left to face.
  GameState returnToPort() {
    final r = _raid;
    if (r.phase != RaidPhase.victory || r.protectorWaiting) {
      throw StateError('Cannot return to port now');
    }
    return _with(
      raid: r.copyWith(
        phase: RaidPhase.port,
        clearBattle: true,
        clearUnlock: true,
      ),
    );
  }

  /// Bank the loot and end the raid from port.
  GameState retire() {
    final r = _raid;
    if (r.phase != RaidPhase.port) throw StateError('Retire from port only');
    return _with(profile: _banked(r.loot), clearRaid: true);
  }

  /// Leave the defeat screen. The loot was already banked.
  GameState acknowledgeDefeat() {
    if (_raid.phase != RaidPhase.defeat) throw StateError('Not defeated');
    return _with(clearRaid: true);
  }

  Map<String, Object?> toJson() => {
    'v': saveVersion,
    'profile': profile.toJson(),
    if (raid != null) 'raid': raid!.toJson(),
  };

  /// Restores a save. Returns a fresh game for an unknown version, keeping
  /// the profile when it can be read.
  static GameState fromJson(Map<String, Object?> j) {
    final profile = j['profile'] is Map<String, Object?>
        ? Profile.fromJson(j['profile'] as Map<String, Object?>)
        : const Profile();
    if (j['v'] != saveVersion) return GameState(profile: profile);
    return GameState(
      profile: profile,
      raid: j['raid'] == null
          ? null
          : RaidState.fromJson(j['raid'] as Map<String, Object?>),
    );
  }
}
