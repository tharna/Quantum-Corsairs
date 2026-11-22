/// Seeded xorshift32 generator.
///
/// Uses only shifts, xor and 32-bit masks, so it gives the same sequence on
/// the Dart VM and when compiled to JavaScript. The whole state is one int,
/// which is stored in game saves so a battle can be resumed and replayed.
class Rng {
  /// Resumes from a [state] previously read from [Rng.state].
  Rng(int state) : _state = _normalise(state);

  /// Starts a fresh sequence from any seed. Small or similar seeds are
  /// scrambled first, so seeds 1, 2, 3 give unrelated sequences.
  Rng.seeded(int seed) : _state = _normalise(_mix(seed & 0xFFFFFFFF));

  int _state;

  /// The current state. Passing it to [Rng.new] continues the same sequence.
  int get state => _state;

  /// 32-bit multiply that stays exact when compiled to JavaScript.
  static int _imul(int a, int b) {
    final ah = (a >> 16) & 0xFFFF, al = a & 0xFFFF;
    final bh = (b >> 16) & 0xFFFF, bl = b & 0xFFFF;
    return (al * bl + ((((ah * bl) + (al * bh)) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  }

  /// MurmurHash3 finaliser.
  static int _mix(int h) {
    h ^= h >> 16;
    h = _imul(h, 0x85EBCA6B);
    h ^= h >> 13;
    h = _imul(h, 0xC2B2AE35);
    h ^= h >> 16;
    return h;
  }

  static int _normalise(int seed) {
    final s = seed & 0xFFFFFFFF;
    return s == 0 ? 0x9E3779B9 : s;
  }

  /// Next raw value in [1, 2^32).
  int nextUint32() {
    var x = _state;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _state = x & 0xFFFFFFFF;
    return _state;
  }

  /// Uniform double in [0, 1).
  double nextDouble() => nextUint32() / 4294967296.0;

  /// Uniform int in [0, max).
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max', 'must be positive');
    return (nextDouble() * max).floor();
  }

  /// True with probability [p].
  bool chance(double p) => nextDouble() < p;
}
