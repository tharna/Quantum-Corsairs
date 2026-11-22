import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:qc_core/qc_core.dart';
import 'package:test/test.dart';

void main() {
  void expectEquivalent(Tuning a, Tuning b, double f) {
    final ops = compileRound(a, b, f);
    final got = simulateNative(ops);
    final want = outcomeProbabilities(a, b, f);
    for (var i = 0; i < 4; i++) {
      expect(
        got[i],
        closeTo(want[i], 1e-9),
        reason: '$a vs $b at F=$f, outcome $i\n${ops.join('\n')}',
      );
    }
  }

  test('compiled circuits match the engine for every preset pairing', () {
    for (final f in [0.0, 0.35, 0.6, 0.85, 1.0]) {
      for (final a in TuningPreset.values) {
        for (final b in TuningPreset.values) {
          expectEquivalent(a.tuning, b.tuning, f);
        }
      }
    }
  });

  test('compiled circuits match the engine for random dial settings', () {
    final rng = math.Random(42);
    for (var i = 0; i < 500; i++) {
      Tuning t() => Tuning(
        rng.nextDouble() * math.pi,
        rng.nextDouble() * math.pi / 2,
        rng.nextDouble() * math.pi / 2,
      );
      expectEquivalent(t(), t(), rng.nextDouble());
    }
  });

  test('only native operations, four CZs, measurement last', () {
    final ops = compileRound(
      TuningPreset.lance.tuning,
      TuningPreset.conjugate.tuning,
      0.6,
    );
    expect(ops.map((o) => o.name).toSet(), {'prx', 'cz', 'measure'});
    expect(ops.where((o) => o.name == 'cz').length, 4);
    expect(ops.reversed.take(2).map((o) => o.key).toSet(), {youKey, themKey});
    for (final o in ops.where((o) => o.name == 'prx')) {
      expect(o.angle.isFinite && o.phase.isFinite, isTrue);
      expect(o.phase.abs(), lessThanOrEqualTo(math.pi + 1e-9));
    }
  });

  test('native_vectors.json is up to date with the compiler', () {
    // test/qiskit_check.py verifies this file against Qiskit in CI. If this
    // fails, regenerate it: dart run bin/export_native.dart > test/native_vectors.json
    final file =
        jsonDecode(File('test/native_vectors.json').readAsStringSync())
            as List<Object?>;
    final result = Process.runSync(Platform.resolvedExecutable, [
      'run',
      'bin/export_native.dart',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode(result.stdout as String), file);
  });
}
