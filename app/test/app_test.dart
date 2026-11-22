import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qc_core/qc_core.dart';
import 'package:quantum_corsairs/controller.dart';
import 'package:quantum_corsairs/main.dart';

GameController _controller(MemoryStore store, {int seed = 1}) => GameController(
  store: store,
  sounds: SoundBank(enabled: false),
  seeds: math.Random(seed),
);

MemoryStore _quietStore() => MemoryStore()
  ..data['qc.settings'] = jsonEncode(
    const Settings(sound: false, haptics: false, reducedMotion: true).toJson(),
  );

Future<void> _pump(WidgetTester tester, GameController c) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await c.load();
  await tester.pumpWidget(QuantumCorsairsApp(controller: c));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first raid: title, port, battle and a collapse report', (
    tester,
  ) async {
    final c = _controller(_quietStore());
    await _pump(tester, c);

    expect(find.text('BEGIN YOUR FIRST RAID'), findsOneWidget);
    await tester.tap(find.text('BEGIN YOUR FIRST RAID'));
    await tester.pumpAndSettle();

    expect(find.text('HILBERT STATION'), findsOneWidget);
    expect(find.text('MERCHANTS GUILD'), findsOneWidget);
    // Only the Guild lane is open for a new captain.
    expect(c.game.openLanes, [0]);

    await tester.tap(find.text('MERCHANTS GUILD'));
    await tester.pumpAndSettle();
    expect(c.raid!.phase, RaidPhase.battle);
    expect(find.text("KEPLER'S PURSE"), findsOneWidget);
    expect(
      find.text('Not yet learned'),
      findsNWidgets(2),
      reason: 'two phase tricks locked',
    );
    expect(
      find.textContaining('Bell-locked'),
      findsOneWidget,
      reason: 'first-battle hint',
    );

    await tester.tap(find.text('Tunnelling lance'));
    await tester.pumpAndSettle();
    expect(c.battle!.round, 1);
    expect(find.textContaining('Bell-lock '), findsWidgets);
    expect(
      find.text('NEXT ROUND').evaluate().isNotEmpty || c.battle!.result.isOver,
      isTrue,
    );
  });

  testWidgets('a whole battle can be played through the UI', (tester) async {
    final c = _controller(_quietStore(), seed: 3);
    await _pump(tester, c);
    await tester.tap(find.text('BEGIN YOUR FIRST RAID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MERCHANTS GUILD'));
    await tester.pumpAndSettle();

    var guard = 0;
    while (c.raid!.phase == RaidPhase.battle && guard++ < 60) {
      if (find.text('NEXT ROUND').evaluate().isNotEmpty) {
        await tester.tap(find.text('NEXT ROUND'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.text(guard.isEven ? 'Tunnelling lance' : 'Hold harmonics'),
      );
      await tester.pumpAndSettle();
    }
    expect(c.raid!.phase, anyOf(RaidPhase.victory, RaidPhase.defeat));
    if (c.raid!.phase == RaidPhase.victory) {
      expect(find.text('PRIZE TAKEN'), findsOneWidget);
      await tester.ensureVisible(
        find.text('JETTISON ${c.raid!.fleeCost} CR AND RUN'),
      );
      await tester.tap(find.text('JETTISON ${c.raid!.fleeCost} CR AND RUN'));
      await tester.pumpAndSettle();
      expect(find.text('HILBERT STATION'), findsOneWidget);
    } else {
      expect(find.text('RAID OVER'), findsOneWidget);
      await tester.tap(find.text('END RAID'));
      await tester.pumpAndSettle();
      expect(c.raid, isNull);
    }
  });

  testWidgets('codex and settings open from the title', (tester) async {
    final c = _controller(_quietStore());
    await _pump(tester, c);
    await tester.tap(find.text('Codex'));
    await tester.pumpAndSettle();
    expect(find.text('CODEX'), findsOneWidget);
    expect(find.text('Bell-lock'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Reduced motion'), findsOneWidget);
  });

  test('the game saves after every action and resumes', () async {
    final store = _quietStore();
    final a = _controller(store, seed: 9);
    await a.load();
    a.newRaid();
    a.startLane(0);
    a.fire(TuningPreset.lance.tuning);
    await a.flushed;

    final b = _controller(store);
    await b.load();
    expect(b.battle!.round, 1);
    expect(jsonEncode(b.game.toJson()), jsonEncode(a.game.toJson()));
  });

  test('a corrupt save starts a fresh game', () async {
    final store = _quietStore()..data['qc.save'] = '{not json';
    final c = _controller(store);
    await c.load();
    expect(c.raid, isNull);
    expect(c.loaded, isTrue);
  });

  test(
    'writes land in order even when the store finishes out of order',
    () async {
      final store = _SlowStore();
      final c = _controller(store, seed: 4);
      await c.load();
      c.newRaid(); // slow write
      c.startLane(0); // fast write
      await c.flushed;
      final saved = GameState.fromJson(
        jsonDecode(store.data['qc.save']!) as Map<String, Object?>,
      );
      expect(saved.raid!.phase, RaidPhase.battle);
    },
  );

  test('reset is not undone by a pending save', () async {
    final store = _SlowStore();
    final c = _controller(store, seed: 5);
    await c.load();
    c.newRaid();
    await c.resetProgress();
    expect(store.data.containsKey('qc.save'), isFalse);
  });

  testWidgets('an unread report survives pausing to the title', (tester) async {
    final c = _controller(_quietStore(), seed: 6);
    await _pump(tester, c);
    await tester.tap(find.text('BEGIN YOUR FIRST RAID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('MERCHANTS GUILD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tunnelling lance'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back to title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CONTINUE RAID'));
    await tester.pumpAndSettle();
    expect(find.text('NEXT ROUND'), findsOneWidget);
  });

  testWidgets('screen readers can activate lanes and tunings', (tester) async {
    final handle = tester.ensureSemantics();
    final c = _controller(_quietStore(), seed: 7);
    await _pump(tester, c);
    await tester.tap(find.text('BEGIN YOUR FIRST RAID'));
    await tester.pumpAndSettle();

    final lane = find.semantics.byLabel(RegExp('^Merchants Guild'));
    tester.semantics.tap(lane);
    await tester.pumpAndSettle();
    expect(c.raid!.phase, RaidPhase.battle);

    final order = find.semantics.byLabel(RegExp('^Tunnelling lance'));
    tester.semantics.tap(order);
    await tester.pumpAndSettle();
    expect(c.battle!.round, 1);
    handle.dispose();
  });

  testWidgets('font licence texts are bundled', (tester) async {
    for (final f in ['chakra-petch', 'ibm-plex-mono', 'ibm-plex-sans']) {
      final text = await rootBundle.loadString('assets/fonts/OFL-$f.txt');
      expect(text, contains('Open Font License'));
    }
  });
}

/// A store whose first write is slower than the ones after it.
class _SlowStore extends MemoryStore {
  int _writes = 0;

  @override
  Future<void> write(String key, String value) async {
    final delay = _writes++ == 0 ? 30 : 1;
    await Future<void>.delayed(Duration(milliseconds: delay));
    data[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    data.remove(key);
  }
}
