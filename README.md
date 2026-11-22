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

## Real quantum hardware (IQM Resonance)

Rounds can be measured on a real superconducting quantum computer through [IQM Resonance](https://resonance.iqm.tech/), IQM's cloud service. Set it up under Settings › Quantum hardware:

1. Paste the API token from your Resonance account. It is kept in the device's secure storage (Keychain on iOS, an encrypted store on Android, WebCrypto-encrypted storage on the web), never in the game save.
2. Check the quantum computer name. The default is `sirius`. Any device in your Resonance account works, whatever its layout:
   - **Crystal chips such as Garnet** couple qubits directly.
   - **Star chips such as Sirius** couple them through a central resonator. There, each CZ runs as MOVE into the resonator, CZ, then MOVE back, the same way IQM's own transpiler handles it.
3. Choose the shots per round, then tap **Save and test connection**. The test asks the device for its current calibration and reports the two coupled qubits it will use.
4. Switch on **Measure on real hardware**.

**How a round runs:**
1. The game builds the round's circuit: the Bell-lock RYY(γ), both tunings, RYY(−γ) and a measurement. The Bell-lock fidelity γ is drawn from the forecast when the enemy commits, so the whole circuit is known before you fire.
2. `packages/qc_core/lib/src/native.dart` compiles the circuit to IQM's native gates: 4 `cz` gates, single-qubit `prx` gates, and Z rotations tracked as virtual frame changes. On a star chip, each `cz` is wrapped in `move` gates.
3. The app submits it as a circuit job to the IQM Server REST API (`POST /api/v1/jobs/{computer}/circuit`), polls the job, and reads every shot.
4. The **first shot** decides the round, so the collapse is a single real measurement. The report also shows all shots next to the ideal odds; the difference between them is the hardware's noise.

The compiled circuits are checked in two ways:
- **In Dart:** against the game engine, for every preset pairing and 500 random dial settings.
- **In CI:** against Qiskit, which rebuilds them with `RGate` (the same gate as IQM's `prx`) and CZ (`test/native_vectors.json`).

If anything fails (no network, a rejected token, a failed job, more than 3 minutes in the queue) or you leave the queue, the round is simulated instead and the report says why. Jobs use your Resonance credits.

In the web version, the browser can only reach IQM Resonance if IQM's server allows cross-origin requests. If it doesn't, the round falls back to the simulator; the Android and iOS apps are not affected.

The client follows the endpoints and payloads of IQM's official `iqm-client` Python package (version 37). It is tested against a fake server. It has not yet been run against a live Resonance account, because the IQM servers are not reachable from the environment where it was written.

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

### Play in the browser

Every merge to `main` publishes the web build to GitHub Pages:

**https://tharna.github.io/Quantum-Corsairs/**

On an iPhone, open the link in Safari and choose Share › Add to Home Screen. The game then runs full-screen with its own icon, and keeps working offline after the first load. Haptics are not available in mobile Safari; everything else is.

The deployment is `.github/workflows/pages.yml`. You can also start it by hand from the Actions tab.

### Android release APK

Every merge to `main` builds a release APK in CI. Download it from the workflow run's **Artifacts** section (`android-release-apk`, kept for 90 days). Pull requests build one too, so a broken release build shows up before merging.

Without signing secrets, the APK is signed with the debug key. Its file name ends in `-debug-signed.apk`. It installs fine for testing, but Google Play will not accept it. To sign with your own upload key, create one:

```sh
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Then add these repository secrets under Settings › Secrets and variables › Actions:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Output of `base64 -w0 upload-keystore.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | Key password |

Signed builds end in `-signed.apk`. To build a signed APK locally, put the same values in `app/android/key.properties`. That file is gitignored, and the comment at the top of `app/android/app/build.gradle.kts` shows the format.

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
