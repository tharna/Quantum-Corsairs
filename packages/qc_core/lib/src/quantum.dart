import 'dart:math' as math;

/// The four preset tunings. At full Bell-lock each beats exactly one other.
enum TuningPreset {
  hold(
    'Hold harmonics',
    'no gate',
    '|0⟩',
    0,
    0,
    0,
    'Shields at rest phase. A phase-shifted lance breaks against them.',
  ),
  lance(
    'Tunnelling lance',
    'Y gate',
    'Y|0⟩',
    math.pi,
    0,
    0,
    'All power to the lance. Punches through held harmonics.',
  ),
  conjugate(
    'Conjugate shields',
    'Z gate',
    'Z|0⟩',
    0,
    math.pi / 2,
    0,
    'Shield phase turned 90°. Throws a plain lance back at its sender.',
  ),
  phaseLance(
    'Phase-shifted lance',
    'X gate',
    'X|0⟩',
    math.pi,
    0,
    math.pi / 2,
    'Lance phase turned 90°. Slips through conjugate shields.',
  );

  const TuningPreset(
    this.label,
    this.gate,
    this.ket,
    this.theta,
    this.phi,
    this.alpha,
    this.description,
  );

  final String label;
  final String gate;
  final String ket;
  final double theta;
  final double phi;
  final double alpha;
  final String description;

  Tuning get tuning => Tuning(theta, phi, alpha, preset: this);

  /// True for the two lance tunings.
  bool get isLance => theta > math.pi / 2;
}

/// One captain's emitter setting: lance power θ (0..π), shield phase φ and
/// lance phase α (0..π/2), all in radians.
class Tuning {
  const Tuning(this.theta, this.phi, this.alpha, {this.preset});

  factory Tuning.degrees(num theta, num phi, num alpha) {
    final t = Tuning(
      theta * math.pi / 180,
      phi * math.pi / 180,
      alpha * math.pi / 180,
    );
    return t._withPresetIfMatching();
  }

  final double theta;
  final double phi;
  final double alpha;

  /// Set when this tuning is exactly one of the presets.
  final TuningPreset? preset;

  int get thetaDegrees => (theta * 180 / math.pi).round();
  int get phiDegrees => (phi * 180 / math.pi).round();
  int get alphaDegrees => (alpha * 180 / math.pi).round();

  String get label =>
      preset?.label ??
      'Manual tuning (θ $thetaDegrees°, φ $phiDegrees°, α $alphaDegrees°)';

  /// Measurement back-action of a probe: lance power is untouched and both
  /// phases are turned by 90°.
  Tuning kicked() => Tuning(
    theta,
    math.pi / 2 - phi,
    math.pi / 2 - alpha,
  )._withPresetIfMatching();

  Tuning _withPresetIfMatching() {
    for (final p in TuningPreset.values) {
      // The unused dial of a preset carries no meaning, so snap to the
      // canonical preset values. This keeps saves and equality stable.
      if (_matches(p)) return p.tuning;
    }
    return Tuning(theta, phi, alpha);
  }

  bool _matches(TuningPreset p) {
    bool near(double a, double b) => (a - b).abs() < 1e-6;
    if (!near(theta, p.theta)) return false;
    // A shield tuning ignores α and a lance tuning ignores φ, exactly as the
    // preset table says ("not used").
    if (near(theta, 0)) return near(phi, p.phi);
    if (near(theta, math.pi)) return near(alpha, p.alpha);
    return near(phi, p.phi) && near(alpha, p.alpha);
  }

  Map<String, Object?> toJson() => {
    't': theta,
    'p': phi,
    'a': alpha,
    if (preset != null) 'k': preset!.name,
  };

  static Tuning fromJson(Map<String, Object?> j) {
    final k = j['k'] as String?;
    if (k != null) return TuningPreset.values.byName(k).tuning;
    return Tuning(
      (j['t'] as num).toDouble(),
      (j['p'] as num).toDouble(),
      (j['a'] as num).toDouble(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Tuning &&
      other.theta == theta &&
      other.phi == phi &&
      other.alpha == alpha;

  @override
  int get hashCode => Object.hash(theta, phi, alpha);

  @override
  String toString() => label;
}

/// Outcome index = 2 × yourBit + theirBit, where 0 is shield-side and 1 is
/// lance-side. So 0 = |00⟩, 1 = |01⟩, 2 = |10⟩, 3 = |11⟩ in |you, them⟩ order.
enum Outcome {
  bothShield(false, false),
  theyLance(false, true),
  youLance(true, false),
  bothLance(true, true);

  const Outcome(this.youAreLance, this.theyAreLance);

  /// Your emitter collapsed lance-side.
  final bool youAreLance;

  /// Their emitter collapsed lance-side.
  final bool theyAreLance;

  String get ket => '|${youAreLance ? 1 : 0}${theyAreLance ? 1 : 0}⟩';
}

typedef _C = (double, double);

_C _mul(_C a, _C b) => (a.$1 * b.$1 - a.$2 * b.$2, a.$1 * b.$2 + a.$2 * b.$1);
_C _add(_C a, _C b) => (a.$1 + b.$1, a.$2 + b.$2);

List<List<_C>> _gate(Tuning m) {
  final c = math.cos(m.theta / 2), s = math.sin(m.theta / 2);
  return [
    [
      (math.cos(m.phi) * c, math.sin(m.phi) * c),
      (math.cos(m.alpha) * s, math.sin(m.alpha) * s),
    ],
    [
      (-math.cos(m.alpha) * s, math.sin(m.alpha) * s),
      (math.cos(m.phi) * c, -math.sin(m.phi) * c),
    ],
  ];
}

/// Bell-lock angle γ for a fidelity in [0, 1].
double gammaForFidelity(double fidelity) => fidelity * math.pi / 2;

/// Probabilities of the four [Outcome]s for one round.
///
/// |ψ⟩ = J†(U_you ⊗ U_them) J |00⟩ with J(γ) = cos(γ/2) I⊗I + i sin(γ/2) D⊗D.
/// This is the Eisert–Wilkens–Lewenstein quantum prisoner's dilemma with a
/// third dial. It matches Qiskit's ryy(γ), u(θ, π−α−φ, π+α−φ), ryy(−γ).
List<double> outcomeProbabilities(Tuning you, Tuning them, double fidelity) {
  final gamma = gammaForFidelity(fidelity);
  final c = math.cos(gamma / 2), s = math.sin(gamma / 2);
  final List<_C> start = [(c, 0), (0, 0), (0, 0), (0, s)];
  final ua = _gate(you), ub = _gate(them);
  final out = List<_C>.filled(4, (0, 0));
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      final amp = _mul(ua[i >> 1][j >> 1], ub[i & 1][j & 1]);
      out[i] = _add(out[i], _mul(amp, start[j]));
    }
  }
  final dd = <_C>[
    out[3],
    (-out[2].$1, -out[2].$2),
    (-out[1].$1, -out[1].$2),
    out[0],
  ];
  final probs = <double>[];
  for (var k = 0; k < 4; k++) {
    final f = _add((c * out[k].$1, c * out[k].$2), _mul((0, -s), dd[k]));
    probs.add(f.$1 * f.$1 + f.$2 * f.$2);
  }
  return probs;
}

/// Picks an outcome from [probs] with a uniform draw [u] in [0, 1).
Outcome sampleOutcome(List<double> probs, double u) {
  var acc = 0.0;
  for (var i = 0; i < 4; i++) {
    acc += probs[i];
    if (u < acc) return Outcome.values[i];
  }
  return Outcome.bothLance;
}

/// The round as a runnable Qiskit program, for the in-game "show circuit".
String qiskitCode(Tuning you, Tuning them, int fidelityPercent) {
  String f(double x) => (((x * 10000).round()) / 10000).toString();
  String u(Tuning m) =>
      '${f(m.theta)}, ${f(math.pi - m.alpha - m.phi)}, ${f(math.pi + m.alpha - m.phi)}';
  return [
    'from qiskit import QuantumCircuit',
    'from qiskit_aer import AerSimulator',
    '',
    'gamma = ${f(gammaForFidelity(fidelityPercent / 100))}  # Bell-lock fidelity $fidelityPercent%',
    'qc = QuantumCircuit(2)',
    'qc.ryy(gamma, 0, 1)   # Bell-lock: entangle the emitters',
    'qc.u(${u(you)}, 0)   # you: ${you.label}',
    'qc.u(${u(them)}, 1)   # them: ${them.label}',
    'qc.ryy(-gamma, 0, 1)  # undo the lock before readout',
    'qc.measure_all()',
    '',
    'sim = AerSimulator()',
    'counts = sim.run(qc, shots=1000).result().get_counts()',
    'print(counts)  # bits read "them, you"; 0 = shield, 1 = lance',
  ].join('\n');
}
