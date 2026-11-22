import 'rng.dart';

/// Game content as data. Balancing changes belong here, not in the rules.
///
/// All values are the prototype's starting values from the design document.

// ---------------------------------------------------------------- player ship

const String playerShipName = 'The Uncollapsed';
const int playerHull = 30;
const int playerSystems = 3;
const int ratingMax = 3;
const int baseProbes = 3;
const double baseKickChance = 0.30;
const double shieldedKickChance = 0.15;

/// Share of cargo paid when the enemy is destroyed rather than disabled.
const double salvageShare = 0.4;

// ---------------------------------------------------------------- factions

enum Tactic { guild, federation, corp, mercenary, defence, police, wild }

enum FactionId { guild, federation, corp, hunters, defence, police, corsairs }

class Faction {
  const Faction({
    required this.id,
    required this.name,
    required this.shipName,
    required this.shipClass,
    required this.hull,
    required this.systems,
    required this.beam,
    required this.barrier,
    required this.loot,
    required this.tactic,
    required this.habit,
  });

  final FactionId id;
  final String name;
  final String shipName;
  final String shipClass;
  final int hull;
  final int systems;
  final int beam;
  final int barrier;

  /// Cargo for a trader, bounty for a protector.
  final int loot;
  final Tactic tactic;

  /// What the player is told about how this faction fights.
  final String habit;
}

const Map<FactionId, Faction> factions = {
  FactionId.guild: Faction(
    id: FactionId.guild,
    name: 'Merchants Guild',
    shipName: "Kepler's Purse",
    shipClass: 'Freighter',
    hull: 24,
    systems: 3,
    beam: 0,
    barrier: 2,
    loot: 800,
    tactic: Tactic.guild,
    habit:
        'Always on defence. Mostly conjugate shields while the lock holds '
        '(3 rounds in 4), otherwise held harmonics.',
  ),
  FactionId.federation: Faction(
    id: FactionId.federation,
    name: 'Trade Federation',
    shipName: "Dirac's Dividend",
    shipClass: 'Hauler',
    hull: 28,
    systems: 3,
    beam: 1,
    barrier: 2,
    loot: 1200,
    tactic: Tactic.federation,
    habit:
        'Always on defence. Leans on held harmonics (3 rounds in 5), with '
        'conjugate shields the rest of the time.',
  ),
  FactionId.corp: Faction(
    id: FactionId.corp,
    name: 'Corp Fleet',
    shipName: "Planck's Margin",
    shipClass: 'Bulk carrier',
    hull: 32,
    systems: 4,
    beam: 1,
    barrier: 3,
    loot: 2000,
    tactic: Tactic.corp,
    habit:
        'Always on defence, behind the tallest barriers in the sector. '
        'Splits evenly between held harmonics and conjugate shields.',
  ),
  FactionId.hunters: Faction(
    id: FactionId.hunters,
    name: 'Bounty Hunters',
    shipName: 'Heisenberg',
    shipClass: 'Cruiser',
    hull: 30,
    systems: 3,
    beam: 2,
    barrier: 1,
    loot: 400,
    tactic: Tactic.mercenary,
    habit:
        'Strategic. They study your last three tunings and the forecast, '
        'then fire the best counter. About one round in five they bluff.',
  ),
  FactionId.defence: Faction(
    id: FactionId.defence,
    name: 'Planetary Defence Force',
    shipName: 'Born Rule',
    shipClass: 'Corvette',
    hull: 28,
    systems: 3,
    beam: 2,
    barrier: 0,
    loot: 300,
    tactic: Tactic.defence,
    habit:
        'Always attacks. Mostly a tunnelling lance, sometimes a '
        'phase-shifted lance, and a plain lance in a storm.',
  ),
  FactionId.police: Faction(
    id: FactionId.police,
    name: 'Corp Police',
    shipName: 'Pauli Exclusion',
    shipClass: 'Interceptor',
    hull: 36,
    systems: 4,
    beam: 3,
    barrier: 2,
    loot: 600,
    tactic: Tactic.police,
    habit:
        'Each captain is either drilled like the Defence Force or hired '
        'from the Bounty Hunters. You are not told which.',
  ),
  FactionId.corsairs: Faction(
    id: FactionId.corsairs,
    name: 'Rival Corsairs',
    shipName: "Schrödinger's Wake",
    shipClass: 'Raider',
    hull: 30,
    systems: 3,
    beam: 1,
    barrier: 1,
    loot: 1000,
    tactic: Tactic.wild,
    habit:
        'Wildcards. Any of the four tunings, picked on a whim, storm or '
        'no storm. Nobody comes to their rescue.',
  ),
};

// ---------------------------------------------------------------- lanes

class Lane {
  const Lane(this.trade, this.guard, {this.unlockLevel = 0});
  final FactionId trade;
  final FactionId? guard;

  /// Progression level at which the lane opens on the sector chart.
  final int unlockLevel;
}

const List<Lane> lanes = [
  Lane(FactionId.guild, FactionId.hunters),
  Lane(FactionId.federation, FactionId.defence, unlockLevel: 1),
  Lane(FactionId.corp, FactionId.police, unlockLevel: 3),
  Lane(FactionId.corsairs, null, unlockLevel: 2),
];

// ---------------------------------------------------------------- weather

enum Weather {
  calm(
    'Calm void',
    85,
    100,
    'The Bell-lock is holding. Phase tricks work as tuned.',
  ),
  front(
    'Decoherence front',
    45,
    90,
    'Stray fields are fraying the lock. Phase tricks may misfire, and a storm may follow.',
  ),
  storm(
    'Coherence storm',
    0,
    35,
    'The lock has collapsed. Phases wash out, so only lance power counts.',
  );

  const Weather(this.label, this.minPercent, this.maxPercent, this.description);

  final String label;
  final int minPercent;
  final int maxPercent;
  final String description;

  /// What the enemy AI plans against.
  double get midpoint => (minPercent + maxPercent) / 200;

  /// "Calm" in the faction rules means the forecast midpoint is at least 50%.
  bool get lockHolds => midpoint >= 0.5;

  Weather next(Rng rng) {
    final r = rng.nextDouble();
    switch (this) {
      case Weather.calm:
        return r < 0.28 ? Weather.front : Weather.calm;
      case Weather.front:
        return r < 0.7 ? Weather.storm : Weather.calm;
      case Weather.storm:
        return r < 0.4 ? Weather.storm : Weather.calm;
    }
  }

  /// Actual fidelity for a round, in whole percent.
  int drawPercent(Rng rng) =>
      (minPercent + rng.nextDouble() * (maxPercent - minPercent)).round();
}

// ---------------------------------------------------------------- refits

enum Upgrade {
  beam('Beam energy', 'Adds to the damage your lance deals.', 2),
  barrier('Barrier height', 'Cuts the damage you take while shield-side.', 2),
  probeRack('Spare probe rack', 'One more probe per battle.', 2),
  shieldedProbe(
    'Shielded probe',
    'Back-action chance falls from 30% to 15%.',
    1,
  );

  const Upgrade(this.label, this.description, this.maxLevel);

  final String label;
  final String description;

  /// Levels you can buy on top of the starting ship.
  final int maxLevel;

  /// Price of the next level when [owned] levels are already fitted.
  int cost(int owned) {
    switch (this) {
      case Upgrade.beam:
      case Upgrade.barrier:
        return 400 * (owned + 1);
      case Upgrade.probeRack:
        return 300 * (owned + 1);
      case Upgrade.shieldedProbe:
        return 700;
    }
  }
}

// ---------------------------------------------------------------- unlocks

/// Teaching order. Each level unlocks after one more prize taken in total.
enum Unlock {
  classic(0, 'Hold harmonics and tunnelling lance'),
  conjugate(1, 'Conjugate shields: the first phase trick'),
  phaseLance(2, 'Phase-shifted lance: the cycle is complete'),
  probe(3, 'The probe: read their emitter, at a price'),
  dials(4, 'Manual emitter dials');

  const Unlock(this.level, this.label);
  final int level;
  final String label;
}

const int maxUnlockLevel = 4;
