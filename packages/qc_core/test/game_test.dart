import 'dart:convert';

import 'package:qc_core/qc_core.dart';
import 'package:test/test.dart';

const _all = {
  TuningPreset.hold,
  TuningPreset.lance,
  TuningPreset.conjugate,
  TuningPreset.phaseLance,
};

BattleState _battle(
  FactionId foe, {
  int seed = 1,
  Set<TuningPreset> allowed = _all,
}) => BattleState.start(
  foe: foe,
  stage: 0,
  beam: 1,
  barrier: 1,
  probes: 3,
  kickChance: 0.3,
  allowed: allowed,
  seed: seed,
);

/// A profile with everything unlocked.
const _veteran = Profile(prizesTotal: 10);

void main() {
  group('battle', () {
    test('starts in calm with full ships and a committed plan', () {
      final b = _battle(FactionId.guild);
      expect(b.weather, Weather.calm);
      expect(b.you.hull, playerHull);
      expect(b.them.hull, factions[FactionId.guild]!.hull);
      expect(b.plan.preset, isNotNull);
      expect(b.result, BattleResult.ongoing);
    });

    test('fire resolves a round, logs it and keeps fidelity in range', () {
      var b = _battle(FactionId.federation);
      final before = b.weather;
      b = b.fire(TuningPreset.lance.tuning);
      expect(b.round, 1);
      expect(
        b.log.single.fidelityPercent,
        inInclusiveRange(before.minPercent, before.maxPercent),
      );
      final d = b.log.single.damage;
      expect(b.you.hull, playerHull - d.toYou);
    });

    test('is deterministic for a seed', () {
      BattleState play(int seed) {
        var b = _battle(FactionId.hunters, seed: seed);
        while (!b.result.isOver) {
          b = b.fire(TuningPreset.values[b.round % 4].tuning);
        }
        return b;
      }

      final a = play(99), c = play(99);
      expect(a.round, c.round);
      expect(a.you.hull, c.you.hull);
      expect(jsonEncode(a.toJson()), jsonEncode(c.toJson()));
    });

    test('every battle ends', () {
      for (var seed = 1; seed <= 200; seed++) {
        for (final foe in FactionId.values) {
          var b = _battle(foe, seed: seed);
          var guard = 0;
          while (!b.result.isOver) {
            b = b.fire(TuningPreset.values[(seed + b.round) % 4].tuning);
            expect(++guard, lessThan(200));
          }
        }
      }
    });

    test('probe reads the planned tuning and may kick it', () {
      var kicks = 0, reads = 0;
      for (var seed = 1; seed <= 400; seed++) {
        final b = _battle(FactionId.corsairs, seed: seed);
        final p = b.probe();
        reads++;
        expect(p.scan!.shown, b.plan);
        expect(p.probesLeft, 2);
        expect(p.canProbe, isFalse, reason: 'one probe per round');
        if (p.scan!.kicked) {
          kicks++;
          expect(p.plan, b.plan.kicked());
        } else {
          expect(p.plan, b.plan);
        }
        // Lance power is always read correctly.
        expect(p.plan.theta, b.plan.theta);
      }
      expect(kicks / reads, closeTo(0.3, 0.07));
    });

    test('probe report carries into the round and then clears', () {
      final b = _battle(FactionId.guild).probe().fire(TuningPreset.hold.tuning);
      expect(b.log.single.probe, isNotNull);
      expect(b.scan, isNull);
    });

    test('no probes means no probing', () {
      final b = BattleState.start(
        foe: FactionId.guild,
        stage: 0,
        beam: 1,
        barrier: 1,
        probes: 0,
        kickChance: 0.3,
        allowed: _all,
        seed: 3,
      );
      expect(b.canProbe, isFalse);
      expect(b.probe, throwsStateError);
    });

    test('disabling pays full cargo, destroying pays 40%', () {
      final guild = factions[FactionId.guild]!;
      // Countering every plan keeps their emitter shield-side while ours goes
      // lance-side: one system per round, so the freighter is disabled.
      var b = _battle(FactionId.guild, seed: 4);
      while (!b.result.isOver) {
        b = b.fire(
          b.plan.preset == TuningPreset.conjugate
              ? TuningPreset.phaseLance.tuning
              : TuningPreset.lance.tuning,
        );
      }
      expect(b.result, BattleResult.enemyDisabled);
      expect(b.payout, guild.loot);

      final j = b.toJson()..['result'] = BattleResult.enemyDestroyed.name;
      expect(BattleState.fromJson(j).payout, (guild.loot * 0.4).round());
    });

    test('json round trip mid-battle continues identically', () {
      var b = _battle(FactionId.police, seed: 5);
      b = b.fire(TuningPreset.hold.tuning).probe();
      final restored = BattleState.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, Object?>,
      );
      final a = b.fire(TuningPreset.lance.tuning);
      final c = restored.fire(TuningPreset.lance.tuning);
      expect(jsonEncode(c.toJson()), jsonEncode(a.toJson()));
    });

    test('corp police captain is defence or mercenary, never told', () {
      final styles = <Tactic>{};
      for (var seed = 1; seed <= 50; seed++) {
        styles.add(_battle(FactionId.police, seed: seed).tactic);
      }
      expect(styles, {Tactic.defence, Tactic.mercenary});
    });
  });

  group('hardware outcomes', () {
    test(
      'the round fidelity is fixed before the shot and inside the forecast',
      () {
        var b = _battle(FactionId.federation, seed: 12);
        for (var i = 0; i < 20 && !b.result.isOver; i++) {
          final w = b.weather, f = b.pendingFidelity;
          expect(f, inInclusiveRange(w.minPercent, w.maxPercent));
          b = b.fire(TuningPreset.lance.tuning);
          expect(b.log.last.fidelityPercent, f);
        }
      },
    );

    test('a measured outcome replaces the sampled one and is recorded', () {
      final b = _battle(FactionId.guild, seed: 3);
      const run = HardwareRun(
        device: 'garnet',
        jobId: 'job-1',
        qubits: ['QB1', 'QB2'],
        shots: 10,
        counts: [1, 6, 2, 1],
      );
      for (final o in Outcome.values) {
        final next = b.fire(
          TuningPreset.hold.tuning,
          measured: o,
          hardware: run,
        );
        expect(next.log.single.outcome, o);
        expect(next.log.single.hardware!.jobId, 'job-1');
        final d = next.log.single.table[o.index];
        expect(next.you.hull, playerHull - d.toYou);
      }
      expect(b.fire(TuningPreset.hold.tuning).log.single.hardware, isNull);
    });

    test('the circuit sent to hardware is the one the round resolves', () {
      final b = _battle(FactionId.corsairs, seed: 9);
      final you = TuningPreset.phaseLance.tuning;
      final ideal = simulateNative(
        compileRound(you, b.plan, b.pendingFidelity / 100),
      );
      final report = b.fire(you).log.single;
      for (var i = 0; i < 4; i++) {
        expect(ideal[i], closeTo(report.probabilities[i], 1e-9));
      }
    });

    test('hardware provenance survives a save', () {
      const run = HardwareRun(
        device: 'garnet',
        jobId: 'abc',
        qubits: ['QB1', 'QB2'],
        shots: 100,
        counts: [10, 60, 25, 5],
      );
      final b = _battle(FactionId.guild).fire(
        TuningPreset.lance.tuning,
        measured: Outcome.youLance,
        hardware: run,
      );
      final r = BattleState.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, Object?>,
      ).log.single.hardware!;
      expect(
        [r.device, r.jobId, r.shots, r.counts],
        [
          'garnet',
          'abc',
          100,
          [10, 60, 25, 5],
        ],
      );
    });
  });

  group('legacy saves', () {
    test('a save without pending fidelity resumes exactly as before', () {
      // Old fire(): draw fidelity, then the outcome, from the saved RNG.
      final b = _battle(FactionId.hunters, seed: 21);
      final j = jsonDecode(jsonEncode(b.toJson())) as Map<String, Object?>;
      j.remove('pf');
      final legacy = BattleState.fromJson(j);

      final rng = Rng(j['rng'] as int);
      final f = b.weather.drawPercent(rng);
      final probs = outcomeProbabilities(
        TuningPreset.lance.tuning,
        b.plan,
        f / 100,
      );
      final expected = sampleOutcome(probs, rng.nextDouble());

      expect(legacy.pendingFidelity, f);
      final r = legacy.fire(TuningPreset.lance.tuning).log.single;
      expect(r.fidelityPercent, f);
      expect(r.outcome, expected);
    });

    test('a simulated-fallback reason is kept with the round', () {
      final b = _battle(
        FactionId.guild,
      ).fire(TuningPreset.hold.tuning, simulatedReason: 'QPU offline');
      final back = BattleState.fromJson(
        jsonDecode(jsonEncode(b.toJson())) as Map<String, Object?>,
      );
      expect(back.log.single.simulatedReason, 'QPU offline');
    });
  });

  group('enemy AI', () {
    final table = damageTable(
      youBeam: 1,
      youBarrier: 1,
      themBeam: 1,
      themBarrier: 2,
    );

    Map<TuningPreset, int> sample(
      Tactic t,
      Weather w, {
      List<Tuning> history = const [],
      Set<TuningPreset> allowed = _all,
    }) {
      final rng = Rng(11);
      final counts = <TuningPreset, int>{};
      for (var i = 0; i < 4000; i++) {
        final k = enemyTuning(
          EnemyContext(
            tactic: t,
            weather: w,
            playerHistory: history,
            table: table,
            allowed: allowed,
          ),
          rng,
        ).preset!;
        counts[k] = (counts[k] ?? 0) + 1;
      }
      return counts;
    }

    test('guild uses conjugate shields 75% in calm and holds in storms', () {
      final c = sample(Tactic.guild, Weather.calm);
      expect(c[TuningPreset.conjugate]! / 4000, closeTo(0.75, 0.03));
      expect(sample(Tactic.guild, Weather.storm).keys, [TuningPreset.hold]);
    });

    test('federation 40%, corp 50%', () {
      expect(
        sample(Tactic.federation, Weather.calm)[TuningPreset.conjugate]! / 4000,
        closeTo(0.4, 0.03),
      );
      expect(
        sample(Tactic.corp, Weather.calm)[TuningPreset.conjugate]! / 4000,
        closeTo(0.5, 0.03),
      );
    });

    test('front counts as calm (midpoint 67.5%)', () {
      expect(Weather.front.lockHolds, isTrue);
      expect(Weather.storm.lockHolds, isFalse);
    });

    test('defence force only lances', () {
      final c = sample(Tactic.defence, Weather.calm);
      expect(c.keys.toSet(), {TuningPreset.lance, TuningPreset.phaseLance});
      expect(c[TuningPreset.phaseLance]! / 4000, closeTo(0.3, 0.03));
    });

    test('mercenaries counter a habit most of the time', () {
      // Against a player who always fires the plain lance in calm, the best
      // counter is conjugate shields.
      final c = sample(
        Tactic.mercenary,
        Weather.calm,
        history: List.filled(3, TuningPreset.lance.tuning),
      );
      expect(c[TuningPreset.conjugate]! / 4000, greaterThan(0.8));
    });

    test('enemies are limited to what the player has been taught', () {
      final c = sample(
        Tactic.wild,
        Weather.calm,
        allowed: {TuningPreset.hold, TuningPreset.lance},
      );
      expect(c.keys.toSet(), {TuningPreset.hold, TuningPreset.lance});
    });
  });

  group('weather', () {
    test('transition frequencies follow the table', () {
      final rng = Rng(5);
      var fronts = 0;
      for (var i = 0; i < 10000; i++) {
        if (Weather.calm.next(rng) == Weather.front) fronts++;
      }
      expect(fronts / 10000, closeTo(0.28, 0.02));
    });
  });

  group('raid', () {
    test('new player sees only the guild lane and two tunings', () {
      final g = const GameState().newRaid(1);
      expect(g.openLanes, [0]);
      expect(g.profile.allowedPresets, {TuningPreset.hold, TuningPreset.lance});
      final b = g.startLane(0).raid!.battle!;
      expect(b.probesMax, 0);
      expect(
        () => g.startLane(0).fire(TuningPreset.conjugate.tuning),
        throwsStateError,
      );
    });

    test('winning a trader offers the protector, fleeing costs half', () {
      var g = const GameState(profile: _veteran).newRaid(3).startLane(0);
      var seed = 0;
      while (g.raid!.phase == RaidPhase.battle) {
        g = g.fire(TuningPreset.values[seed++ % 4].tuning);
      }
      if (g.raid!.phase == RaidPhase.defeat) return; // possible, rare
      expect(g.raid!.protectorWaiting, isTrue);
      final loot = g.raid!.loot;
      final fled = g.flee();
      expect(fled.raid!.phase, RaidPhase.port);
      expect(fled.raid!.loot, loot - g.raid!.lastGain ~/ 2);

      final fight = g.fightProtector();
      expect(fight.raid!.battle!.foe, FactionId.hunters);
      expect(
        fight.raid!.battle!.you.hull,
        g.raid!.battle!.you.hull,
        reason: 'damage carries over',
      );
    });

    test('defeat banks loot into the profile and ends the raid', () {
      for (var seed = 1; seed < 100; seed++) {
        var g = const GameState(profile: _veteran).newRaid(seed).startLane(2);
        while (g.raid!.phase == RaidPhase.battle) {
          g = g.fire(TuningPreset.hold.tuning);
        }
        if (g.raid!.phase == RaidPhase.defeat) {
          expect(g.profile.raidsPlayed, 1);
          expect(g.acknowledgeDefeat().raid, isNull);
          return;
        }
      }
      fail('expected at least one defeat');
    });

    test('a first win unlocks conjugate shields', () {
      for (var seed = 1; seed < 100; seed++) {
        var g = const GameState().newRaid(seed).startLane(0);
        while (g.raid!.phase == RaidPhase.battle) {
          g = g.fire(TuningPreset.lance.tuning);
        }
        if (g.raid!.phase == RaidPhase.victory) {
          expect(g.raid!.unlockedThisBattle, Unlock.conjugate);
          expect(g.profile.allowedPresets, contains(TuningPreset.conjugate));
          return;
        }
      }
      fail('expected a win');
    });

    test('refits cost loot and raise ratings', () {
      const g = GameState(
        profile: _veteran,
        raid: RaidState(
          phase: RaidPhase.port,
          loot: 1000,
          prizes: 0,
          upgrades: {},
          lane: 0,
          lastGain: 0,
          battle: null,
          rngState: 1,
        ),
      );
      final g2 = g.buy(Upgrade.beam);
      expect(g2.raid!.loot, 600);
      expect(g2.raid!.beam, 2);
      expect(g2.canBuy(Upgrade.beam), isFalse, reason: '800 cr needed');
      expect(g2.buy(Upgrade.probeRack).raid!.probes, 4);
      expect(g.buy(Upgrade.shieldedProbe).raid!.kickChance, 0.15);
    });

    test('save round trip', () {
      var g = const GameState(profile: _veteran).newRaid(8).startLane(1);
      g = g.fire(TuningPreset.lance.tuning);
      final restored = GameState.fromJson(
        jsonDecode(jsonEncode(g.toJson())) as Map<String, Object?>,
      );
      expect(jsonEncode(restored.toJson()), jsonEncode(g.toJson()));
    });

    test('unknown save version keeps the profile, drops the raid', () {
      final g = GameState.fromJson({
        'v': 999,
        'profile': {'prizes': 2},
        'raid': {'garbage': true},
      });
      expect(g.profile.prizesTotal, 2);
      expect(g.raid, isNull);
    });
  });
}
