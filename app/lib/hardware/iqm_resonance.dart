import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
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
  static const defaultComputer = 'sirius';

  final String serverUrl;

  /// Quantum computer alias, such as "sirius" or "garnet".
  final String computer;
  final String token;
  final int shots;

  /// Longest time to wait for a job, queue included.
  final Duration timeout;
}

class IqmException implements Exception {
  const IqmException(
    this.message, {
    this.statusCode,
    this.transient = false,
    this.notSent = false,
    this.jobId,
  });
  final String message;
  final int? statusCode;

  /// A network blip or a busy server: worth retrying.
  final bool transient;

  /// The request never left the device (DNS failure, refused connection),
  /// so even a job submission can be retried safely.
  final bool notSent;

  /// Set once a job exists on the server, so the player can find it.
  final String? jobId;

  IqmException withJob(String id) => IqmException(
    message,
    statusCode: statusCode,
    transient: transient,
    notSent: notSent,
    jobId: id,
  );

  @override
  String toString() => message;
}

/// Where a round runs on the chip. See [IqmResonanceClient.route].
class IqmRoute {
  const IqmRoute({
    required this.you,
    required this.them,
    required this.czLocus,
    this.resonator,
    this.moveLocus,
  });

  final String you;
  final String them;

  /// The CZ locus exactly as the device lists it.
  final List<String> czLocus;

  /// Set on star chips: the computational resonator and the MOVE locus.
  final String? resonator;
  final List<String>? moveLocus;
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
  IqmRoute? _route;

  static const _terminal = {'ready', 'failed', 'aborted'};

  /// The API token is only ever sent over HTTPS. Plain HTTP is accepted for
  /// a server on this machine (localhost), as the official client does.
  Uri _uri(String path) {
    final root = config.serverUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$root/api/v1/$path');
    if (uri == null || uri.host.isEmpty) {
      throw IqmException(
        '"${config.serverUrl}" is not a valid server address.',
      );
    }
    final local =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    if (uri.scheme != 'https' && !(uri.scheme == 'http' && local)) {
      throw IqmException(
        'The server address must start with https:// so the API token is '
        'encrypted in transit (got "${config.serverUrl}").',
      );
    }
    return uri;
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${config.token.trim()}',
    'Accept': 'application/json',
  };

  /// Sends a request, retrying transient failures up to [retries] times with
  /// backoff. With [retryOnlyUnsent] (job submission) only failures where
  /// nothing reached the server are retried, so a job is never created twice.
  Future<Object?> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 30),
    int retries = 0,
    bool retryOnlyUnsent = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _sendOnce(method, path, body: body, timeout: timeout);
      } on IqmException catch (e) {
        final retryable = retryOnlyUnsent ? e.notSent : e.transient;
        if (!retryable || attempt >= retries) rethrow;
        await Future<void>.delayed(retryDelay * (1 << attempt));
      }
    }
  }

  /// Base delay between retries; doubled after each attempt.
  @visibleForTesting
  Duration retryDelay = const Duration(milliseconds: 500);

  Future<Object?> _sendOnce(
    String method,
    String path, {
    required Object? body,
    required Duration timeout,
  }) async {
    final uri = _uri(path);
    http.Response r;
    try {
      final req = http.Request(method, uri)..headers.addAll(_headers);
      if (body != null) {
        req.headers['Content-Type'] = 'application/json; charset=UTF-8';
        req.body = jsonEncode(body);
      }
      r = await _http.send(req).then(http.Response.fromStream).timeout(timeout);
    } on TimeoutException {
      throw const IqmException(
        'IQM Resonance did not answer in time',
        transient: true,
      );
    } on http.ClientException catch (e) {
      final m = e.message.toLowerCase();
      throw IqmException(
        'Could not reach IQM Resonance (${e.message})'
        '${kIsWeb ? '. In a web browser the server may also refuse cross-origin requests' : ''}',
        transient: true,
        notSent:
            m.contains('host lookup') ||
            m.contains('connection refused') ||
            m.contains('network is unreachable'),
      );
    }
    if (const {429, 500, 502, 503, 504}.contains(r.statusCode)) {
      throw IqmException(
        'IQM Resonance is busy (HTTP ${r.statusCode})',
        statusCode: r.statusCode,
        transient: true,
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

  /// How the two emitters are placed on the chip.
  ///
  /// Works for both IQM layouts. On crystal chips (such as Garnet) two
  /// qubits share a CZ gate directly. On star chips (such as Sirius) qubits
  /// only couple through a computational resonator, so each CZ becomes
  /// MOVE(them → resonator), CZ(you, resonator), MOVE(resonator → them),
  /// the resolution IQM's own transpiler uses.
  Future<IqmRoute> route() async {
    if (_route != null) return _route!;
    final j = await _send(
      'GET',
      'calibration-sets/${config.computer}/default/dynamic-quantum-architecture',
      retries: 3,
    );
    if (j is! Map) throw const IqmException('Unexpected quantum architecture.');
    final qubits = {for (final q in (j['qubits'] as List? ?? const [])) '$q'};
    final resonators = {
      for (final r in (j['computational_resonators'] as List? ?? const []))
        '$r',
    };
    List<List<String>> loci(String gate) {
      final g = (j['gates'] as Map?)?[gate] as Map?;
      final impls = (g?['implementations'] as Map?) ?? const {};
      return [
        for (final impl in impls.values)
          for (final locus in ((impl as Map)['loci'] as List? ?? const []))
            [for (final c in locus as List) '$c'],
      ];
    }

    int byName(List<String> a, List<String> b) {
      for (var i = 0; i < a.length && i < b.length; i++) {
        final c = _natural(a[i], b[i]);
        if (c != 0) return c;
      }
      return a.length - b.length;
    }

    final cz = loci('cz')..sort(byName);
    // Crystal: a CZ directly between two qubits.
    for (final l in cz) {
      if (l.length == 2 && qubits.contains(l[0]) && qubits.contains(l[1])) {
        return _route = IqmRoute(you: l[0], them: l[1], czLocus: l);
      }
    }
    // Star: CZ(you, r) plus MOVE(them, r) on the same resonator r.
    final moves = loci('move')..sort(byName);
    for (final m in moves) {
      if (m.length != 2) continue;
      final r = m.firstWhere(resonators.contains, orElse: () => '');
      final moved = m.firstWhere(qubits.contains, orElse: () => '');
      if (r.isEmpty || moved.isEmpty) continue;
      for (final l in cz) {
        if (l.length != 2 || !l.contains(r)) continue;
        final other = l.firstWhere((c) => c != r);
        if (qubits.contains(other) && other != moved) {
          return _route = IqmRoute(
            you: other,
            them: moved,
            resonator: r,
            czLocus: l,
            moveLocus: m,
          );
        }
      }
    }
    throw IqmException(
      '${config.computer} offers no CZ between two qubits, directly or '
      'through a resonator, so it cannot run this circuit.',
    );
  }

  /// The two physical qubits used for your emitter and theirs.
  Future<(String, String)> qubitPair() async {
    final r = await route();
    return (r.you, r.them);
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

  /// The job request body for [ops] placed on the chip by [route].
  Map<String, Object?> jobBody(List<NativeOp> ops, IqmRoute route) {
    String q(int i) => i == 0 ? route.you : route.them;
    Map<String, Object?> op(
      String name,
      List<String> locus, [
      Map<String, Object?>? args,
    ]) => {'name': name, 'locus': locus, 'args': args ?? <String, Object?>{}};
    return {
      'circuits': [
        {
          'name': 'quantum-corsairs-round',
          'instructions': [
            for (final o in ops)
              ...switch (o.name) {
                'prx' => [
                  op('prx', [q(o.qubit)], {'angle': o.angle, 'phase': o.phase}),
                ],
                'cz' when route.resonator == null => [op('cz', route.czLocus)],
                'cz' => [
                  op('move', route.moveLocus!),
                  op('cz', route.czLocus),
                  op('move', route.moveLocus!),
                ],
                _ => [
                  op('measure', [q(o.qubit)], {'key': o.key}),
                ],
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
    final placement = await route();
    final pair = (placement.you, placement.them);
    final created = await _send(
      'POST',
      'jobs/${config.computer}/circuit',
      body: jobBody(ops, placement),
      retries: 3,
      retryOnlyUnsent: true,
    );
    final jobId = created is Map
        ? '${created['job_id'] ?? created['id'] ?? ''}'
        : '';
    if (jobId.isEmpty) {
      throw const IqmException('IQM Resonance did not return a job ID.');
    }

    // From here on the job exists on the server and may already be paid for.
    // Network blips must not throw its result away: transient failures are
    // retried until the deadline. Any other way out cancels the job (unless
    // it already finished) and waits for that before returning.
    var finished = false;
    IqmException? lastBlip;
    void checkDeadline() {
      if (DateTime.now().isAfter(deadline)) {
        throw IqmException(
          lastBlip == null
              ? 'The job did not finish within ${config.timeout.inSeconds} s'
              : 'Lost contact with IQM Resonance: ${lastBlip.message}',
        );
      }
    }

    try {
      var wait = pollInterval;
      while (true) {
        _checkCancelled(cancellation);
        checkDeadline();
        Object? j;
        try {
          j = await _send('GET', 'jobs/$jobId', retries: 3);
        } on IqmException catch (e) {
          if (!e.transient) rethrow;
          lastBlip = e;
          await Future<void>.delayed(wait);
          continue;
        }
        lastBlip = null;
        final status = j is Map
            ? '${j['job_status'] ?? j['status'] ?? ''}'
            : '';
        final position = j is Map ? j['position'] as int? : null;
        onProgress?.call(
          IqmProgress(status, queuePosition: position, jobId: jobId),
        );
        if (status == 'ready') break;
        if (_terminal.contains(status)) {
          finished = true; // nothing left to cancel
          final err = j is Map ? j['job_error'] : null;
          final msg = err is Map
              ? (err['user_error_message'] ?? err['full_error_log'])
              : null;
          throw IqmException('The job $status${msg == null ? '' : ': $msg'}');
        }
        await Future<void>.delayed(wait);
        if (wait < const Duration(seconds: 5)) wait *= 2;
      }
      finished = true;
      while (true) {
        _checkCancelled(cancellation);
        checkDeadline();
        try {
          final m = await _send(
            'GET',
            'jobs/$jobId/artifacts/measurements',
            retries: 3,
          );
          final shots = parseShots(m);
          // The player may have left the queue while the results downloaded.
          _checkCancelled(cancellation);
          return IqmRoundResult(jobId: jobId, qubits: pair, shots: shots);
        } on IqmException catch (e) {
          if (!e.transient) rethrow;
          lastBlip = e;
          await Future<void>.delayed(pollInterval);
        }
      }
    } on IqmException catch (e) {
      if (!finished) await _cancelQuietly(jobId);
      throw e.withJob(jobId);
    } catch (_) {
      if (!finished) await _cancelQuietly(jobId);
      rethrow;
    }
  }

  static void _checkCancelled(IqmCancellation? c) {
    if (c?.isCancelled ?? false) throw const IqmException('Cancelled.');
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

  /// One shot of one single-qubit measurement: exactly `[0]` or `[1]`.
  static int _bit(Object? shot) {
    if (shot is List && shot.length == 1) {
      final v = shot.first;
      if (v == 0 || v == 1) return v as int;
    }
    throw IqmException('The job returned an invalid measurement: $shot');
  }

  Future<void> _cancelQuietly(String jobId) async {
    try {
      await _send(
        'POST',
        'jobs/$jobId/cancel',
        timeout: const Duration(seconds: 10),
      );
    } catch (_) {}
  }

  void close() => _http.close();
}
