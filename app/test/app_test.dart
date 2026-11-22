import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
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
    await Future<void>.delayed(Duration.zero);

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
}
