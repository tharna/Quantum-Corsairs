import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../theme.dart';

/// Parses the small subset of SVG path data the blueprints use:
/// absolute M, L, H, V and Z.
Path parseBlueprintPath(String d) {
  final path = Path();
  final tokens = RegExp(r'[MLHVZ]|-?\d+(?:\.\d+)?')
      .allMatches(d)
      .map((m) => m[0]!)
      .toList();
  var i = 0;
  var cmd = 'M';
  var x = 0.0, y = 0.0;
  double num() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final t = tokens[i];
    if (RegExp(r'^[MLHVZ]$').hasMatch(t)) {
      cmd = t;
      i++;
      if (cmd == 'Z') {
        path.close();
        continue;
      }
    }
    switch (cmd) {
      case 'M':
        x = num();
        y = num();
        path.moveTo(x, y);
        cmd = 'L';
      case 'L':
        x = num();
        y = num();
        path.lineTo(x, y);
      case 'H':
        x = num();
        path.lineTo(x, y);
      case 'V':
        y = num();
        path.lineTo(x, y);
      default:
        i++;
    }
  }
  return path;
}

/// Drawing of one ship, top view, nose up, in a 60 × 100 box.
class BlueprintSpec {
  const BlueprintSpec({
    required this.hull,
    this.modules = const [],
    this.details = const [],
    this.ghost,
    this.nozzles = const [],
    required this.emitter,
    this.emitterRadius = 5,
  });

  /// Main outline, tinted and stroked.
  final String hull;

  /// Secondary tinted parts: pods and containers.
  final List<String> modules;

  /// Thin panel lines.
  final List<String> details;

  /// A dashed second outline (the hull that never settles).
  final String? ghost;
  final List<Rect> nozzles;
  final Offset emitter;
  final double emitterRadius;
}

const playerBlueprint = BlueprintSpec(
  hull: 'M30 4 L38 30 L38 52 L54 72 L54 84 L38 78 L36 92 L24 92 L22 78 L6 84 L6 72 L22 52 L22 30 Z',
  details: ['M22 30 H38', 'M22 62 H38', 'M6 72 L22 66', 'M54 72 L38 66'],
  nozzles: [Rect.fromLTWH(25, 92, 4, 5), Rect.fromLTWH(31, 92, 4, 5)],
  emitter: Offset(30, 44),
  emitterRadius: 6,
);

const Map<FactionId, BlueprintSpec> factionBlueprints = {
  FactionId.guild: BlueprintSpec(
    hull: 'M24 6 H36 L40 14 V86 L36 94 H24 L20 86 V14 Z',
    modules: [
      'M8 24 H18 V42 H8 Z',
      'M42 24 H52 V42 H42 Z',
      'M8 54 H18 V72 H8 Z',
      'M42 54 H52 V72 H42 Z',
    ],
    details: [
      'M18 33 H20',
      'M40 33 H42',
      'M18 63 H20',
      'M40 63 H42',
      'M20 50 H40',
    ],
    emitter: Offset(30, 30),
  ),
  FactionId.federation: BlueprintSpec(
    hull: 'M27 4 H33 V96 H27 Z',
    modules: [
      'M18 16 H42 V28 H18 Z',
      'M18 30 H42 V42 H18 Z',
      'M18 44 H42 V56 H18 Z',
      'M18 58 H42 V70 H18 Z',
    ],
    details: ['M22 88 H38 V96 H22 Z'],
    emitter: Offset(30, 80),
  ),
  FactionId.corp: BlueprintSpec(
    hull: 'M14 8 L46 8 L54 20 L54 84 L46 94 L14 94 L6 84 L6 20 Z',
    details: ['M16 28 H44 V78 H16 Z', 'M16 45 H44', 'M16 61 H44', 'M30 28 V78'],
    emitter: Offset(30, 17),
  ),
  FactionId.hunters: BlueprintSpec(
    hull: 'M18 4 L24 30 L30 22 L36 30 L42 4 L48 34 L48 70 L40 92 L20 92 L12 70 L12 34 Z',
    details: ['M12 52 H48', 'M20 92 L24 72 H36 L40 92'],
    emitter: Offset(30, 42),
    emitterRadius: 6,
  ),
  FactionId.defence: BlueprintSpec(
    hull: 'M30 10 L44 80 L30 72 L16 80 Z',
    details: ['M23 44 H37', 'M30 72 V86'],
    emitter: Offset(30, 54),
    emitterRadius: 4,
  ),
  FactionId.police: BlueprintSpec(
    hull: 'M30 2 L34 40 L50 62 L50 70 L34 66 L33 92 L27 92 L26 66 L10 70 L10 62 L26 40 Z',
    details: ['M28 22 L18 30 L18 34 L28 30', 'M32 22 L42 30 L42 34 L32 30'],
    emitter: Offset(30, 52),
    emitterRadius: 4,
  ),
  FactionId.corsairs: BlueprintSpec(
    hull: 'M30 4 L40 26 L52 34 L44 46 L48 70 L36 92 L26 88 L16 92 L18 66 L8 50 L20 38 L22 20 Z',
    ghost: 'M30 4 L42 24 L54 36 L46 48 L50 72 L38 94 L26 90 L14 94 L16 68 L6 50 L18 36 L20 18 Z',
    details: ['M20 38 L44 46', 'M18 66 L48 70'],
    emitter: Offset(30, 56),
    emitterRadius: 6,
  ),
};

/// A ship drawn as a blueprint. The player points up; enemies point down.
class ShipBlueprint extends StatelessWidget {
  const ShipBlueprint({
    super.key,
    this.faction,
    this.width = 54,
    this.pointDown = false,
    this.showCentreline = true,
    this.semanticLabel,
  });

  /// Null for the player's ship.
  final FactionId? faction;
  final double width;
  final bool pointDown;
  final bool showCentreline;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final spec = faction == null
        ? playerBlueprint
        : factionBlueprints[faction]!;
    final color = faction == null ? QC.you : QC.them;
    final drawing = CustomPaint(
      size: Size(width, width * 100 / 60),
      painter: _BlueprintPainter(spec, color, pointDown, showCentreline),
    );
    return semanticLabel == null
        ? ExcludeSemantics(child: drawing)
        : Semantics(label: semanticLabel, image: true, child: drawing);
  }
}

class _BlueprintPainter extends CustomPainter {
  _BlueprintPainter(this.spec, this.color, this.pointDown, this.centreline);

  final BlueprintSpec spec;
  final Color color;
  final bool pointDown;
  final bool centreline;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 60;
    canvas.save();
    if (pointDown) {
      canvas.translate(size.width, size.height);
      canvas.rotate(3.141592653589793);
    }
    canvas.scale(s);
    // Keep strokes about 1 device pixel wide at any size.
    final unit = 1.1 / s;
    final tint = Paint()..color = color.withValues(alpha: 0.08);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = unit;
    final thin = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.55;

    if (centreline) {
      final dash = Paint()
        ..color = QC.muted.withValues(alpha: 0.8)
        ..strokeWidth = unit * 0.45;
      for (var y = 0.0; y < 100; y += 4) {
        canvas.drawLine(Offset(30, y), Offset(30, y + 2), dash);
      }
    }

    final hull = parseBlueprintPath(spec.hull);
    canvas.drawPath(hull, tint);
    canvas.drawPath(hull, line);
    for (final m in spec.modules) {
      final p = parseBlueprintPath(m);
      canvas.drawPath(p, tint);
      canvas.drawPath(p, line..strokeWidth = unit * 0.8);
    }
    line.strokeWidth = unit;
    for (final d in spec.details) {
      canvas.drawPath(parseBlueprintPath(d), thin);
    }
    if (spec.ghost != null) {
      final ghost = parseBlueprintPath(spec.ghost!);
      for (final metric in ghost.computeMetrics()) {
        for (var d = 0.0; d < metric.length; d += 3) {
          canvas.drawPath(metric.extractPath(d, d + 1.5), thin);
        }
      }
    }
    for (final n in spec.nozzles) {
      canvas.drawRect(n, thin..strokeWidth = unit * 0.8);
    }
    final emitter = Paint()
      ..color = QC.quantum
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit;
    canvas.drawCircle(spec.emitter, spec.emitterRadius, emitter);
    canvas.drawCircle(
      spec.emitter,
      spec.emitterRadius * 0.3,
      Paint()..color = QC.quantum,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BlueprintPainter old) =>
      old.spec != spec || old.color != color || old.pointDown != pointDown;
}
