import 'package:material_ui/material_ui.dart';
import 'package:qc_core/qc_core.dart';

import '../controller.dart';
import '../theme.dart';
import '../widgets/blueprint.dart';
import '../widgets/console.dart';
import 'codex_screen.dart';
import 'raid_screen.dart';
import 'settings_screen.dart';

class TitleScreen extends StatelessWidget {
  const TitleScreen({super.key});

  void _openRaid(BuildContext context) =>
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => const RaidScreen()));

  Future<void> _newRaid(BuildContext context, GameController c) async {
    if (c.raid != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: QC.film,
          shape: const RoundedRectangleBorder(
            borderRadius: QC.radius,
            side: BorderSide(color: QC.grid),
          ),
          title: Text('ABANDON RAID?', style: QC.displayStyle(20)),
          content: Text(
            'Your current raid holds ${c.raid!.loot} cr. Starting over abandons it without banking.',
            style: const TextStyle(color: QC.ink),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep raid'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Abandon', style: TextStyle(color: QC.them)),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    c.newRaid();
    if (context.mounted) _openRaid(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = GameScope.of(context);
    final raid = c.raid;
    final profile = c.game.profile;
    String continueLine() {
      if (raid == null) return '';
      final b = raid.battle;
      final where = switch (raid.phase) {
        RaidPhase.port => 'Docked',
        RaidPhase.battle => '${b!.faction.name} · round ${b.round + 1}',
        RaidPhase.victory => 'After the battle',
        RaidPhase.defeat => 'Raid over',
      };
      return '$where · ${raid.loot} cr';
    }

    return Scaffold(
      body: BlueprintBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 64),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '|ψ⟩ = α|shield⟩ + β|lance⟩',
                          style: QC.monoStyle(12, color: QC.quantum),
                        ),
                        const SizedBox(height: 10),
                        Semantics(
                          header: true,
                          label: 'Quantum Corsairs',
                          child: ExcludeSemantics(
                            child: RichText(
                              text: TextSpan(
                                style: QC
                                    .displayStyle(58)
                                    .copyWith(height: 0.92),
                                children: const [
                                  TextSpan(text: 'QUANTUM\n'),
                                  TextSpan(
                                    text: 'CORSAIRS',
                                    style: TextStyle(color: QC.you),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Center(child: _TitleBlueprint()),
                        const SizedBox(height: 28),
                        if (!c.loaded)
                          const Center(
                            child: CircularProgressIndicator(color: QC.you),
                          )
                        else ...[
                          if (raid != null) ...[
                            PrimaryButton(
                              label: 'Continue raid',
                              subtitle: continueLine(),
                              onPressed: () => _openRaid(context),
                            ),
                            const SizedBox(height: 10),
                            GhostButton(
                              label: 'New raid',
                              onPressed: () => _newRaid(context, c),
                            ),
                          ] else
                            PrimaryButton(
                              label: profile.raidsPlayed == 0
                                  ? 'Begin your first raid'
                                  : 'New raid',
                              onPressed: () => _newRaid(context, c),
                            ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: GhostButton(
                                  label: 'Codex',
                                  icon: Icons.menu_book_outlined,
                                  color: QC.grid,
                                  display: false,
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const CodexScreen(),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: GhostButton(
                                  label: 'Settings',
                                  icon: Icons.tune,
                                  color: QC.grid,
                                  display: false,
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            profile.raidsPlayed == 0
                                ? 'Every shot is a real two-qubit circuit.'
                                : 'Prizes ${profile.prizesTotal} · banked ${profile.bankedTotal} cr · best raid ${profile.bestRaid} cr',
                            textAlign: TextAlign.center,
                            style: QC.monoStyle(11.5),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBlueprint extends StatelessWidget {
  const _TitleBlueprint();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    height: 250,
    child: Stack(
      alignment: Alignment.center,
      children: [
        const CustomPaint(size: Size(260, 250), painter: _Rings()),
        const ShipBlueprint(
          width: 120,
          semanticLabel: 'Blueprint of The Uncollapsed, your starship',
        ),
        Positioned(
          right: 0,
          top: 20,
          child: Text('EMITTER', style: QC.monoStyle(10, color: QC.quantum)),
        ),
        Positioned(
          left: 0,
          bottom: 34,
          child: Text('QC-01', style: QC.monoStyle(10, color: QC.you)),
        ),
      ],
    ),
  );
}

class _Rings extends CustomPainter {
  const _Rings();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = QC.grid
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(c, 118, p);
    canvas.drawCircle(c, 82, p..color = QC.grid.withValues(alpha: 0.7));
    final lead = Paint()
      ..color = QC.quantum
      ..strokeWidth = 0.8;
    canvas.drawLine(
      c + const Offset(0, -24),
      Offset(size.width - 60, 38),
      lead,
    );
    canvas.drawLine(Offset(size.width - 60, 38), Offset(size.width, 38), lead);
    final lead2 = Paint()
      ..color = QC.you
      ..strokeWidth = 0.8;
    canvas.drawLine(
      c + const Offset(-14, 70),
      Offset(40, size.height - 26),
      lead2,
    );
    canvas.drawLine(
      Offset(40, size.height - 26),
      Offset(0, size.height - 26),
      lead2,
    );
  }

  @override
  bool shouldRepaint(_Rings old) => false;
}
