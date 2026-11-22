import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../theme.dart';

/// A hairline-bordered panel on film.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.borderColor = QC.grid,
    this.topAccent,
    this.bottomAccent,
    this.background = QC.film,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color borderColor;
  final Color? topAccent;
  final Color? bottomAccent;
  final Color background;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: topAccent == null && bottomAccent == null
          ? QC.radius
          : null,
      border: Border(
        top: BorderSide(
          color: topAccent ?? borderColor,
          width: topAccent == null ? 1 : 2,
        ),
        bottom: BorderSide(
          color: bottomAccent ?? borderColor,
          width: bottomAccent == null ? 1 : 2,
        ),
        left: BorderSide(color: borderColor),
        right: BorderSide(color: borderColor),
      ),
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// "[02] SECTOR CHART" style label.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color = QC.muted});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Text(text.toUpperCase(), style: QC.label(11.5, color: color)),
  );
}

/// Hull as ten segments.
class HullMeter extends StatelessWidget {
  const HullMeter({
    super.key,
    required this.hull,
    required this.max,
    required this.color,
    this.height = 6,
  });
  final int hull;
  final int max;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final lit = max == 0 ? 0 : (hull / max * 10).ceil().clamp(0, 10);
    return Semantics(
      label: 'Hull $hull of $max',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 0; i < 10; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: height,
                  color: i < lit ? color : QC.grid,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Systems as diamond pips.
class SystemPips extends StatelessWidget {
  const SystemPips({
    super.key,
    required this.systems,
    required this.max,
    required this.color,
    this.size = 9,
  });
  final int systems;
  final int max;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Systems $systems of $max',
    child: ExcludeSemantics(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Padding(
              padding: EdgeInsets.only(right: size * 0.7, left: 2),
              child: Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: i < systems ? color : null,
                    border: i < systems
                        ? null
                        : Border.all(color: QC.muted, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Bell-lock forecast: the range for this round, with the 50% mark.
class ForecastBar extends StatelessWidget {
  const ForecastBar({super.key, required this.weather, this.actualPercent});
  final Weather weather;
  final int? actualPercent;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Bell-lock fidelity ${weather.minPercent} to ${weather.maxPercent} percent',
    child: ExcludeSemantics(
      child: SizedBox(
        height: 14,
        width: double.infinity,
        child: CustomPaint(painter: _ForecastPainter(weather, actualPercent)),
      ),
    ),
  );
}

class _ForecastPainter extends CustomPainter {
  _ForecastPainter(this.w, this.actual);
  final Weather w;
  final int? actual;

  @override
  void paint(Canvas canvas, Size size) {
    final top = 3.0, h = size.height - 6;
    canvas.drawRect(
      Rect.fromLTWH(0, top, size.width, h),
      Paint()..color = QC.grid,
    );
    final x0 = size.width * w.minPercent / 100,
        x1 = size.width * w.maxPercent / 100;
    final bright = Paint()..color = QC.coherence;
    final dim = Paint()..color = QC.coherence.withValues(alpha: 0.35);
    for (var x = x0; x < x1; x += 5) {
      canvas.drawRect(Rect.fromLTWH(x, top, math.min(3, x1 - x), h), bright);
      if (x + 3 < x1) {
        canvas.drawRect(
          Rect.fromLTWH(x + 3, top, math.min(2, x1 - x - 3), h),
          dim,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(size.width / 2 - 1, 0, 2, size.height),
      Paint()..color = QC.ink,
    );
    if (actual != null) {
      final x = size.width * actual! / 100;
      final p = Path()
        ..moveTo(x, top + h)
        ..lineTo(x - 5, size.height + 4)
        ..lineTo(x + 5, size.height + 4)
        ..close();
      canvas.drawPath(p, Paint()..color = QC.quantum);
    }
  }

  @override
  bool shouldRepaint(_ForecastPainter old) =>
      old.w != w || old.actual != actual;
}

enum CellState { superposed, idle, measured }

/// One basis state of the two emitters, with its damage and odds.
class BasisCell extends StatelessWidget {
  const BasisCell({
    super.key,
    required this.outcome,
    required this.damage,
    this.probability,
    this.state = CellState.superposed,
  });

  final Outcome outcome;
  final Damage damage;
  final double? probability;
  final CellState state;

  @override
  Widget build(BuildContext context) {
    final measured = state == CellState.measured;
    final ketColor = measured ? QC.ink : QC.quantum;
    final you = 'You −${damage.toYou}${damage.systemsYou > 0 ? ' ◆' : ''}';
    final them = 'They −${damage.toThem}${damage.systemsThem > 0 ? ' ◆' : ''}';
    final p = probability;
    final label =
        '${outcome.ket}. $you. $them.'
        '${p != null ? ' Chance ${(p * 100).round()} percent.' : ''}'
        '${measured ? ' Collapsed here.' : ''}';
    return Semantics(
      label: label,
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: QC.radius,
            color: measured
                ? Color.alphaBlend(QC.ink.withValues(alpha: 0.06), QC.film)
                : null,
            border: measured ? Border.all(color: QC.ink, width: 2) : null,
            boxShadow: measured
                ? [
                    BoxShadow(
                      color: QC.quantum.withValues(alpha: 0.4),
                      blurRadius: 18,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          foregroundDecoration: measured
              ? null
              : _DashedBorder(
                  color: state == CellState.idle ? QC.grid : QC.quantum,
                ),
          child: Row(
            children: [
              Text(outcome.ket, style: QC.monoStyle(13, color: ketColor)),
              const SizedBox(width: 6),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(you, style: QC.monoStyle(11.5, color: QC.you)),
                      Text(them, style: QC.monoStyle(11.5, color: QC.them)),
                      if (p != null)
                        Text(
                          measured
                              ? 'P ${p.toStringAsFixed(2)} ✓'
                              : 'P ${p.toStringAsFixed(2)}',
                          style: QC.monoStyle(11.5, color: ketColor),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends Decoration {
  const _DashedBorder({required this.color});
  final Color color;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _DashedPainter(color);
}

class _DashedPainter extends BoxPainter {
  _DashedPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration cfg) {
    final size = cfg.size!;
    final r = (offset & size).deflate(0.5);
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    void dashLine(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var d = 0.0; d < len; d += 6) {
        canvas.drawLine(a + dir * d, a + dir * math.min(d + 3, len), p);
      }
    }

    dashLine(r.topLeft, r.topRight);
    dashLine(r.topRight, r.bottomRight);
    dashLine(r.bottomRight, r.bottomLeft);
    dashLine(r.bottomLeft, r.topLeft);
  }
}

/// The 2 × 2 grid of basis states.
class BasisGrid extends StatelessWidget {
  const BasisGrid({
    super.key,
    required this.table,
    this.probabilities,
    this.measured,
  });
  final List<Damage> table;
  final List<double>? probabilities;
  final Outcome? measured;

  @override
  Widget build(BuildContext context) {
    Widget cell(Outcome o) => BasisCell(
      outcome: o,
      damage: table[o.index],
      probability: probabilities?[o.index],
      state: measured == null
          ? CellState.superposed
          : (measured == o ? CellState.measured : CellState.idle),
    );
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cell(Outcome.bothShield)),
            const SizedBox(width: 6),
            Expanded(child: cell(Outcome.theyLance)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: cell(Outcome.youLance)),
            const SizedBox(width: 6),
            Expanded(child: cell(Outcome.bothLance)),
          ],
        ),
      ],
    );
  }
}

/// Solid mint call to action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.subtitle,
    this.height = 52,
  });
  final String label;
  final String? subtitle;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: QC.you,
        foregroundColor: QC.youInk,
        disabledBackgroundColor: QC.grid,
        minimumSize: Size.fromHeight(height),
        shape: const RoundedRectangleBorder(borderRadius: QC.radius),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: QC.displayStyle(17, color: QC.youInk),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: QC.monoStyle(12, color: const Color(0xFF0B3A2D)),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Outlined secondary action.
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.color = QC.you,
    this.display = true,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color color;
  final bool display;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: QC.ink,
        side: BorderSide(color: onPressed == null ? QC.grid : color),
        backgroundColor: QC.film,
        minimumSize: const Size.fromHeight(48),
        shape: const RoundedRectangleBorder(borderRadius: QC.radius),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: QC.muted),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              display ? label.toUpperCase() : label,
              textAlign: TextAlign.center,
              style: display
                  ? QC.displayStyle(
                      15,
                      color: onPressed == null ? QC.muted : QC.ink,
                    )
                  : const TextStyle(fontSize: 14, color: QC.ink),
            ),
          ),
        ],
      ),
    ),
  );
}

/// A one-line coaching note, used by onboarding.
class HintCard extends StatelessWidget {
  const HintCard({super.key, required this.text, this.onDismiss});
  final String text;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) => Panel(
    borderColor: QC.quantum,
    padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
    child: Row(
      children: [
        Text('|ψ⟩', style: QC.monoStyle(14, color: QC.quantum)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 13, height: 1.35, color: QC.ink),
          ),
        ),
        if (onDismiss != null)
          IconButton(
            tooltip: 'Dismiss hint',
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18, color: QC.muted),
          ),
      ],
    ),
  );
}
