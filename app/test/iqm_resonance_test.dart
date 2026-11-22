import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:qc_core/qc_core.dart';
import 'package:quantum_corsairs/hardware/iqm_resonance.dart';

const _dqa = {
  'calibration_set_id': '00000000-0000-0000-0000-000000000000',
  'qubits': ['QB1', 'QB2', 'QB3', 'QB10'],
  'computational_resonators': <String>[],
  'gates': {
    'prx': {
      'implementations': {
        'drag_gaussian': {
          'loci': [
            ['QB1'],
            ['QB2'],
          ],
        },
      },
      'default_implementation': 'drag_gaussian',
      'override_default_implementation': <String, String>{},
    },
    'cz': {
      'implementations': {
        'tgss': {
          'loci': [
            ['QB10', 'QB2'],
            ['QB2', 'QB3'],
            ['QB1', 'QB2'],
          ],
        },
      },
      'default_implementation': 'tgss',
      'override_default_implementation': <String, String>{},
    },
  },
};

/// A fake IQM server: records requests and walks a job through statuses.
class _FakeServer {
  final requests = <http.Request>[];
  final statuses = [
    'received',
    'compilation_started',
    'pending_execution',
    'ready',
  ];
  var polls = 0;
  int? failWith;
  Object? measurements = [
    {
      'you': [
        [1],
        [0],
        [1],
      ],
      'them': [
        [0],
        [1],
        [0],
      ],
    },
  ];

  late final client = MockClient((r) async {
    requests.add(r);
    if (failWith != null) return http.Response('{"detail": "nope"}', failWith!);
    final p = r.url.path;
    if (p.endsWith('/dynamic-quantum-architecture')) {
      return http.Response(jsonEncode(_dqa), 200);
    }
    if (r.method == 'POST' && p.endsWith('/jobs/sirius/circuit')) {
      return http.Response(
        jsonEncode({'job_id': 'job-42', 'job_status': 'received'}),
        200,
      );
    }
    if (p.endsWith('/jobs/job-42')) {
      final s = statuses[polls < statuses.length ? polls : statuses.length - 1];
      polls++;
      return http.Response(
        jsonEncode({
          'job_id': 'job-42',
          'job_status': s,
          'position': s == 'pending_execution' ? 2 : null,
        }),
        200,
      );
    }
    if (p.endsWith('/jobs/job-42/artifacts/measurements')) {
      return http.Response(jsonEncode(measurements), 200);
    }
    if (p.endsWith('/cancel')) return http.Response('', 200);
    return http.Response('not found', 404);
  });
}

IqmResonanceClient _client(_FakeServer s, {int shots = 3}) =>
    IqmResonanceClient(
      IqmConfig(
        token: ' secret-token ',
        shots: shots,
        serverUrl: 'https://resonance.iqm.tech/',
      ),
      client: s.client,
    );

void main() {
  final ops = compileRound(
    TuningPreset.lance.tuning,
    TuningPreset.conjugate.tuning,
    0.6,
  );

  test('picks the first coupled pair of qubits in natural order', () async {
    final s = _FakeServer();
    expect(await _client(s).qubitPair(), ('QB1', 'QB2'));
    expect(
      s.requests.single.url.toString(),
      'https://resonance.iqm.tech/api/v1/calibration-sets/sirius/default/dynamic-quantum-architecture',
    );
    expect(s.requests.single.headers['Authorization'], 'Bearer secret-token');
  });

  test('job body uses native operations on physical qubits', () {
    final body = _client(_FakeServer()).jobBody(
      ops,
      const IqmRoute(you: 'QB1', them: 'QB2', czLocus: ['QB1', 'QB2']),
    );
    expect(body['shots'], 3);
    final circuit = (body['circuits'] as List).single as Map;
    final instr = circuit['instructions'] as List;
    expect(instr.length, ops.length);
    expect(instr.map((i) => (i as Map)['name']).toSet(), {
      'prx',
      'cz',
      'measure',
    });
    final cz = instr.firstWhere((i) => (i as Map)['name'] == 'cz') as Map;
    expect(cz['locus'], ['QB1', 'QB2']);
    final measures = instr
        .where((i) => (i as Map)['name'] == 'measure')
        .toList();
    expect(measures.map((m) => (m as Map)['args']), [
      {'key': 'you'},
      {'key': 'them'},
    ]);
    final prx = instr.firstWhere((i) => (i as Map)['name'] == 'prx') as Map;
    expect((prx['args'] as Map).keys.toSet(), {'angle', 'phase'});
  });

  test('runs a round: submit, poll to ready, read every shot', () async {
    final s = _FakeServer();
    final progress = <String>[];
    final r = await _client(s).runRound(
      ops,
      onProgress: (p) => progress.add(p.label),
      pollInterval: Duration.zero,
    );
    expect(r.jobId, 'job-42');
    expect(r.qubits, ('QB1', 'QB2'));
    expect(r.shots, [Outcome.youLance, Outcome.theyLance, Outcome.youLance]);
    expect(r.counts, [0, 1, 2, 0]);
    expect(progress, contains('Queued, position 2'));
    final post = s.requests.firstWhere((q) => q.method == 'POST');
    expect(post.url.path, '/api/v1/jobs/sirius/circuit');
    expect(post.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(post.body), isA<Map<String, Object?>>());
  });

  test('a failed job reports the server message', () async {
    final s = _FakeServer()
      ..statuses.setAll(0, ['received', 'failed', 'failed', 'failed']);
    final c = _client(s);
    await expectLater(
      c.runRound(ops, pollInterval: Duration.zero),
      throwsA(
        isA<IqmException>().having(
          (e) => e.message,
          'message',
          contains('failed'),
        ),
      ),
    );
  });

  test('a rejected token is reported as such', () async {
    final s = _FakeServer()..failWith = 401;
    await expectLater(
      _client(s).qubitPair(),
      throwsA(
        isA<IqmException>().having(
          (e) => e.message,
          'message',
          contains('token'),
        ),
      ),
    );
  });

  test('cancelling stops polling and cancels the job', () async {
    final s = _FakeServer()
      ..statuses.setAll(0, List.filled(4, 'pending_execution'));
    final cancel = IqmCancellation();
    final c = _client(s);
    final run = c.runRound(
      ops,
      cancellation: cancel,
      pollInterval: const Duration(milliseconds: 5),
      onProgress: (p) {
        if (p.queuePosition != null) cancel.cancel();
      },
    );
    await expectLater(run, throwsA(isA<IqmException>()));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(
      s.requests.any((r) => r.url.path.endsWith('/jobs/job-42/cancel')),
      isTrue,
    );
  });

  test('incomplete measurements are an error, not a guess', () {
    expect(
      () => IqmResonanceClient.parseShots([
        {
          'you': [
            [1],
          ],
        },
      ]),
      throwsA(isA<IqmException>()),
    );
  });

  test(
    'star chips route each CZ through the resonator with MOVE gates',
    () async {
      final star = MockClient(
        (r) async => http.Response(
          jsonEncode({
            'qubits': ['QB1', 'QB2', 'QB3'],
            'computational_resonators': ['COMP_R'],
            'gates': {
              'cz': {
                'implementations': {
                  'tgss': {
                    'loci': [
                      ['QB1', 'COMP_R'],
                      ['QB2', 'COMP_R'],
                    ],
                  },
                },
              },
              'move': {
                'implementations': {
                  'tgss_crf': {
                    'loci': [
                      ['QB3', 'COMP_R'],
                    ],
                  },
                },
              },
            },
          }),
          200,
        ),
      );
      final c = IqmResonanceClient(const IqmConfig(token: 't'), client: star);
      final route = await c.route();
      expect(
        [route.you, route.them, route.resonator],
        ['QB1', 'QB3', 'COMP_R'],
      );

      final instr =
          ((c.jobBody(ops, route)['circuits'] as List).single
                  as Map)['instructions']
              as List;
      final names = [for (final i in instr) (i as Map)['name']];
      expect(names.where((n) => n == 'cz').length, 4);
      expect(names.where((n) => n == 'move').length, 8);
      for (var i = 0; i < names.length; i++) {
        if (names[i] == 'cz') {
          expect([names[i - 1], names[i + 1]], ['move', 'move']);
          expect((instr[i] as Map)['locus'], ['QB1', 'COMP_R']);
          expect((instr[i - 1] as Map)['locus'], ['QB3', 'COMP_R']);
        }
      }
      // Single-qubit gates and measurements stay on the two qubits.
      final touched = {
        for (final i in instr)
          if ((i as Map)['name'] != 'cz' && i['name'] != 'move')
            ...(i['locus'] as List),
      };
      expect(touched, {'QB1', 'QB3'});
    },
  );

  test('crystal chips keep a direct CZ', () async {
    final s = _FakeServer();
    final route = await _client(s).route();
    expect(route.resonator, isNull);
    expect(route.czLocus, ['QB1', 'QB2']);
  });

  test('the token is never sent over plain HTTP', () async {
    final s = _FakeServer();
    final c = IqmResonanceClient(
      const IqmConfig(token: 't', serverUrl: 'http://resonance.example.com'),
      client: s.client,
    );
    await expectLater(
      c.route(),
      throwsA(
        isA<IqmException>().having(
          (e) => e.message,
          'message',
          contains('https://'),
        ),
      ),
    );
    expect(s.requests, isEmpty);
  });

  test('a failed status request cancels the submitted job', () async {
    final requests = <http.Request>[];
    var submitted = false;
    final flaky = MockClient((r) async {
      requests.add(r);
      final p = r.url.path;
      if (p.endsWith('/dynamic-quantum-architecture')) {
        return http.Response(jsonEncode(_dqa), 200);
      }
      if (r.method == 'POST' && p.endsWith('/circuit')) {
        submitted = true;
        return http.Response(jsonEncode({'job_id': 'job-9'}), 200);
      }
      if (p.endsWith('/cancel')) return http.Response('', 200);
      // Not a blip: the server refuses the request outright.
      return http.Response('{"detail": "bad request"}', 400);
    });
    final c = IqmResonanceClient(const IqmConfig(token: 't'), client: flaky);
    await expectLater(
      c.runRound(ops, pollInterval: Duration.zero),
      throwsA(isA<IqmException>()),
    );
    expect(submitted, isTrue);
    // Awaited before the error surfaces, not left running.
    expect(requests.last.url.path, '/api/v1/jobs/job-9/cancel');
  });

  test('leaving the queue during the final download still simulates', () async {
    final s = _FakeServer();
    final cancel = IqmCancellation();
    final c = _client(s);
    await expectLater(
      c.runRound(
        ops,
        cancellation: cancel,
        pollInterval: Duration.zero,
        onProgress: (p) {
          if (p.status == 'ready') cancel.cancel();
        },
      ),
      throwsA(
        isA<IqmException>().having((e) => e.message, 'message', 'Cancelled.'),
      ),
    );
  });

  test('measurements that are not single 0/1 bits are rejected', () {
    for (final bad in [
      [2],
      [-1],
      [0.5],
      <int>[],
      [0, 1],
      1,
    ]) {
      expect(
        () => IqmResonanceClient.parseShots([
          {
            'you': [bad],
            'them': [
              [0],
            ],
          },
        ]),
        throwsA(isA<IqmException>()),
        reason: '$bad',
      );
    }
  });

  group('network blips while a paid job runs', () {
    /// Like the phone that reported this: the job is created and completes,
    /// but some later requests fail DNS lookup.
    MockClient flakyServer({
      required int statusFailures,
      required int measurementFailures,
      int submitFailures = 0,
      List<http.Request>? log,
    }) {
      var status = 0, meas = 0, submits = 0;
      return MockClient((r) async {
        log?.add(r);
        final p = r.url.path;
        if (p.endsWith('/dynamic-quantum-architecture')) {
          return http.Response(jsonEncode(_dqa), 200);
        }
        if (r.method == 'POST' && p.endsWith('/circuit')) {
          if (submits++ < submitFailures) {
            throw http.ClientException(
              "Failed host lookup: 'resonance.iqm.tech'",
              r.url,
            );
          }
          return http.Response(jsonEncode({'job_id': 'paid'}), 200);
        }
        if (p.endsWith('/jobs/paid')) {
          if (status++ < statusFailures) {
            throw http.ClientException(
              "Failed host lookup: 'resonance.iqm.tech'",
              r.url,
            );
          }
          return http.Response(
            jsonEncode({'job_id': 'paid', 'job_status': 'ready'}),
            200,
          );
        }
        if (p.endsWith('/artifacts/measurements')) {
          if (meas++ < measurementFailures) {
            return http.Response('{"detail": "upstream"}', 503);
          }
          return http.Response(
            jsonEncode([
              {
                'you': [
                  [1],
                ],
                'them': [
                  [0],
                ],
              },
            ]),
            200,
          );
        }
        if (p.endsWith('/cancel')) return http.Response('', 200);
        return http.Response('', 404);
      });
    }

    IqmResonanceClient client(MockClient m) =>
        IqmResonanceClient(const IqmConfig(token: 't'), client: m)
          ..retryDelay = Duration.zero;

    test('the result survives failed host lookups and a busy server', () async {
      final log = <http.Request>[];
      final r = await client(
        flakyServer(statusFailures: 6, measurementFailures: 5, log: log),
      ).runRound(ops, pollInterval: Duration.zero);
      expect(r.jobId, 'paid');
      expect(r.shots, [Outcome.youLance]);
      expect(
        log.any((q) => q.url.path.endsWith('/cancel')),
        isFalse,
        reason: 'a paid, finished job is never cancelled',
      );
    });

    test(
      'a submission that never left the device is retried once safely',
      () async {
        final log = <http.Request>[];
        final r = await client(
          flakyServer(
            statusFailures: 0,
            measurementFailures: 0,
            submitFailures: 2,
            log: log,
          ),
        ).runRound(ops, pollInterval: Duration.zero);
        expect(r.jobId, 'paid');
        expect(
          log
              .where(
                (q) => q.method == 'POST' && q.url.path.endsWith('/circuit'),
              )
              .length,
          3,
        );
      },
    );

    test(
      'a timed-out submission is not resent, so a job is never paid twice',
      () async {
        var submits = 0;
        final m = MockClient((r) async {
          if (r.url.path.endsWith('/dynamic-quantum-architecture')) {
            return http.Response(jsonEncode(_dqa), 200);
          }
          submits++;
          throw http.ClientException(
            'Connection closed while receiving data',
            r.url,
          );
        });
        await expectLater(
          client(m).runRound(ops, pollInterval: Duration.zero),
          throwsA(isA<IqmException>()),
        );
        expect(submits, 1);
      },
    );

    test('errors after submission name the job', () async {
      final m = MockClient((r) async {
        final p = r.url.path;
        if (p.endsWith('/dynamic-quantum-architecture')) {
          return http.Response(jsonEncode(_dqa), 200);
        }
        if (r.method == 'POST' && p.endsWith('/circuit')) {
          return http.Response(jsonEncode({'job_id': 'j-77'}), 200);
        }
        if (p.endsWith('/jobs/j-77')) {
          return http.Response(jsonEncode({'job_status': 'failed'}), 200);
        }
        return http.Response('', 200);
      });
      await expectLater(
        client(m).runRound(ops, pollInterval: Duration.zero),
        throwsA(isA<IqmException>().having((e) => e.jobId, 'jobId', 'j-77')),
      );
    });
  });

  test(
    'if contact never comes back, the job is cancelled at the deadline',
    () async {
      final requests = <http.Request>[];
      final m = MockClient((r) async {
        requests.add(r);
        final p = r.url.path;
        if (p.endsWith('/dynamic-quantum-architecture')) {
          return http.Response(jsonEncode(_dqa), 200);
        }
        if (r.method == 'POST' && p.endsWith('/circuit')) {
          return http.Response(jsonEncode({'job_id': 'gone'}), 200);
        }
        if (p.endsWith('/cancel')) return http.Response('', 200);
        return http.Response('', 503);
      });
      final c = IqmResonanceClient(
        const IqmConfig(token: 't', timeout: Duration(milliseconds: 200)),
        client: m,
      )..retryDelay = Duration.zero;
      await expectLater(
        c.runRound(ops, pollInterval: const Duration(milliseconds: 10)),
        throwsA(
          isA<IqmException>()
              .having((e) => e.message, 'message', contains('Lost contact'))
              .having((e) => e.jobId, 'jobId', 'gone'),
        ),
      );
      expect(requests.last.url.path, '/api/v1/jobs/gone/cancel');
    },
  );
}
