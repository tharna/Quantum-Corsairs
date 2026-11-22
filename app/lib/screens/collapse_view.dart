import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../controller.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/blueprint.dart';
import '../widgets/console.dart';

/// The signature beat: the four basis states flicker as if undecided, then
/// one locks in. Under a second; a tap skips it; reduced motion skips it.
class CollapseView extends StatefulWidget {
  const CollapseView({
    super.key,
    required this.topBar,
    required this.battle,
    required this.raid,
    required this.onNext,
  });

  final Widget topBar;
  final BattleState battle;
  final RaidState raid;
  final VoidCallback onNext;

  @override
  State<CollapseView> createState() => _CollapseViewState();
}

class _CollapseViewState extends State<CollapseView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  static const _lockAt = 0.55;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _anim.value = 1;
    } else if (!_anim.isAnimating && _anim.value == 0) {
      _anim.forward();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _skip() => _anim.value = 1;

  void _showCircuit(RoundReport r) {
    final code = qiskitCode(r.you, r.them, r.fidelityPercent);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: QC.film,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: QC.radius,
        side: BorderSide(color: QC.grid),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('This round as a Qiskit circuit'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: QC.field,
                  border: Border.all(color: QC.grid),
                  borderRadius: QC.radius,
                ),
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    code,
                    style: QC
                        .monoStyle(11.5, color: QC.ink)
                        .copyWith(height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              GhostButton(
                label: 'Copy code',
                display: false,
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Circuit copied')),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final b = widget.battle;
    final raid = widget.raid;
    final r = b.last!;
    final foe = b.faction.shipName;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: widget.topBar,
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) {
              final t = _anim.value;
              final locked = t >= _lockAt;
              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                children: [
                  GestureDetector(
                    onTap: _skip,
                    behavior: HitTestBehavior.opaque,
                    child: _Field(
                      report: r,
                      foe: b.foe,
                      progress: locked ? (t - _lockAt) / (1 - _lockAt) : 0,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'You: '),
                        TextSpan(
                          text: r.you.label,
                          style: const TextStyle(
                            color: QC.you,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: '. $foe: '),
                        TextSpan(
                          text: r.them.label,
                          style: const TextStyle(
                            color: QC.them,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(
                          text:
                              '. Bell-lock ${r.fidelityPercent}% (${r.weather.label.toLowerCase()}).',
                        ),
                        if (r.probe != null)
                          TextSpan(
                            text: r.probe!.kicked
                                ? ' Your probe turned their phase: they had planned ${r.probe!.shown.label}.'
                                : ' Your probe left their tuning undisturbed.',
                            style: const TextStyle(color: QC.coherence),
                          ),
                      ],
                    ),
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: QC.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Opacity(
                    opacity: locked ? 1 : _flicker(t),
                    child: BasisGrid(
                      table: r.table.isEmpty ? b.table : r.table,
                      probabilities: r.probabilities,
                      measured: locked ? r.outcome : null,
                    ),
                  ),
                  if (r.hardware != null) ...[
                    const SizedBox(height: 10),
                    _HardwarePanel(report: r),
                  ] else if (c.qpuNotice?.round == r.round) ...[
                    const SizedBox(height: 10),
                    Text(
                      c.qpuNotice!.message,
                      style: const TextStyle(fontSize: 13, color: QC.them),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AnimatedOpacity(
                    opacity: locked ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Semantics(
                      liveRegion: true,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            verdictTitle(r).toUpperCase(),
                            style: QC.displayStyle(
                              26,
                              color: r.outcome == Outcome.theyLance
                                  ? QC.them
                                  : QC.you,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            verdictText(r, foe),
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.45,
                              color: QC.ink,
                            ),
                          ),
                          if (b.result.isOver) ...[
                            const SizedBox(height: 12),
                            _Ending(battle: b, raid: raid),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => IgnorePointer(
              ignoring: _anim.value < _lockAt,
              child: Opacity(
                opacity: _anim.value < _lockAt ? 0.3 : 1,
                child: Column(
                  children: [
                    ..._actions(c, b, raid),
                    const SizedBox(height: 6),
                    GhostButton(
                      label: 'See this round as a Qiskit circuit',
                      icon: Icons.code,
                      color: QC.grid,
                      display: false,
                      onPressed: () => _showCircuit(r),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _flicker(double t) {
    const steps = [0.2, 0.9, 0.3, 0.8, 0.45];
    return steps[(t / _lockAt * steps.length).floor().clamp(
      0,
      steps.length - 1,
    )];
  }

  List<Widget> _actions(GameController c, BattleState b, RaidState raid) {
    if (!b.result.isOver) {
      return [PrimaryButton(label: 'Next round', onPressed: widget.onNext)];
    }
    if (raid.phase == RaidPhase.defeat) {
      return [
        PrimaryButton(
          label: 'End raid',
          subtitle: '${raid.loot} cr banked',
          onPressed: c.acknowledgeDefeat,
        ),
      ];
    }
    if (raid.protectorWaiting) {
      final guard = factions[lanes[raid.lane].guard]!;
      return [
        PrimaryButton(
          label: 'Stand and fight',
          subtitle: '${guard.shipName} · bounty ${guard.loot} cr',
          onPressed: c.fightProtector,
        ),
        const SizedBox(height: 8),
        GhostButton(
          label: 'Jettison ${raid.fleeCost} cr and run',
          onPressed: c.flee,
          color: QC.them,
        ),
      ];
    }
    return [PrimaryButton(label: 'Return to port', onPressed: c.returnToPort)];
  }
}

/// Where a hardware round was measured, and how all its shots fell compared
/// with the ideal odds.
class _HardwarePanel extends StatelessWidget {
  const _HardwarePanel({required this.report});
  final RoundReport report;

  @override
  Widget build(BuildContext context) {
    final hw = report.hardware!;
    final total = hw.counts.fold<int>(0, (a, b) => a + b);
    return Panel(
      borderColor: QC.quantum,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.memory, size: 16, color: QC.quantum),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MEASURED ON IQM ${hw.device.toUpperCase()}',
                  style: QC.displayStyle(15, color: QC.quantum),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Qubits ${hw.qubits.join(' and ')} · ${hw.shots} shots · the first shot decided the round',
            style: const TextStyle(fontSize: 12.5, color: QC.muted),
          ),
          const SizedBox(height: 8),
          for (final o in Outcome.values)
            Semantics(
              label:
                  '${o.ket}: measured ${hw.counts[o.index]} of $total, ideal ${(report.probabilities[o.index] * 100).round()} percent',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 40,
                        child: Text(
                          o.ket,
                          style: QC.monoStyle(
                            12,
                            color: o == report.outcome ? QC.ink : QC.quantum,
                          ),
                        ),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) {
                            final measured = total == 0
                                ? 0.0
                                : hw.counts[o.index] / total;
                            final ideal = report.probabilities[o.index];
                            return SizedBox(
                              height: 12,
                              child: Stack(
                                children: [
                                  Container(color: QC.grid),
                                  Container(
                                    width: box.maxWidth * measured,
                                    color: QC.quantum,
                                  ),
                                  Positioned(
                                    left: (box.maxWidth * ideal - 1).clamp(
                                      0,
                                      box.maxWidth - 2,
                                    ),
                                    top: 0,
                                    bottom: 0,
                                    child: Container(width: 2, color: QC.ink),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(
                        width: 44,
                        child: Text(
                          '${hw.counts[o.index]}',
                          textAlign: TextAlign.right,
                          style: QC.monoStyle(12, color: QC.ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 2),
          Text(
            'Violet bars: real shots. White ticks: the ideal odds. The gap is the hardware noise.',
            style: QC.monoStyle(10.5),
          ),
          Text('JOB ${hw.jobId}', style: QC.monoStyle(10.5)),
        ],
      ),
    );
  }
}

class _Ending extends StatelessWidget {
  const _Ending({required this.battle, required this.raid});
  final BattleState battle;
  final RaidState raid;

  @override
  Widget build(BuildContext context) {
    final won = battle.result.playerWon;
    final unlocked = raid.unlockedThisBattle;
    return Panel(
      borderColor: won ? QC.you : QC.them,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            won ? 'PRIZE TAKEN' : 'RAID OVER',
            style: QC.displayStyle(18, color: won ? QC.you : QC.them),
          ),
          const SizedBox(height: 6),
          Text(
            battleEndText(battle, raid.loot),
            style: const TextStyle(fontSize: 14, height: 1.4, color: QC.ink),
          ),
          if (raid.protectorWaiting) ...[
            const SizedBox(height: 6),
            Text(
              'Her distress call got out: the ${factions[lanes[raid.lane].guard]!.name} are inbound, and there is no time to repair.',
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: QC.muted,
              ),
            ),
          ],
          if (unlocked != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text('|ψ⟩', style: QC.monoStyle(14, color: QC.quantum)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Unlocked: ${unlocked.label}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: QC.quantum,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Enemy above, you below, and the beam that the collapse decided.
class _Field extends StatelessWidget {
  const _Field({
    required this.report,
    required this.foe,
    required this.progress,
  });
  final RoundReport report;
  final FactionId foe;

  /// 0 before the collapse locks, then 0 → 1.
  final double progress;

  @override
  Widget build(BuildContext context) {
    final o = report.outcome;
    final d = report.damage;
    String dmg(int h, int s) => h == 0 && s == 0
        ? 'NO DAMAGE'
        : '−$h HULL${s > 0 ? '\n−$s SYSTEM' : ''}';
    return Semantics(
      label:
          'Collapse report. ${o.ket}. You lose ${d.toYou} hull, they lose ${d.toThem} hull.',
      child: Container(
        height: 250,
        decoration: BoxDecoration(
          color: QC.field,
          border: Border.all(color: QC.grid),
          borderRadius: QC.radius,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _BeamPainter(o, progress)),
            ),
            Align(
              alignment: const Alignment(0, -0.88),
              child: ShipBlueprint(faction: foe, width: 58, pointDown: true),
            ),
            const Align(
              alignment: Alignment(0, 0.9),
              child: ShipBlueprint(width: 58),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: Opacity(
                opacity: progress > 0 ? 1 : 0,
                child: Text(
                  dmg(d.toThem, d.systemsThem),
                  textAlign: TextAlign.right,
                  style: QC.monoStyle(
                    12.5,
                    color: QC.them,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Opacity(
                opacity: progress > 0 ? 1 : 0,
                child: Text(
                  dmg(d.toYou, d.systemsYou),
                  textAlign: TextAlign.right,
                  style: QC.monoStyle(
                    12.5,
                    color: QC.you,
                    weight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Text(
                'F = ${(report.fidelityPercent / 100).toStringAsFixed(2)}',
                style: QC.monoStyle(12, color: QC.coherence),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: Text(
                o.ket,
                style: QC.monoStyle(
                  16,
                  color: progress > 0 ? QC.ink : QC.quantum,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  _BeamPainter(this.o, this.t);
  final Outcome o;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final enemyY = size.height * 0.26, youY = size.height * 0.74;
    // Superposition: the entanglement link, dashed, until the collapse.
    if (t == 0) {
      final p = Paint()
        ..color = QC.quantum.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      for (var y = enemyY + 20; y < youY - 20; y += 8) {
        canvas.drawLine(Offset(cx, y), Offset(cx, y + 4), p);
      }
      return;
    }
    final e = Curves.easeOut.transform(t.clamp(0, 1));
    void beam(Color c, double from, double to) {
      final end = from + (to - from) * e;
      final glow = Paint()
        ..color = c.withValues(alpha: 0.35)
        ..strokeWidth = 9
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      final core = Paint()
        ..color = c
        ..strokeWidth = 3;
      canvas.drawLine(Offset(cx, from), Offset(cx, end), glow);
      canvas.drawLine(Offset(cx, from), Offset(cx, end), core);
    }

    void burst(double y) {
      if (e < 0.95) return;
      final p = Paint()
        ..color = QC.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(Offset(cx, y), 10, p);
      for (var i = 0; i < 4; i++) {
        final a = i * math.pi / 2;
        canvas.drawLine(
          Offset(cx, y) + Offset(math.cos(a), math.sin(a)) * 14,
          Offset(cx, y) + Offset(math.cos(a), math.sin(a)) * 22,
          p,
        );
      }
    }

    void shield(double y, Color c, bool up) {
      final p = Paint()
        ..color = c.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      final r = Rect.fromCenter(
        center: Offset(cx, y),
        width: 110 * e,
        height: 30,
      );
      canvas.drawArc(r, up ? math.pi : 0, math.pi, false, p);
    }

    switch (o) {
      case Outcome.youLance:
        beam(QC.you, youY - 30, enemyY + 18);
        burst(enemyY + 6);
      case Outcome.theyLance:
        beam(QC.them, enemyY + 30, youY - 18);
        burst(youY - 6);
      case Outcome.bothLance:
        beam(QC.you, youY - 30, size.height / 2 + 4);
        beam(QC.them, enemyY + 30, size.height / 2 - 4);
        burst(size.height / 2);
      case Outcome.bothShield:
        shield(enemyY + 34, QC.them, false);
        shield(youY - 34, QC.you, true);
    }
  }

  @override
  bool shouldRepaint(_BeamPainter old) => old.t != t || old.o != o;
}
