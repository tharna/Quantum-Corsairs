import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:qc_core/qc_core.dart';
import 'package:test/test.dart';

Tuning _parse(Map<String, Object?> j) {
  final preset = j['preset'] as String?;
  if (preset != null) return TuningPreset.values.byName(preset).tuning;
  final d = j['deg'] as List<Object?>;
  return Tuning.degrees(d[0] as num, d[1] as num, d[2] as num);
}

void main() {
  group('reference vectors', () {
    // Generated from the prototype's engine, which was checked against
    // Qiskit's Aer simulator. See test/qiskit_check.py.
    final cases =
        jsonDecode(File('test/reference_vectors.json').readAsStringSync())
            as List<Object?>;

    for (final c in cases.cast<Map<String, Object?>>()) {
      final you = _parse(c['you'] as Map<String, Object?>);
      final them = _parse(c['them'] as Map<String, Object?>);
      final f = (c['f'] as num).toDouble();
      final expected = [
        for (final x in c['p'] as List<Object?>) (x as num).toDouble(),
      ];
      test('${you.label} vs ${them.label} at F=$f', () {
        final p = outcomeProbabilities(you, them, f);
        for (var i = 0; i < 4; i++) {
          expect(p[i], closeTo(expected[i], 1e-9), reason: 'outcome $i');
        }
        expect(p.reduce((a, b) => a + b), closeTo(1, 1e-9));
      });
    }

    test('covers 16 preset pairings at full and zero fidelity', () {
      final presetCases = cases
          .cast<Map<String, Object?>>()
          .where((c) => (c['you'] as Map)['preset'] != null)
          .length;
      expect(presetCases, 32);
    });
  });

  group('design facts', () {
    final h = TuningPreset.hold.tuning;
    final l = TuningPreset.lance.tuning;
    final q = TuningPreset.conjugate.tuning;
    final x = TuningPreset.phaseLance.tuning;

    test('at full lock each preset beats exactly one other, in a cycle', () {
      // Winner is the side that is lance-side alone.
      expect(
        outcomeProbabilities(l, h, 1)[Outcome.youLance.index],
        closeTo(1, 1e-9),
      );
      expect(
        outcomeProbabilities(q, l, 1)[Outcome.youLance.index],
        closeTo(1, 1e-9),
      );
      expect(
        outcomeProbabilities(x, q, 1)[Outcome.youLance.index],
        closeTo(1, 1e-9),
      );
      expect(
        outcomeProbabilities(h, x, 1)[Outcome.youLance.index],
        closeTo(1, 1e-9),
      );
    });

    test('conjugate shields beat a lance with probability sin²γ', () {
      for (final f in [0.2, 0.5, 0.6, 0.9]) {
        final g = gammaForFidelity(f);
        expect(
          outcomeProbabilities(q, l, f)[Outcome.youLance.index],
          closeTo(math.pow(math.sin(g), 2), 1e-9),
        );
      }
    });

    test('a phase-shifted lance beats conjugate shields at every fidelity', () {
      for (var f = 0.0; f <= 1.0; f += 0.1) {
        expect(
          outcomeProbabilities(x, q, f)[Outcome.youLance.index],
          closeTo(1, 1e-9),
        );
      }
    });

    test('at zero fidelity only lance power matters', () {
      for (final a in TuningPreset.values) {
        for (final b in TuningPreset.values) {
          final p = outcomeProbabilities(a.tuning, b.tuning, 0);
          final idx = (a.isLance ? 2 : 0) + (b.isLance ? 1 : 0);
          expect(p[idx], closeTo(1, 1e-9));
        }
      }
    });
  });

  group('tunings', () {
    test('probe kick swaps hold/conjugate and lance/phase-shifted lance', () {
      expect(TuningPreset.hold.tuning.kicked().preset, TuningPreset.conjugate);
      expect(TuningPreset.conjugate.tuning.kicked().preset, TuningPreset.hold);
      expect(
        TuningPreset.lance.tuning.kicked().preset,
        TuningPreset.phaseLance,
      );
      expect(
        TuningPreset.phaseLance.tuning.kicked().preset,
        TuningPreset.lance,
      );
    });

    test('manual dials matching a preset are recognised', () {
      expect(Tuning.degrees(180, 0, 0).preset, TuningPreset.lance);
      expect(Tuning.degrees(0, 90, 45).preset, TuningPreset.conjugate);
      expect(Tuning.degrees(90, 45, 45).preset, isNull);
    });

    test('json round trip', () {
      final t = Tuning.degrees(90, 30, 60);
      expect(Tuning.fromJson(t.toJson()), t);
      expect(
        Tuning.fromJson(TuningPreset.lance.tuning.toJson()).preset,
        TuningPreset.lance,
      );
    });

    test('sampling follows the cumulative distribution', () {
      final p = [0.0, 0.65, 0.35, 0.0];
      expect(sampleOutcome(p, 0.1), Outcome.theyLance);
      expect(sampleOutcome(p, 0.7), Outcome.youLance);
      expect(sampleOutcome(p, 0.9999), Outcome.youLance);
    });

    test('qiskit code names both tunings', () {
      final code = qiskitCode(
        TuningPreset.lance.tuning,
        TuningPreset.conjugate.tuning,
        60,
      );
      expect(code, contains('qc.ryy(gamma, 0, 1)'));
      expect(code, contains('Tunnelling lance'));
      expect(code, contains('Conjugate shields'));
    });
  });

  group('damage', () {
    test('base table with zero ratings', () {
      final t = damageTable(
        youBeam: 0,
        youBarrier: 0,
        themBeam: 0,
        themBarrier: 0,
      );
      expect([t[0].toYou, t[0].toThem], [2, 2]);
      expect([t[1].toYou, t[1].toThem, t[1].systemsYou], [5, 0, 1]);
      expect([t[2].toYou, t[2].toThem, t[2].systemsThem], [0, 5, 1]);
      expect([t[3].toYou, t[3].toThem], [4, 4]);
    });

    test('ratings apply and damage never goes negative', () {
      final t = damageTable(
        youBeam: 1,
        youBarrier: 3,
        themBeam: 1,
        themBarrier: 2,
      );
      expect(t[0].toYou, 0);
      expect(t[0].toThem, 0);
      expect(t[1].toYou, 3);
      expect(t[2].toThem, 4);
      expect(t[3].toYou, 5);
      expect(t[3].toThem, 5);
    });
  });

  group('rng', () {
    test('is deterministic and resumable', () {
      final a = Rng(42);
      final first = [for (var i = 0; i < 5; i++) a.nextUint32()];
      final b = Rng(42);
      expect([for (var i = 0; i < 5; i++) b.nextUint32()], first);
      final c = Rng(42)..nextUint32();
      final d = Rng(c.state);
      expect(d.nextUint32(), first[1]);
    });

    test('stays in range', () {
      final r = Rng(7);
      for (var i = 0; i < 10000; i++) {
        final x = r.nextDouble();
        expect(x >= 0 && x < 1, isTrue);
      }
    });

    test('zero seed is usable', () {
      expect(Rng(0).nextUint32(), isNot(0));
    });
  });
}
