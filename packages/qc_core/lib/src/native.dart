import 'dart:math' as math;

import 'quantum.dart';

/// One operation in IQM's native gate set.
///
/// * `prx(angle, phase)` = exp(−i (X cos φ + Y sin φ) θ/2), angles in radians.
/// * `cz` on two qubits.
/// * `measure` in the Z basis, labelled with a key.
///
/// Qubits are logical: 0 is your emitter, 1 is theirs. A hardware client maps
/// them to physical qubit names.
class NativeOp {
  const NativeOp.prx(this.qubit, this.angle, this.phase)
    : name = 'prx',
      other = null,
      key = null;
  const NativeOp.cz(this.qubit, int this.other)
    : name = 'cz',
      angle = 0,
      phase = 0,
      key = null;
  const NativeOp.measure(this.qubit, String this.key)
    : name = 'measure',
      other = null,
      angle = 0,
      phase = 0;

  final String name;
  final int qubit;
  final int? other;
  final double angle;
  final double phase;
  final String? key;

  @override
  String toString() => switch (name) {
    'prx' =>
      'prx(q$qubit, θ=${angle.toStringAsFixed(4)}, φ=${phase.toStringAsFixed(4)})',
    'cz' => 'cz(q$qubit, q$other)',
    _ => 'measure(q$qubit → $key)',
  };
}

/// Measurement keys used by [compileRound].
const String youKey = 'you';
const String themKey = 'them';

// ------------------------------------------------------------ 2×2 complex math

typedef _C = (double, double);
typedef _M = (_C, _C, _C, _C); // row-major a, b, c, d

_C _mul(_C a, _C b) => (a.$1 * b.$1 - a.$2 * b.$2, a.$1 * b.$2 + a.$2 * b.$1);
_C _add(_C a, _C b) => (a.$1 + b.$1, a.$2 + b.$2);
_C _exp(double t) => (math.cos(t), math.sin(t));
double _abs(_C a) => math.sqrt(a.$1 * a.$1 + a.$2 * a.$2);
double _arg(_C a) => math.atan2(a.$2, a.$1);

/// Matrix product m · n (n is applied first).
_M _mm(_M m, _M n) => (
  _add(_mul(m.$1, n.$1), _mul(m.$2, n.$3)),
  _add(_mul(m.$1, n.$2), _mul(m.$2, n.$4)),
  _add(_mul(m.$3, n.$1), _mul(m.$4, n.$3)),
  _add(_mul(m.$3, n.$2), _mul(m.$4, n.$4)),
);

const _M _identity = ((1, 0), (0, 0), (0, 0), (1, 0));

_M _rx(double t) => (
  (math.cos(t / 2), 0),
  (0, -math.sin(t / 2)),
  (0, -math.sin(t / 2)),
  (math.cos(t / 2), 0),
);
_M _rz(double t) => (_exp(-t / 2), (0, 0), (0, 0), _exp(t / 2));
const _M _h = (
  (math.sqrt1_2, 0),
  (math.sqrt1_2, 0),
  (math.sqrt1_2, 0),
  (-math.sqrt1_2, 0),
);

/// The game's tuning gate, as in [outcomeProbabilities].
_M _tuning(Tuning m) {
  final c = math.cos(m.theta / 2), s = math.sin(m.theta / 2);
  return (
    (math.cos(m.phi) * c, math.sin(m.phi) * c),
    (math.cos(m.alpha) * s, math.sin(m.alpha) * s),
    (-math.cos(m.alpha) * s, math.sin(m.alpha) * s),
    (math.cos(m.phi) * c, -math.sin(m.phi) * c),
  );
}

/// ZYZ decomposition: U = e^{iα} Rz(a) Ry(b) Rz(c). Returns (a, b, c).
///
/// With p_ij the phase of each entry (using −u01), a = p11 − p01 and
/// c = p11 − p10 exactly. Reading a and c directly, rather than a + c and
/// a − c, keeps any 2π ambiguity a global phase.
(double, double, double) _zyz(_M u) {
  final b = 2 * math.atan2(_abs(u.$3), _abs(u.$1));
  const eps = 1e-12;
  final p00 = _arg(u.$1), p01 = _arg((-u.$2.$1, -u.$2.$2));
  final p10 = _arg(u.$3), p11 = _arg(u.$4);
  if (_abs(u.$1) <= eps) return (p10 - p01, b, 0); // only a − c is defined
  if (_abs(u.$3) <= eps) return (p11 - p00, b, 0); // only a + c is defined
  return (p11 - p01, b, p11 - p10);
}

// ------------------------------------------------------------ compiler

/// Compiles one round into native operations:
/// RYY(γ) · (U_you ⊗ U_them) · RYY(−γ), then measurement of both emitters.
///
/// RYY is built from CZ and single-qubit gates; runs of single-qubit gates
/// are merged and emitted as one `prx` each. Z rotations are tracked as
/// virtual frame changes: they commute with CZ and with the final Z-basis
/// measurement, so they never become physical pulses.
List<NativeOp> compileRound(Tuning you, Tuning them, double fidelity) {
  final gamma = gammaForFidelity(fidelity);
  // Time-ordered steps: a 1-qubit matrix on a qubit, or a CZ.
  final steps = <(int, _M)?>[]; // null = CZ
  void one(int q, _M m) => steps.add((q, m));
  void cz() => steps.add(null);

  // RYY(g) = (V†⊗V†) RZZ(g) (V⊗V) with V = Rx(π/2), since V Y V† = Z.
  // RZZ(g) = CNOT (I⊗Rz(g)) CNOT and CNOT = (I⊗H) CZ (I⊗H).
  void ryy(double g) {
    one(0, _rx(math.pi / 2));
    one(1, _rx(math.pi / 2));
    one(1, _h);
    cz();
    one(1, _h);
    one(1, _rz(g));
    one(1, _h);
    cz();
    one(1, _h);
    one(0, _rx(-math.pi / 2));
    one(1, _rx(-math.pi / 2));
  }

  ryy(gamma);
  one(0, _tuning(you));
  one(1, _tuning(them));
  ryy(-gamma);

  final ops = <NativeOp>[];
  final pending = [_identity, _identity];
  final frame = [0.0, 0.0];

  void flush(int q) {
    final u = pending[q];
    pending[q] = _identity;
    final (a, b, c) = _zyz(u);
    // u · Rz(f) = Rz(a) Ry(b) Rz(c + f) = Rz(a + t) · PRX(b, π/2 − t), t = c + f.
    final t = c + frame[q];
    if (b.abs() > 1e-12) ops.add(NativeOp.prx(q, b, _wrap(math.pi / 2 - t)));
    frame[q] = _wrap(a + t);
  }

  for (final s in steps) {
    if (s == null) {
      flush(0);
      flush(1);
      ops.add(const NativeOp.cz(0, 1));
    } else {
      pending[s.$1] = _mm(s.$2, pending[s.$1]);
    }
  }
  flush(0);
  flush(1);
  ops
    ..add(const NativeOp.measure(0, youKey))
    ..add(const NativeOp.measure(1, themKey));
  return ops;
}

double _wrap(double x) {
  final t = 2 * math.pi;
  var y = x % t;
  if (y > math.pi) y -= t;
  return y;
}

// ------------------------------------------------------------ simulator

/// Ideal outcome probabilities of a native circuit on two qubits starting in
/// |00⟩, indexed like [Outcome]: 2 × bit(qubit 0) + bit(qubit 1).
List<double> simulateNative(List<NativeOp> ops) {
  var psi = <_C>[(1, 0), (0, 0), (0, 0), (0, 0)];
  for (final op in ops) {
    if (op.name == 'cz') {
      psi[3] = (-psi[3].$1, -psi[3].$2);
    } else if (op.name == 'prx') {
      final c = math.cos(op.angle / 2), s = math.sin(op.angle / 2);
      // PRX = [[c, −i s e^{−iφ}], [−i s e^{iφ}, c]]
      final _M g = (
        (c, 0),
        _mul((0, -s), _exp(-op.phase)),
        _mul((0, -s), _exp(op.phase)),
        (c, 0),
      );
      final next = List<_C>.filled(4, (0, 0));
      for (var i = 0; i < 4; i++) {
        final bit = op.qubit == 0 ? (i >> 1) & 1 : i & 1;
        final partner = op.qubit == 0 ? i ^ 2 : i ^ 1;
        final i0 = bit == 0 ? i : partner, i1 = bit == 0 ? partner : i;
        final row = bit == 0 ? (g.$1, g.$2) : (g.$3, g.$4);
        next[i] = _add(_mul(row.$1, psi[i0]), _mul(row.$2, psi[i1]));
      }
      psi = next;
    }
  }
  return [for (final a in psi) a.$1 * a.$1 + a.$2 * a.$2];
}
