# Quantum Corsairs: Concept Design Document

Nov 22, 2026 · @Janne

## Overview

Quantum Corsairs is a turn-based mobile duelling game in which a space pirate fights other ships using real two-qubit quantum mechanics, presented as weapon and shield tuning.

| Item | Decision |
| --- | --- |
| Genre | Single-player, turn-based tactics with a roguelite raid structure |
| Platforms | Android and iOS, portrait, playable one-handed and offline |
| Business model | Free to play |
| Technology | Flutter, one codebase for both platforms |
| Session length | One battle is 7 to 8 rounds in simulation, a few minutes of play. A raid is several battles. |
| Audience | Strategy and puzzle players, and the science-curious. No physics knowledge is needed. |
| Status | A playable [web prototype](https://claude.ai/artifact/H5tjWnVeGoevgpkMFhyhQ6) implements the battle system, weather, probe, refits and seven factions. |

### Design pillars

1. **Real physics underneath.** Every outcome comes from an actual two-qubit circuit. The same circuit runs unchanged in Qiskit.
2. **Read the enemy, not the manual.** Each faction has a habit the player learns and exploits.
3. **Uncertainty is the fun.** Each round is measured once, storms change the rules, and scanning disturbs what it scans.
4. **Technobabble that is true.** Every invented term maps to one real quantum principle.

All balance numbers in this document come from the prototype. They are starting values and have not been playtested with people.

## Setting and fantasy

The player captains the pirate starship *The Uncollapsed* and raids shipping lanes for loot.

Ships in this setting fight with an **emitter**: a device that sits in a blend of a shield state and a lance state until the moment it fires. When two ships lock on to each other, their emitters become linked through a **Bell-lock**. From then on, how one captain tunes an emitter changes what the other emitter does.

The fantasy is being the clever captain who wins by tuning, bluffing and reading the weather, against ships with heavier hulls. A pirate wants cargo, so disabling a ship and boarding it pays more than blowing it up.

The tone is swashbuckling with deadpan technical jargon. The jargon is never nonsense: see the glossary under Art, audio and tone.

## Core loop

The loop is pick a prize, beat the trader, deal with its protector, upgrade.

1. **Pick a target.** At port the player chooses a trade lane, seeing the trader, its cargo and the protector that will answer.
2. **Fight the trader.** Rounds repeat until one ship is destroyed or disabled.
3. **Take the loot.** A disabled ship pays its full cargo. A destroyed ship pays 40% as salvage.
4. **Face the protector or run.** The player fights the protector with damage carried over, or jettisons half the cargo and escapes.
5. **Repair and upgrade.** Back at port the ship is repaired, and loot buys refits before the next target.

The prototype implements all five steps in a simple form: a port screen with four targets and two refits. The fuller version is described under Progression and economy.

## Battle system

A battle is a series of simultaneous-choice rounds between two ships, each with a hull and a set of systems.

### Ship stats

- **Hull**: hit points. At 0 the ship is destroyed.
- **Systems**: a small number of pips. At 0 the ship is disabled.
- **Beam energy**: weapon power. It adds to the damage a ship deals when its emitter collapses lance-side.
- **Barrier height**: shield power. It cuts the damage a ship takes when its emitter collapses shield-side.
- The player's ship starts with 30 hull, 3 systems, beam energy 1 and barrier height 1.
- Beam energy and barrier height vary by faction and the player can upgrade both, up to 3.

### Round sequence

1. The game shows the coherence forecast for the round as a range.
2. The enemy secretly commits to a tuning. It never sees the player's choice for the round.
3. The player may fire one probe to read the enemy tuning.
4. The player picks a tuning.
5. The actual Bell-lock fidelity is drawn at random from the forecast range.
6. The engine computes the chance of each of four outcomes and samples one.
7. Damage is applied and the collapse report is shown.
8. If neither ship is down, the weather advances and the next round starts.

### The four tunings

At full Bell-lock, each tuning beats exactly one other, in a cycle.

| Tuning | Quantum gate | Lance power θ | Shield phase φ | Lance phase α | Beats |
| --- | --- | --- | --- | --- | --- |
| Hold harmonics | none | 0° | 0° | not used | Phase-shifted lance |
| Tunnelling lance | Y | 180° | not used | 0° | Hold harmonics |
| Conjugate shields | Z | 0° | 90° | not used | Tunnelling lance |
| Phase-shifted lance | X | 180° | not used | 90° | Conjugate shields |

The remaining pairings are symmetric at full Bell-lock. Damage figures here are before ratings:

- Hold harmonics against conjugate shields: both ships take 4.
- Tunnelling lance against phase-shifted lance: both ships take 2.
- The same shield tuning on both sides: both take 2. The same lance tuning on both sides: both take 4.

As the Bell-lock weakens, phase matters less. At zero, both shield tunings behave as plain shields and both lances as a plain lance, and the lance wins.

### Manual tuning

The player can set the three dials directly instead of using a preset: lance power θ from 0° to 180°, shield phase φ and lance phase α from 0° to 90°. Together the dials describe any single-qubit gate, so presets are four points in a continuous space.

### Outcomes and damage

Each emitter collapses shield-side or lance-side, giving four outcomes.

| Your emitter | Their emitter | Hull damage to you | Hull damage to them |
| --- | --- | --- | --- |
| Shield-side | Shield-side | 2 − your barrier | 2 − their barrier |
| Lance-side | Shield-side | none | 5 + your beam − their barrier, and 1 system |
| Shield-side | Lance-side | 5 + their beam − your barrier, and 1 system | none |
| Lance-side | Lance-side | 4 + their beam | 4 + your beam |

Damage is never below 0. A barrier only helps a ship whose emitter collapsed shield-side, and beam energy only helps one that collapsed lance-side. With both ratings at 0 the table is 2 and 2, 5 and none, 4 and 4.

This is a prisoner's dilemma written as damage: going lance-side alone is best, both going lance-side is worse for both than both staying shield-side.

### Ending a battle

- Enemy systems at 0 with hull remaining: the enemy is disabled and the player takes the full cargo.
- Enemy hull at 0: the enemy is destroyed and the player salvages 40% of the cargo.
- Player hull or systems at 0: the raid ends. This applies even if the enemy goes down in the same round.

## Quantum model

The engine simulates two qubits exactly, which takes four complex numbers and a few dozen multiplications per round.

The model is the quantum prisoner's dilemma of Eisert, Wilkens and Lewenstein (1999), extended with a third dial so that every tuning has a counter.

### State

The state has four amplitudes, indexed as 2 × your bit + their bit. A bit of 0 is shield-side and 1 is lance-side. Both emitters start at 0.

### Bell-lock (entangling gate)

Bell-lock fidelity F runs from 0 to 1 and sets the angle γ = F × π/2.

```latex
J(\gamma) = \cos\tfrac{\gamma}{2}\, I \otimes I + i \sin\tfrac{\gamma}{2}\, D \otimes D, \qquad D = \begin{pmatrix} 0 & 1 \\ -1 & 0 \end{pmatrix}
```

### Tuning gate

Each captain applies one gate to their own qubit, set by the three dials.

```latex
U(\theta,\phi,\alpha) = \begin{pmatrix} e^{i\phi}\cos\tfrac{\theta}{2} & e^{i\alpha}\sin\tfrac{\theta}{2} \\ -e^{-i\alpha}\sin\tfrac{\theta}{2} & e^{-i\phi}\cos\tfrac{\theta}{2} \end{pmatrix}
```

### Outcome probabilities

The lock is applied, both captains apply their gates, the lock is undone, and both qubits are measured once.

```latex
|\psi\rangle = J^{\dagger}\,\bigl(U_{\text{you}} \otimes U_{\text{them}}\bigr)\, J\, |00\rangle, \qquad P(k) = |\psi_k|^2
```

The engine samples one outcome k from the four probabilities using a seeded random number generator.

### Qiskit equivalence

The prototype's maths was checked against Qiskit's Aer simulator and matched.

- The Bell-lock J(γ) is the `ryy(gamma)` gate, and its inverse is `ryy(-gamma)`.
- The tuning gate is `u(theta, pi - alpha - phi, pi + alpha - phi)`, up to a global phase.
- Qiskit prints result bits in the order "them, you".

### Facts useful for balancing

- Conjugate shields against a tunnelling lance win with probability sin²γ. The break-even point is 50% fidelity.
- A phase-shifted lance beats conjugate shields at every fidelity.
- At zero fidelity only lance power θ affects the outcome.

### Implementation notes

- Build the engine as a pure function: two tunings and a fidelity in, four probabilities out.
- Keep reference test vectors: the 16 preset pairings at full and zero fidelity, plus a few random dial settings checked against Qiskit.
- Use a seeded generator for the fidelity draw and the outcome sample, so battles can be replayed and tested.

## Coherence weather

Weather sets how strong the Bell-lock is each round, which decides whether phase tricks work or raw lance power wins.

| Weather | Bell-lock fidelity range | Next round |
| --- | --- | --- |
| Calm void | 85% to 100% | 28% chance of a decoherence front, otherwise calm |
| Decoherence front | 45% to 90% | 70% chance of a storm, otherwise calm |
| Coherence storm | 0% to 35% | 40% chance the storm continues, otherwise calm |

- Every battle starts in calm void.
- The player sees the range before choosing. The actual value is drawn uniformly from the range after both sides commit.
- The forecast bar marks 50%, the point below which conjugate shields stop beating a lance.
- Enemy AI sees the same forecast as the player and uses the midpoint of the range.

The real principle is decoherence: outside noise disturbs the qubits and destroys their entanglement. Without entanglement, phase has nothing to interfere with and the game becomes the classical dilemma.

Weather tables can vary by sector in the full game, for example a nebula where fronts are common.

## Probe scan

A probe shows the enemy's committed tuning for the round, at the risk of changing it.

- The player has 3 probes per battle and may use one per round, before giving orders.
- The probe reads lance power exactly, so shields-or-lance is always correct.
- With 30% probability the probe's back-action turns both enemy phases by 90°: φ becomes 90° − φ and α becomes 90° − α.
- For presets this swaps hold harmonics with conjugate shields, and tunnelling lance with phase-shifted lance.
- The readout shows the tuning as planned before any kick. The collapse report after the shot says whether the probe changed it.

The real principle is measurement back-action: measuring one property of a quantum system disturbs the properties that were not measured.

Probe count and kick chance are the two balance levers, and both are natural upgrade targets.

## Factions and enemy AI

Seven factions each play one clear strategy. Three trade factions carry the loot, and each is paired with a defence faction that answers its distress call. The Rival Corsairs stand alone.

### Trade and defence pairs

| Trade faction | Cargo | Protected by | Bounty on the protector |
| --- | --- | --- | --- |
| Merchants Guild | 800 cr | Bounty Hunters | 400 cr |
| Trade Federation | 1,200 cr | Planetary Defence Force | 300 cr |
| Corp Fleet | 2,000 cr | Corp Police | 600 cr |
| Rival Corsairs | 1,000 cr | nobody | none |

The Corp Fleet pays best and has the tallest barriers. Its Corp Police are the most advanced ships in the game.

### How a raid on a trader plays

1. The player attacks the trade ship.
2. On a win, the trader's distress call brings its protector. There is no time to repair.
3. The player either stands and fights, with hull and systems damage carried over, or jettisons half of that trader's cargo and runs.
4. The player returns to port, where the ship is fully repaired and can be refitted.

### Ship stats

| Faction | Ship | Hull | Systems | Beam energy | Barrier height | Strategy |
| --- | --- | --- | --- | --- | --- | --- |
| Merchants Guild | Freighter *Kepler's Purse* | 24 | 3 | 0 | 2 | Always on defence |
| Trade Federation | Hauler *Dirac's Dividend* | 28 | 3 | 1 | 2 | Always on defence |
| Corp Fleet | Bulk carrier *Planck's Margin* | 32 | 4 | 1 | 3 | Always on defence |
| Bounty Hunters | Cruiser *Heisenberg* | 30 | 3 | 2 | 1 | Strategic |
| Planetary Defence Force | Corvette *Born Rule* | 28 | 3 | 2 | 0 | Always attacks |
| Corp Police | Interceptor *Pauli Exclusion* | 36 | 4 | 3 | 2 | Defence Force or mercenary tactics, by captain |
| Rival Corsairs | Raider *Schrödinger's Wake* | 30 | 3 | 1 | 1 | Wildcards |

### Exact rules

"Calm" below means the midpoint of the forecast range is 50% or higher.

- **Trade factions.** Shield tunings only. Outside calm they all hold harmonics. In calm they differ in how often they use conjugate shields: Merchants Guild 75%, Trade Federation 40%, Corp Fleet 50%. The rest of the time they hold harmonics.
- **Planetary Defence Force.** Lance tunings only. In calm: tunnelling lance 70%, phase-shifted lance 30%. Otherwise: tunnelling lance.
- **Bounty Hunters (mercenary tactics).** 20% of rounds: a random preset. Otherwise: the preset that scores best against the player's last three tunings at the forecast midpoint, where score is expected damage dealt minus damage taken. In round one: conjugate shields in calm, tunnelling lance otherwise.
- **Corp Police.** Each ship's captain is assigned at random, 50/50, when the battle starts: Defence Force tactics or mercenary tactics. The captain keeps that style for the whole battle and the player is not told which it is.
- **Rival Corsairs.** One of the four presets, uniformly at random, in any weather.

### Intended counterplay

- **Trade factions.** A phase-shifted lance beats conjugate shields and a tunnelling lance beats held harmonics. The Guild and Federation lean one way, so play the odds. The Corp Fleet splits evenly, so a probe is worth spending.
- **Defence Force.** Conjugate shields in calm, with hold harmonics when a probe shows a phase-shifted lance. Match lances in storms.
- **Bounty Hunters.** Vary tunings so the last three give no clear counter, or predict the counter they will pick and beat that.
- **Corp Police.** Use the first rounds and a probe to identify the captain. A shield tuning from the police means a mercenary captain, because Defence Force drill never uses one.
- **Corsairs.** No pattern to read, so probes and forecast odds carry the fight.
- **Fight or run.** After a costly win against a trader, giving up half the cargo can be the better choice.

### Simulation check

These figures are from 1,500 simulated raids per lane with the player at starting ratings, always choosing to fight the protector.

| Lane | Random player beats trader | Random player beats both | Skilled player beats trader | Skilled player beats both |
| --- | --- | --- | --- | --- |
| Merchants Guild, then Bounty Hunters | 71% | 8% | 93% | 88% |
| Trade Federation, then Defence Force | 66% | 7% | 80% | 42% |
| Corp Fleet, then Corp Police | 47% | 1% | 53% | 25% |
| Rival Corsairs | 43% | no protector | 63% | no protector |

The skilled player is a script that picks the best reply to each faction's stated habit and predicts the mercenary counter. It is also told the Corp Police captain's style, so its Corp lane figures are an upper bound. It is not an optimal player.

Two findings need design work. Mercenary tactics are too easy to out-think: the Guild lane is the easiest for a skilled player even though the Bounty Hunters are meant to be dangerous. And a random player almost never survives a protector, so running must stay an attractive option for beginners.

Future depth can come from named captains with traits and elite variants of each faction.

## Progression and economy

Everything in this section is a proposal for the full game. The prototype has a simple version: a port with two refits, a choice of four targets, and damage carried from a trader into its protector.

### Raid structure

- A raid is one run across a sector map with branching nodes: targets, ports and storm zones.
- Hull and systems damage carries over between battles within a raid.
- Ports sell repairs and upgrades for loot.
- Losing a battle ends the raid. Banked loot converts to permanent progress.

### Teaching through unlocks

The player starts with fewer options and gains them in an order that teaches the game.

1. Hold harmonics and tunnelling lance only. The player feels the classic dilemma.
2. Conjugate shields, the first phase trick.
3. Phase-shifted lance, which completes the cycle.
4. The probe.
5. Manual tuning dials.

### Upgrade examples

| Upgrade | Effect | Lever it uses |
| --- | --- | --- |
| Beam energy | +1 weapon power per level, up to 3. In the prototype: 400 cr for level 2, 800 cr for level 3. | Damage dealt lance-side |
| Barrier height | +1 shield power per level, up to 3. Same prices in the prototype. | Damage taken shield-side |
| Spare probe rack | One more probe per battle | Probe count |
| Shielded probe | Back-action chance falls from 30% to 15% | Kick chance |
| Phase stabiliser | Narrows the forecast range | Weather uncertainty |
| Reinforced hull | More hull points | Hull |
| Redundant systems | One more systems pip | Systems |
| Storm anchor | Raises Bell-lock fidelity during storms | Weather ranges |

Beam energy suits an aggressive captain who destroys ships. Barrier height suits a patient one who disables them, so the two refits also steer how much loot a raid earns.

### Longer-term hooks

- **Heat.** Attacking the Defence Force raises a wanted level, which makes Bounty Hunters appear more often.
- **Codex.** Short physics entries unlock as the player meets each mechanic.
- **Cosmetics.** Ship hulls, emitter effects and flags.

### Free-to-play model

The game is free to download and the whole campaign is playable without paying. Which revenue sources to use is still open. The candidates are:

- **Cosmetics.** Ship hulls, emitter effects, flags and collapse animations, bought directly.
- **Rewarded ads.** Optional, player-initiated, for a bonus outside battle, such as cosmetic currency or keeping more loot after a lost raid.
- **Supporter purchase.** A one-time purchase that removes ads and adds a cosmetic pack.

Proposed guardrails, to be confirmed:

- Nothing that changes battle odds is sold for money.
- No energy timers or forced waiting.
- No forced ads during a battle.
- The game stays playable offline. Ads and the shop simply do not appear without a connection.

## Mobile UX

The game is portrait, one-handed and readable at a glance, with every round's decision reachable by thumb.

### Screens

| Screen | Purpose |
| --- | --- |
| Title | Continue a raid or start a new one |
| Sector map | Choose the next target, port or route |
| Battle | The whole fight, including the collapse report as an overlay |
| Port | Repairs and upgrades |
| Codex | Faction habits and the physics behind each mechanic |
| Settings | Sound, haptics, motion, text size, handedness |

### Battle screen, top to bottom

1. Both ships with hull bars and systems pips, the enemy's faction and habit one tap away.
2. The coherence forecast: weather name and a fidelity range bar with the 50% mark.
3. The collapse grid: four outcomes with their damage, and the odds once the shot is fired.
4. The probe button with remaining count.
5. The four tuning buttons in a 2 × 2 grid in the thumb zone, with manual dials in a drawer.

### The collapse moment

This is the signature beat. On firing, the four outcome cells flicker as if undecided, then one locks in, with a haptic pulse and a hit effect on the ships. It lasts under a second and a tap skips it.

### Onboarding

- The first battle is against the Merchants Guild with two tunings and scripted prompts.
- Each new tuning or tool is introduced in the battle after it unlocks.
- No physics is explained up front. The codex is optional reading.

### Requirements

- Fully playable offline.
- Saves after every round, so a battle resumes after an interruption.
- Colour is never the only signal: the player and enemy are also told apart by position and label.
- A reduced-motion setting replaces the flicker with a plain reveal.
- Text scales with the system font size.

## Art, audio and tone

The look pairs pirate romance with instrument-panel precision, as the prototype does.

- **Palette.** Deep navy space, gold for the player, coral for enemies, cyan for quantum effects and weather.
- **Type.** A blackletter display face for ship and faction names, a monospaced face for readouts.
- **Ships.** 2D side-view silhouettes, one distinct shape per faction, facing each other.
- **Effects.** Lance beams, shield shimmer, storm static and the collapse flicker.
- **Audio.** Synth textures with shanty-like motifs, and one unmistakable sound for the collapse.

### Technobabble glossary

Each term maps to one real principle. Writers should keep new jargon to the same rule.

| Game term | Real principle |
| --- | --- |
| Emitter | A qubit in a superposition of two states until measured |
| Bell-lock | Entanglement between two qubits |
| Lance power | A rotation of the qubit that sets the odds of each result |
| Shield phase and lance phase | The qubit's phase, which changes results only through interference |
| Collapse | Measurement, with random results at the computed odds |
| Beam energy and barrier height | Quantum tunnelling: higher particle energy and a lower barrier both make it easier to get through |
| Probe scan | Measurement back-action |
| Coherence storm | Decoherence destroying entanglement |

Two names are flavour only: "tunnelling" and "conjugate" borrow from quantum tunnelling and phase-conjugate mirrors, but the gates behind them are plain qubit flips and phase flips. Likewise, beam energy and barrier height follow the idea of tunnelling, but the damage rule is simple arithmetic and not a tunnelling calculation.

## Technical approach

Build one Flutter codebase for both platforms, and keep the game rules in a pure Dart package with no UI code.

### Flutter stack

Flutter suits the game because it is mostly interface with light 2D effects. The package choices below are candidates from general knowledge. Check each one's current status before adopting it.

| Need | Approach |
| --- | --- |
| Battle screen and menus | Standard Flutter widgets with built-in animations. Add the Flame game library only if effects outgrow widgets. |
| Rules core | A separate pure Dart package with no Flutter imports, covered by unit tests |
| Game state | One immutable battle state that only the rules core changes, with a light state-management package of the team's choice |
| Saves | A local key-value store or embedded database package |
| Audio and haptics | An audio package, plus Flutter's built-in haptic feedback |
| Purchases | The official `in_app_purchase` plugin |
| Ads | The official `google_mobile_ads` plugin, only if rewarded ads are chosen |
| Balance simulator | A Dart command-line program that imports the rules core |

Building and publishing the iOS version needs a Mac and an Apple developer account.

### Architecture

- **Rules core.** Quantum engine, damage, weather, probe, enemy AI and seeded random numbers. No UI code. The prototype's version is about 150 lines of JavaScript and ports directly to Dart.
- **Content as data.** Factions, ships, upgrades and weather tables live in data files, so balancing needs no code changes.
- **Presentation.** Screens, animation, audio and haptics, driven by events from the rules core.
- **Persistence.** A local, versioned save of the raid state and permanent progress.
- **No backend for the MVP.** Purchases and ads go through the app stores and ad network. Cloud saves, leaderboards and a daily seeded raid can come later.

### Tooling

- **Reference tests.** The rules core must reproduce the Qiskit-checked test vectors listed under Quantum model.
- **Balance simulator.** A headless runner plays thousands of battles per configuration with scripted player policies: random, habit-following and best-response.

### Stretch: real quantum hardware

A showcase mode could send a round's circuit to a real quantum computer through a small backend service using Qiskit. Queue times make this unsuitable for normal play, so it stays optional.

## MVP scope and milestones

The MVP is the prototype's battle game rebuilt natively, plus a port, a handful of upgrades and proper onboarding.

### In the MVP

- The battle system, weather and probe as specified above.
- The seven factions: three trade lanes with their protectors, plus the Rival Corsairs.
- A port with repairs and three or four upgrades.
- Unlock-based onboarding.
- Save and resume, offline play, Android and iOS builds.

### Not in the MVP

- Branching sector map, heat system and codex.
- Multiplayer of any kind.
- Real-hardware showcase mode.
- The shop, ads and backend services. Monetisation is built after the closed beta.

### Milestones

No durations are given because team size is not yet known.

1. **Prototype.** Done: the web demo.
2. **Core port.** The rules core runs as a pure Dart package. Exit: all reference tests pass.
3. **Vertical slice.** One complete battle against the Merchants Guild in Flutter on a phone, with the final collapse moment. Exit: new players grasp the tuning cycle in a playtest without reading instructions.
4. **MVP feature-complete.** Everything in the MVP list works on both platforms. Exit: a full raid can be played start to finish.
5. **Balance and polish.** Numbers tuned with the simulator and playtests, audio and accessibility finished. Exit: target win rates per faction are agreed and met.
6. **Closed beta.** Distribution through TestFlight and Google Play closed testing, with no monetisation. Exit: retention and completion data support going on.
7. **Monetisation and launch.** The chosen revenue sources are built and tested, then the game launches free on both stores. Exit: purchases and ads pass store review.

## Open questions and risks

### Open questions

- [ ] Which free-to-play revenue sources: cosmetics, rewarded ads, a supporter purchase, or a mix?
- [ ] Are the proposed guardrails accepted, especially selling nothing that changes battle odds?
- [ ] Are plain Flutter widgets enough for the battle effects, or is the Flame library needed?
- [ ] Should the outcome odds be shown before firing, only after, or as an upgrade?
- [ ] What are the target win rates per faction for a competent player?
- [ ] Is asynchronous player-versus-player worth planning for? The commit-then-reveal round structure suits it.
- [ ] Is the name "Quantum Corsairs" free to use? It needs a trademark and app-store search.

### Risks

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| Free-to-play revenue is thin | A short single-player game with nothing pay-to-win gives players few reasons to spend | Decide revenue sources before the vertical slice, design cosmetics players want to show off, measure in the beta |
| The cycle is solved too quickly | Predictable factions plus a four-tuning cycle may leave little to master | Captain traits, manual dials with real advantages, sector weather, elite variants |
| Randomness feels unfair | One unlucky collapse can cost 5 or more hull and a system | Always show the odds after the shot, keep battles short, let upgrades reduce variance |
| Storm rounds feel automatic | In a storm the lance is simply best | Add storm-specific choices, such as the storm anchor upgrade or a brace action |
| The physics intimidates | Players may bounce off jargon | Theme first, unlocks one at a time, physics kept in the optional codex |
| Balance is unproven | All numbers come from an untested prototype | Balance simulator, then playtests at the vertical-slice milestone |
