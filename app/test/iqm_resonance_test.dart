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
    if (r.method == 'POST' && p.endsWith('/jobs/garnet/circuit')) {
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
      'https://resonance.iqm.tech/api/v1/calibration-sets/garnet/default/dynamic-quantum-architecture',
    );
    expect(s.requests.single.headers['Authorization'], 'Bearer secret-token');
  });

  test('job body uses native operations on physical qubits', () {
    final body = _client(_FakeServer()).jobBody(ops, ('QB1', 'QB2'));
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
    expect(post.url.path, '/api/v1/jobs/garnet/circuit');
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
}
