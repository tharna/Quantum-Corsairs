// Writes the reference cases compiled to IQM native gates, for
// test/qiskit_check.py to verify against Qiskit.
//
//   dart run bin/export_native.dart > test/native_vectors.json
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:qc_core/qc_core.dart';

void main() {
  final cases = <Map<String, Object?>>[];
  void add(Tuning a, Tuning b, double f) {
    cases.add({
      'f': f,
      'ops': [
        for (final o in compileRound(a, b, f))
          {
            'name': o.name,
            'qubits': [o.qubit, ?o.other],
            if (o.name == 'prx') 'angle': o.angle,
            if (o.name == 'prx') 'phase': o.phase,
          },
      ],
      'p': outcomeProbabilities(a, b, f),
    });
  }

  for (final f in [0.0, 0.6, 1.0]) {
    for (final a in TuningPreset.values) {
      for (final b in TuningPreset.values) {
        add(a.tuning, b.tuning, f);
      }
    }
  }
  final rng = math.Random(7);
  for (var i = 0; i < 20; i++) {
    Tuning t() => Tuning(
      rng.nextDouble() * math.pi,
      rng.nextDouble() * math.pi / 2,
      rng.nextDouble() * math.pi / 2,
    );
    add(t(), t(), rng.nextDouble());
  }
  stdout.writeln(const JsonEncoder.withIndent(' ').convert(cases));
}
