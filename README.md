# Quantum Corsairs

A turn-based mobile duelling game in which a space pirate fights other ships using real two-qubit quantum mechanics, presented as weapon and shield tuning.

## Repository layout

| Path | What it is |
| --- | --- |
| [`packages/qc_core`](packages/qc_core) | The rules core, in pure Dart with no UI code. It holds the quantum engine, damage, coherence weather, probes, enemy AI, battles, raids, progression, saves and seeded randomness. |
| [`packages/qc_core/bin/simulate.dart`](packages/qc_core/bin/simulate.dart) | The balance simulator, which plays thousands of raids per lane with scripted players. |
| [`app`](app) | The Flutter game for Android, iOS and web. |
| [`docs/concept-design-document.md`](docs/concept-design-document.md) | The concept design document. |
| [`prototype/index.html`](prototype/index.html) | The original single-file web prototype. |

## What is implemented

This is the MVP scope from the design document:

- **Battles:** simultaneous-choice rounds on an exact two-qubit simulation, which is the Eisert–Wilkens–Lewenstein quantum prisoner's dilemma with a third dial. It includes:
  - the four preset tunings, plus manual θ/φ/α dials
  - the damage table with beam energy and barrier height
  - destroying a ship (40% salvage) or disabling it (full cargo)
- **Coherence weather:** calm void, decoherence front and coherence storm. The player sees a Bell-lock forecast range, and the actual fidelity is drawn after both sides commit.
- **Probe scan:** reads the enemy's planned tuning, with a 30% chance that its back-action turns the enemy's phases by 90°.
- **Seven factions:**
  - three trade lanes, each with a protector that answers the distress call
  - the Rival Corsairs, whom nobody protects
  - the Corp Police captain's hidden style
- **Raids:** fight the protector with damage carried over, or jettison half the cargo and run. Back at port the ship is repaired, and four refits are for sale: beam energy, barrier height, a spare probe rack and a shielded probe. Retiring banks the loot.
- **Teaching through unlocks:** a new player starts with two tunings and gains conjugate shields, the phase-shifted lance, the probe and the manual dials one prize at a time. Enemies only use tunings the player has learned. Onboarding hints appear once each.
- **Mobile UX:**
  - a vertical battle layout with the enemy above and the player below
  - the collapse moment: cells flicker, then lock, with a haptic pulse and a synthesised sound
  - a Qiskit export of every round
  - a codex and settings for sound, haptics and reduced motion
- **Offline play:** the game saves after every action, uses bundled fonts and loads CanvasKit locally on web.
- **Accessibility:** semantics labels on custom widgets, 44 px minimum tap targets, and colour never used as the only signal.

## Running

You need Flutter 3.50 or later.

```sh
# Rules core
cd packages/qc_core
dart test
dart run bin/simulate.dart --raids 1500

# The game (from the repository root)
cd ../../app
flutter test
flutter run                  # on a connected device or emulator
flutter run -d chrome        # in the browser
flutter build web --release --no-web-resources-cdn
```

Building for iOS needs a Mac with Xcode.

### Checking the physics against Qiskit

`packages/qc_core/test/reference_vectors.json` holds 38 reference cases: all 16 preset pairings at full and zero fidelity, plus six arbitrary dial settings. The Dart tests check the engine against them. This script rebuilds each case as a Qiskit circuit, `ryy(γ) · (u ⊗ u) · ryy(−γ)`, and compares the results:

```sh
pip install qiskit
python packages/qc_core/test/qiskit_check.py
```

### Balance check

The simulator reproduces the design document's table to within a few points. These are 1,500 raids per lane at starting ratings, with the player always fighting the protector:

| Lane | Random player: trader | Random player: both | Skilled player: trader | Skilled player: both |
| --- | --- | --- | --- | --- |
| Merchants Guild, then Bounty Hunters | 70% | 9% | 94% | 89% |
| Trade Federation, then Defence Force | 64% | 8% | 80% | 45% |
| Corp Fleet, then Corp Police | 49% | 2% | 56% | 30% |
| Rival Corsairs | 49% | – | 62% | – |

## Assets

- **Fonts:** Chakra Petch, IBM Plex Sans and IBM Plex Mono, all under the SIL Open Font License. The licence texts are in `app/assets/fonts`, and the game shows them under Settings › Licences.
- **Sound effects:** synthesised from sine waves and noise by `app/tool/make_sounds.py`.

## Licence

MIT. See [LICENSE](LICENSE).
