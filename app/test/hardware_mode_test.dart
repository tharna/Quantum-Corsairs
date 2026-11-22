import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart' show Size;
import 'package:qc_core/qc_core.dart';
import 'package:quantum_corsairs/controller.dart';
import 'package:quantum_corsairs/hardware/iqm_resonance.dart';
import 'package:quantum_corsairs/hardware/token_store.dart';
import 'package:quantum_corsairs/main.dart';

/// A fake IQM server whose job measures |10⟩ on the first shot.
MockClient _server({bool fail = false, List<http.Request>? log}) =>
    MockClient((r) async {
      log?.add(r);
      if (fail) return http.Response('{"detail": "maintenance"}', 503);
      final p = r.url.path;
      if (p.endsWith('/dynamic-quantum-architecture')) {
        return http.Response(
          jsonEncode({
            'qubits': ['QB1', 'QB2'],
            'gates': {
              'cz': {
                'implementations': {
                  'tgss': {
                    'loci': [
                      ['QB1', 'QB2'],
                    ],
                  },
                },
              },
            },
          }),
          200,
        );
      }
      if (r.method == 'POST' && p.endsWith('/circuit')) {
        return http.Response(jsonEncode({'job_id': 'j1'}), 200);
      }
      if (p.endsWith('/jobs/j1')) {
        return http.Response(
          jsonEncode({'job_id': 'j1', 'job_status': 'ready'}),
          200,
        );
      }
      if (p.endsWith('/artifacts/measurements')) {
        return http.Response(
          jsonEncode([
            {
              'you': [
                [1],
                [0],
                [1],
                [1],
              ],
              'them': [
                [0],
                [1],
                [0],
                [1],
              ],
            },
          ]),
          200,
        );
      }
      return http.Response('', 404);
    });

/// A server whose job stays queued until it is cancelled.
MockClient _stuck(List<http.Request> log) => MockClient((r) async {
  log.add(r);
  final p = r.url.path;
  if (p.endsWith('/dynamic-quantum-architecture')) {
    return http.Response(
      jsonEncode({
        'qubits': ['QB1', 'QB2'],
        'gates': {
          'cz': {
            'implementations': {
              'tgss': {
                'loci': [
                  ['QB1', 'QB2'],
                ],
              },
            },
          },
        },
      }),
      200,
    );
  }
  if (r.method == 'POST' && p.endsWith('/circuit')) {
    return http.Response(jsonEncode({'job_id': 'slow'}), 200);
  }
  if (p.endsWith('/cancel')) return http.Response('', 200);
  return http.Response(
    jsonEncode({
      'job_id': 'slow',
      'job_status': 'pending_execution',
      'position': 9,
    }),
    200,
  );
});

GameController _controller({
  required http.Client http,
  String? token = 'tok',
  bool hardware = true,
  bool veteran = false,
}) {
  final store = MemoryStore()
    ..data['qc.save'] = jsonEncode({
      'v': 1,
      'profile': {'prizes': veteran ? 10 : 0},
    })
    ..data['qc.settings'] = jsonEncode(
      Settings(
        sound: false,
        haptics: false,
        reducedMotion: true,
        hardware: hardware,
        iqmShots: 4,
      ).toJson(),
    );
  return GameController(
    store: store,
    sounds: SoundBank(enabled: false),
    seeds: math.Random(1),
    tokens: MemoryTokenStore(token),
    iqm: (cfg) => IqmResonanceClient(cfg, client: http),
  );
}

Future<void> _untilIdle(GameController c) async {
  for (var i = 0; i < 100 && c.qpu != null; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  test(
    'a hardware round uses the first measured shot and records the job',
    () async {
      final log = <http.Request>[];
      final c = _controller(http: _server(log: log));
      await c.load();
      expect(c.hardwareActive, isTrue);
      c.newRaid();
      c.startLane(0);
      final b = c.battle!;
      c.fire(TuningPreset.lance.tuning);
      expect(c.qpu, isNotNull, reason: 'waiting on the QPU');
      await _untilIdle(c);

      final r = c.battle!.last!;
      expect(r.outcome, Outcome.youLance);
      expect(r.hardware!.jobId, 'j1');
      expect(r.hardware!.device, 'sirius');
      expect(r.hardware!.counts, [0, 1, 2, 1]);
      expect(r.fidelityPercent, b.pendingFidelity);
      expect(r.simulatedReason, isNull);

      final post = log.firstWhere((q) => q.method == 'POST');
      expect(post.headers['Authorization'], 'Bearer tok');
      final body = jsonDecode(post.body) as Map<String, Object?>;
      expect(body['shots'], 4);
    },
  );

  test(
    'a hardware failure falls back to the simulator with a notice',
    () async {
      final c = _controller(http: _server(fail: true));
      await c.load();
      c.newRaid();
      c.startLane(0);
      c.fire(TuningPreset.lance.tuning);
      await _untilIdle(c);
      expect(c.battle!.round, 1);
      expect(c.battle!.last!.hardware, isNull);
      expect(c.battle!.last!.simulatedReason, contains('simulated'));
    },
  );

  test('without a token, rounds stay in the simulator', () async {
    final c = _controller(http: _server(), token: null);
    await c.load();
    expect(c.hardwareActive, isFalse);
    c.newRaid();
    c.startLane(0);
    c.fire(TuningPreset.lance.tuning);
    expect(c.qpu, isNull);
    expect(c.battle!.round, 1);
  });

  test('the token is kept out of the settings file', () async {
    final c = _controller(http: _server(), token: null);
    await c.load();
    await c.setIqmToken('very-secret');
    c.updateSettings(c.settings.copyWith(hardware: true));
    await c.flushed;
    expect(jsonEncode(c.settings.toJson()), isNot(contains('very-secret')));
    await c.setIqmToken('');
    expect(c.settings.hardware, isFalse);
  });

  testWidgets('settings offer the hardware section', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = _controller(http: _server(), token: null, hardware: false);
    await c.load();
    await tester.pumpWidget(QuantumCorsairsApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Measure on real hardware'), findsOneWidget);
    expect(find.text('Add an API token first'), findsOneWidget);
  });

  test('starting over while a round is queued abandons it cleanly', () async {
    final log = <http.Request>[];
    final c = _controller(http: _stuck(log));
    await c.load();
    c.newRaid();
    c.startLane(0);
    c.fire(TuningPreset.lance.tuning);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(c.qpu, isNotNull);

    c.newRaid();
    expect(c.qpu, isNull, reason: 'the new raid must not inherit the queue');
    c.updateSettings(c.settings.copyWith(hardware: false));
    c.startLane(0);
    c.fire(TuningPreset.lance.tuning);
    expect(c.battle!.round, 1, reason: 'the new battle can fire at once');

    // The abandoned job is cancelled on the server and never touches the game.
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    expect(log.any((r) => r.url.path.endsWith('/jobs/slow/cancel')), isTrue);
    expect(c.battle!.round, 1);
    expect(c.battle!.last!.hardware, isNull);
  });

  test('the probe is blocked while a round is on the QPU', () async {
    final c = _controller(http: _stuck(<http.Request>[]), veteran: true);
    await c.load();
    c.newRaid();
    c.startLane(0);
    expect(c.battle!.canProbe, isTrue);
    c.fire(TuningPreset.lance.tuning);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final before = c.battle;
    c.probe();
    expect(identical(c.battle, before), isTrue, reason: 'probe ignored');
    c.cancelHardware();
    await _untilIdle(c);
    expect(c.battle!.round, 1);
    expect(c.battle!.last!.simulatedReason, contains('left the queue'));
  });
}
