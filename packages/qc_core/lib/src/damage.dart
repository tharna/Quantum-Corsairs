import 'quantum.dart';

/// Hull and systems damage for one outcome.
class Damage {
  const Damage(
    this.toYou,
    this.toThem, {
    this.systemsYou = 0,
    this.systemsThem = 0,
  });

  final int toYou;
  final int toThem;
  final int systemsYou;
  final int systemsThem;

  @override
  String toString() =>
      'Damage(you −$toYou${systemsYou > 0 ? ' sys' : ''}, them −$toThem${systemsThem > 0 ? ' sys' : ''})';
}

/// Damage for each [Outcome], indexed by `outcome.index`.
///
/// Beam energy adds to the damage a ship deals when its emitter collapses
/// lance-side. Barrier height cuts the damage it takes when its emitter
/// collapses shield-side. Damage never goes below 0.
List<Damage> damageTable({
  required int youBeam,
  required int youBarrier,
  required int themBeam,
  required int themBarrier,
}) {
  int c(int x) => x < 0 ? 0 : x;
  return [
    Damage(c(2 - youBarrier), c(2 - themBarrier)),
    Damage(c(5 + themBeam - youBarrier), 0, systemsYou: 1),
    Damage(0, c(5 + youBeam - themBarrier), systemsThem: 1),
    Damage(4 + themBeam, 4 + youBeam),
  ];
}
