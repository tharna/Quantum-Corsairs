import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hardware/iqm_resonance.dart';
import 'hardware/token_store.dart';

/// Player preferences, saved with the game.
class Settings {
  const Settings({
    this.sound = true,
    this.haptics = true,
    this.reducedMotion = false,
    this.seenHints = const {},
    this.hardware = false,
    this.iqmServer = IqmConfig.defaultServer,
    this.iqmComputer = IqmConfig.defaultComputer,
    this.iqmShots = 100,
  });

  final bool sound;
  final bool haptics;
  final bool reducedMotion;
  final Set<String> seenHints;

  /// Measure rounds on a real quantum computer through IQM Resonance.
  final bool hardware;
  final String iqmServer;
  final String iqmComputer;
  final int iqmShots;

  Settings copyWith({
    bool? sound,
    bool? haptics,
    bool? reducedMotion,
    Set<String>? seenHints,
    bool? hardware,
    String? iqmServer,
    String? iqmComputer,
    int? iqmShots,
  }) => Settings(
    sound: sound ?? this.sound,
    haptics: haptics ?? this.haptics,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    seenHints: seenHints ?? this.seenHints,
    hardware: hardware ?? this.hardware,
    iqmServer: iqmServer ?? this.iqmServer,
    iqmComputer: iqmComputer ?? this.iqmComputer,
    iqmShots: iqmShots ?? this.iqmShots,
  );

  Map<String, Object?> toJson() => {
    'sound': sound,
    'haptics': haptics,
    'reducedMotion': reducedMotion,
    'hints': seenHints.toList()..sort(),
    'hardware': hardware,
    'iqmServer': iqmServer,
    'iqmComputer': iqmComputer,
    'iqmShots': iqmShots,
  };

  static Settings fromJson(Map<String, Object?> j) => Settings(
    sound: j['sound'] as bool? ?? true,
    haptics: j['haptics'] as bool? ?? true,
    reducedMotion: j['reducedMotion'] as bool? ?? false,
    seenHints: {
      for (final h in (j['hints'] as List<Object?>? ?? const [])) h as String,
    },
    hardware: j['hardware'] as bool? ?? false,
    iqmServer: j['iqmServer'] as String? ?? IqmConfig.defaultServer,
    iqmComputer: j['iqmComputer'] as String? ?? IqmConfig.defaultComputer,
    iqmShots: j['iqmShots'] as int? ?? 100,
  );
}

/// Where saves live. Swapped for [MemoryStore] in tests.
abstract class SaveStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

class PrefsStore implements SaveStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

class MemoryStore implements SaveStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> remove(String key) async => data.remove(key);
}

enum Sfx { tap, probe, collapse, hit, hurt, victory, defeat, unlock }

/// Plays the synthesised effects. Failures are ignored: sound is optional.
class SoundBank {
  SoundBank({this.enabled = true});

  final bool enabled;
  final List<AudioPlayer> _pool = [];
  int _next = 0;

  Future<void> play(Sfx s) async {
    if (!enabled) return;
    try {
      if (_pool.isEmpty) {
        for (var i = 0; i < 4; i++) {
          _pool.add(AudioPlayer()..setReleaseMode(ReleaseMode.stop));
        }
      }
      final p = _pool[_next++ % _pool.length];
      await p.stop();
      await p.play(AssetSource('audio/${s.name}.wav'));
    } catch (e) {
      debugPrint('sound unavailable: $e');
    }
  }
}

/// A round waiting on the quantum computer.
class QpuRun {
  QpuRun(this.device, this.tuning, this.battle);
  final String device;
  final Tuning tuning;

  /// The battle state the round was fired from. The result only applies
  /// while the game is still in exactly this state.
  final BattleState battle;
  final IqmCancellation cancellation = IqmCancellation();
  IqmProgress progress = const IqmProgress('submitting');
}

/// Owns the [GameState], applies actions, saves after every one, and fires
/// sound and haptics. Screens read it and call its methods.
class GameController extends ChangeNotifier {
  GameController({
    SaveStore? store,
    SoundBank? sounds,
    math.Random? seeds,
    TokenStore? tokens,
    IqmResonanceClient Function(IqmConfig)? iqm,
  }) : _store = store ?? PrefsStore(),
       _sounds = sounds ?? SoundBank(),
       _seeds = seeds ?? math.Random(),
       _tokens = tokens ?? SecureTokenStore(),
       _iqmFactory = iqm ?? IqmResonanceClient.new;

  static const _gameKey = 'qc.save';
  static const _settingsKey = 'qc.settings';

  final SaveStore _store;
  final SoundBank _sounds;
  final math.Random _seeds;
  final TokenStore _tokens;
  final IqmResonanceClient Function(IqmConfig) _iqmFactory;
  String _iqmToken = '';

  /// The round currently running on quantum hardware, if any.
  QpuRun? qpu;

  bool get hasIqmToken => _iqmToken.trim().isNotEmpty;

  /// Rounds go to the quantum computer only when switched on with a token.
  bool get hardwareActive => _settings.hardware && hasIqmToken;

  GameState _game = const GameState();
  Settings _settings = const Settings();
  bool _loaded = false;

  GameState get game => _game;
  Settings get settings => _settings;
  bool get loaded => _loaded;
  RaidState? get raid => _game.raid;
  BattleState? get battle => _game.raid?.battle;

  Future<void> load() async {
    try {
      final g = await _store.read(_gameKey);
      if (g != null) {
        _game = GameState.fromJson(jsonDecode(g) as Map<String, Object?>);
      }
    } catch (e) {
      debugPrint('save unreadable, starting fresh: $e');
      _game = const GameState();
    }
    try {
      final s = await _store.read(_settingsKey);
      if (s != null) {
        _settings = Settings.fromJson(jsonDecode(s) as Map<String, Object?>);
      }
    } catch (_) {
      _settings = const Settings();
    }
    _iqmToken = await _tokens.read() ?? '';
    _loaded = true;
    notifyListeners();
  }

  /// Persistence runs one operation at a time, in the order requested, so an
  /// older snapshot can never overwrite a newer one and a reset cannot be
  /// undone by a write that was still pending.
  Future<void> _queue = Future<void>.value();

  Future<void> _enqueue(Future<void> Function() op) {
    _queue = _queue.then((_) => op()).catchError((Object e) {
      debugPrint('save failed: $e');
    });
    return _queue;
  }

  /// Snapshots the state now and writes it in order.
  Future<void> _save() {
    final json = jsonEncode(_game.toJson());
    return _enqueue(() => _store.write(_gameKey, json));
  }

  /// Completes when every queued write has finished.
  Future<void> get flushed => _queue;

  /// The battle round whose collapse report the player last dismissed. Kept
  /// in memory so pausing to the title and back never skips an unread
  /// report; after a restart the latest report is shown again.
  int? acknowledgedRound;

  void acknowledgeReport(int round) {
    acknowledgedRound = round;
    notifyListeners();
  }

  void _apply(GameState next) {
    // Any change that replaces the battle abandons a pending hardware round.
    if (qpu != null && !identical(next.raid?.battle, qpu!.battle)) {
      _detachQpu();
    }
    _game = next;
    notifyListeners();
    _save();
  }

  void sfx(Sfx s) {
    if (_settings.sound) _sounds.play(s);
  }

  void buzz({bool heavy = false}) {
    if (!_settings.haptics) return;
    heavy ? HapticFeedback.heavyImpact() : HapticFeedback.selectionClick();
  }

  // ------------------------------------------------------------ actions

  void newRaid() {
    sfx(Sfx.tap);
    _apply(_game.newRaid(_seeds.nextInt(0x7FFFFFFF)));
  }

  void buy(Upgrade u) {
    if (!_game.canBuy(u)) return;
    sfx(Sfx.tap);
    buzz();
    _apply(_game.buy(u));
  }

  void startLane(int i) {
    acknowledgedRound = 0;
    sfx(Sfx.tap);
    _apply(_game.startLane(i));
  }

  /// Cancels a pending hardware round and forgets it. Its result, if one
  /// still arrives, is ignored.
  void _detachQpu() {
    qpu?.cancellation.cancel();
    qpu = null;
  }

  void probe() {
    // Probing changes the battle, which would orphan a round on the QPU.
    if (qpu != null || !(battle?.canProbe ?? false)) return;
    sfx(Sfx.probe);
    buzz();
    _apply(_game.probe());
  }

  /// Fires a round: on the quantum computer when [hardwareActive], else in
  /// the simulator. A hardware failure falls back to the simulator.
  void fire(Tuning t) {
    if (raid?.phase != RaidPhase.battle || qpu != null) return;
    if (hardwareActive) {
      _fireOnHardware(t);
    } else {
      _resolve(t);
    }
  }

  /// Leaves the queue and simulates the round instead.
  void cancelHardware() => qpu?.cancellation.cancel();

  IqmConfig _iqmConfig() => IqmConfig(
    serverUrl: _settings.iqmServer,
    computer: _settings.iqmComputer,
    token: _iqmToken,
    shots: _settings.iqmShots,
  );

  Future<void> _fireOnHardware(Tuning t) async {
    final b = battle!;
    final run = QpuRun(_settings.iqmComputer, t, b);
    qpu = run;
    sfx(Sfx.probe);
    notifyListeners();
    // Only the run that is still current may touch the game.
    bool current() => identical(qpu, run) && identical(battle, b);
    final client = _iqmFactory(_iqmConfig());
    try {
      final ops = compileRound(t, b.plan, b.pendingFidelity / 100);
      final r = await client.runRound(
        ops,
        cancellation: run.cancellation,
        onProgress: (p) {
          if (!identical(qpu, run)) return;
          run.progress = p;
          notifyListeners();
        },
      );
      if (!current()) return;
      qpu = null;
      _resolve(
        t,
        measured: r.shots.first,
        hardware: HardwareRun(
          device: run.device,
          jobId: r.jobId,
          qubits: [r.qubits.$1, r.qubits.$2],
          shots: r.shots.length,
          counts: r.counts,
        ),
      );
    } catch (e) {
      if (!current()) return;
      qpu = null;
      final String why;
      if (run.cancellation.isCancelled) {
        why = 'You left the queue';
      } else {
        final msg = '$e'.replaceAll(RegExp(r'[.\s]+$'), '');
        why = 'The quantum computer was unavailable: $msg';
      }
      final job = e is IqmException && e.jobId != null
          ? ' (job ${e.jobId})'
          : '';
      _resolve(t, simulatedReason: '$why$job. This round was simulated.');
    } finally {
      client.close();
    }
  }

  void _resolve(
    Tuning t, {
    Outcome? measured,
    HardwareRun? hardware,
    String? simulatedReason,
  }) {
    final unlockBefore = _game.profile.unlockLevel;
    _apply(
      _game.fire(
        t,
        measured: measured,
        hardware: hardware,
        simulatedReason: simulatedReason,
      ),
    );
    final report = battle!.last!;
    sfx(Sfx.collapse);
    buzz(heavy: true);
    if (!_settings.sound) return;
    // Impact sounds land as the collapse animation locks in.
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      final d = report.damage;
      if (d.toThem > 0 || d.systemsThem > 0) sfx(Sfx.hit);
      if (d.toYou > 0 || d.systemsYou > 0) sfx(Sfx.hurt);
      final phase = raid?.phase;
      if (phase == RaidPhase.victory) {
        sfx(
          _game.profile.unlockLevel > unlockBefore ? Sfx.unlock : Sfx.victory,
        );
      }
      if (phase == RaidPhase.defeat) sfx(Sfx.defeat);
    });
  }

  void fightProtector() {
    acknowledgedRound = 0;
    sfx(Sfx.tap);
    _apply(_game.fightProtector());
  }

  void flee() {
    sfx(Sfx.tap);
    _apply(_game.flee());
  }

  void returnToPort() {
    sfx(Sfx.tap);
    _apply(_game.returnToPort());
  }

  void retire() {
    sfx(Sfx.tap);
    _apply(_game.retire());
  }

  void acknowledgeDefeat() => _apply(_game.acknowledgeDefeat());

  // ------------------------------------------------------------ settings

  void updateSettings(Settings s) {
    _settings = s;
    notifyListeners();
    final json = jsonEncode(s.toJson());
    _enqueue(() => _store.write(_settingsKey, json));
  }

  /// Stores the IQM Resonance API token in secure storage. An empty token
  /// removes it and switches hardware mode off.
  Future<void> setIqmToken(String token) async {
    _iqmToken = token.trim();
    if (_iqmToken.isEmpty) {
      await _tokens.delete();
      if (_settings.hardware) {
        updateSettings(_settings.copyWith(hardware: false));
      }
    } else {
      await _tokens.write(_iqmToken);
    }
    notifyListeners();
  }

  /// Checks the token and computer by asking for a usable pair of qubits.
  Future<String> testIqmConnection() async {
    if (!hasIqmToken) throw const IqmException('Add an API token first.');
    final client = _iqmFactory(_iqmConfig());
    try {
      final r = await client.route();
      final via = r.resonator == null ? '' : ', coupled through ${r.resonator}';
      return 'Connected to ${_settings.iqmComputer}. Rounds will use qubits ${r.you} and ${r.them}$via.';
    } finally {
      client.close();
    }
  }

  bool hintSeen(String id) => _settings.seenHints.contains(id);

  void dismissHint(String id) => updateSettings(
    _settings.copyWith(seenHints: {..._settings.seenHints, id}),
  );

  Future<void> resetProgress() async {
    _detachQpu();
    _game = const GameState();
    _settings = _settings.copyWith(seenHints: {});
    acknowledgedRound = null;
    final json = jsonEncode(_settings.toJson());
    notifyListeners();
    await _enqueue(() async {
      await _store.remove(_gameKey);
      await _store.write(_settingsKey, json);
    });
  }
}

/// Makes the controller available below it in the tree.
class GameScope extends InheritedNotifier<GameController> {
  const GameScope({
    super.key,
    required GameController controller,
    required super.child,
  }) : super(notifier: controller);

  static GameController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GameScope>()!.notifier!;

  /// Reads the controller without rebuilding on changes. Safe in initState
  /// and in callbacks.
  static GameController read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<GameScope>()!.notifier!;
}
