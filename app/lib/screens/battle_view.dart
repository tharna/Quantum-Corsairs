import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../controller.dart';
import '../copy.dart';
import '../theme.dart';
import '../widgets/console.dart';
import '../widgets/ship_card.dart';
import 'collapse_view.dart';
import 'raid_screen.dart';

/// The battle, laid out vertically: the enemy above, the quantum readouts
/// between the ships, you below, and the orders in the thumb zone.
class BattleView extends StatefulWidget {
  const BattleView({super.key});

  @override
  State<BattleView> createState() => _BattleViewState();
}

class _BattleViewState extends State<BattleView> {
  void _fire(GameController c, Tuning t) => c.fire(t);

  Future<void> _openDials(GameController c) async {
    final t = await showModalBottomSheet<Tuning>(
      context: context,
      backgroundColor: QC.film,
      shape: const RoundedRectangleBorder(
        borderRadius: QC.radius,
        side: BorderSide(color: QC.grid),
      ),
      isScrollControlled: true,
      builder: (_) => const _DialsSheet(),
    );
    if (t != null && mounted) _fire(c, t);
  }

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final raid = c.raid;
    final b = raid?.battle;
    // While the switcher fades this view out, the battle may already be gone.
    if (raid == null || b == null) return const SizedBox.expand();
    // A battle reopened after a restart shows its latest report again, so a
    // result the player had not read is never skipped.
    final ack = c.acknowledgedRound ?? (b.round > 0 ? b.round - 1 : 0);
    final showingReport = b.round > ack;

    final top = RaidTopBar(
      label:
          '[R${(b.round + (showingReport ? 0 : 1)).toString().padLeft(2, '0')}] ${b.stage == 1 ? 'PROTECTOR' : 'ENGAGEMENT'}',
      loot: raid.loot,
    );

    if (showingReport) {
      return CollapseView(
        key: ValueKey('report-${b.round}'),
        topBar: top,
        battle: b,
        raid: raid,
        onNext: () => c.acknowledgeReport(b.round),
      );
    }

    final hint = battleHint(b, c.game.profile, c.hintSeen);
    final allowed = b.allowed;
    final profile = c.game.profile;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: top,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            children: [
              ShipCard(
                ship: b.them,
                faction: b.foe,
                subtitle: shortHabit(b.foe, b.allowed),
              ),
              const SizedBox(height: 8),
              _Entangled(
                children: [
                  Panel(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                b.weather.label.toUpperCase(),
                                style: QC.displayStyle(16, color: QC.coherence),
                              ),
                            ),
                            Text(
                              'BELL-LOCK ${b.weather.minPercent}–${b.weather.maxPercent}%',
                              style: QC.monoStyle(11.5, color: QC.ink),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ForecastBar(weather: b.weather),
                        const SizedBox(height: 6),
                        Text(
                          b.weather.description,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: QC.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  BasisGrid(table: b.table),
                  Text(
                    '|you, them⟩ · 0 shield · 1 lance · ◆ also costs a system',
                    style: QC.monoStyle(10.5),
                  ),
                  if (profile.has(Unlock.probe))
                    _ProbeRow(battle: b, onProbe: c.probe),
                ],
              ),
              const SizedBox(height: 8),
              ShipCard(ship: b.you),
              if (hint != null) ...[
                const SizedBox(height: 8),
                HintCard(
                  text: hint.text,
                  onDismiss: () => c.dismissHint(hint.id),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
          child: c.qpu != null
              ? _QpuPanel(run: c.qpu!, onCancel: c.cancelHardware)
              : Column(
                  children: [
                    if (c.hardwareActive)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.memory,
                              size: 14,
                              color: QC.quantum,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'QPU · IQM ${c.settings.iqmComputer.toUpperCase()} · ${c.settings.iqmShots} SHOTS',
                              style: QC.monoStyle(11, color: QC.quantum),
                            ),
                          ],
                        ),
                      ),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _OrderButton(
                              preset: TuningPreset.hold,
                              enabled: allowed.contains(TuningPreset.hold),
                              onTap: (t) => _fire(c, t),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _OrderButton(
                              preset: TuningPreset.lance,
                              enabled: allowed.contains(TuningPreset.lance),
                              onTap: (t) => _fire(c, t),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _OrderButton(
                              preset: TuningPreset.conjugate,
                              enabled: allowed.contains(TuningPreset.conjugate),
                              onTap: (t) => _fire(c, t),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _OrderButton(
                              preset: TuningPreset.phaseLance,
                              enabled: allowed.contains(
                                TuningPreset.phaseLance,
                              ),
                              onTap: (t) => _fire(c, t),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (profile.has(Unlock.dials))
                      TextButton.icon(
                        onPressed: () => _openDials(c),
                        icon: const Icon(Icons.tune, size: 16, color: QC.muted),
                        label: Text(
                          'MANUAL DIALS θ φ α',
                          style: QC.monoStyle(11.5),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Shown in place of the orders while a round runs on the quantum computer.
class _QpuPanel extends StatelessWidget {
  const _QpuPanel({required this.run, required this.onCancel});
  final QpuRun run;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Panel(
    borderColor: QC.quantum,
    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    child: Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: QC.quantum,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'TRANSMITTING TO IQM ${run.device.toUpperCase()}',
                  style: QC.displayStyle(15, color: QC.quantum),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${run.tuning.label} is compiled to native prx and cz gates and '
            'measured on a real quantum processor.',
            style: const TextStyle(fontSize: 13, height: 1.35, color: QC.ink),
          ),
          const SizedBox(height: 6),
          Text(
            run.progress.label.toUpperCase(),
            style: QC.monoStyle(11.5, color: QC.coherence),
          ),
          if (run.progress.jobId != null)
            Text('JOB ${run.progress.jobId}', style: QC.monoStyle(10.5)),
          const SizedBox(height: 10),
          GhostButton(
            label: 'Leave the queue and simulate',
            color: QC.grid,
            display: false,
            onPressed: onCancel,
          ),
        ],
      ),
    ),
  );
}

/// The dashed violet line that ties the readouts between the two ships.
class _Entangled extends StatelessWidget {
  const _Entangled({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: const _LinkPainter(),
    child: Padding(
      padding: const EdgeInsets.only(left: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class _LinkPainter extends CustomPainter {
  const _LinkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = QC.quantum
      ..strokeWidth = 2;
    for (var y = -8.0; y < size.height + 8; y += 8) {
      canvas.drawLine(Offset(6, y), Offset(6, y + 4), p);
    }
  }

  @override
  bool shouldRepaint(_LinkPainter old) => false;
}

class _ProbeRow extends StatelessWidget {
  const _ProbeRow({required this.battle, required this.onProbe});
  final BattleState battle;
  final VoidCallback onProbe;

  @override
  Widget build(BuildContext context) {
    final scan = battle.scan;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: QC.film,
            side: BorderSide(color: battle.canProbe ? QC.coherence : QC.grid),
            shape: const RoundedRectangleBorder(borderRadius: QC.radius),
            minimumSize: const Size.fromHeight(44),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: battle.canProbe ? onProbe : null,
          child: Row(
            children: [
              const Icon(Icons.radar, size: 18, color: QC.coherence),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  scan == null
                      ? 'Probe their emitter'
                      : 'Probe fired this round',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: QC.ink,
                  ),
                ),
              ),
              Text(
                '${battle.probesLeft}/${battle.probesMax}',
                semanticsLabel:
                    '${battle.probesLeft} of ${battle.probesMax} probes left',
                style: QC.monoStyle(11.5, color: QC.coherence),
              ),
            ],
          ),
        ),
        if (scan != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Semantics(
              liveRegion: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'Probe reads: '),
                    TextSpan(
                      text: scan.shown.label,
                      style: const TextStyle(
                        color: QC.them,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text: '. Their lance power is certain; their phase may have been turned 90° by the probe itself.',
                    ),
                  ],
                ),
                style: const TextStyle(fontSize: 13, color: QC.ink),
              ),
            ),
          ),
      ],
    );
  }
}

class _OrderButton extends StatelessWidget {
  const _OrderButton({
    required this.preset,
    required this.enabled,
    required this.onTap,
  });
  final TuningPreset preset;
  final bool enabled;
  final ValueChanged<Tuning> onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    onTap: enabled ? () => onTap(preset.tuning) : null,
    label: enabled
        ? '${preset.label}, ${preset.gate}. ${preset.description}'
        : '${preset.label}. Locked: take more prizes to learn it.',
    child: ExcludeSemantics(
      child: Material(
        color: QC.film,
        borderRadius: QC.radius,
        child: InkWell(
          borderRadius: QC.radius,
          onTap: enabled ? () => onTap(preset.tuning) : null,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            decoration: BoxDecoration(
              borderRadius: QC.radius,
              border: Border.all(color: enabled ? QC.you : QC.grid),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preset.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14.5,
                          color: enabled ? QC.ink : QC.muted,
                        ),
                      ),
                    ),
                    enabled
                        ? Text(
                            preset.ket,
                            style: QC.monoStyle(13, color: QC.you),
                          )
                        : const Icon(
                            Icons.lock_outline,
                            size: 15,
                            color: QC.muted,
                          ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  enabled ? orderHint(preset) : 'Not yet learned',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: QC.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _DialsSheet extends StatefulWidget {
  const _DialsSheet();

  @override
  State<_DialsSheet> createState() => _DialsSheetState();
}

class _DialsSheetState extends State<_DialsSheet> {
  double theta = 90, phi = 45, alpha = 45;

  Widget _dial(
    String label,
    String help,
    double value,
    double max,
    ValueChanged<double> set,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: QC.ink),
            ),
          ),
          Text('${value.round()}°', style: QC.monoStyle(13, color: QC.you)),
        ],
      ),
      Slider(
        value: value,
        max: max,
        divisions: max ~/ 5,
        label: '${value.round()}°',
        semanticFormatterCallback: (v) => '${v.round()} degrees',
        onChanged: (v) => setState(() => set(v)),
      ),
      Text(help, style: const TextStyle(fontSize: 12, color: QC.muted)),
      const SizedBox(height: 10),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final t = Tuning.degrees(theta.round(), phi.round(), alpha.round());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Manual emitter dials'),
            const SizedBox(height: 12),
            _dial(
              'Lance power θ',
              '0° keeps everything in the shields; 180° puts everything in the lance.',
              theta,
              180,
              (v) => theta = v,
            ),
            _dial(
              'Shield phase φ',
              'Retunes the shields against an incoming lance. 90° is full conjugation.',
              phi,
              90,
              (v) => phi = v,
            ),
            _dial(
              'Lance phase α',
              'Retunes the lance to get past their shield phase.',
              alpha,
              90,
              (v) => alpha = v,
            ),
            Text(t.label, style: QC.monoStyle(12, color: QC.quantum)),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Fire with this tuning',
              onPressed: () => Navigator.pop(context, t),
            ),
          ],
        ),
      ),
    );
  }
}
