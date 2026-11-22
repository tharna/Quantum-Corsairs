import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:qc_core/qc_core.dart';

/// Runs rounds on real quantum hardware through the IQM Resonance cloud API.
///
/// Implements the subset of the IQM Server REST API (v1) that the official
/// `iqm-client` Python package uses for circuit jobs:
///
/// * `GET  api/v1/calibration-sets/{computer}/default/dynamic-quantum-architecture`
/// * `POST api/v1/jobs/{computer}/circuit`
/// * `GET  api/v1/jobs/{id}`
/// * `GET  api/v1/jobs/{id}/artifacts/measurements`
/// * `POST api/v1/jobs/{id}/cancel`
///
/// Every request carries `Authorization: Bearer <API token>`.
class IqmConfig {
  const IqmConfig({
    this.serverUrl = defaultServer,
    this.computer = defaultComputer,
    required this.token,
    this.shots = 100,
    this.timeout = const Duration(minutes: 3),
  });

  static const defaultServer = 'https://resonance.iqm.tech';
  static const defaultComputer = 'garnet';

  final String serverUrl;

  /// Quantum computer alias, such as "garnet".
  final String computer;
  final String token;
  final int shots;

  /// Longest time to wait for a job, queue included.
  final Duration timeout;
}

class IqmException implements Exception {
  const IqmException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Progress of a job, for the waiting screen.
class IqmProgress {
  const IqmProgress(this.status, {this.queuePosition, this.jobId});
  final String status;
  final int? queuePosition;
  final String? jobId;

  String get label {
    if (queuePosition != null && queuePosition! > 0) {
      return 'Queued, position $queuePosition';
    }
    return switch (status) {
      'submitting' => 'Sending the circuit',
      'received' || 'validation_started' || 'validation_ended' => 'Validating',
      'fetch_calibration_started' ||
      'fetch_calibration_ended' ||
      'compilation_started' ||
      'compilation_ended' ||
      'save_sweep_metadata_started' ||
      'save_sweep_metadata_ended' => 'Compiling pulses',
      'pending_execution' => 'Waiting for the QPU',
      'execution_started' || 'execution_ended' => 'Running on the QPU',
      'post_processing_pending' ||
      'post_processing_started' ||
      'post_processing_ended' => 'Reading out',
      'ready' => 'Done',
      _ => status.replaceAll('_', ' '),
    };
  }
}

/// Lets the caller abandon a running job.
class IqmCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Outcomes measured on the hardware for one round.
class IqmRoundResult {
  const IqmRoundResult({
    required this.jobId,
    required this.qubits,
    required this.shots,
  });

  final String jobId;
  final (String, String) qubits;

  /// One [Outcome] per shot, in the order the hardware measured them.
  final List<Outcome> shots;

  List<int> get counts {
    final c = List.filled(4, 0);
    for (final o in shots) {
      c[o.index]++;
    }
    return c;
  }
}

class IqmResonanceClient {
  IqmResonanceClient(this.config, {http.Client? client})
    : _http = client ?? http.Client();

  final IqmConfig config;
  final http.Client _http;
  (String, String)? _pair;

  static const _terminal = {'ready', 'failed', 'aborted'};

  Uri _uri(String path) {
    final root = config.serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$root/api/v1/$path');
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${config.token.trim()}',
    'Accept': 'application/json',
  };

  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final uri = _uri(path);
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json; charset=UTF-8';
        req.body = jsonEncode(body);
      }
      r = await http.Response.fromStream(
        await _http.send(req).timeout(timeout),
      );
    } on TimeoutException {
      throw const IqmException('IQM Resonance did not answer in time.');
    } on http.ClientException catch (e) {
      throw IqmException(
        'Could not reach IQM Resonance (${e.message}). In a web browser the '
        'server may also refuse cross-origin requests.',
      );
    }
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw IqmException(
        'IQM Resonance rejected the API token (HTTP ${r.statusCode}).',
        statusCode: r.statusCode,
      );
    }
    if (r.statusCode == 404) {
      throw IqmException(
        'Not found on IQM Resonance: check the quantum computer name '
        '"${config.computer}" (HTTP 404).',
        statusCode: 404,
      );
    }
    if (r.statusCode >= 400) {
      throw IqmException(
        'IQM Resonance error HTTP ${r.statusCode}: ${_errorDetail(r.body)}',
        statusCode: r.statusCode,
      );
    }
    if (r.body.isEmpty) return null;
    try {
      return jsonDecode(r.body);
    } on FormatException {
      throw const IqmException(
        'IQM Resonance sent a response that is not JSON.',
      );
    }
  }

  static String _errorDetail(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] != null) return '${j['detail']}';
      if (j is Map && j['message'] != null) return '${j['message']}';
    } catch (_) {}
    return body.length > 200 ? '${body.substring(0, 200)}…' : body;
  }

  /// Two qubits joined by a CZ gate in the current calibration.
  Future<(String, String)> qubitPair() async {
    if (_pair != null) return _pair!;
    final j = await _send(
      'GET',
      'calibration-sets/${config.computer}/default/dynamic-quantum-architecture',
    );
    if (j is! Map) throw const IqmException('Unexpected quantum architecture.');
    final qubits = {for (final q in (j['qubits'] as List? ?? const [])) '$q'};
    final cz = (j['gates'] as Map?)?['cz'] as Map?;
    final impls = (cz?['implementations'] as Map?) ?? const {};
    final loci = <(String, String)>[];
    for (final impl in impls.values) {
      for (final locus in ((impl as Map)['loci'] as List? ?? const [])) {
        final l = [for (final c in locus as List) '$c'];
        if (l.length == 2 && qubits.contains(l[0]) && qubits.contains(l[1])) {
          loci.add((l[0], l[1]));
        }
      }
    }
    if (loci.isEmpty) {
      throw IqmException(
        '${config.computer} has no CZ gate directly between two qubits, '
        'so it cannot run this circuit.',
      );
    }
    loci.sort(
      (a, b) => _natural(a.$1, b.$1) != 0
          ? _natural(a.$1, b.$1)
          : _natural(a.$2, b.$2),
    );
    return _pair = loci.first;
  }

  static int _natural(String a, String b) {
    final ra = RegExp(r'^(\D*)(\d*)$').firstMatch(a);
    final rb = RegExp(r'^(\D*)(\d*)$').firstMatch(b);
    final c = (ra?[1] ?? a).compareTo(rb?[1] ?? b);
    if (c != 0) return c;
    return (int.tryParse(ra?[2] ?? '') ?? 0).compareTo(
      int.tryParse(rb?[2] ?? '') ?? 0,
    );
  }

  /// The job request body for [ops] on physical [qubits].
  Map<String, Object?> jobBody(List<NativeOp> ops, (String, String) qubits) {
    String q(int i) => i == 0 ? qubits.$1 : qubits.$2;
    return {
      'circuits': [
        {
          'name': 'quantum-corsairs-round',
          'instructions': [
            for (final o in ops)
              switch (o.name) {
                'prx' => {
                  'name': 'prx',
                  'locus': [q(o.qubit)],
                  'args': {'angle': o.angle, 'phase': o.phase},
                },
                'cz' => {
                  'name': 'cz',
                  'locus': [q(o.qubit), q(o.other!)],
                  'args': <String, Object?>{},
                },
                _ => {
                  'name': 'measure',
                  'locus': [q(o.qubit)],
                  'args': {'key': o.key},
                },
              },
          ],
        },
      ],
      'shots': config.shots,
    };
  }

  /// Submits [ops], waits for the job and returns every measured shot.
  Future<IqmRoundResult> runRound(
    List<NativeOp> ops, {
    void Function(IqmProgress)? onProgress,
    IqmCancellation? cancellation,
    Duration pollInterval = const Duration(seconds: 1),
  }) async {
    final deadline = DateTime.now().add(config.timeout);
    onProgress?.call(const IqmProgress('submitting'));
    final pair = await qubitPair();
    final created = await _send(
      'POST',
      'jobs/${config.computer}/circuit',
      body: jobBody(ops, pair),
    );
    final jobId = created is Map
        ? '${created['job_id'] ?? created['id'] ?? ''}'
        : '';
    if (jobId.isEmpty) {
      throw const IqmException('IQM Resonance did not return a job ID.');
    }

    var wait = pollInterval;
    while (true) {
      if (cancellation?.isCancelled ?? false) {
        unawaited(_cancelQuietly(jobId));
        throw const IqmException('Cancelled.');
      }
      if (DateTime.now().isAfter(deadline)) {
        unawaited(_cancelQuietly(jobId));
        throw IqmException(
          'The job did not finish within ${config.timeout.inSeconds} s.',
        );
      }
      final j = await _send('GET', 'jobs/$jobId');
      final status = j is Map ? '${j['job_status'] ?? j['status'] ?? ''}' : '';
      final position = j is Map ? j['position'] as int? : null;
      onProgress?.call(
        IqmProgress(status, queuePosition: position, jobId: jobId),
      );
      if (status == 'ready') break;
      if (_terminal.contains(status)) {
        final err = j is Map ? j['job_error'] : null;
        final msg = err is Map
            ? (err['user_error_message'] ?? err['full_error_log'])
            : null;
        throw IqmException('The job $status${msg == null ? '' : ': $msg'}');
      }
      await Future<void>.delayed(wait);
      if (wait < const Duration(seconds: 5)) wait *= 2;
    }

    final m = await _send('GET', 'jobs/$jobId/artifacts/measurements');
    return IqmRoundResult(jobId: jobId, qubits: pair, shots: parseShots(m));
  }

  /// Turns the measurements artifact (one map per circuit, measurement key →
  /// shots → qubit bits) into one [Outcome] per shot.
  static List<Outcome> parseShots(Object? artifact) {
    final circuits = artifact is List ? artifact : const [];
    if (circuits.isEmpty || circuits.first is! Map) {
      throw const IqmException('The job returned no measurements.');
    }
    final m = circuits.first as Map;
    final you = m[youKey] as List?, them = m[themKey] as List?;
    if (you == null ||
        them == null ||
        you.length != them.length ||
        you.isEmpty) {
      throw const IqmException('The job returned incomplete measurements.');
    }
    return [
      for (var s = 0; s < you.length; s++)
        Outcome.values[2 * _bit(you[s]) + _bit(them[s])],
    ];
  }

  static int _bit(Object? shot) {
    final v = shot is List ? shot.first : shot;
    return (v as num).toInt() == 0 ? 0 : 1;
  }

  Future<void> _cancelQuietly(String jobId) async {
    try {
      await _send('POST', 'jobs/$jobId/cancel');
    } catch (_) {}
  }

  void close() => _http.close();
}
