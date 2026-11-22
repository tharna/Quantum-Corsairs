import 'dart:convert';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Player preferences, saved with the game.
class Settings {
  const Settings({
    this.sound = true,
    this.haptics = true,
    this.reducedMotion = false,
    this.seenHints = const {},
  });

  final bool sound;
  final bool haptics;
  final bool reducedMotion;
  final Set<String> seenHints;

  Settings copyWith({
    bool? sound,
    bool? haptics,
    bool? reducedMotion,
    Set<String>? seenHints,
  }) => Settings(
    sound: sound ?? this.sound,
    haptics: haptics ?? this.haptics,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    seenHints: seenHints ?? this.seenHints,
  );

  Map<String, Object?> toJson() => {
    'sound': sound,
    'haptics': haptics,
    'reducedMotion': reducedMotion,
    'hints': seenHints.toList()..sort(),
  };

  static Settings fromJson(Map<String, Object?> j) => Settings(
    sound: j['sound'] as bool? ?? true,
    haptics: j['haptics'] as bool? ?? true,
    reducedMotion: j['reducedMotion'] as bool? ?? false,
    seenHints: {
      for (final h in (j['hints'] as List<Object?>? ?? const [])) h as String,
    },
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

/// Owns the [GameState], applies actions, saves after every one, and fires
/// sound and haptics. Screens read it and call its methods.
class GameController extends ChangeNotifier {
  GameController({SaveStore? store, SoundBank? sounds, math.Random? seeds})
    : _store = store ?? PrefsStore(),
      _sounds = sounds ?? SoundBank(),
      _seeds = seeds ?? math.Random();

  static const _gameKey = 'qc.save';
  static const _settingsKey = 'qc.settings';

  final SaveStore _store;
  final SoundBank _sounds;
  final math.Random _seeds;

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

  void probe() {
    if (!(battle?.canProbe ?? false)) return;
    sfx(Sfx.probe);
    buzz();
    _apply(_game.probe());
  }

  /// Fires and returns the resolved round, or null if nothing happened.
  RoundReport? fire(Tuning t) {
    if (raid?.phase != RaidPhase.battle) return null;
    final unlockBefore = _game.profile.unlockLevel;
    _apply(_game.fire(t));
    final report = battle!.last!;
    sfx(Sfx.collapse);
    buzz(heavy: true);
    if (!_settings.sound) return report;
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
    return report;
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

  bool hintSeen(String id) => _settings.seenHints.contains(id);

  void dismissHint(String id) => updateSettings(
    _settings.copyWith(seenHints: {..._settings.seenHints, id}),
  );

  Future<void> resetProgress() async {
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
}
