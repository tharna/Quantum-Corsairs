import 'package:qc_core/qc_core.dart';

/// Player-facing words that depend on game state.

/// One-line habit for the battle screen. Enemies only use tunings the
/// player has learned, so the line follows what is unlocked.
String shortHabit(FactionId f, Set<TuningPreset> allowed) {
  final conj = allowed.contains(TuningPreset.conjugate);
  final phase = allowed.contains(TuningPreset.phaseLance);
  final trade =
      f == FactionId.guild || f == FactionId.federation || f == FactionId.corp;
  if (trade && !conj) return '${factions[f]!.name} · always holds harmonics';
  if (f == FactionId.defence && !phase) {
    return 'Defence Force · always a plain lance';
  }
  return _habit(f);
}

String _habit(FactionId f) => switch (f) {
  FactionId.guild => 'Merchants Guild · conjugate shields 3 in 4',
  FactionId.federation => 'Trade Federation · holds harmonics 3 in 5',
  FactionId.corp => 'Corp Fleet · splits shields evenly',
  FactionId.hunters => 'Bounty Hunters · counter your last three',
  FactionId.defence => 'Defence Force · always attacks',
  FactionId.police => 'Corp Police · drilled or hired, unknown',
  FactionId.corsairs => 'Rival Corsairs · no pattern',
};

String orderHint(TuningPreset p) => switch (p) {
  TuningPreset.hold => 'Breaks a phase-shifted lance',
  TuningPreset.lance => 'Punches through held harmonics',
  TuningPreset.conjugate => 'Throws a plain lance back',
  TuningPreset.phaseLance => 'Slips through conjugate shields',
};

/// Headline for a collapse report.
String verdictTitle(RoundReport r) {
  final p = r.probabilities[r.outcome.index];
  switch (r.outcome) {
    case Outcome.youLance:
      return p < 0.5 ? 'Against the odds' : 'Clean through';
    case Outcome.theyLance:
      return p < 0.5 ? 'Unlucky collapse' : 'Hull breached';
    case Outcome.bothShield:
      return 'Volleys scatter';
    case Outcome.bothLance:
      return 'Broadside';
  }
}

String verdictText(RoundReport r, String foe) {
  final d = r.damage;
  final storm = r.fidelityPercent < 50;
  final lockNote = storm
      ? 'With the lock at ${r.fidelityPercent}%, phase did almost nothing. '
      : '';
  switch (r.outcome) {
    case Outcome.bothShield:
      return '$lockNote${'Both emitters collapsed shield-side. The volleys scatter off the barriers: you take ${d.toYou}, the $foe takes ${d.toThem}.'}';
    case Outcome.theyLance:
      return '$lockNote${'The state collapsed to |01⟩. Their lance tunnels through: you lose ${d.toYou} hull and a system.'}';
    case Outcome.youLance:
      return '$lockNote${'The state collapsed to |10⟩. Your lance tunnels through: the $foe loses ${d.toThem} hull and a system.'}';
    case Outcome.bothLance:
      return '$lockNote${'Both lances fire with barriers down. You take ${d.toYou}, the $foe takes ${d.toThem}.'}';
  }
}

String battleEndText(BattleState b, int loot) {
  final f = b.faction;
  switch (b.result) {
    case BattleResult.enemyDisabled:
      return 'The ${f.shipName} is dark in the water. You board her and take the full ${b.payout} credits.';
    case BattleResult.enemyDestroyed:
      return 'The ${f.shipName} breaks apart. You salvage ${b.payout} of her ${f.loot} credits from the wreck.';
    case BattleResult.playerDestroyed:
      return '$playerShipName breaks apart. The raid ends with $loot credits banked.';
    case BattleResult.playerDisabled:
      return 'Your systems are dark and the ${f.shipName} has you in a tractor beam. The raid ends with $loot credits banked.';
    case BattleResult.ongoing:
      return '';
  }
}

/// Onboarding notes, in the order they are offered. Each shows once.
class Hint {
  const Hint(this.id, this.text);
  final String id;
  final String text;
}

Hint? battleHint(BattleState b, Profile p, bool Function(String) seen) {
  final hints = <Hint>[
    if (p.prizesTotal == 0)
      const Hint(
        'first-battle',
        'Your emitter and theirs are Bell-locked. Pick a tuning: a lone lance hits hard, but two lances hurt you both.',
      ),
    if (p.has(Unlock.conjugate))
      const Hint(
        'unlock-conjugate',
        'New: conjugate shields turn a plain lance back at its sender, while the lock holds.',
      ),
    if (p.has(Unlock.phaseLance))
      const Hint(
        'unlock-phaseLance',
        'New: a phase-shifted lance slips through conjugate shields. The cycle is complete.',
      ),
    if (p.has(Unlock.probe))
      const Hint(
        'unlock-probe',
        'New: a probe reads their planned tuning. Its back-action may turn their phase.',
      ),
    if (p.has(Unlock.dials))
      const Hint(
        'unlock-dials',
        'New: manual dials. Any single-qubit gate is yours to tune.',
      ),
    if (b.weather == Weather.storm)
      const Hint(
        'storm',
        'Coherence storm: no entanglement, so phase does nothing. Only lance power counts.',
      ),
  ];
  for (final h in hints) {
    if (!seen(h.id)) return h;
  }
  return null;
}

const glossary = <(String, String)>[
  (
    'Emitter',
    'One qubit per ship. Until it fires it is in a superposition of a shield state |0⟩ and a lance state |1⟩.',
  ),
  (
    'Bell-lock',
    'Entanglement. Locking on ties the two emitters into one shared state, so your tuning changes what their emitter does.',
  ),
  (
    'Lance power θ',
    'A rotation of the qubit between |0⟩ and |1⟩. It sets the odds of collapsing lance-side.',
  ),
  (
    'Shield phase φ, lance phase α',
    'The qubit\'s phase. It changes no odds on its own; through the Bell-lock it makes the two tunings interfere.',
  ),
  (
    'Collapse',
    'Measurement. Each round is measured once, at the odds shown in the grid.',
  ),
  (
    'Beam energy, barrier height',
    'Borrowed from quantum tunnelling: higher energy and lower barriers both make it easier to get through.',
  ),
  (
    'Probe scan',
    'Measurement back-action. Reading lance power disturbs the phase, the property the probe did not measure.',
  ),
  (
    'Coherence storm',
    'Decoherence. Outside noise breaks the entanglement, phase has nothing to interfere with, and the fight turns classical.',
  ),
];
